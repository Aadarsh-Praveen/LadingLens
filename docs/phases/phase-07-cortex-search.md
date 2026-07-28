# Phase 7 — Cortex Search over 10-K Risk Factors

**Duration:** ~0.5-1 day
**Depends on:** Phase 2 (SEC 10-K filings loaded), Phase 6 (Gold layer complete)
**Goal:** Publish a Snowflake Cortex Search service over the 10-K/20-F Item 1A risk factor text so the Phase 8 agent can retrieve relevant risk excerpts for any consignee entity. This is the unstructured-data half of the "structured + unstructured fusion" story.

---

## Context

Phase 2 loaded 19 tickers. Phase 4 backfilled 5 more (WMT, HBI, GES, JNPR, TTM) for a total of 24. The `LADINGLENS_DB.RAW.SEC_10K_FILINGS` table has:
- `cik`, `ticker`, `filing_date`, `filing_type` (10-K or 20-F)
- `item_1a_text` — the extracted risk factors section, typically 40-120K characters per filing
- Total: 24 filings × ~80K chars average = ~2M chars of risk factor text

Cortex Search is Snowflake's native RAG service. Point it at a table with text columns, specify which column contains the searchable content plus optional attributes, and Snowflake handles chunking, embedding, indexing, and query-time retrieval. Returns top-K nearest chunks per query.

Phase 8's Cortex Agent will use this service as a "retrieval tool" — when a user asks "what does Nike say about tariff exposure?", the agent calls Cortex Search filtered to `ticker='NKE'`, gets back relevant risk factor chunks, and synthesizes an answer.

---

## Deliverables

- [ ] `dbt/models/gold/dim_ticker.sql` — ticker↔consignee mapping (built from spotlight consignee list + loaded 10-Ks)
- [ ] `dbt/models/gold/fact_10k_risk_chunks.sql` — pre-chunked 10-K text, one row per chunk, with ticker + filing metadata
- [ ] `scripts/publish_cortex_search.sql` — DDL to create the Cortex Search service
- [ ] `scripts/07_cortex_search_smoke_test.sql` — 10 retrieval queries with sample outputs
- [ ] `dbt/models/gold/schema.yml` updates for new models
- [ ] `data/sources.md` — Phase 7 wrap section

---

## Claude Code Prompt

```
Phase 7 — Cortex Search over 10-K risk factors. Read ./LadingLens.md, ./docs/phases/phase-07-cortex-search.md, and ./data/sources.md before starting.

STATE RECAP (verified, do not re-check):
- Phases 1-6 complete and committed. HEAD includes Gold star schema + native SEMANTIC VIEW.
- LADINGLENS_DB.RAW.SEC_10K_FILINGS has 24 rows (tickers loaded in Phase 2 + backfill in Phase 4).
  Confirmed loaded: AAPL, MSFT, NVDA, TSLA, AMZN, WMT, NKE, LULU, PVH, LEVI, DE, CAT, HPQ, AMD,
  WDC, RL, ANET, F, GM, GES, HBI, JNPR, TTM, plus 1-2 others. Verify exact list via
  SELECT DISTINCT ticker FROM LADINGLENS_DB.RAW.SEC_10K_FILINGS.
- Phase 4 also tried WMT, STLA, VWAGY, TTM. STLA remains deferred (regex extraction fails on
  their filing structure), VWAGY confirmed doesn't file 20-F with SEC.
- Cortex AI functions (EMBED_TEXT_768, AI_COMPLETE) are available on this account. Cortex
  Analyst is NOT available but Cortex Search IS — different products under the Cortex
  umbrella with different account-tier gating.
- Resource monitor LADINGLENS_CAP active. Current usage ~18-20 credits of 50.

YOUR TASK:
Build a Cortex Search service over the 10-K risk factor text, chunked appropriately.
Test retrieval quality with 10 questions. Document everything for Phase 8's agent to
consume as a retrieval tool.

CONSTRAINTS:
- Chunking: 800-1200 characters per chunk with 100-200 character overlap. This is a
  standard RAG chunk size that balances retrieval precision (smaller chunks are more
  focused) against context completeness (larger chunks preserve surrounding meaning).
- Attributes on chunks (searchable via WHERE-clause filter at query time):
  ticker, filing_type (10-K/20-F), filing_year
- Do NOT re-run 10-K downloads. If additional tickers surface as needed later, defer.
- All chunking logic in dbt SQL. Snowflake has native string functions for this.
- Total Cortex spend budget for Phase 7: <$5 (Cortex Search service creation embeds
  once, then queries are metered separately at low rate).

===========================================
STEP 0 — Verify Cortex Search is available
===========================================

Quick smoke test to confirm the service DDL is available on this account:

    -- This should succeed (return an empty list, no error) if Cortex Search is available:
    SHOW CORTEX SEARCH SERVICES IN SCHEMA LADINGLENS_DB.SEMANTIC;
    
    -- If error "Cortex Search is not enabled for this account", report immediately.

Also verify the current 10-K population:

    SELECT
      COUNT(*) AS total_filings,
      COUNT(DISTINCT ticker) AS unique_tickers,
      AVG(LENGTH(item_1a_text)) AS avg_text_length,
      MIN(LENGTH(item_1a_text)) AS min_length,
      MAX(LENGTH(item_1a_text)) AS max_length,
      SUM(LENGTH(item_1a_text)) AS total_chars
    FROM LADINGLENS_DB.RAW.SEC_10K_FILINGS
    WHERE item_1a_text IS NOT NULL
      AND LENGTH(item_1a_text) >= 5000;

Report the output. Expected: ~24 filings, ~2M total chars, avg ~80K chars per filing.

CHECKPOINT — do not proceed to Step 1 without confirming both.

===========================================
STEP 1 — Build dim_ticker
===========================================

Build dbt/models/gold/dim_ticker.sql:

The idea: map golden_consignee_id (Phase 4 ER output) to ticker (10-K filing owner) where
we can. This ticker↔consignee link is what enables the Phase 8 agent to answer
"what does Walmart's 10-K say about supply chain risk?" by joining the concentration
analysis (on Walmart's golden_consignee_id) with the 10-K retrieval (on ticker=WMT).

Structure:

SELECT
    ticker,
    company_name,               -- from a hand-curated list, matched to filings
    cik,                        -- from RAW.SEC_10K_FILINGS
    filing_type_latest,         -- most recent filing type: 10-K or 20-F
    filing_date_latest,
    item_1a_length_latest,
    is_supply_chain_relevant,   -- TRUE if item_1a_length >= 5000
    -- Best-effort mapping to golden_consignee_id via fuzzy name match:
    matched_consignee_key,      -- may be NULL if no confident match
    match_confidence            -- 'exact', 'partial', 'none'
FROM ...

Approach — build in three CTEs:

1. `filings_latest` — for each ticker, keep only the latest filing:
    SELECT ticker, cik, filing_type, filing_date, item_1a_text
    FROM (
      SELECT *,
             ROW_NUMBER() OVER (PARTITION BY ticker ORDER BY filing_date DESC) AS rn
      FROM LADINGLENS_DB.RAW.SEC_10K_FILINGS
      WHERE item_1a_text IS NOT NULL
    ) WHERE rn = 1

2. `ticker_to_company` — hand-curated map for the 24 loaded tickers (INLINE as VALUES;
   for tickers where you don't have the company name at hand, use SELECT company_name FROM
   RAW.SEC_10K_FILINGS if that column exists, otherwise use a hand-list):
    
    ticker | company_name
    AAPL   | Apple Inc.
    MSFT   | Microsoft Corporation
    NVDA   | Nvidia Corporation
    TSLA   | Tesla, Inc.
    AMZN   | Amazon.com Inc.
    WMT    | Walmart Inc.
    NKE    | Nike, Inc.
    LULU   | Lululemon Athletica Inc.
    PVH    | PVH Corp.
    LEVI   | Levi Strauss & Co.
    DE     | Deere & Company
    CAT    | Caterpillar Inc.
    HPQ    | HP Inc.
    AMD    | Advanced Micro Devices, Inc.
    WDC    | Western Digital Corporation
    RL     | Ralph Lauren Corporation
    ANET   | Arista Networks, Inc.
    F      | Ford Motor Company
    GM     | General Motors Company
    GES    | Guess?, Inc.
    HBI    | HanesBrands Inc.
    JNPR   | Juniper Networks, Inc.
    TTM    | Tata Motors Limited
    (add any others actually loaded)

3. `consignee_match` — try to match ticker's company_name to silver_consignee_golden.canonical_name:
    
    SELECT tc.ticker, tc.company_name, cg.golden_consignee_id,
           CASE
             WHEN UPPER(cg.canonical_name) = UPPER(tc.company_name) THEN 'exact'
             WHEN UPPER(cg.canonical_name) LIKE '%' || UPPER(SPLIT_PART(tc.company_name, ' ', 1)) || '%' THEN 'partial'
             ELSE 'none'
           END AS match_confidence
    FROM ticker_to_company tc
    LEFT JOIN LADINGLENS_DB.SILVER.SILVER_CONSIGNEE_GOLDEN cg
      ON UPPER(cg.canonical_name) LIKE '%' || UPPER(SPLIT_PART(tc.company_name, ' ', 1)) || '%'
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY tc.ticker
      ORDER BY CASE WHEN UPPER(cg.canonical_name) = UPPER(tc.company_name) THEN 0 ELSE 1 END,
               cg.total_shipments DESC NULLS LAST
    ) = 1

Materialize as TABLE.

Report:
- Row count of dim_ticker (should be 20-24 depending on data availability)
- Distribution of match_confidence (exact / partial / none)
- List the tickers with match_confidence='none' — these are cases where the 10-K filer
  isn't in our BoL consignee data. Expected for TTM (Tata Motors, doesn't ship to itself
  as US importer) and possibly others.

===========================================
STEP 2 — Chunk the 10-K text
===========================================

Build dbt/models/gold/fact_10k_risk_chunks.sql:

Chunk each 10-K's item_1a_text into ~1000-character chunks with 200-character overlap.
This is character-based chunking (not token-based) because Snowflake SQL string functions
don't natively count tokens. 1000 chars ≈ 200-250 tokens on English prose, which is a
standard RAG chunk size.

WITH filings AS (
    SELECT
        ticker,
        cik,
        filing_type,
        filing_date,
        EXTRACT(YEAR FROM filing_date) AS filing_year,
        item_1a_text,
        LENGTH(item_1a_text) AS total_chars
    FROM LADINGLENS_DB.RAW.SEC_10K_FILINGS
    WHERE item_1a_text IS NOT NULL
      AND LENGTH(item_1a_text) >= 5000
),
chunk_positions AS (
    SELECT
        f.ticker, f.cik, f.filing_type, f.filing_date, f.filing_year,
        f.item_1a_text, f.total_chars,
        seq.value * 800 + 1 AS chunk_start   -- start position (1-indexed), stride 800 chars
    FROM filings f,
         LATERAL FLATTEN(input => ARRAY_GENERATE_RANGE(0, CEIL(f.total_chars / 800.0))) seq
),
chunks AS (
    SELECT
        MD5(ticker || '|' || filing_date || '|' || chunk_start) AS chunk_id,
        ticker,
        cik,
        filing_type,
        filing_date,
        filing_year,
        chunk_start,
        LEAST(chunk_start + 999, total_chars) AS chunk_end,
        SUBSTR(item_1a_text, chunk_start, 1000) AS chunk_text
    FROM chunk_positions
    WHERE chunk_start <= total_chars
)
SELECT
    chunk_id,
    ticker,
    cik,
    filing_type,
    filing_year,
    filing_date,
    chunk_start,
    chunk_end,
    LENGTH(chunk_text) AS chunk_length,
    chunk_text
FROM chunks
-- Filter out tiny tail chunks (last chunk of a doc may be <200 chars, not useful)
WHERE LENGTH(chunk_text) >= 200

Materialize as TABLE.

Note on overlap: The chunk stride is 800 chars but chunk width is 1000 chars. This
creates 200-char overlap between consecutive chunks — every chunk's last 200 chars
appear at the start of the next chunk. This preserves context across chunk boundaries
for concepts that span the boundary.

Report:
- Row count of fact_10k_risk_chunks (expected 2,000-3,000 chunks total across 24 filings)
- Chunks per ticker breakdown:
    SELECT ticker, COUNT(*) AS n_chunks, MIN(chunk_length), AVG(chunk_length)::INT AS avg_chunk_length
    FROM {{ ref('fact_10k_risk_chunks') }}
    GROUP BY ticker
    ORDER BY n_chunks DESC;
- Sample 3 random chunks — verify they contain readable prose (not garbled boilerplate,
  not tables, not just headers).

===========================================
STEP 3 — Publish Cortex Search service
===========================================

Build scripts/publish_cortex_search.sql:

CREATE OR REPLACE CORTEX SEARCH SERVICE LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH
  ON chunk_text                                  -- the searchable content column
  ATTRIBUTES ticker, filing_type, filing_year    -- searchable-filter columns
  WAREHOUSE = LADINGLENS_WH                      -- warehouse for indexing
  TARGET_LAG = '1 hour'                          -- max staleness before re-indexing
  EMBEDDING_MODEL = 'snowflake-arctic-embed-m-v1.5'  -- Snowflake's default; or e5-base-v2 if preferred
AS (
    SELECT
        chunk_id,
        chunk_text,
        ticker,
        filing_type,
        filing_year,
        filing_date,
        chunk_start,
        chunk_end
    FROM LADINGLENS_DB.GOLD.FACT_10K_RISK_CHUNKS
);

Snowflake's Cortex Search will:
1. Embed every chunk_text using the specified embedding model
2. Store embeddings in a vector index
3. Enable retrieval via a REST endpoint OR the CORTEX.SEARCH_PREVIEW function

Verify the service was created:

    SHOW CORTEX SEARCH SERVICES IN SCHEMA LADINGLENS_DB.SEMANTIC;
    DESC CORTEX SEARCH SERVICE LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH;

Wait 2-5 minutes for indexing to complete. Then test with a basic query:

SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH',
        '{
            "query": "tariff risk from China imports",
            "limit": 5,
            "columns": ["chunk_text", "ticker", "filing_year"]
        }'
    )
):results;

If this returns 5 chunks with visible tariff-related text, indexing worked and retrieval
is functional. If it returns empty or errors, wait longer for indexing and retry.

Report:
- Service creation SQL and confirmation
- The first successful retrieval preview result

===========================================
STEP 4 — 10-question smoke test
===========================================

Build scripts/07_cortex_search_smoke_test.sql with 10 realistic questions that Phase 8's
agent will translate to Cortex Search calls.

For each question, use SNOWFLAKE.CORTEX.SEARCH_PREVIEW with:
- The natural-language query
- limit: 3 (top 3 chunks)
- columns: ["chunk_text", "ticker", "filing_year"]
- Optional filter on ticker via the filters parameter

Questions:

1. "What tariff-related risks does Apple describe in their 10-K?"
   filter: {"@eq": {"ticker": "AAPL"}}

2. "What supply chain concentration risks does Nike disclose?"
   filter: {"@eq": {"ticker": "NKE"}}

3. "Which risks does Walmart's 10-K mention about China trade policy?"
   filter: {"@eq": {"ticker": "WMT"}}

4. "What does Caterpillar say about steel and aluminum tariffs?"
   filter: {"@eq": {"ticker": "CAT"}}

5. "What foreign currency exchange risks does Ford disclose?"
   filter: {"@eq": {"ticker": "F"}}

6. "What geopolitical risks are described for semiconductors?"
   (no ticker filter — cross-company semantic search)

7. "Which companies mention Section 301 tariffs as a specific risk?"
   (no filter — return top chunks across all filings)

8. "What supply chain diversification strategies do companies describe?"
   (no filter — cross-company query)

9. "How does Tata Motors describe US import risks?"
   filter: {"@eq": {"ticker": "TTM"}}

10. "What does Deere say about agricultural equipment tariff exposure?"
    filter: {"@eq": {"ticker": "DE"}}

For each: record the top-3 chunk text (first 200 chars each), the ticker/year of each,
and whether the result looks relevant to the question.

Report:
- All 10 query outputs
- Success rate (how many returned relevant-looking chunks)
- p50 and p95 query latency
- Any queries that returned 0 results (indicates either indexing gap or query mismatch)

Expected success rate: 8-10 of 10. Cortex Search on chunk-embedded documents is a mature
pattern and should perform well on this scale (24 documents, ~2K chunks).

===========================================
STEP 5 — dbt tests
===========================================

Add dbt tests to dbt/models/gold/schema.yml:

- dim_ticker:
    - unique: ticker
    - not_null: ticker, cik, filing_type_latest
    - accepted_values: filing_type_latest IN ('10-K', '20-F')
    - accepted_values: match_confidence IN ('exact', 'partial', 'none')
- fact_10k_risk_chunks:
    - unique: chunk_id
    - not_null: chunk_id, ticker, chunk_text
    - Row count > 1500 AND < 5000 (sanity bound on chunk count)
    - custom test: chunk_length between 200 and 1000

Run dbt test. Report all pass/fail. Total test count after Phase 7 should be ~40+.

===========================================
STEP 6 — Documentation
===========================================

Append to data/sources.md a Phase 7 wrap section:

    Phase 7 wrap — Cortex Search over 10-K Risk Factors:
    
    Unstructured data pipeline built on top of the 24 loaded 10-K/20-F filings:
    - dim_ticker: 24 rows mapping tickers to CIK, latest filing, and best-effort
      consignee golden IDs (X exact matches, Y partial, Z no match)
    - fact_10k_risk_chunks: [X] chunks totaling [Y]K characters. 1000-char chunks
      with 200-char overlap. Attributes: ticker, filing_type, filing_year.
    - Cortex Search service LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH published
      using snowflake-arctic-embed-m-v1.5 embedding model.
    
    Smoke test: [X] of 10 queries returned relevant chunks. p50 latency [X]ms.
    Cortex Search's chunk-embedding + vector-index approach works well on this
    scale — 24 documents totaling ~2M characters.
    
    Design notes:
    - Character-based chunking (not token-based) chosen because Snowflake SQL
      lacks native token counting. 1000 chars ≈ 200-250 English tokens, a standard
      RAG size.
    - 200-char overlap between chunks preserves context across chunk boundaries
      for risks that span the boundary.
    - Ticker↔consignee mapping is best-effort via fuzzy name match. Some tickers
      (e.g., TTM/Tata Motors as a foreign parent) have no corresponding US-importer
      consignee entity, which is expected and documented.
    
    What Phase 7 unlocks:
    - Phase 8 (Cortex Agent) can now use RISK_FACTORS_SEARCH as a retrieval tool
      to answer "what does [company]'s 10-K say about [topic]?" questions
    - The structured+unstructured fusion story: agent joins concentration analysis
      (from SEMANTIC_VIEW) with risk factor retrieval (from Cortex Search)
      via ticker↔consignee_key link
    
    Cortex spend for Phase 7: ~$1-3 (one-time indexing of ~2M characters, subsequent
    query metering is minimal).
    
    Total dbt tests: [X] pass (up from 37 at end of Phase 6).
    Cumulative Phase 4+5+6+7 data-quality catches: [update from current count].

===========================================
EXECUTION ORDER & CHECKPOINTS
===========================================

CHECKPOINT 0: Cortex Search availability confirmed + 10-K population verified.

CHECKPOINT 1 (after Steps 1-2): dim_ticker built with match distribution reported,
fact_10k_risk_chunks built with chunk-per-ticker breakdown + 3 random chunk samples.

CHECKPOINT 2 (after Step 3): Cortex Search service created, indexed, first retrieval
preview returns relevant chunks.

CHECKPOINT 3 (after Step 4): 10 smoke test queries executed with relevance scores.
If success rate < 7/10, iterate on chunking or embedding model choice.

CHECKPOINT 4 (after Step 5): all dbt tests pass.

Do NOT commit anything. I review the full Phase 7 diff before greenlighting commit.
```

---

## Your Tasks (Human)

- [ ] **Verify Cortex Search is available on your account** BEFORE Claude Code starts. Run this in Snowsight: `SHOW CORTEX SEARCH SERVICES IN SCHEMA LADINGLENS_DB.SEMANTIC;` If it errors with "not enabled," ping me — we may need to fall back to a hand-rolled retrieval using EMBED_TEXT_768 + VECTOR_COSINE_SIMILARITY on the chunks table (similar to Phase 5's UDTF pattern, adapted for retrieval).
- [ ] **Screenshot 2-3 great smoke-test results** — the Nike/Walmart/Apple queries returning specific risk factor language is a demo moment.
- [ ] **Test 1-2 queries yourself** in Snowsight after Cortex Search is published. Type a question relevant to what you personally know about the loaded filings.

---

## Success Criteria

- Cortex Search service `LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH` created and indexed
- `fact_10k_risk_chunks` has 1,500-3,500 rows (in the expected range for 24 filings)
- Smoke test: ≥8 of 10 queries return relevant chunks
- p50 query latency < 500ms
- Total dbt tests: 40+ passing
- Cortex spend for Phase 7: <$5

## Gotchas

- **Indexing takes 2-5 minutes** after `CREATE CORTEX SEARCH SERVICE`. First query may return empty if run immediately. Wait, then retry.
- **Chunk boundaries can split sentences.** A chunk starting mid-sentence is fine for retrieval (embedding still captures the surrounding meaning) but looks weird when shown to a user. Phase 8's agent should present chunks with a note that they're excerpts.
- **Very long filings** (>150K chars) generate 150+ chunks. This is fine for Cortex Search but bloats `fact_10k_risk_chunks`. If total row count is >5,000, chunking may be too aggressive — increase stride from 800 to 1500.
- **Cortex Search attribute filters use JSON syntax** (`{"@eq": {"ticker": "AAPL"}}`), different from SQL WHERE clauses. This is documented in Snowflake's Cortex Search reference.
- **Some 10-K text is boilerplate** ("These forward-looking statements are subject to..."). If retrieval keeps returning boilerplate for every query, consider adding a filter that removes chunks with high boilerplate word density. Not needed for MVP but worth noting.
- **STLA (Stellantis) and VWAGY (Volkswagen) are not in the data.** If your smoke test question asks about them, it will return empty or irrelevant results. Use TTM (Tata Motors) as the foreign-parent example instead. This is a Phase 4 deferral, not a Phase 7 defect.
