# Phase 4 — dbt Bronze/Silver + Entity Resolution

**Duration:** ~2 days (this is the hardest phase)
**Depends on:** Phase 3 (EDA findings, target scope, cleaning rules identified)
**Goal:** Build the dbt medallion pipeline. Bronze = typed and deduplicated raw. Silver = cleaned + entity-resolved. Produce golden supplier records that recruiters can look at and immediately understand what "MDM" means.

---

## Context

Entity resolution is the marquee data-engineering skill of this project. Most portfolio projects skip it. You will not.

The approach is a three-stage matcher:
1. **Deterministic pass** — legal-suffix stripping, case/punctuation normalization, obvious matches.
2. **Blocking** — group candidate pairs by first-N-chars and country to make the pairwise-match tractable.
3. **Embedding + probabilistic match** — Snowflake Cortex `AI_EMBED` to vectorize normalized names, then `VECTOR_COSINE_SIMILARITY` inside blocks; threshold-tuned on a labeled pair set.

The Cortex embedding function is the "hot new tool" that makes this a Snowflake-native ER pipeline instead of a Python-in-a-notebook toy.

---

## Deliverables

- [ ] `dbt/models/bronze/` — typed + deduplicated raw for all 4 sources
- [ ] `dbt/models/silver/` — cleaned + normalized + entity-resolved
- [ ] `dbt/models/silver/int_supplier_name_normalized.sql` — normalization SQL
- [ ] `dbt/models/silver/int_supplier_blocking.sql` — blocking key generation
- [ ] `dbt/models/silver/int_supplier_pair_candidates.sql` — pair generation within blocks
- [ ] `dbt/models/silver/silver_supplier_golden.sql` — the golden supplier records table
- [ ] `dbt/models/silver/silver_consignee_golden.sql` — same for consignees
- [ ] `dbt/models/silver/silver_bol_shipments.sql` — cleaned shipments joined to golden IDs
- [ ] `dbt/tests/` — dbt tests: not_null, unique, accepted_values, relationships
- [ ] `dbt/analyses/er_evaluation.sql` — precision/recall vs. labeled pairs
- [ ] `data/labels/supplier_pairs_labeled.csv` — ~100 hand-labeled positive/negative pairs (from user)

---

## Claude Code Prompt

```
You are in Phase 4 of LadingLens. Phases 1-3 are complete. Read ./LadingLens.md, ./docs/phases/phase-04-dbt-and-er.md, ./docs/eda-findings.md, and ./config/target_scope.yml before starting.

Your task: build the dbt Bronze and Silver layers, including a Snowflake-native entity resolution pipeline using Cortex AI_EMBED and VECTOR_COSINE_SIMILARITY.

Constraints:
- All logic lives in dbt models. No standalone Python scripts for cleaning.
- Bronze models are 1:1 with raw tables but typed, deduplicated, and with an ingested_at column preserved.
- Silver models are cleaned, normalized, and entity-resolved. Use dbt refs, not hardcoded schemas.
- Add dbt tests to every model. Minimum: not_null on primary keys, unique on golden IDs, relationships between fact and dim.
- Use dbt macros where the same transformation is applied multiple times.
- Filter to config/target_scope.yml scope in the Silver layer, NOT in Bronze — keep Bronze complete.

Please build:

1. dbt/models/bronze/bronze_hts.sql
   - Typed columns from RAW.HTS_TARIFF_SCHEDULE
   - Parse hts_number into hs2, hs4, hs6, hs8, hs10
   - Deduplicate on hts_number
   - Cast rate columns to NUMBER after stripping "%" and "Free"→0

2. dbt/models/bronze/bronze_bol.sql
   - Typed columns from RAW.BOL_SHIPMENTS_ICEBERG
   - Deduplicate on bill_of_lading_number + arrival_date + shipper_name_raw
   - Cast weight_kg, teu to NUMBER; arrival_date to DATE

3. dbt/models/bronze/bronze_10k.sql
   - Typed columns from RAW.SEC_10K_FILINGS
   - Deduplicate on cik + filing_date
   - Length columns for item_1a_text, item_7_text

4. dbt/models/bronze/bronze_comtrade.sql
   - Typed columns; deduplicate on reporter+partner+hs6+period_year

5. dbt/macros/normalize_company_name.sql
   - A macro that takes a column name and returns a normalized string:
     - LOWER
     - Strip legal suffixes: "co", "corp", "corporation", "inc", "incorporated", "ltd", "limited", "llc", "llp", "gmbh", "co ltd", "sa", "sarl", "bv", "ag", "kk", "spa", "srl", "pty", "plc"
     - Strip punctuation and extra whitespace
     - Strip common noise: "the ", trailing " group", " international", " global", " trading", " co"
     - Return the normalized string

6. dbt/models/silver/int_supplier_name_normalized.sql
   - Reads bronze_bol
   - Applies the normalize_company_name macro to shipper_name_raw AS shipper_name_norm
   - Adds a blocking_key = LEFT(shipper_name_norm, 8) || '|' || shipper_country
   - Groups exact-match norm+country as first-pass canonical, using MIN(raw_name) as the display name

7. dbt/models/silver/int_supplier_pair_candidates.sql
   - Generates all pairs of distinct normalized names within the same blocking_key
   - Uses a WHERE constraint so shipper_name_norm_a < shipper_name_norm_b (avoids duplicates and self-pairs)
   - Adds two columns: name_length_diff = ABS(LEN(name_a) - LEN(name_b)), jaccard_char_bigram_sim (compute in SQL — use a helper macro if needed)

8. dbt/models/silver/int_supplier_embedded.sql
   - For each distinct shipper_name_norm, compute embedding = SNOWFLAKE.CORTEX.EMBED_TEXT_768('e5-base-v2', shipper_name_norm)
   - This is expensive — LIMIT to unique names in scope only. Cache with is_incremental().

9. dbt/models/silver/int_supplier_pair_scored.sql
   - Join int_supplier_pair_candidates to int_supplier_embedded twice (a and b)
   - Compute VECTOR_COSINE_SIMILARITY(emb_a, emb_b) AS embed_sim
   - Combine: match_score = 0.7 * embed_sim + 0.3 * jaccard_char_bigram_sim
   - Classify: match_label = CASE WHEN match_score > 0.92 THEN 'match' WHEN match_score > 0.80 THEN 'review' ELSE 'no_match' END

10. dbt/models/silver/silver_supplier_golden.sql
    - Union-find style: use int_supplier_pair_scored WHERE match_label='match' to build clusters.
    - Implement via recursive CTE or via a Python UDF (snowflake-snowpark) if recursion is easier.
    - Assign a golden_supplier_id (hash-based) to each cluster.
    - Output columns: golden_supplier_id, canonical_name (MIN raw name in cluster), country, raw_name_variants_count, first_seen_date, last_seen_date

11. dbt/models/silver/silver_consignee_golden.sql — identical structure but for consignees.

12. dbt/models/silver/silver_bol_shipments.sql
    - Bronze BoL joined to silver_supplier_golden and silver_consignee_golden by name+country
    - Filters to config/target_scope.yml scope (HS chapters, origin countries)
    - Adds golden_supplier_id, golden_consignee_id, canonical_shipper_name, canonical_consignee_name

13. dbt tests (in a schema.yml per model):
    - unique on golden_supplier_id, golden_consignee_id
    - not_null on primary keys
    - relationships: silver_bol_shipments.golden_supplier_id → silver_supplier_golden.golden_supplier_id
    - accepted_values on match_label

14. dbt/analyses/er_evaluation.sql
    - Joins int_supplier_pair_scored to data/labels/supplier_pairs_labeled.csv (loaded as a seed)
    - Computes precision, recall, F1 at match_score thresholds [0.80, 0.85, 0.90, 0.92, 0.95]
    - Outputs a small results table

15. dbt seeds/supplier_pairs_labeled.csv
    - The user will populate this. Create it as a placeholder with the header: name_a, name_b, country, true_label (1=match, 0=no_match), notes

Run `dbt build` and report:
- Row counts at each layer (bronze vs. silver)
- Entity resolution compression ratio (raw names → golden records) for suppliers and consignees
- Any failing tests, with root cause
- If er_evaluation.sql produces F1 < 0.80, suggest specific tightening (e.g., stricter blocking, higher threshold)

Ask before making any assumption not covered above.
```

---

## Your Tasks (Human)

- [ ] **Hand-label ~100 supplier name pairs.** Take the top 200 raw supplier names from Phase 3 EDA, look at pairs that share a blocking key, and mark true match (1) vs. no match (0). This is critical — Phase 4's F1 score depends on it. Save as `dbt/seeds/supplier_pairs_labeled.csv`.
- [ ] **Review the golden supplier records manually.** Query `SELECT * FROM SILVER.silver_supplier_golden ORDER BY raw_name_variants_count DESC LIMIT 20`. Do these clusters look right? If not, tighten thresholds and re-run.
- [ ] **Screenshot the compression ratio** ("X raw names → Y golden records — Z:1 compression"). This is a headline demo number.
- [ ] **Approve dbt tests.** Run `dbt test` and make sure everything passes before Phase 5.

---

## Success Criteria

- `dbt build` completes with all tests passing.
- Bronze row counts match raw row counts (minus duplicates).
- Silver supplier golden table has a meaningful compression ratio (≥2:1 for messy real BoL data).
- ER F1 score ≥ 0.80 on the labeled pair set (target 0.85+).
- `silver_bol_shipments` has at least 50k rows in scope.

## Gotchas

- **Cortex embedding costs credits.** LIMIT to distinct names in scope only. Don't embed every raw string.
- **Recursive CTE for cluster building** can be slow. If you have >100k distinct names, switch to a Python UDF using networkx connected_components.
- **Threshold tuning is empirical.** Start at 0.92, adjust based on eval results. Don't over-fit to the labeled set — hold out 20% as a test set.
- **This phase can bleed into 2 days.** That's expected. Don't rush ER — it's the resume centerpiece.
