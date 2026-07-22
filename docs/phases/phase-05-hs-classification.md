# Phase 5 — HS-Code Auto-Classification

**Duration:** ~1 day
**Depends on:** Phase 4 (silver_bol_shipments), Phase 3 (`data/labels/hs_eval_seed.csv`)
**Goal:** Automatically classify free-text product descriptions into HS codes using Cortex AISQL. Measure and report accuracy. This is the second AI-native pipeline in the project and one of the primary differentiators.

---

## Context

Raw BoL data has messy free-text product descriptions like "cotton knit t-shirt, mens size L" or "integrated circuit, memory, 128GB DRAM" — but often no HS code, or a truncated/incorrect one.

Snowflake's `AI_CLASSIFY` and `AI_COMPLETE` functions can map these to HS codes directly from SQL. That's the wow moment: **classification-as-SQL**, no separate ML infra. But the accuracy depends on prompt design, few-shot examples, and how much of the HS hierarchy you present.

Strategy:
- Two-pass classification: first predict HS-2 (chapter), then HS-6 given the chapter.
- Few-shot with 3-5 examples pulled from HTS itself (real HS descriptions per chapter).
- Fallback to a rule-based keyword lookup for high-confidence exact matches.

---

## Deliverables

- [ ] `dbt/models/silver/int_hs_classification_prompts.sql` — prompt-building SQL
- [ ] `dbt/models/silver/int_hs_predicted.sql` — the AISQL-classified rows
- [ ] `dbt/models/silver/silver_bol_shipments_hs.sql` — final BoL rows with hs_6_predicted, hs_2_predicted, prediction_confidence, prediction_source
- [ ] `dbt/analyses/hs_classifier_evaluation.sql` — accuracy vs. `hs_eval_seed.csv`
- [ ] `docs/hs-classifier-report.md` — findings, prompt iterations, final accuracy
- [ ] `scripts/label_more_hs_samples.py` — a quick CLI to expand the eval set

---

## Claude Code Prompt

```
You are in Phase 5 of LadingLens. Phases 1-4 are complete. Silver layer has cleaned BoL shipments joined to golden supplier IDs. Read ./LadingLens.md and ./docs/phases/phase-05-hs-classification.md before starting.

Your task: build a Snowflake-native HS-code classifier for free-text product descriptions using Cortex AISQL, and rigorously evaluate it.

Constraints:
- All classification logic in dbt models using SNOWFLAKE.CORTEX functions. No Python ML.
- Two-pass: HS-2 first, then HS-6 conditional on the predicted HS-2.
- Include prompt-source-of-truth in the SQL as a comment header.
- Batch inference — do NOT call the LLM per-row in a UDF loop. Use SQL-level batching.
- Track cost: log the number of AISQL calls made.

Please build:

1. dbt/models/silver/int_hs_few_shot_examples.sql
   - From bronze_hts, pick 3 example descriptions per HS-2 chapter (limit to chapters in config/target_scope.yml).
   - Store as (hs_2, example_description_1, example_hs_6_1, example_description_2, ...) so they can be inlined into prompts.

2. dbt/models/silver/int_hs_predicted_hs2.sql
   - Reads distinct product_description_raw from silver_bol_shipments where hs_code_raw IS NULL OR hs_code_raw = ''
   - For each row, build a prompt like:
       "You are an HS code classifier. Given a product description, return ONLY the 2-digit HS chapter number.
        Examples:
        - 'cotton knit shirt' → 61
        - 'DRAM memory chip' → 85
        Description: {product_description_raw}
        HS-2:"
   - Call SNOWFLAKE.CORTEX.COMPLETE('claude-4-sonnet', prompt) — or the equivalent AI_COMPLETE with structured output.
   - Parse the 2-digit response into hs_2_predicted.
   - Add prediction_source = 'cortex_llm' and confidence = 1.0 for now (will refine below).

3. dbt/models/silver/int_hs_predicted_hs6.sql
   - Joins int_hs_predicted_hs2 to int_hs_few_shot_examples on hs_2.
   - Builds a second prompt that includes 3 in-chapter few-shot examples pulled from HTS descriptions.
   - Calls SNOWFLAKE.CORTEX.COMPLETE again to predict hs_6_predicted.
   - Structured output: use AI_CLASSIFY if available with a candidate list (the top 50 hs_6 codes in that chapter from HTS), else AI_COMPLETE with a JSON-parsing wrapper.

4. dbt/models/silver/silver_bol_shipments_hs.sql
   - Left joins silver_bol_shipments to int_hs_predicted_hs6 on product_description_raw
   - Coalesces: hs_6_final = COALESCE(hs_code_raw_normalized_to_6, hs_6_predicted)
   - prediction_source = CASE WHEN hs_code_raw IS NOT NULL THEN 'source_data' ELSE 'cortex_llm' END
   - hs_2_final = LEFT(hs_6_final, 2)

5. dbt seeds/hs_eval_seed.csv
   - Load ./data/labels/hs_eval_seed.csv (the user's 20-50 hand-labeled examples from Phase 3) as a dbt seed.

6. dbt/analyses/hs_classifier_evaluation.sql
   - Joins int_hs_predicted_hs6 to hs_eval_seed on product_description
   - Computes:
     - HS-2 accuracy
     - HS-6 exact-match accuracy
     - HS-6 top-3 (if the LLM returns alternatives)
     - Per-chapter breakdown
     - Confusion matrix at HS-2 level
   - Writes results to LADINGLENS_DB.GOLD.HS_CLASSIFIER_METRICS

7. docs/hs-classifier-report.md — writeup with:
   - Final HS-2 accuracy, HS-6 accuracy
   - Per-chapter accuracy table
   - 5 failure cases with root-cause analysis
   - Prompt iterations attempted and their impact
   - Recommendations if accuracy < 70%

8. scripts/label_more_hs_samples.py
   - CLI that pulls random unlabeled product descriptions from silver_bol_shipments, prompts the user with a code lookup helper, and appends to hs_eval_seed.csv
   - Just makes it easy for the user to grow the eval set

Run `dbt build --select int_hs_predicted+ silver_bol_shipments_hs+` and report:
- HS-2 accuracy on the labeled eval set
- HS-6 exact-match accuracy on the labeled eval set
- Per-chapter accuracy for chapters in scope
- Approximate credit cost (Cortex calls made × known per-call cost)
- Recommended next-step tweaks if accuracy is below target

Target: HS-2 accuracy ≥ 90%, HS-6 exact ≥ 65%. If below, iterate on prompts before declaring done.

Ask before choosing which Cortex model to use if there is ambiguity (Claude 4 Sonnet vs Snowflake Arctic vs Llama variants). Prefer Claude 4 Sonnet for quality, note the cost tradeoff.
```

---

## Your Tasks (Human)

- [ ] **Expand `hs_eval_seed.csv` to 50 labeled rows** if you only had 20 from Phase 3. Use `scripts/label_more_hs_samples.py` — should take 30-45 min.
- [ ] **Review the top 5 failure cases** in `docs/hs-classifier-report.md`. Is the LLM systematically wrong somewhere (e.g., confusing HS 8471 vs 8542)? That's an interview talking point.
- [ ] **Screenshot the per-chapter accuracy table**. Great demo material.
- [ ] **Watch credit usage.** If Cortex COMPLETE calls hit >5% of your trial credits in this phase, cap `int_hs_predicted_hs6` to a sample instead of full silver.

---

## Success Criteria

- HS-2 accuracy ≥ 90% on labeled eval set.
- HS-6 exact-match accuracy ≥ 65% on labeled eval set.
- `silver_bol_shipments_hs` has non-null hs_6_final for ≥ 95% of rows.
- `hs_classifier_evaluation.sql` writes a metrics row to `GOLD.HS_CLASSIFIER_METRICS`.

## Gotchas

- **Cortex COMPLETE cost:** Claude 4 Sonnet is ~$0.003 per 1K input tokens. 100k descriptions × ~200 tokens each ≈ $60. If your trial is tight, sample 10k rows or use a cheaper model (Llama 3.3 70B).
- **AI_CLASSIFY vs AI_COMPLETE:** AI_CLASSIFY with a candidate list is faster and cheaper if HS-6 candidates fit under 128 items. For big chapters, use AI_COMPLETE with structured output (response_format).
- **JSON parsing failures:** LLMs occasionally return malformed JSON. Wrap the parse in TRY_PARSE_JSON and route failures to a review queue.
- **Don't chase 90% HS-6.** 65-75% is realistic for messy real data. The story is: "here's my prompt-engineering journey and human-in-the-loop fallback," not "perfect classifier."
