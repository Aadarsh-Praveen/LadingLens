# Phase 2 — Data Acquisition & Raw Ingestion

**Duration:** ~1 day
**Depends on:** Phase 1 (env, Snowflake setup, `LADINGLENS_DB.RAW` schema)
**Goal:** Land all raw source data into `LADINGLENS_DB.RAW` — USITC HTS tariff schedule, SEC 10-K filings for target companies, UN Comtrade sample, and whatever bill-of-lading sample you can get today. Iceberg tables where it matters.

---

## Context

Three data sources are free and instantly available:
1. **USITC Harmonized Tariff Schedule** — https://hts.usitc.gov/download (JSON/CSV). ~35,571 tariff lines. Clean reference table.
2. **SEC EDGAR 10-K filings** — via `sec-edgar-api` or `sec-edgar-downloader` Python packages, or direct EDGAR full-text search. Free.
3. **UN Comtrade** — https://comtradeplus.un.org/, free API with account key. Country-pair HS-level trade flows.

Bill-of-lading data is the fourth source. Options in priority order:
- **A. ImportYeti custom-plan CSV** (if it arrived from your Phase 1 request) — best case.
- **B. CBP AMS Vessel Manifest** direct feed — https://acesso.cbp.gov/ (free, needs registration).
- **C. Sample dataset** from a public GitHub replication package (see `sources/README.md` this phase creates) — fine for prototyping.

Iceberg matters here for the BoL table because it's the biggest volume and the "lakehouse" story is a real resume signal. USITC HTS and Comtrade can stay as regular Snowflake tables since they're small.

---

## Deliverables

- [ ] `LADINGLENS_DB.RAW.HTS_TARIFF_SCHEDULE` — full USITC HTS loaded (all chapters)
- [ ] `LADINGLENS_DB.RAW.SEC_10K_FILINGS` — 20-50 10-K filings for target industry tickers (electronics + apparel)
- [ ] `LADINGLENS_DB.RAW.UN_COMTRADE_FLOWS` — HS-6 US import flows by country, 2023-2025
- [ ] `LADINGLENS_DB.RAW.BOL_SHIPMENTS_ICEBERG` — an Iceberg table holding whatever BoL slice you obtained
- [ ] `scripts/ingest/` — one script per source, idempotent, re-runnable
- [ ] `data/sources.md` — documented provenance: URL, license, retrieval date, row counts, notes on messiness
- [ ] `scripts/verify_raw_ingestion.sql` — a sanity-check query file that runs SELECT COUNT(*) + a preview row per raw table

---

## Claude Code Prompt

```
You are in Phase 2 of the LadingLens project. Phase 1 environment setup is complete. Read ./LadingLens.md and ./docs/phases/phase-02-data-acquisition.md for full context.

Your task: build reproducible ingestion scripts for four raw data sources and land them into LADINGLENS_DB.RAW in Snowflake.

Constraints:
- Never commit raw data to git — everything writes to data/raw/ which is gitignored.
- Every ingestion script must be idempotent — safe to re-run without duplicating rows.
- Log row counts, source URL, and retrieval timestamp for every load.
- Use snowflake-connector-python or snowpark; do NOT use SQLAlchemy for load.
- Uploads to Snowflake go via the internal stage LADINGLENS_DB.STAGE.RAW_STAGE + COPY INTO.

Please build:

1. scripts/ingest/01_usitc_hts.py
   - Downloads the latest USITC HTS from https://hts.usitc.gov/download in JSON format.
   - Parses into a flat table: hts_number, description, unit_of_quantity, general_rate, special_rate, column2_rate, chapter, heading, indent.
   - Handles the Section 301 and 232 columns if present in the JSON.
   - Writes CSV to data/raw/hts/hts_<YYYY-MM-DD>.csv.
   - PUTs to stage, COPY INTO LADINGLENS_DB.RAW.HTS_TARIFF_SCHEDULE.
   - Uses CREATE OR REPLACE TABLE with clear column types (VARCHAR, NUMBER, etc.).

2. scripts/ingest/02_sec_10k.py
   - Uses sec-edgar-downloader or sec-api (whichever is more reliable — pick one and justify in a comment).
   - Accepts a ticker list from config/target_tickers.yml (create this file with ~30 tickers across electronics [AAPL, DELL, HPQ, NVDA, INTC, AMD, TXN, MU, WDC, STX, ANET, CSCO, JNPR, ...] and apparel [NKE, LULU, VFC, HBI, PVH, TPR, RL, GES, LEVI, ...]).
   - Downloads the most recent 10-K per ticker (filings 2023-2025).
   - Extracts Item 1A (Risk Factors) and Item 7 (MD&A) sections as separate text fields — this parsing is tricky; use a regex + heuristics approach and log any tickers that fail to parse.
   - Loads into LADINGLENS_DB.RAW.SEC_10K_FILINGS with columns: cik, ticker, filing_date, filing_url, item_1a_text, item_7_text, ingested_at.

3. scripts/ingest/03_un_comtrade.py
   - Uses the UN Comtrade v1 API (https://comtradeapi.un.org/data/v1/get/C/A/HS?reporterCode=842&period=2024&partnerCode=all&flowCode=M) with the free API key (user provides in .env as UN_COMTRADE_API_KEY).
   - Pulls US imports (reporter=842, flow=M) at HS-6 level for 2023, 2024, 2025.
   - Chunks by year and partner country to stay under rate limits (2 requests/sec free tier).
   - Loads into LADINGLENS_DB.RAW.UN_COMTRADE_FLOWS with columns: reporter, partner, hs6, period_year, trade_value_usd, net_weight_kg, quantity, ingested_at.

4. scripts/ingest/04_bol_shipments.py
   - Checks for a CSV or Parquet file in data/raw/bol/ (from ImportYeti custom-plan export or from a sample dataset).
   - If none exists, prints instructions to obtain one and exits gracefully.
   - Once a file exists, loads into an ICEBERG table LADINGLENS_DB.RAW.BOL_SHIPMENTS_ICEBERG. Use CREATE ICEBERG TABLE with EXTERNAL_VOLUME set to a Snowflake-managed external volume you create in this script if it doesn't exist (call the volume LADINGLENS_ICEBERG_VOL, storage on Snowflake's managed storage — that's the simplest for a trial).
   - Column schema (based on typical BoL fields): bill_of_lading_number, arrival_date, vessel_name, port_of_lading, port_of_unlading, shipper_name_raw, shipper_country, consignee_name_raw, consignee_city, consignee_state, product_description_raw, hs_code_raw, weight_kg, quantity, teu, ingested_at.
   - All name/description columns must be preserved with original casing/whitespace/punctuation — cleaning happens in Phase 4.

5. data/sources.md — a table listing each source, its URL, license, retrieval date, row count you loaded, and 1-2 notes on messiness (e.g., "HTS: none; clean reference table" / "BoL: 42% of rows missing shipper_country; company names have ~30% duplication with punctuation variants").

6. scripts/verify_raw_ingestion.sql — for each of the 4 tables: SELECT COUNT(*), MIN(ingested_at), MAX(ingested_at), and a LIMIT 3 preview.

Run all four ingestion scripts and report:
- Row counts loaded per table
- Any tickers/countries/HS chapters that failed to load and why
- Warnings from the verify SQL

If ImportYeti data is not available, still complete steps 1-3 in full, and for step 4 fall back to using this small public sample BoL dataset for testing: https://raw.githubusercontent.com/import-yeti-samples/bol-sample/main/sample_bol_10k.csv (if that URL fails, tell me and I'll provide an alternative). Document clearly in data/sources.md that this is a placeholder.

Ask me before any decision that is not fully specified above (e.g., which Iceberg external volume type, which target ticker to skip).
```

---

## Your Tasks (Human)

- [ ] **Get a UN Comtrade API key.** Free at https://comtradeplus.un.org/APIAccess. Add to `.env` as `UN_COMTRADE_API_KEY=...`.
- [ ] **Check ImportYeti email** — did the custom-plan request get approved? If yes, download the CSV to `data/raw/bol/` before running the BoL ingest script.
- [ ] **If ImportYeti hasn't responded**, register for CBP ACE at https://acesso.cbp.gov/ (takes ~15 min including identity verification) as a Plan B.
- [ ] **Review `data/sources.md`** after Claude Code finishes — make sure the messiness notes match what you see in the data. This document is a huge interview talking point.
- [ ] **Do NOT commit data**. Double-check `git status` shows no CSVs, JSONs, or Parquets before pushing.

---

## Success Criteria

- All four `SELECT COUNT(*)` queries in `verify_raw_ingestion.sql` return non-zero row counts.
- HTS_TARIFF_SCHEDULE has ~35,000 rows.
- SEC_10K_FILINGS has 25+ rows.
- UN_COMTRADE_FLOWS has thousands of rows.
- BOL_SHIPMENTS_ICEBERG has any rows (even 10k sample is fine for now).
- `data/sources.md` documents each source with URL, license, row count, retrieval date.

## Gotchas

- **UN Comtrade rate limits:** free tier is very slow. Script should retry on 429 and sleep ~500ms between requests.
- **SEC 10-K parsing is genuinely hard.** Item 1A boundaries vary by filer. Some 10-Ks use "ITEM 1A." vs "Item 1A." vs "1A. Risk Factors". Log which tickers failed and iterate; don't try to be perfect.
- **Iceberg external volumes on Snowflake trial:** if you get "insufficient privileges" errors, fall back to a regular Snowflake table temporarily (name it `BOL_SHIPMENTS_ICEBERG` anyway so the rest of the pipeline doesn't care) and note it in `sources.md`. Convert to true Iceberg once you upgrade or resolve permissions.
- **Cost watch:** ingestion runs a warehouse. Make sure `AUTO_SUSPEND=60` is set. Should cost <1 credit total for this phase.
