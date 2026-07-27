# Phase 5 — HS Code Auto-Classification

**Duration:** ~1-1.5 days
**Depends on:** Phase 4 (silver_bol_shipments with 52,611 rows, 45.6% HS coverage; hs_eval_seed.csv with 30 hand-labeled rows)
**Goal:** Fill in the missing HS codes on the ~54% of scoped shipments that lack them, using Snowflake Cortex AI. Evaluate accuracy against the hand-labeled seed set at HS-2/HS-4/HS-6 levels. Produce a unified `hs_code` column in a new Silver-plus model that downstream phases (6-8) will use.

---

## Context — what Phase 4 gave us and where the gap is

Phase 4 landed 52,611 in-scope shipments in `LADINGLENS_DB.SILVER.SILVER_BOL_SHIPMENTS`. Of these:

- **~24,000 rows have an HS code from the source field or regex extraction** (`harmonized_number_final IS NOT NULL`, ~46% of scoped)
- **~28,000 rows have `harmonized_number_final IS NULL`** — these need LLM classification

The `text` field on the NULL-HS rows carries the raw commercial description as filed with CBP (examples verified during Phase 3):
- `"COLD ROLLED STAINLESS STEEL COILS 15 BUNDLES"` → clearly HS 7219
- `"PAPER AND PAPERBOARD 39 PACKAGES"` → clearly HS 4823
- `"HOUSEHOLD GOODS AND PERSONAL EFFECTS"` → ambiguous, no confident classification possible
- `"BMW AUTOMOTIVE PARTS"` → HS 8708 (vehicle parts)
- `"EMPTY CONTAINER"` → not a real product, unclassifiable

Ground truth: `data/labels/hs_eval_seed.csv` — 30 hand-labeled rows with `correct_hs_6` codes (24 real HS-6 codes, ~6 marked `999999` for genuinely ambiguous descriptions). This is Phase 5's evaluation set.

Reference table for prompt context: `LADINGLENS_DB.BRONZE.BRONZE_HTS` — 26,750 HTS lines including description text at each level (hs2/hs4/hs6/hs8/hs10).

Cortex is unblocked on this account (verified in Phase 4 embedding step). `AI_CLASSIFY`, `AI_COMPLETE`, and `EMBED_TEXT_768` all work.

---

## Deliverables

- [ ] `dbt/models/silver/int_hs_candidates.sql` — for each NULL-HS shipment, retrieve top-N candidate HS codes via embedding similarity between product `text` and HTS `description` (retrieval-augmented classification)
- [ ] `dbt/models/silver/int_hs_classified.sql` — call Cortex `AI_COMPLETE` (or `AI_CLASSIFY`) on the NULL-HS rows with the retrieved candidates as context; parse the response into an HS-6 code
- [ ] `dbt/models/silver/silver_bol_shipments_classified.sql` — unified table with `hs_code` populated from all three sources: source field, regex extraction, LLM classification. Add `hs_source` column indicating which method produced it.
- [ ] `dbt/analyses/hs_classifier_accuracy.sql` — evaluates classifier predictions against `hs_eval_seed.csv` at HS-2, HS-4, HS-6 levels
- [ ] `dbt/seeds/hs_eval_seed.csv` (already in `data/labels/`, needs to become a dbt seed) — the 30-row hand-labeled ground truth
- [ ] Documented final accuracy numbers in `data/sources.md`
- [ ] All dbt tests pass on the new models

---

## Claude Code Prompt

```
You are in Phase 5 of LadingLens. Phases 1-4 are complete. Read ./LadingLens.md, ./docs/phases/phase-05-hs-classification.md, and ./data/sources.md before starting.

STATE RECAP:
- silver_bol_shipments has 52,611 rows; ~46% have harmonized_number_final populated, ~54% NULL.
- Cortex is unblocked on this account. Verified functions: EMBED_TEXT_768, AI_COMPLETE, AI_CLASSIFY.
- Resource monitor LADINGLENS_CAP active at 50 credit cap.
- data/labels/hs_eval_seed.csv contains 30 hand-labeled (product_description, correct_hs_6) pairs — 24 with real HS-6 codes and 6 marked '999999' for genuinely ambiguous descriptions.
- Reference tariff schedule in LADINGLENS_DB.BRONZE.BRONZE_HTS (26,750 rows) has description text at every HS level.
- Key-pair auth working; dbt build works; all Phase 4 tests pass.

YOUR TASK:
Build a retrieval-augmented HS classifier using Cortex, evaluate accuracy at three levels, and produce a unified silver_bol_shipments_classified model that downstream Phase 6+ will consume.

CONSTRAINTS:
- All logic in dbt models. No standalone Python scripts.
- Use SNOWFLAKE.CORTEX.EMBED_TEXT_768 for HTS description embeddings and product-text embeddings.
- Use SNOWFLAKE.CORTEX.AI_COMPLETE with a small model (e.g., 'llama3.1-8b' or 'mistral-large2') for classification. Do NOT use frontier models — cost matters, accuracy on this task is what we measure.
- Restrict classification calls to distinct product_text values (deduplicated) not raw rows — critical for cost control.
- Env vars from .env; do not modify credentials files.
- Budget: expected Cortex spend for the full Phase 5 is $5-15. Monitor via CORTEX_FUNCTIONS_USAGE_HISTORY after each major step and stop if any single step exceeds 5 credits before completion.

===========================================
STEP 0 — CONVERT hs_eval_seed.csv INTO A DBT SEED
===========================================

The hand-labeled file lives at data/labels/hs_eval_seed.csv but isn't yet a dbt seed. Two actions:

a. Copy it to dbt/seeds/hs_eval_seed.csv (or symlink; either works)
b. Add a schema entry in dbt/seeds/schema.yml:
    seeds:
      - name: hs_eval_seed
        description: "30 hand-labeled BoL product descriptions with correct HS-6 codes. Used to evaluate HS classifier accuracy in Phase 5."
        columns:
          - name: product_description
            description: "Raw text of the shipment product description as filed with CBP"
            tests: [not_null]
          - name: correct_hs_6
            description: "Hand-assigned HS-6 code. '999999' marks descriptions that are too ambiguous for confident classification."
            tests: [not_null]
          - name: notes
            description: "Reason for ambiguous cases, alternate HS candidates, or classification rationale."
c. Run: dbt seed --select hs_eval_seed
   Verify: SELECT COUNT(*) FROM LADINGLENS_DB.RAW.HS_EVAL_SEED — expect 30.

===========================================
STEP 1 — HTS EMBEDDINGS FOR RETRIEVAL
===========================================

Build dbt/models/silver/int_hts_embedded.sql:

- For each row in bronze_hts where hs6 IS NOT NULL, compute an embedding of the description field.
- Materialize as TABLE (or incremental with unique_key=hts_number).
- The output should have columns: hs6, hs4, hs2, description, embedding (VECTOR(FLOAT, 768))
- Deduplicate to one embedding per hs6 (pick the shortest/most-general description at each hs6 level).

SQL sketch:

WITH hts_hs6 AS (
    SELECT
        hs6,
        MIN(hs4) AS hs4,       -- consistent across siblings
        MIN(hs2) AS hs2,
        MIN(description) AS description  -- pick shortest as representative
    FROM {{ ref('bronze_hts') }}
    WHERE hs6 IS NOT NULL
      AND description IS NOT NULL
    GROUP BY hs6
)
SELECT
    hs6, hs4, hs2, description,
    SNOWFLAKE.CORTEX.EMBED_TEXT_768('e5-base-v2', description) AS embedding
FROM hts_hs6

Expected: ~5,000 distinct HS-6 codes embedded.

Report Cortex spend after this step:
    SELECT SUM(TOKEN_CREDITS) AS credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY
    WHERE START_TIME >= DATEADD('hour', -1, CURRENT_TIMESTAMP());

Expected: <0.5 credits. If it exceeds 2 credits, STOP and report — something is embedding raw rows instead of distinct HS codes.

===========================================
STEP 2 — DEDUPED PRODUCT-TEXT UNIVERSE
===========================================

Build dbt/models/silver/int_product_text_universe.sql — the DISTINCT set of NULL-HS product texts that need classification:

WITH null_hs_rows AS (
    SELECT DISTINCT TRIM(text) AS product_text
    FROM {{ ref('silver_bol_shipments') }}
    WHERE harmonized_number_final IS NULL
      AND text IS NOT NULL
      AND LENGTH(TRIM(text)) >= 5
)
SELECT
    product_text,
    SNOWFLAKE.CORTEX.EMBED_TEXT_768('e5-base-v2', product_text) AS embedding
FROM null_hs_rows

Report:
- Row count of distinct product texts (expect roughly 3,000-8,000 — much less than 28K raw rows because commercial descriptions repeat heavily)
- Cortex spend delta after this step

If distinct-text count is close to raw-row count (e.g., >20K distinct), stop and investigate — indicates product_text has too much per-row uniqueness (container numbers embedded in the text?), and we may need to strip metadata before embedding.

===========================================
STEP 3 — RETRIEVAL: TOP-N HS CANDIDATES PER PRODUCT TEXT
===========================================

Build dbt/models/silver/int_hs_candidates.sql:

For each distinct product text, retrieve the top-5 nearest HTS descriptions by cosine similarity:

WITH ranked AS (
    SELECT
        p.product_text,
        h.hs6,
        h.hs4,
        h.hs2,
        h.description AS hts_description,
        VECTOR_COSINE_SIMILARITY(p.embedding, h.embedding) AS sim,
        ROW_NUMBER() OVER (PARTITION BY p.product_text ORDER BY VECTOR_COSINE_SIMILARITY(p.embedding, h.embedding) DESC) AS rank
    FROM {{ ref('int_product_text_universe') }} p
    CROSS JOIN {{ ref('int_hts_embedded') }} h
)
SELECT product_text, hs6, hs4, hs2, hts_description, sim, rank
FROM ranked
WHERE rank <= 5

Note: this is a big cross join — distinct products × 5000 HS codes × 768-dim cosine = expensive but bounded. Estimate: ~40M pairwise computations. On XS warehouse should run in 2-5 minutes.

Materialize as TABLE.

Report:
- Row count of candidates (should be ~5 × distinct product count)
- Sample the top-5 candidates for 3 known product texts to verify quality:
    SELECT product_text, rank, hs6, hts_description, ROUND(sim, 3) AS sim
    FROM {{ ref('int_hs_candidates') }}
    WHERE product_text IN (
        'COLD ROLLED STAINLESS STEEL COILS',   -- if this text appears verbatim
        'AUTOMOTIVE SPARE PARTS',
        'MACARONI PRODUCTS'
    )
    ORDER BY product_text, rank;

Expected: top-1 candidate should look "obviously right" for at least 2 of 3 samples.

===========================================
STEP 4 — LLM CLASSIFICATION WITH RETRIEVAL CONTEXT
===========================================

Build dbt/models/silver/int_hs_classified.sql:

For each product text, aggregate the top-5 candidates into a prompt and call AI_COMPLETE. Prompt design:

WITH candidates AS (
    SELECT
        product_text,
        LISTAGG(
            '  - HS ' || hs6 || ': ' || hts_description,
            CHR(10)
        ) WITHIN GROUP (ORDER BY rank) AS candidate_block
    FROM {{ ref('int_hs_candidates') }}
    GROUP BY product_text
),
prompted AS (
    SELECT
        product_text,
        candidate_block,
        'You are a customs classification expert. Given a shipment product description ' ||
        'and 5 candidate HS-6 codes retrieved by semantic similarity, choose the single ' ||
        'most-likely HS-6 code. If the description is too vague to classify confidently ' ||
        '(e.g., "GENERAL CARGO", "HOUSEHOLD GOODS"), respond with 999999.' || CHR(10) ||
        CHR(10) ||
        'Product description: ' || product_text || CHR(10) ||
        CHR(10) ||
        'Candidate HS codes:' || CHR(10) ||
        candidate_block || CHR(10) ||
        CHR(10) ||
        'Respond ONLY with the 6-digit HS code (no explanation, no HS prefix, no dots). ' ||
        'Example valid responses: 720719, 870899, 999999.' AS prompt
    FROM candidates
)
SELECT
    product_text,
    TRIM(SNOWFLAKE.CORTEX.AI_COMPLETE('llama3.1-8b', prompt)) AS raw_response,
    prompt
FROM prompted

Materialize as TABLE (incremental if possible with unique_key=product_text).

Post-process to parse the response — the model may respond with extra chars despite the instruction. Add a downstream column:

    REGEXP_SUBSTR(raw_response, '\\d{6}') AS predicted_hs_6

Report:
- Row count classified (should equal distinct product text count)
- Cortex spend delta
- Sample 20 (product_text, raw_response, predicted_hs_6) rows to verify parsing works
- Any rows where predicted_hs_6 IS NULL after regex extraction (model returned no valid 6-digit code)

If Cortex spend exceeds 8 credits at this step, STOP and report.

===========================================
STEP 5 — UNIFIED SILVER FACT TABLE
===========================================

Build dbt/models/silver/silver_bol_shipments_classified.sql:

SELECT
    s.*,  -- all columns from silver_bol_shipments
    COALESCE(s.harmonized_number_final,
             c.predicted_hs_6) AS hs_code,
    CASE
        WHEN s.hs_source IS NOT NULL THEN s.hs_source
        WHEN c.predicted_hs_6 IS NOT NULL AND c.predicted_hs_6 != '999999' THEN 'llm_classified'
        WHEN c.predicted_hs_6 = '999999' THEN 'llm_unclassifiable'
        ELSE 'unresolved'
    END AS hs_source_final,
    LEFT(COALESCE(s.harmonized_number_final, c.predicted_hs_6), 4) AS hs_4_final,
    LEFT(COALESCE(s.harmonized_number_final, c.predicted_hs_6), 2) AS hs_2_final
FROM {{ ref('silver_bol_shipments') }} s
LEFT JOIN {{ ref('int_hs_classified') }} c
    ON TRIM(s.text) = c.product_text

Materialize as TABLE. This is the final Silver fact table that downstream Phase 6-8 will use.

Report:
- Total rows (should equal silver_bol_shipments = 52,611)
- Distribution by hs_source_final: source_field / regex_from_text / llm_classified / llm_unclassifiable / unresolved
- Distribution by HS-2 chapter (expect 84/87/39/73 dominance to persist)

===========================================
STEP 6 — CLASSIFIER ACCURACY EVALUATION
===========================================

Build dbt/analyses/hs_classifier_accuracy.sql:

Evaluate against the 30 rows in hs_eval_seed. For each seed row, look up the classifier's prediction (matching on product_description = text field content), and compare at three levels.

WITH seed AS (
    SELECT
        product_description,
        correct_hs_6,
        LEFT(correct_hs_6, 4) AS correct_hs_4,
        LEFT(correct_hs_6, 2) AS correct_hs_2
    FROM {{ ref('hs_eval_seed') }}
),
predicted AS (
    SELECT
        product_text,
        predicted_hs_6,
        LEFT(predicted_hs_6, 4) AS predicted_hs_4,
        LEFT(predicted_hs_6, 2) AS predicted_hs_2
    FROM {{ ref('int_hs_classified') }}
),
joined AS (
    -- Fuzzy match: seed product_description may be a subset of the full text field.
    -- Use LIKE-based join. If exact matches yield zero, that's a data-alignment issue to flag.
    SELECT
        s.product_description,
        s.correct_hs_6, s.correct_hs_4, s.correct_hs_2,
        p.predicted_hs_6, p.predicted_hs_4, p.predicted_hs_2
    FROM seed s
    LEFT JOIN predicted p
        ON UPPER(p.product_text) LIKE '%' || UPPER(s.product_description) || '%'
       OR UPPER(s.product_description) LIKE '%' || UPPER(p.product_text) || '%'
)
SELECT
    COUNT(*) AS total_seed_rows,
    COUNT(predicted_hs_6) AS classified_seed_rows,

    -- Overall accuracy including unclassifiable (999999)
    SUM(CASE WHEN correct_hs_6 = predicted_hs_6 THEN 1 ELSE 0 END) AS exact_hs6_matches,
    SUM(CASE WHEN correct_hs_4 = predicted_hs_4 THEN 1 ELSE 0 END) AS hs4_matches,
    SUM(CASE WHEN correct_hs_2 = predicted_hs_2 THEN 1 ELSE 0 END) AS hs2_matches,

    -- Accuracy excluding rows where seed marked ambiguous (999999)
    SUM(CASE WHEN correct_hs_6 != '999999' AND correct_hs_6 = predicted_hs_6 THEN 1 ELSE 0 END) AS clean_hs6_matches,
    SUM(CASE WHEN correct_hs_6 != '999999' THEN 1 ELSE 0 END) AS clean_total,

    ROUND(100.0 * SUM(CASE WHEN correct_hs_6 = predicted_hs_6 THEN 1 ELSE 0 END) / COUNT(*), 1) AS overall_hs6_pct,
    ROUND(100.0 * SUM(CASE WHEN correct_hs_4 = predicted_hs_4 THEN 1 ELSE 0 END) / COUNT(*), 1) AS overall_hs4_pct,
    ROUND(100.0 * SUM(CASE WHEN correct_hs_2 = predicted_hs_2 THEN 1 ELSE 0 END) / COUNT(*), 1) AS overall_hs2_pct
FROM joined;

Also produce a per-row diagnostic view for inspection:

SELECT
    joined.product_description,
    joined.correct_hs_6,
    joined.predicted_hs_6,
    CASE WHEN joined.correct_hs_6 = joined.predicted_hs_6 THEN '✅ exact' 
         WHEN joined.correct_hs_4 = joined.predicted_hs_4 THEN '➖ hs4-only' 
         WHEN joined.correct_hs_2 = joined.predicted_hs_2 THEN '➖ hs2-only' 
         ELSE '❌ miss' END AS match_level
FROM joined
ORDER BY match_level, product_description;

Report both.

===========================================
STEP 7 — DBT TESTS ON NEW MODELS
===========================================

Add tests to dbt/models/silver/schema.yml for the new models:

- silver_bol_shipments_classified:
    - not_null: identifier, container_number, golden_supplier_id, golden_consignee_id, hs_code, hs_source_final
    - accepted_values: hs_source_final IN ('source_field', 'regex_from_text', 'llm_classified', 'llm_unclassifiable', 'unresolved')
    - Row count is 52,611 (equals silver_bol_shipments)

Run: dbt test. Report which tests pass/fail.

===========================================
STEP 8 — DOCUMENTATION
===========================================

Append to data/sources.md a Phase 5 wrap section:

    Phase 5 wrap — HS Classification:
    Filled in HS codes for the ~54% of Silver in-scope shipments that lacked them,
    using Cortex retrieval-augmented classification. Approach: embed HTS descriptions
    with e5-base-v2, embed shipment product texts, retrieve top-5 nearest HS-6
    candidates per shipment text via cosine similarity, then call AI_COMPLETE with
    the candidates as context to select the best match.
    
    Final coverage:
    - source_field: X rows (Y%)
    - regex_from_text: X rows (Y%)
    - llm_classified: X rows (Y%)
    - llm_unclassifiable: X rows (Y%) — LLM correctly returned 999999 for ambiguous
      inputs like "GENERAL CARGO", "HOUSEHOLD GOODS"
    - unresolved: X rows (Y%) — remaining edge cases where LLM returned no valid code
    
    Accuracy against 30-row hand-labeled seed:
    - HS-6 (exact subheading): X%
    - HS-4 (heading): X%
    - HS-2 (chapter): X%
    
    Total Cortex spend for Phase 5: $X.XX

    Interpretation: [fill in based on results — e.g., "HS-2 accuracy at Y% is sufficient
    for chapter-level tariff exposure computation in downstream phases. Row-level
    HS-6 accuracy at X% reflects the inherent ambiguity of short commercial
    descriptions; production systems typically use classifier confidence to trigger
    human review on uncertain predictions."]

Fill in the actual numbers from the analyses above.

Also update data/sources.md's Phase 4 open items section — REMOVE the ~54% HS coverage
gap since Phase 5 has addressed it (or update to reflect the residual "unresolved" count if any).

===========================================
EXECUTION ORDER & CHECKPOINTS
===========================================

Do NOT run all steps in a single silent sweep. Pause at these checkpoints and report:

CHECKPOINT A — after Step 2 (product text universe):
- Report distinct product text count and Cortex spend so far
- If distinct count > 20K, STOP and ask before continuing

CHECKPOINT B — after Step 3 (candidate retrieval):
- Report sample candidate quality for 3 known product texts
- If top-1 candidates look obviously wrong for majority of samples, STOP and iterate

CHECKPOINT C — after Step 4 (LLM classification):
- Report distinct classifications made + parsing failures + Cortex spend
- If Cortex spend > 8 credits, STOP
- If parsing failure rate > 10%, STOP and iterate on the prompt

CHECKPOINT D — after Step 6 (accuracy evaluation):
- Report all three accuracy metrics + per-row diagnostic
- If HS-6 accuracy < 30%, we discuss whether to iterate on prompt/model
- If HS-6 accuracy is in 30-70% range, we accept and move to Step 7

Do NOT commit. I will review the final numbers before greenlighting commit.

===========================================
GOTCHAS
===========================================

1. Cortex model choice matters. llama3.1-8b is a good default (cheap + accurate on classification). If accuracy is low, try mistral-large2 which sometimes wins on structured extraction. Do not use claude-3-5-sonnet or gpt-4 class models — 10x more expensive with marginal gain on this specific task.

2. The 30-row seed set has 6 rows marked 999999. Report accuracy both including and excluding these rows. The LLM is expected to return 999999 on ambiguous inputs — if it correctly returns 999999 for the 6 ambiguous rows, that's a *positive* signal, not a miss.

3. The seed set's product_description column is verbatim text from BoL rows. The match to int_hs_classified should be on the FULL text field, not the truncated seed. Verify the join works — if it returns zero matches on all 30 seed rows, the join is broken and needs debugging.

4. Some product texts have embedded HS codes in the raw text (Phase 3 finding: 11 of 30 seed rows had HS codes embedded). These already got captured by the regex extraction in Phase 4's Bronze layer, so they should have harmonized_number_final populated and NOT be routed to LLM classification. Verify.

5. If Cortex returns rate-limit errors (429), it means you're hitting the concurrent-request cap. Wrap the AI_COMPLETE call in a slower dbt configuration (e.g., threads: 1) or add explicit throttling. Rare on XS warehouse but possible if 3000+ classifications fire in parallel.
```

---

## Your Tasks (Human)

- [ ] **Watch checkpoints B and D closely.** These are your two decision moments — candidate quality (are the top-5 HS candidates reasonable?) and final accuracy. Everything else is mechanical.
- [ ] **Approve the Cortex model choice.** llama3.1-8b is my default recommendation. If Phase 5 accuracy comes in weak, we may want to try mistral-large2 which sometimes wins on structured extraction tasks. Cost delta is small.
- [ ] **Screenshot the accuracy numbers** once they land — HS-2, HS-4, HS-6 accuracy is a resume artifact.
- [ ] **Sanity-check the per-row diagnostic.** If several rows show `❌ miss` on obviously-classifiable products (like "COLD ROLLED STAINLESS STEEL COILS"), the prompt needs iteration.
- [ ] **Commit + push after all checkpoints pass.**

---

## Success Criteria

- All 52,611 rows in `silver_bol_shipments_classified` have a non-null `hs_code`
- HS-2 accuracy against seed ≥ 70% (chapter-level should be easy)
- HS-4 accuracy against seed ≥ 50% (heading-level is harder)
- HS-6 accuracy against seed ≥ 30% (subheading-level is the hardest, small variations are OK)
- 999999-unclassifiable count is small (<5% of LLM classifications) — if this is high, the prompt is being too conservative
- Total Cortex spend for Phase 5 ≤ 15 credits
- All dbt tests pass

## Gotchas

- **Retrieval quality > prompt quality.** If the top-5 HS candidates are wrong, no prompt engineering saves you. Spend most iteration time on the embedding step if accuracy is weak.
- **HS classification is genuinely hard.** Even human customs brokers disagree on marginal cases (was that "STAINLESS STEEL COIL" cold-rolled 7219 or hot-rolled 7220?). Don't chase perfect accuracy.
- **The unified column matters more than the accuracy number.** Downstream Phase 6-8 doesn't care if 40% or 60% of shipments are LLM-classified vs source-field. It cares that every row has an HS code.
- **Cost creep is real.** Distinct-text dedup is what keeps this cheap. If Claude Code tries to classify raw rows instead of distinct texts, cost balloons 10x. Verify the row count at Step 2 is small (thousands, not tens of thousands).
