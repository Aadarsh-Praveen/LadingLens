# Phase 7 — Cortex Search over 10-K Risk Factors

**Duration:** ~1 day
**Depends on:** Phase 2 (SEC 10-K loaded), Phase 3 (sample-risk-passages.md identified)
**Goal:** Build a Cortex Search service over unstructured 10-K text so the copilot can retrieve verbatim supply-chain risk disclosures. This is the "unstructured intelligence" leg of the hackathon problem statement.

---

## Context

Cortex Search is Snowflake's hybrid vector + keyword retrieval service. It handles the RAG-index-lifecycle so you don't have to manage a separate vector database. It also plays natively with Cortex Agents.

You already have the 10-K Item 1A and Item 7 text in `RAW.SEC_10K_FILINGS`. This phase:
1. Chunks it appropriately (~512 tokens, with overlap).
2. Enriches with structured metadata (ticker, filing_date, section, risk_theme).
3. Registers it as a Cortex Search service.
4. Tests retrieval on grounded questions.
5. Extracts structured mentions ("company X has Y% supplier concentration") via `EXTRACT_ANSWER`.

---

## Deliverables

- [ ] `dbt/models/silver/silver_10k_chunks.sql` — chunked 10-K text with metadata
- [ ] `dbt/models/silver/silver_10k_risk_theme_tagged.sql` — chunks tagged with themes via AI_CLASSIFY
- [ ] `scripts/publish_cortex_search.sql` — CREATE CORTEX SEARCH SERVICE DDL
- [ ] `dbt/models/gold/mart_10k_extracted_facts.sql` — structured extractions (supplier concentration %, single-source flags)
- [ ] `notebooks/07_cortex_search_eval.ipynb` — retrieval quality evaluation
- [ ] `docs/rag-eval-report.md` — recall@k, MRR, groundedness sample

---

## Claude Code Prompt

```
You are in Phase 7 of LadingLens. Phases 1-6 are complete. RAW.SEC_10K_FILINGS has ~30-50 10-K filings. Read ./LadingLens.md and ./docs/phases/phase-07-cortex-search.md before starting.

Your task: build a Cortex Search service over 10-K Item 1A + Item 7 text, plus a structured-extraction pipeline that pulls supplier concentration statements as facts.

Constraints:
- Chunk size: 512 tokens with 64-token overlap. Use a token-aware splitter (not char-based).
- Every chunk keeps its ticker, filing_date, section (item_1a or item_7), and chunk_index in metadata for filtered retrieval.
- Use SNOWFLAKE.CORTEX.EMBED_TEXT (Snowflake handles this inside the search service — you just provide text).
- Register the service via CREATE CORTEX SEARCH SERVICE with attribute columns for filtering.

Please build:

1. dbt/models/silver/silver_10k_chunks.sql
   - For each row in bronze_10k, split item_1a_text and item_7_text into ~512-token chunks with 64-token overlap.
   - Use a Snowpark Python UDF that wraps tiktoken (or a simple approximation: chunk on paragraphs, then merge until close to 512 tokens).
   - Output columns: chunk_id (hash of ticker+section+chunk_index), ticker, cik, filing_date, section, chunk_index, chunk_text, chunk_token_count

2. dbt/models/silver/silver_10k_risk_theme_tagged.sql
   - Uses SNOWFLAKE.CORTEX.CLASSIFY_TEXT to tag each chunk with one or more themes from:
     ["supplier_concentration", "geographic_concentration", "tariff_exposure", "regulatory_change", "logistics_disruption", "input_cost_inflation", "labor_disruption", "geopolitical_risk", "other"]
   - Store as risk_themes ARRAY<STRING>.

3. scripts/publish_cortex_search.sql
   - CREATE OR REPLACE CORTEX SEARCH SERVICE ladinglens_10k_search
       ON chunk_text
       ATTRIBUTES ticker, cik, filing_date, section, risk_themes
       WAREHOUSE = LADINGLENS_WH
       TARGET_LAG = '1 hour'
       AS (SELECT chunk_id, chunk_text, ticker, cik, filing_date, section, risk_themes FROM silver_10k_risk_theme_tagged);

4. dbt/models/gold/mart_10k_extracted_facts.sql
   - For each chunk tagged "supplier_concentration" or "geographic_concentration":
     - Call SNOWFLAKE.CORTEX.EXTRACT_ANSWER (or AI_COMPLETE with structured output) to extract:
       {
         "concentration_percentage": FLOAT or NULL,
         "supplier_or_country_named": STRING or NULL,
         "hs_or_product_named": STRING or NULL,
         "verbatim_quote": STRING (max 400 chars)
       }
   - Output columns: ticker, filing_date, chunk_id, extraction_json, concentration_percentage, verbatim_quote

5. notebooks/07_cortex_search_eval.ipynb
   - Load ~10 hand-crafted eval queries (create at data/labels/rag_eval_queries.csv with columns query, expected_ticker, expected_theme, notes)
   - For each query, call the Cortex Search service with k=5 and k=10.
   - Compute:
     - recall@5, recall@10 (how often is the "expected" ticker's chunk in the top-k?)
     - MRR (mean reciprocal rank)
     - Groundedness sample: for 3 queries, use Claude/GPT to judge whether the top-1 chunk actually answers the query (human review at least once)
   - Chart: retrieval quality by query type (supplier vs. geographic vs. tariff)

6. Also create data/labels/rag_eval_queries.csv seed with 10 queries such as:
   - "Which apparel companies disclose single-supplier risk?"
   - "What supply-chain disclosures mention China concentration above 50%?"
   - "Which semiconductor firms warn about Section 301 tariffs?"

7. docs/rag-eval-report.md
   - Recall@5, recall@10, MRR
   - 3 sample retrievals with the top chunk shown verbatim
   - Notes on what queries fail and why
   - Recommended improvements (chunk size tuning, hybrid weighting, adding synonyms)

Run everything and report:
- Chunk count total
- Themes distribution (how many chunks in each category)
- Cortex Search service status (READY or LAGGING)
- Retrieval eval numbers with brief commentary
- 3 verbatim examples of extracted concentration facts

Ask before making assumptions about chunking strategy (paragraph-first vs. sentence-first) — I have a preference we can discuss.
```

---

## Your Tasks (Human)

- [ ] **Create `data/labels/rag_eval_queries.csv`** with 10-15 evaluation queries. Base them on the sample risk passages you saved in Phase 3.
- [ ] **Manually rate 3 retrievals** for groundedness — is the top-1 chunk actually answering the query? Save this as evidence in the demo.
- [ ] **Screenshot a great retrieval** — one where Cortex Search returns a verbatim 10-K passage that perfectly answers a supplier-concentration question. Prime demo material.
- [ ] **Verify the Cortex Search service in Snowsight** — it should appear under your database's "Cortex Search" section with status READY.

---

## Success Criteria

- Cortex Search service is registered and returns results in <1 second for k=5.
- `silver_10k_chunks` has at least 500 chunks total.
- Recall@5 ≥ 0.7, MRR ≥ 0.5 on the eval set.
- `mart_10k_extracted_facts` has ≥ 20 rows with non-null verbatim quotes.

## Gotchas

- **Token counting:** if you don't have tiktoken available in Snowpark, approximate as `char_count / 4` and adjust. Don't chunk on characters — that breaks sentences mid-word.
- **AI_CLASSIFY output for multi-label:** it may return one label even when multiple apply. Use two passes if needed (once per theme) or use AI_COMPLETE with a JSON list output.
- **Cortex Search lag:** newly-published services take a few minutes to build. Wait for status=READY before querying.
- **EXTRACT_ANSWER hallucination risk:** for numbers like "X% concentration," the LLM may fabricate. Manually verify at least 5 extractions and reject the mart row if the number doesn't appear in the source text.
