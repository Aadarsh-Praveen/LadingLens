# Phase 4 — dbt Bronze/Silver + Entity Resolution + Ticker Backfill

**Duration:** ~2-3 days (this is the hardest and most valuable phase)
**Depends on:** Phase 3 (EDA findings, `config/target_scope.yml`, `data/labels/hs_eval_seed.csv`)
**Goal:** Build the dbt medallion pipeline. Bronze = typed and deduplicated raw with sentinel-identifier filtering and regex-extracted HS codes. Silver = cleaned, normalized, entity-resolved with a freight-forwarder classifier and derived country. Golden supplier/consignee records validated against NIST's `identified_orgs` ground truth. Ticker backfill for foreign-parent companies (BMW, Mercedes, Volvo, JLR, Walmart, Stellantis, VW) unblocks the BoL↔10-K join.

---

## Context — what Phase 3 gave us

Phase 3 EDA surfaced five findings that shape Phase 4's design:

1. **Sentinel identifiers (36.2% of BoL rows)** — `YYYY`+`MM`+`00000` placeholder pattern. Cannot be used as shipment keys. Must be filtered in Bronze.
2. **HS coverage is 42% direct + 13.8% in free text** — Bronze should regex-extract HS codes from the `text` field to lift usable HS coverage toward 56%.
3. **Freight forwarders (DHL, Schenker, Expeditors, Yusen, Maersk, Panalpina, CEVA, Kuehne+Nagel, Geodis, DSV) dominate top-20 consignees** — need party-type classification, not filtering.
4. **No `shipper_country`/`consignee_country` column exists** — must derive from `shipper_address`/`consignee_address` text or `foreign_port_of_lading`.
5. **0% BoL↔10-K match rate at top-50 consignees** — real top consignees are foreign-parent OEMs (BMW, Mercedes, Volvo, JLR) not present in current `SEC_10K_FILINGS`. Ticker backfill is mandatory, not optional.

Ground truth for ER validation: `identified_orgs` in BoL (19% of rows populated, 725K labeled examples).

Scope from `config/target_scope.yml`:
- HS chapters: 87 (vehicles), 84 (machinery), 39 (plastics), 61/62 (apparel), 73 (steel)
- Origin countries: DE, BE, VN, ES, GB, FR, MX, CN
- In-scope BoL volume: 598,449 shipments

---

## Deliverables

### Ticker backfill (do FIRST, before dbt models)
- [ ] `config/target_tickers.yml` — updated with parent/ADR tickers (WMT, STLA, VWAGY, TTM, plus retry of DELL/INTC/EMR/JNPR/HBI/GES with explicit CIKs)
- [ ] `scripts/ingest/03_sec_10k.py` — extended to support 20-F filings (foreign private issuers) and to accept explicit CIK overrides
- [ ] Re-run 03_sec_10k.py → target 25+ total filings in `LADINGLENS_DB.RAW.SEC_10K_FILINGS`

### Bronze layer
- [ ] `dbt/models/bronze/bronze_hts.sql`
- [ ] `dbt/models/bronze/bronze_bol.sql` — with sentinel-identifier filter + regex HS extraction
- [ ] `dbt/models/bronze/bronze_10k.sql`

### Silver layer — normalization
- [ ] `dbt/macros/normalize_company_name.sql` — legal-suffix stripping, punctuation, common noise
- [ ] `dbt/macros/extract_country_from_text.sql` — country derivation macro
- [ ] `dbt/macros/is_freight_forwarder.sql` — party-type classifier
- [ ] `dbt/models/silver/int_supplier_name_normalized.sql`
- [ ] `dbt/models/silver/int_consignee_name_normalized.sql`

### Silver layer — entity resolution
- [ ] `dbt/models/silver/int_supplier_embedded.sql` — Cortex AI_EMBED on distinct names
- [ ] `dbt/models/silver/int_consignee_embedded.sql`
- [ ] `dbt/models/silver/int_supplier_pair_candidates.sql` — blocking + pairwise
- [ ] `dbt/models/silver/int_consignee_pair_candidates.sql`
- [ ] `dbt/models/silver/int_supplier_pair_scored.sql` — cosine + jaccard scoring
- [ ] `dbt/models/silver/int_consignee_pair_scored.sql`
- [ ] `dbt/models/silver/silver_supplier_golden.sql` — union-find clustering via Snowpark UDTF
- [ ] `dbt/models/silver/silver_consignee_golden.sql`
- [ ] `dbt/models/silver/silver_bol_shipments.sql` — joined to golden IDs, in-scope only

### Testing + evaluation
- [ ] `dbt/tests/` — schema.yml files with `not_null`, `unique`, `relationships`, `accepted_values` tests
- [ ] `dbt/analyses/er_evaluation.sql` — precision/recall/F1 vs `identified_orgs` at multiple thresholds
- [ ] `dbt/analyses/silver_health_checks.sql` — row counts, scope coverage, compression ratios

---

## Claude Code Prompt

```
You are in Phase 4 of LadingLens. Phases 1-3 are complete. Read ./LadingLens.md, ./docs/phases/phase-04-dbt-and-er.md, ./docs/eda-findings.md, and ./config/target_scope.yml before starting.

Your task: build the dbt Bronze and Silver layers with entity resolution, plus a ticker backfill for the SEC 10-K ingest. This is the marquee technical phase — the ER pipeline is the resume centerpiece.

CONSTRAINTS
- All logic in dbt models unless a Snowpark Python UDF/UDTF is genuinely required (only for connected-components clustering).
- Bronze models: 1:1 with raw tables but typed, deduplicated, with ingested_at preserved. Bronze does the sentinel-identifier filter and HS-from-text extraction — these are pre-scope corrections, not scope filters.
- Silver models: normalized, cleaned, entity-resolved. Filter to config/target_scope.yml scope in Silver, NOT in Bronze.
- Every model has a schema.yml with tests: not_null on PKs, unique on golden IDs, relationships between fact and dim, accepted_values on categorical columns.
- Use SNOWFLAKE.CORTEX.EMBED_TEXT_768 with model 'e5-base-v2' for embeddings. Restrict to distinct normalized names, not raw rows.
- Env vars from .env; do not modify .env or credentials files.
- Do NOT modify: .env, .env.example, dbt/profiles.yml, .gitignore, docs/phases/*.md, LadingLens.md.

===========================================
STEP 0 — TICKER BACKFILL (do first, standalone)
===========================================

The Phase 3 EDA discovered 0% BoL↔10-K match rate because the real top consignees are foreign-parent OEMs. Fix this before building models that depend on the join.

a. Update config/target_tickers.yml:
   - Add a new section `foreign_parents_and_retail` with these tickers and CIKs:
       WMT   (Walmart Inc, CIK 0000104169, 10-K filer)
       STLA  (Stellantis NV, CIK 0001605484, 20-F filer)
       VWAGY (Volkswagen AG, CIK 0000723612, 20-F filer)
       TTM   (Tata Motors Ltd, CIK 0001269823, 20-F filer)
   - Add a `retry_with_explicit_cik` section for the 6 previously-failed tickers:
       DELL (CIK 1571996, 10-K)
       INTC (CIK 50863, 10-K)
       EMR  (CIK 32604, 10-K)
       JNPR (CIK 1043604, 10-K)
       HBI  (CIK 1359841, 10-K)
       GES  (CIK 912463, 10-K)
   The retry list bypasses the sec-edgar-downloader ticker cache which was stale.

b. Extend scripts/ingest/03_sec_10k.py:
   - Accept a `filing_type` parameter per ticker (default '10-K', can be '20-F')
   - Accept an explicit CIK parameter that bypasses ticker→CIK lookup
   - For 20-F filings, extract different section markers:
       * Item 3.D (Risk Factors) — 20-F equivalent of Item 1A
       * Item 5 (Operating and Financial Review) — 20-F equivalent of Item 7
   - Apply the same longest-span extraction fix that worked for Item 1A to Item 7/Item 5 for the retry list — this may unlock DELL/INTC/EMR.
   - Log filing_type in the loaded row so downstream can distinguish 10-K from 20-F.

c. Re-run the script: python scripts/ingest/03_sec_10k.py
   Target: 25+ filings loaded (was 19). Report which of the 10 newly-added tickers (4 backfill + 6 retry) succeeded and which failed.

===========================================
STEP 1 — BRONZE LAYER
===========================================

1. dbt/models/bronze/bronze_hts.sql
   - Reads RAW.HTS_TARIFF_SCHEDULE
   - Parse hts_number into hs2, hs4, hs6, hs8, hs10 (LEFT-substring based)
   - Cast general_rate_text to a parsed rate:
       * 'Free' → 0.0
       * '3.4%' → 0.034
       * If contains only a specific rate (like '1¢/kg'), set ad_valorem_rate to NULL and specific_rate_raw to the string
   - Deduplicate on hts_number
   - Materialize as TABLE (not view)

2. dbt/models/bronze/bronze_bol.sql — the most important Bronze model
   - Reads RAW.BOL_SHIPMENTS
   - Type coercion: cast dates, harmonized_value/weight to NUMBER, piece_count to NUMBER
   - SENTINEL IDENTIFIER FILTER: exclude rows where identifier matches YYYY-MM-00000 pattern:
       WHERE NOT REGEXP_LIKE(TO_VARCHAR(identifier), '^20[0-9]{2}[0-1][0-9]0{5,}$')
     Expected removal: ~1.38M rows (36.2%). Log the count.
   - HS-FROM-TEXT EXTRACTION: for rows where harmonized_number IS NULL AND text IS NOT NULL, attempt regex extraction:
       CASE
         WHEN harmonized_number IS NOT NULL AND harmonized_number != '' THEN harmonized_number
         WHEN REGEXP_LIKE(text, 'HS[- ]?CODE:?\\s*[0-9]{4}\\.?[0-9]{2}') THEN
              REGEXP_SUBSTR(text, '[0-9]{4}\\.?[0-9]{2}', 1, 1, 'i')
         ELSE NULL
       END AS harmonized_number_final,
       CASE
         WHEN harmonized_number IS NOT NULL AND harmonized_number != '' THEN 'source_field'
         WHEN harmonized_number_final IS NOT NULL THEN 'regex_from_text'
         ELSE NULL
       END AS hs_source
   - Deduplicate on (identifier, description_sequence_number) — after sentinel filter
   - Report: total rows after sentinel filter, HS coverage before regex vs after regex (should lift from 42% to ~56%)
   - Materialize as TABLE

3. dbt/models/bronze/bronze_10k.sql
   - Reads RAW.SEC_10K_FILINGS
   - Deduplicate on (cik, filing_date)
   - Add computed column: filing_type (10-K vs 20-F) — infer from filing_url path or from a new column added in Step 0
   - Add computed column: is_supply_chain_relevant BOOLEAN — TRUE if item_1a_length >= 5000 (item_5 for 20-F filers)
   - Materialize as TABLE

===========================================
STEP 2 — SILVER MACROS (build before Silver models)
===========================================

1. dbt/macros/normalize_company_name.sql — a Jinja macro that takes a column reference:

   {% macro normalize_company_name(col) %}
     LOWER(
       REGEXP_REPLACE(
         REGEXP_REPLACE(
           REGEXP_REPLACE(
             REGEXP_REPLACE({{ col }},
               '\\b(inc|incorporated|corp|corporation|co|company|ltd|limited|llc|llp|gmbh|sarl|sa|sarl|bv|ag|kk|spa|srl|pty|plc|nv|as|oy|ab)\\b',
               '', 1, 0, 'i'),
             '[^a-z0-9 ]', '', 1, 0, 'i'),
           '\\s+', ' ', 1, 0, 'i'),
         '^the |^\\s+|\\s+$', '', 1, 0, 'i')
     )
   {% endmacro %}

   Handles: legal suffix stripping (case-insensitive), punctuation, extra whitespace, leading "the ".

2. dbt/macros/extract_country_from_text.sql — best-effort country extraction:

   {% macro extract_country_from_text(address_col, port_col) %}
     COALESCE(
       CASE
         WHEN UPPER({{ address_col }}) LIKE '% GERMANY%' OR UPPER({{ address_col }}) LIKE '% DE %' THEN 'DE'
         WHEN UPPER({{ address_col }}) LIKE '% BELGIUM%' OR UPPER({{ address_col }}) LIKE '%,BE%' THEN 'BE'
         WHEN UPPER({{ address_col }}) LIKE '% VIETNAM%' OR UPPER({{ address_col }}) LIKE '% VN %' THEN 'VN'
         WHEN UPPER({{ address_col }}) LIKE '% CHINA%' OR UPPER({{ address_col }}) LIKE '% CN %' THEN 'CN'
         WHEN UPPER({{ address_col }}) LIKE '% MEXICO%' OR UPPER({{ address_col }}) LIKE '% MX %' THEN 'MX'
         WHEN UPPER({{ address_col }}) LIKE '% SPAIN%' OR UPPER({{ address_col }}) LIKE '% ES %' THEN 'ES'
         WHEN UPPER({{ address_col }}) LIKE '% FRANCE%' OR UPPER({{ address_col }}) LIKE '% FR %' THEN 'FR'
         WHEN UPPER({{ address_col }}) LIKE '% UNITED KINGDOM%' OR UPPER({{ address_col }}) LIKE '% GB %' OR UPPER({{ address_col }}) LIKE '% ENGLAND%' THEN 'GB'
         WHEN UPPER({{ address_col }}) LIKE '% JAPAN%' THEN 'JP'
         WHEN UPPER({{ address_col }}) LIKE '% KOREA%' THEN 'KR'
         ELSE NULL
       END,
       -- Fallback: derive from port_col string patterns
       CASE
         WHEN UPPER({{ port_col }}) LIKE '%GERMANY%' OR UPPER({{ port_col }}) LIKE '%BREMERHAVEN%' OR UPPER({{ port_col }}) LIKE '%HAMBURG%' THEN 'DE'
         WHEN UPPER({{ port_col }}) LIKE '%BELGIUM%' OR UPPER({{ port_col }}) LIKE '%ANVERS%' OR UPPER({{ port_col }}) LIKE '%ANTWERP%' THEN 'BE'
         WHEN UPPER({{ port_col }}) LIKE '%VIETNAM%' OR UPPER({{ port_col }}) LIKE '%HO CHI MINH%' OR UPPER({{ port_col }}) LIKE '%HAIPHONG%' THEN 'VN'
         WHEN UPPER({{ port_col }}) LIKE '%CHINA%' OR UPPER({{ port_col }}) LIKE '%SHANGHAI%' OR UPPER({{ port_col }}) LIKE '%NINGBO%' OR UPPER({{ port_col }}) LIKE '%SHENZHEN%' THEN 'CN'
         ELSE NULL
       END
     )
   {% endmacro %}

3. dbt/macros/is_freight_forwarder.sql:

   {% macro is_freight_forwarder(name_col) %}
     (UPPER({{ name_col }}) LIKE '%DHL%' OR
      UPPER({{ name_col }}) LIKE '%SCHENKER%' OR
      UPPER({{ name_col }}) LIKE '%EXPEDITORS%' OR
      UPPER({{ name_col }}) LIKE '%YUSEN%' OR
      UPPER({{ name_col }}) LIKE '%MAERSK%' OR
      UPPER({{ name_col }}) LIKE '%PANALPINA%' OR
      UPPER({{ name_col }}) LIKE '%CEVA%' OR
      UPPER({{ name_col }}) LIKE '%KUEHNE%' OR
      UPPER({{ name_col }}) LIKE '%NAGEL%' OR
      UPPER({{ name_col }}) LIKE '%GEODIS%' OR
      UPPER({{ name_col }}) LIKE '%DSV%' OR
      UPPER({{ name_col }}) LIKE '%NIPPON EXPRESS%' OR
      UPPER({{ name_col }}) LIKE '%DAMCO%' OR
      UPPER({{ name_col }}) LIKE '%HELLMANN%')
   {% endmacro %}

===========================================
STEP 3 — SILVER NORMALIZATION MODELS
===========================================

1. dbt/models/silver/int_supplier_name_normalized.sql
   - Reads bronze_bol, distinct shipper_party_name values
   - Applies normalize_company_name macro → shipper_name_norm
   - Derives shipper_country using extract_country_from_text(shipper_address, foreign_port_of_lading)
   - Applies is_freight_forwarder → is_forwarder
   - Adds blocking_key = LEFT(shipper_name_norm, 8) || '|' || COALESCE(shipper_country, 'UNK')
   - Output columns: shipper_name_raw, shipper_name_norm, shipper_country, is_forwarder, blocking_key, shipment_count (count of BoL rows with this exact raw name)
   - Materialize as TABLE

2. dbt/models/silver/int_consignee_name_normalized.sql
   - Same structure but for consignees. Country derived from consignee_address.

===========================================
STEP 4 — SILVER ER MODELS
===========================================

1. dbt/models/silver/int_supplier_embedded.sql
   - For each distinct shipper_name_norm in int_supplier_name_normalized (should be ~50-100K unique after normalization):
       SELECT
         shipper_name_norm,
         SNOWFLAKE.CORTEX.EMBED_TEXT_768('e5-base-v2', shipper_name_norm) AS embedding
       FROM {{ ref('int_supplier_name_normalized') }}
       WHERE shipper_name_norm IS NOT NULL AND LENGTH(shipper_name_norm) >= 3
   - Materialize as TABLE (embeddings are expensive; do not recompute unnecessarily). Use dbt incremental with unique_key=shipper_name_norm if the phase is re-run.

2. dbt/models/silver/int_consignee_embedded.sql — same for consignees.

3. dbt/models/silver/int_supplier_pair_candidates.sql
   - Generate pairs within the same blocking_key:
       SELECT
         a.shipper_name_norm AS name_a,
         b.shipper_name_norm AS name_b,
         a.shipper_country AS country_a,
         b.shipper_country AS country_b,
         a.blocking_key,
         ABS(LENGTH(a.shipper_name_norm) - LENGTH(b.shipper_name_norm)) AS length_diff
       FROM {{ ref('int_supplier_name_normalized') }} a
       INNER JOIN {{ ref('int_supplier_name_normalized') }} b
         ON a.blocking_key = b.blocking_key
        AND a.shipper_name_norm < b.shipper_name_norm  -- avoids self-pairs and duplicates
       WHERE ABS(LENGTH(a.shipper_name_norm) - LENGTH(b.shipper_name_norm)) < 20  -- length prefilter

4. dbt/models/silver/int_supplier_pair_scored.sql
   - Join pairs to embeddings twice (name_a → emb_a, name_b → emb_b)
   - Compute:
       VECTOR_COSINE_SIMILARITY(emb_a, emb_b) AS embed_sim
       -- Jaccard on character bigrams (approximate using EDITDISTANCE as a shortcut acceptable here):
       (1.0 - EDITDISTANCE(name_a, name_b) / GREATEST(LENGTH(name_a), LENGTH(name_b))) AS char_sim
       0.7 * embed_sim + 0.3 * char_sim AS match_score
       CASE
         WHEN match_score >= 0.92 THEN 'match'
         WHEN match_score >= 0.80 THEN 'review'
         ELSE 'no_match'
       END AS match_label

5. dbt/models/silver/silver_supplier_golden.sql
   - Cluster the pair-matches into golden entities using Snowpark Python UDTF:

     ```python
     -- Register a Snowpark UDTF once (in a pre_hook or separate script):
     CREATE OR REPLACE FUNCTION cluster_matches(name_a STRING, name_b STRING)
     RETURNS TABLE (canonical_name STRING, cluster_id STRING)
     LANGUAGE PYTHON
     RUNTIME_VERSION = '3.11'
     HANDLER = 'ClusterHandler'
     PACKAGES = ('networkx==3.2')
     AS $$
     import networkx as nx
     class ClusterHandler:
         def __init__(self):
             self.G = nx.Graph()
         def process(self, name_a, name_b):
             self.G.add_edge(name_a, name_b)
         def end_partition(self):
             for i, component in enumerate(nx.connected_components(self.G)):
                 canonical = min(component)  # shortest/alphabetic first
                 for name in component:
                     yield (canonical, hash(canonical))
     $$;
     ```
     If UDTF creation fails on trial account, fall back to a recursive CTE approach (up to 20 iterations).

   - Output columns:
       golden_supplier_id (hash of canonical_name + country),
       canonical_name,
       country,
       raw_name_variants_count,
       total_shipments (sum from int_supplier_name_normalized.shipment_count),
       first_seen_date, last_seen_date,
       is_forwarder (any variant is a forwarder → cluster is)

6. dbt/models/silver/silver_consignee_golden.sql — same structure for consignees.

7. dbt/models/silver/silver_bol_shipments.sql
   - Joins bronze_bol → normalized names → golden IDs
   - Filters to config/target_scope.yml scope:
       * HS chapter (LEFT(harmonized_number_final, 2)) IN scope
       * Origin country (derived from foreign_port_of_lading) IN scope
   - Excludes freight-forwarder-as-consignee rows via a party_type column (KEEP the rows but label them):
       consignee_party_type = CASE WHEN is_forwarder THEN 'freight_forwarder' ELSE 'importer' END
   - Adds all relevant golden IDs + canonical names
   - Materialize as TABLE

===========================================
STEP 5 — TESTS
===========================================

Create dbt/models/silver/schema.yml with these tests:
- unique: silver_supplier_golden.golden_supplier_id, silver_consignee_golden.golden_consignee_id
- not_null: all *_golden.canonical_name, silver_bol_shipments.golden_supplier_id (after filter), silver_bol_shipments.golden_consignee_id
- relationships: silver_bol_shipments.golden_supplier_id → silver_supplier_golden.golden_supplier_id
- accepted_values: int_supplier_pair_scored.match_label IN ('match', 'review', 'no_match')
- accepted_values: silver_bol_shipments.consignee_party_type IN ('freight_forwarder', 'importer')

Also add source freshness / row count sanity check:
- silver_bol_shipments row count > 300,000 (expect ~600K post-scope filter)

===========================================
STEP 6 — ER EVALUATION vs identified_orgs
===========================================

dbt/analyses/er_evaluation.sql
- Compare our silver_consignee_golden clusters against NIST's identified_orgs where populated (19% of raw BoL)
- For each row in bronze_bol where identified_orgs IS NOT NULL:
    * Get our golden_consignee_id assignment
    * Get NIST's identified_orgs value
    * Two consignees agree if both point to the same golden_consignee_id from our side AND same identified_orgs on their side
- Compute precision/recall/F1 at match_score thresholds [0.80, 0.85, 0.90, 0.92, 0.95]
- Report the threshold that maximizes F1
- Also report:
    - Total distinct raw consignee names in scope
    - Total distinct golden consignees in scope
    - Compression ratio (raw / golden)
    - Number of clusters with >5 raw variants (the "wow" clusters)
    - Top 10 largest clusters by raw variant count

dbt/analyses/silver_health_checks.sql
- Row counts: bronze_bol vs silver_bol_shipments
- Sentinel-filter drop: rows removed by sentinel identifier filter
- HS coverage: direct + regex-extracted, before and after
- Country derivation: what % of shipments have derived country vs NULL
- Freight-forwarder split: what % of silver_bol_shipments have consignee_party_type='freight_forwarder'
- Scope coverage: what % of pre-scope silver_bol rows survive the scope filter

===========================================
EXECUTION ORDER
===========================================

1. Step 0: ticker backfill (run 03_sec_10k.py, verify counts)
2. dbt deps (if needed)
3. dbt build --select bronze — verify Bronze counts match Phase 3 expectations after sentinel filter
4. dbt build --select silver.int_ — normalization + embeddings first (embeddings are expensive; validate before scoring)
5. dbt build --select silver.int_supplier_pair_scored silver.int_consignee_pair_scored
6. Create the Snowpark UDTF for clustering (or fall back to recursive CTE)
7. dbt build --select silver.silver_ — golden records + final BoL Silver
8. dbt build --select analyses.er_evaluation analyses.silver_health_checks — output the numbers
9. dbt test — all tests should pass

Report at the end:
- Ticker backfill outcome: N tickers loaded, which succeeded, which failed
- Bronze row counts before/after sentinel filter
- HS coverage lift from regex extraction
- Number of distinct supplier/consignee raw names → golden entities (compression ratio)
- ER F1 at the best threshold vs identified_orgs
- Top 10 largest clusters (should include Mercedes-Benz merging its 4+ variants)
- silver_bol_shipments final row count
- All dbt test results
- Any tickers still failing after backfill (for Phase 4 open items)

Ask before making decisions not covered above. In particular, ask before:
- Changing embedding model from e5-base-v2
- Changing match_score threshold from 0.92 default
- Filtering rows in Bronze (only Silver should filter to scope)
- Skipping any of the 10 backfill/retry tickers
```

---

## Your Tasks (Human)

- [ ] **Approve the ticker backfill list** before Claude Code runs Step 0. If you have preferences on which foreign parents matter most, edit before starting. Recommended keeps: WMT, STLA, VWAGY, TTM. Optional adds: ADDYY (Adidas), BMWYY (BMW ADR), MBGAF (Mercedes ADR), VLVLY (Volvo).
- [ ] **Watch Cortex embedding cost** during Step 4. ~50-100K distinct names × e5-base-v2 is inexpensive (~$0.10-$1) but monitor via Snowsight → Admin → Usage.
- [ ] **Review the top 10 largest clusters** manually before committing. Query `SELECT * FROM SILVER.silver_consignee_golden ORDER BY raw_name_variants_count DESC LIMIT 10`. Do the clusters look right? Mercedes should collapse its 4 variants. If any cluster looks wrong (over-merged unrelated entities), the threshold needs tightening.
- [ ] **Screenshot the Mercedes-Benz golden cluster** — the "N raw variants → 1 golden record" number is a headline demo screenshot.
- [ ] **Screenshot the compression ratio and ER F1** — resume-line material.
- [ ] **Review `dbt/analyses/er_evaluation.sql` output** in Snowsight before Phase 5. F1 ≥ 0.80 is the target. If it's below, we need to iterate on threshold or blocking before proceeding.
- [ ] **Commit and push after all tests green.**

---

## Success Criteria

- All new SEC 10-K tickers loaded: target 25+ total filings in `LADINGLENS_DB.RAW.SEC_10K_FILINGS` (up from 19). At least 2 of 4 foreign-parent backfills must succeed for the BoL↔10-K story to be viable.
- `dbt build` completes with all tests passing.
- Bronze row counts: sentinel filter removes ~1.38M rows (~36.2%), leaving ~2.44M rows.
- HS coverage after regex extraction lifts from 42% to ≥55%.
- Silver supplier compression ratio ≥ 2:1 (measured across all distinct raw names in scope, not top-200).
- Silver consignee compression ratio ≥ 3:1 (Mercedes, DHL, Schenker clusters drive this).
- ER F1 vs `identified_orgs` ≥ 0.80 at the best threshold. Target 0.85+.
- `silver_bol_shipments` in-scope row count ≥ 300,000.
- Freight-forwarder classification labels ≥ 80% of top-20 consignees correctly.
- No orphan `golden_supplier_id` / `golden_consignee_id` (relationship tests pass).

---

## Gotchas

- **Cortex embedding cost management.** e5-base-v2 is cheap but not free. Only embed distinct normalized names, never raw rows. Use dbt's `incremental` materialization on `int_*_embedded.sql` models so re-runs skip already-embedded names.

- **The Snowpark UDTF for clustering may fail on trial accounts** due to Python UDF privilege restrictions. Fallback plan: use a Snowflake recursive CTE with a maximum iteration count of 20, then flatten. Slower but works everywhere. Do NOT abandon clustering entirely — golden records are the whole point.

- **The 20-F filings for foreign parents have different section markers than 10-K.** The parsing logic must handle both. Section 3.D of a 20-F is not the same as Item 1A of a 10-K, but for our purposes (extracting supply-chain risk text) they serve the same role. Log which filing_type each row is.

- **Recursive CTE for clustering has row limits on trial accounts.** If the recursion errors on max-rows, split by country first (cluster German suppliers separately from Belgian etc.) then union. This is fine architecturally — cross-country merges are rare and mostly noise.

- **The `identified_orgs` ground truth is only 19% coverage AND is short-token (e.g. just "BMW", not "BMW MANUFACTURING CORP").** F1 calculation needs to compare *cluster assignment consistency*, not exact string match. Two rows agree if: our golden_consignee_id is the same AND their identified_orgs token is the same. Two rows disagree if: our IDs differ but their tokens match (or vice versa). Rows where identified_orgs IS NULL are excluded from F1.

- **Freight-forwarder consignees can legitimately be part of the concentration story** (someone is depending on DHL) — that's why we CLASSIFY rather than FILTER. Downstream Phase 6 will decide whether to include or exclude based on the question being asked.

- **Threshold tuning is empirical, not theoretical.** Start at 0.92, look at what merges vs what doesn't, adjust. Don't over-fit to a specific F1 number by tuning against the eval set — that's data leakage. Report both F1 and manual review of top-10 clusters.

- **This phase can bleed into 3 days.** Don't panic. The ER pipeline is the resume centerpiece — do it right. If the schedule slips, compress Phase 9 (UI) later.
