# Phase 2 — Data Acquisition & Raw Ingestion

**Duration:** ~1 day
**Depends on:** Phase 1 (env, Snowflake setup, `LADINGLENS_DB.RAW` schema, ~356MB gzipped BoL CSV in `data/raw/bol/`)
**Goal:** Land all raw source data into `LADINGLENS_DB.RAW`. Three ingest scripts, three data sources, all idempotent.

---

## Context — what changed from the original plan

The original Phase 2 spec assumed we'd pull BoL data from ImportYeti and pair it with UN Comtrade for trade flows. Neither happened. The current, locked plan is:

| Source | Volume | Location | Ingest method |
|---|---|---|---|
| **NIST FEIII 2019 BoL** (primary) | 3.8M rows, 31 cols, 2018 CBP AMS | Local file: `data/raw/bol/export_sample_countries_challenge_with_orgs.csv.gz` (356MB gzipped) | Snowflake `PUT` + `COPY INTO` Iceberg |
| **USITC HTS** (tariff schedule) | ~35,571 lines, 2026 Rev 11 | `hts.usitc.gov/download` | Python script → HTTP download → `COPY INTO` |
| **SEC 10-K filings** (unstructured risk) | ~30 tickers × 1 filing each | EDGAR full-text search | Python script using `sec-edgar-downloader` |

Two more sources are **already in your Snowflake account** via Snowflake Marketplace (Phase 1 subscriptions) — no ingest needed:
- **D&B Shipping Insights Sample** (`DB_SHIPPING_INSIGHTS_SAMPLE.SHARED_SHIPPINGDATA_INSIGHTS_SAMPLE.SHIPPING_INSIGHTS_DATA_SAMPLE`) — 1K rows, 158 cols. Used later for cross-validation.
- **CEIC Shipping Data** (`CEIC_SHIPPING_DATA.MARKETPLACE_LISTINGS.*`) — port activity, freight rates. Used for macro context.

**All three ingest scripts must be idempotent** — safe to re-run without duplicating rows. This is the "production-ready even though it's a static snapshot" pattern.

---

## Deliverables

- [ ] `LADINGLENS_DB.RAW.BOL_SHIPMENTS` — 3.8M rows loaded (as Iceberg if permissions allow, else regular table)
- [ ] `LADINGLENS_DB.RAW.HTS_TARIFF_SCHEDULE` — ~35,000 rows
- [ ] `LADINGLENS_DB.RAW.SEC_10K_FILINGS` — 25-30 filings with Item 1A + Item 7 text
- [ ] `scripts/ingest/01_bol_shipments.py` — NIST CSV → Snowflake
- [ ] `scripts/ingest/02_usitc_hts.py` — USITC HTS downloader + loader
- [ ] `scripts/ingest/03_sec_10k.py` — EDGAR downloader + loader
- [ ] `scripts/verify_raw_ingestion.sql` — sanity checks per table
- [ ] `data/sources.md` — provenance table (URL, license, retrieval date, row count, messiness notes)
- [ ] `config/target_tickers.yml` — ~30 tickers to pull 10-Ks for (electronics + apparel + machinery)

---

## Claude Code Prompt

```
You are in Phase 2 of the LadingLens project. Phase 1 environment setup is complete. Read ./LadingLens.md and ./docs/phases/phase-02-data-acquisition.md for full context.

Your task: build three reproducible ingestion scripts and land three raw data sources into LADINGLENS_DB.RAW in Snowflake.

Data source summary (all static, one-shot ingest, all scripts must be idempotent):

1. NIST FEIII 2019 BoL — a local 356MB gzipped CSV at data/raw/bol/export_sample_countries_challenge_with_orgs.csv.gz (2GB uncompressed, 3,825,304 rows, 31 columns). This is the ONLY BoL source and is on the local filesystem.

2. USITC Harmonized Tariff Schedule — download the latest full HTS in JSON or CSV format from https://hts.usitc.gov/download. Public, no auth.

3. SEC EDGAR 10-K filings — download the most recent 10-K per ticker in config/target_tickers.yml using sec-edgar-downloader (justify choice of library in a comment).

Constraints:
- Load env from ./.env at script start using python-dotenv.
- Use snowflake-connector-python or snowpark; do NOT use SQLAlchemy.
- Every ingest script must be idempotent — either DROP+CREATE, or MERGE-upsert. Do NOT append blindly.
- Log row counts, source URL, and ingested_at timestamp for every load.
- Never commit raw data — everything writes to data/raw/ which is gitignored (already configured in Phase 1).
- Do NOT modify existing files: dbt/profiles.yml, .gitignore, .env, .env.example, dbt/profiles.yml.example.

Please build:

===========================================
1. scripts/ingest/01_bol_shipments.py — NIST BoL loader
===========================================

Prerequisite check: verify data/raw/bol/export_sample_countries_challenge_with_orgs.csv.gz exists. If missing, print instructions to download from https://drive.google.com/open?id=1tMkoOGF9lC6RJXm5DzmFJlvcIprTY0mI and exit.

Steps:
a. Connect to Snowflake using env vars (SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, etc.). If SNOWFLAKE_AUTHENTICATOR=externalbrowser is set, use externalbrowser auth (a browser will open once).

b. First-time setup: create the Iceberg external volume if it doesn't already exist. Use Snowflake-managed storage:
      CREATE EXTERNAL VOLUME IF NOT EXISTS LADINGLENS_ICEBERG_VOL ...
   If the trial account rejects EXTERNAL VOLUME creation (insufficient privileges), catch the error, log a warning, and fall back to a regular TABLE instead of an ICEBERG TABLE. Same downstream schema, so nothing else breaks.

c. Create the target table LADINGLENS_DB.RAW.BOL_SHIPMENTS with these columns (types chosen for NIST's actual data):
      identifier                       NUMBER
      trade_update_date                DATE
      run_date                         DATE
      vessel_name                      VARCHAR
      port_of_unlading                 VARCHAR
      estimated_arrival_date           DATE
      foreign_port_of_lading           VARCHAR
      record_status_indicator          VARCHAR
      place_of_receipt                 VARCHAR
      port_of_destination              VARCHAR
      foreign_port_of_destination      VARCHAR
      secondary_notify_party_1         VARCHAR
      actual_arrival_date              DATE
      consignee_name                   VARCHAR
      consignee_address                VARCHAR
      consignee_contact_name           VARCHAR
      consignee_comm_number_qualifier  VARCHAR
      consignee_comm_number            VARCHAR
      shipper_party_name               VARCHAR
      shipper_address                  VARCHAR
      shipper_contact_name             VARCHAR
      shipper_comm_number_qualifier    VARCHAR
      shipper_comm_number              VARCHAR
      container_number                 VARCHAR
      description_sequence_number      NUMBER
      piece_count                      NUMBER
      text                             VARCHAR
      harmonized_number                VARCHAR
      harmonized_value                 NUMBER
      harmonized_weight                NUMBER
      harmonized_weight_unit           VARCHAR
      identified_orgs                  VARCHAR
      ingested_at                      TIMESTAMP_NTZ  -- ADDED by us, DEFAULT CURRENT_TIMESTAMP()

   Idempotency: use CREATE OR REPLACE TABLE. This wipes the target on re-run, which is correct for a static snapshot.

d. PUT the local gzipped file to LADINGLENS_DB.STAGE.RAW_STAGE:
      PUT file://data/raw/bol/export_sample_countries_challenge_with_orgs.csv.gz
           @LADINGLENS_DB.STAGE.RAW_STAGE/bol/
           AUTO_COMPRESS=FALSE OVERWRITE=TRUE
   AUTO_COMPRESS must be FALSE because the file is already gzipped.

e. COPY INTO the table:
      COPY INTO LADINGLENS_DB.RAW.BOL_SHIPMENTS (
          identifier, trade_update_date, run_date, vessel_name, port_of_unlading,
          estimated_arrival_date, foreign_port_of_lading, record_status_indicator,
          place_of_receipt, port_of_destination, foreign_port_of_destination,
          secondary_notify_party_1, actual_arrival_date, consignee_name,
          consignee_address, consignee_contact_name, consignee_comm_number_qualifier,
          consignee_comm_number, shipper_party_name, shipper_address,
          shipper_contact_name, shipper_comm_number_qualifier, shipper_comm_number,
          container_number, description_sequence_number, piece_count, text,
          harmonized_number, harmonized_value, harmonized_weight,
          harmonized_weight_unit, identified_orgs
      )
      FROM @LADINGLENS_DB.STAGE.RAW_STAGE/bol/export_sample_countries_challenge_with_orgs.csv.gz
      FILE_FORMAT = (
          TYPE = 'CSV'
          SKIP_HEADER = 1
          FIELD_OPTIONALLY_ENCLOSED_BY = '"'
          NULL_IF = ('', 'NULL')
          EMPTY_FIELD_AS_NULL = TRUE
          COMPRESSION = 'GZIP'
      )
      ON_ERROR = 'CONTINUE'
      PURGE = FALSE;
   FIELD_OPTIONALLY_ENCLOSED_BY='"' is critical — the NIST data has commas inside quoted address fields like "Norfolk, Virginia". ON_ERROR='CONTINUE' lets bad rows skip rather than aborting the whole load. Log the number of rows rejected.

f. Post-load verification (log to stdout):
   - COUNT(*) should be very close to 3,825,304
   - COUNT(harmonized_number) — should be ~2.4M (63%)
   - COUNT(identified_orgs) — should be ~725K (19%)
   - MIN/MAX(trade_update_date) — should span roughly 2017-12 to 2018-06

===========================================
2. scripts/ingest/02_usitc_hts.py — USITC HTS loader
===========================================

a. Download the latest HTS in JSON format from https://hts.usitc.gov/reststop/exportList?from=0&to=99&format=JSON&styles=false (this is USITC's actual public endpoint; if it fails, fall back to https://hts.usitc.gov/download and grab the JSON there). Save the raw file to data/raw/hts/hts_<YYYY-MM-DD>.json.

b. Parse the JSON. Each record has fields like: htsno, description, indent, superior, units, general, special, other, footnotes.

c. Flatten into a table LADINGLENS_DB.RAW.HTS_TARIFF_SCHEDULE with columns:
      hts_number VARCHAR       -- e.g., "0101.21.00.10"
      description VARCHAR
      indent NUMBER
      units VARCHAR
      general_rate_text VARCHAR    -- raw string, e.g., "Free" or "3.4%"
      special_rate_text VARCHAR
      column2_rate_text VARCHAR
      footnotes VARCHAR (parsed from array if present)
      hs2 VARCHAR                  -- LEFT(hts_number, 2)
      hs4 VARCHAR
      hs6 VARCHAR
      hs8 VARCHAR
      hs10 VARCHAR
      ingested_at TIMESTAMP_NTZ

   Idempotency: CREATE OR REPLACE TABLE.

d. Write to CSV in data/raw/hts/, PUT to stage, COPY INTO.

e. Post-load verify:
   - COUNT(*) should be ~35,000+
   - COUNT(DISTINCT hs2) should be ~99
   - Sample 5 rows and log them

===========================================
3. scripts/ingest/03_sec_10k.py — SEC 10-K loader
===========================================

a. First create config/target_tickers.yml with this list (drawn from likely importers of HS 61 apparel and HS 85 electronics — the industries with the most tariff exposure):

   electronics:
     - AAPL
     - DELL
     - HPQ
     - NVDA
     - INTC
     - AMD
     - MU
     - WDC
     - CSCO
     - ANET
     - JNPR
   apparel:
     - NKE
     - LULU
     - VFC
     - HBI
     - PVH
     - TPR
     - RL
     - LEVI
     - GES
   machinery_and_industrial:
     - CAT
     - DE
     - PH
     - ETN
     - EMR

b. Install sec-edgar-downloader (justify vs sec-api in a comment: prefer sec-edgar-downloader because it's free, no API key needed, and pulls directly from SEC EDGAR's public HTTPS endpoints).

c. For each ticker, download the most recent 10-K filed 2023-2025. Store the raw HTML/TXT under data/raw/sec/{TICKER}/.

d. Parse each 10-K to extract:
   - cik (from filing header)
   - ticker
   - filing_date
   - filing_url
   - item_1a_text (Risk Factors section)
   - item_7_text (MD&A section)

   Extraction is genuinely hard — 10-K formats vary. Use a regex-based approach that looks for "ITEM 1A", "Item 1A", "1A. Risk Factors" as start markers and "ITEM 1B" / "Item 1B" as end markers. Log any tickers whose Item 1A extraction produced <5000 chars (likely failed) and skip them. Do not fail the whole ingest on parse errors.

e. Load into LADINGLENS_DB.RAW.SEC_10K_FILINGS:
      cik VARCHAR
      ticker VARCHAR
      filing_date DATE
      filing_url VARCHAR
      item_1a_text VARCHAR (up to 16MB)
      item_7_text VARCHAR (up to 16MB)
      item_1a_length NUMBER
      item_7_length NUMBER
      ingested_at TIMESTAMP_NTZ

   Idempotency: MERGE on (cik, filing_date). If a filing already exists, update the text fields (in case parsing improved between runs).

f. Post-load verify:
   - COUNT(*) should be 20-30
   - COUNT(*) WHERE item_1a_length >= 5000
   - Log any tickers that failed to parse

===========================================
4. scripts/verify_raw_ingestion.sql
===========================================

For each of the 3 tables:
   SELECT
     'BOL_SHIPMENTS' AS table_name,
     COUNT(*) AS row_count,
     MIN(ingested_at) AS earliest,
     MAX(ingested_at) AS latest
   FROM LADINGLENS_DB.RAW.BOL_SHIPMENTS
   UNION ALL
   SELECT 'HTS_TARIFF_SCHEDULE', COUNT(*), MIN(ingested_at), MAX(ingested_at) FROM LADINGLENS_DB.RAW.HTS_TARIFF_SCHEDULE
   UNION ALL
   SELECT 'SEC_10K_FILINGS', COUNT(*), MIN(ingested_at), MAX(ingested_at) FROM LADINGLENS_DB.RAW.SEC_10K_FILINGS;

Also include 3 quick-look queries at the bottom:
   -- BoL top consignees by shipment count
   SELECT consignee_name, COUNT(*) AS shipment_count FROM LADINGLENS_DB.RAW.BOL_SHIPMENTS WHERE consignee_name IS NOT NULL GROUP BY 1 ORDER BY 2 DESC LIMIT 20;

   -- HTS top-level chapters
   SELECT hs2, COUNT(*) AS line_count FROM LADINGLENS_DB.RAW.HTS_TARIFF_SCHEDULE GROUP BY 1 ORDER BY 1 LIMIT 10;

   -- SEC 10-Ks loaded
   SELECT ticker, filing_date, item_1a_length, item_7_length FROM LADINGLENS_DB.RAW.SEC_10K_FILINGS ORDER BY ticker;

===========================================
5. data/sources.md
===========================================

A markdown table documenting each of the 3 ingested sources plus the 2 Snowflake Marketplace subscriptions (D&B, CEIC). Columns:
   - Source | URL | License | Retrieval date | Row count | Messiness notes

Fill in with real values discovered during ingestion.

===========================================
Execution plan
===========================================

Please run these scripts in order:
   python scripts/ingest/02_usitc_hts.py    # smallest, fastest, do first to validate Snowflake connection
   python scripts/ingest/03_sec_10k.py      # medium, ~30 filings
   python scripts/ingest/01_bol_shipments.py # largest, PUT will take 5-15 min for 356MB

After all three complete, run scripts/verify_raw_ingestion.sql via `snow sql -f scripts/verify_raw_ingestion.sql` and report the output.

Report back:
- Row counts loaded per table
- Any tickers that failed to parse (with reason)
- Any COPY INTO errors on BoL (rejected rows count)
- Warnings from the verify SQL
- The top 10 BoL consignees list — this is a fun sanity check (we should recognize names like Walmart, Amazon, IKEA, etc.)

Ask me before making any decision not fully specified above. In particular, ask before:
- Choosing between EXTERNAL VOLUME and regular table if Iceberg creation fails
- Modifying the target_tickers.yml list
- Changing extraction heuristics for 10-K parsing if Item 1A repeatedly fails
```

---

## Your Tasks (Human)

- [ ] **Verify the gzipped BoL file is where the script expects it.** Run:
   ```bash
   ls -lh data/raw/bol/export_sample_countries_challenge_with_orgs.csv.gz
   ```
   Should show ~356MB. If not, re-gzip from Phase 1's earlier step.
- [ ] **Watch the PUT upload.** It uploads 356MB over your home internet — expect 5-15 min. Don't kill the process. If it fails midway, `PUT ... OVERWRITE=TRUE` makes re-runs safe.
- [ ] **Watch credit usage in Snowsight.** The full ingest (all 3 scripts) should burn <2 credits on an XS warehouse. If you see credits spike, ping me.
- [ ] **Review the top-20 consignees** after BoL load — quick sanity check that the data is what we think it is. Should see recognizable importers.
- [ ] **Skim `data/sources.md`** once Claude Code writes it — this document becomes an interview talking point.
- [ ] **Do NOT commit anything under `data/raw/`.** Verify with `git status` after ingestion completes.

---

## Success Criteria

- `SELECT COUNT(*) FROM LADINGLENS_DB.RAW.BOL_SHIPMENTS` returns 3,800,000+ (some rows may be rejected by CSV parser, ≤1% loss acceptable)
- `SELECT COUNT(harmonized_number) FROM ...BOL_SHIPMENTS` returns ~2.4M (matches our 62.9% coverage from earlier)
- `SELECT COUNT(identified_orgs) FROM ...BOL_SHIPMENTS` returns ~725K (matches 19%)
- HTS_TARIFF_SCHEDULE has 35,000+ rows spanning 99 chapters
- SEC_10K_FILINGS has 20+ rows with `item_1a_length >= 5000` for the majority
- `data/sources.md` documents each source completely

## Gotchas

- **PUT for a 356MB file takes 5-15 min.** If it fails on `SnowflakeInternalError: 404`, your account URL in `~/.snowflake/connections.toml` might not match the one dbt is using. Check both are `spgkqzk-op14572`.
- **CSV parsing edge cases.** NIST's data has embedded newlines inside quoted `text` (product description) fields. If `COPY INTO` complains about "unexpected end of record," the fix is adding `MULTI_LINE = TRUE` to the FILE_FORMAT. Only add if needed.
- **10-K parsing failures.** Different filers structure Item 1A differently. Expect ~20-30% of tickers to fail on first pass. Iterate on the regex, don't try to be perfect. Failed tickers get logged and skipped, not rescheduled.
- **Iceberg vs regular table.** Snowflake trial accounts sometimes lack the privileges to create an EXTERNAL VOLUME. Script must fall back gracefully to `CREATE OR REPLACE TABLE` (non-Iceberg) if Iceberg creation fails. This is the honest engineering answer.
- **`ON_ERROR = 'CONTINUE'` masks bugs.** After BoL load, always check the rejected-rows count. If more than 1% of rows are rejected, don't just proceed — investigate the pattern first.
