# Phase 6 — Gold Layer + Cortex Analyst Semantic View

**Duration:** ~1 day
**Depends on:** Phase 4 (silver golden tables), Phase 5 (silver_bol_shipments_scoped)
**Goal:** Build the Kimball-style star schema in Gold, then publish a Cortex Analyst semantic view over it. This turns the raw analytical base into a governed natural-language-queryable surface — the "self-serve BI" story that hiring managers screen for.

---

## Context

Everything hard is done. Phase 4 gave us clean entity resolution. Phase 5 filled in HS codes. Phase 6 is straight dimensional modeling on top of `silver_bol_shipments_scoped`.

The star schema:
- **fact_shipments** — one row per shipment (grain = `silver_bol_shipments_scoped` row)
- **dim_supplier** — golden supplier records, surrogate key on golden_supplier_id
- **dim_consignee** — same for consignees
- **dim_hs_code** — HS-6 with descriptions, base duty rate, Section 232 flag
- **dim_country** — country codes, region, Section 232 status
- **dim_date** — standard date dimension
- **fact_tariff_events** — hand-curated list of historical tariff changes (Section 232 steel/aluminum + 2018-2025 Section 301 rounds)

The Cortex Analyst semantic view exposes these tables to natural-language queries with business-friendly synonyms and pre-defined measures like `total_landed_cost`, `supplier_hhi`, `is_single_source`.

---

## Deliverables

- [ ] `dbt/models/gold/dim_country.sql`
- [ ] `dbt/models/gold/dim_hs_code.sql`
- [ ] `dbt/models/gold/dim_supplier.sql`
- [ ] `dbt/models/gold/dim_consignee.sql`
- [ ] `dbt/models/gold/dim_date.sql`
- [ ] `dbt/models/gold/fact_shipments.sql`
- [ ] `dbt/models/gold/fact_tariff_events.sql`
- [ ] `dbt/models/gold/mart_concentration_metrics.sql` — pre-computed HHI per (consignee, hs_6)
- [ ] `dbt/seeds/tariff_events.csv` — 10-15 hand-curated real tariff events
- [ ] `dbt/models/gold/schema.yml` — dbt tests on all Gold models
- [ ] `semantic/ladinglens_semantic_view.yml` — Cortex Analyst YAML
- [ ] `semantic/verified_queries.yml` — 10-15 NL→SQL examples
- [ ] `scripts/publish_semantic_view.sql` — DDL to register the semantic view
- [ ] `notebooks/06_semantic_view_smoke_test.ipynb` — 10 NL questions with answers
- [ ] `data/sources.md` — Phase 6 wrap section

---

## Claude Code Prompt

```
You are in Phase 6 of LadingLens. Phases 1-5 are complete. Read ./LadingLens.md, ./docs/phases/phase-06-gold-semantic.md, and ./data/sources.md before starting.

STATE RECAP (verified, do not re-check):
- silver_bol_shipments_scoped has 89,200 in-scope shipments with unified hs_code_unified column
- silver_supplier_golden (41,338) and silver_consignee_golden (40,629) provide golden entity IDs
- bronze_hts has 26,750 HTS rows with duty rate columns
- Cortex is unblocked on this account. AI_COMPLETE, EMBED_TEXT_768, semantic view publishing all functional.
- Resource monitor LADINGLENS_CAP active. Current usage: ~17-18 credits of 50.
- 32/32 dbt tests pass.

YOUR TASK:
Build the Kimball star schema in Gold, add concentration-metrics mart, publish a Cortex Analyst semantic view, and smoke-test with 10 NL queries.

CONSTRAINTS:
- All Gold models materialize as TABLE (not view) — Cortex Analyst performs better on materialized inputs.
- Kimball rules: surrogate keys on dims, no measures on dims, one grain per fact table.
- Every measure has a business-friendly description in the semantic view.
- No new Cortex-embedding or LLM calls needed for Phase 6 — this is pure SQL modeling and semantic view publishing.

===========================================
STEP 1 — dim_country
===========================================

Build dbt/models/gold/dim_country.sql:

Columns:
- country_code (PK) — 2-letter ISO code, e.g., 'DE', 'BE', 'VN'
- country_name — full name
- region — 'EU', 'ASIA', 'NORTH_AMERICA', 'LATAM', 'OTHER'
- is_section_232_target BOOLEAN — TRUE for countries subject to Section 232 tariffs (EU, JP, KR on steel/aluminum; adjust as of 2025-2026)
- is_section_301_target BOOLEAN — TRUE for China (CN), broadly
- notes VARCHAR

Seed the countries appearing in silver_bol_shipments_scoped plus the top 20 US trade partners globally. Approach: SELECT DISTINCT shipment_origin_country FROM silver_bol_shipments_scoped as the base, then hand-add other economically-relevant countries (US, CA, JP, KR, TW, IN, TH, ID, MY, SG, MX, BR, AR, CL, CO, PL, CZ, AT, CH, SE, DK, NO, FI, PT, TR, GB, IT, NL, FR, DE, BE, ES, CN, VN, HK, AU).

Use dbt seed to load a countries.csv reference file, then aggregate that into dim_country. OR just define the dim inline as a UNION of SELECT VALUES statements — either is fine. Prefer inline VALUES for maintainability at this scale.

Row count target: 30-50 countries.

===========================================
STEP 2 — dim_hs_code
===========================================

Build dbt/models/gold/dim_hs_code.sql:

Aggregate bronze_hts to HS-6 grain. Columns:
- hs_6 (PK) — 6-digit HS code
- hs_6_description — pick shortest/most-general description at the HS-6 level (or LISTAGG the top 3 subheading descriptions)
- hs_4 — 4-digit heading
- hs_4_description
- hs_2 — 2-digit chapter
- hs_2_description
- general_duty_rate_pct — normalized numeric from bronze_hts.general_rate_text (e.g., 'Free' → 0.0, '3.4%' → 3.4). If parsing fails, default to NULL.
- section_232_rate_pct — additional Section 232 rate applicable if origin country is a S232 target (steel = 25%, aluminum = 10%; hard-code per HS chapter). Chapter 72/73 (steel) = 25%, chapter 76 (aluminum) = 10%, else 0.
- section_301_rate_pct — for CN origin: hard-code a representative additional rate (25% for lists 1-3, 7.5% for list 4A) — since we don't have per-HS granularity easily, use 25% as a default for chapters likely in Section 301 (electronics, machinery). Alternative: leave as 0 for Phase 6 and add per-chapter in Phase 8 scenario simulator.

Aggregation approach: group bronze_hts by hs_6 (LEFT(hts_number, 6) with dots stripped), pick MIN(description) to keep the most general. Same for hs_4, hs_2.

Row count target: ~4,000-5,000 distinct HS-6 codes.

===========================================
STEP 3 — dim_supplier, dim_consignee
===========================================

Both are thin wrappers on the silver golden tables with a surrogate key rename.

Build dbt/models/gold/dim_supplier.sql:

SELECT
    golden_supplier_id AS supplier_key,   -- PK
    canonical_name AS supplier_name,
    country AS supplier_country_code,
    raw_name_variants_count,
    total_shipments,
    is_forwarder,
    sample_address
FROM {{ ref('silver_supplier_golden') }}

Build dbt/models/gold/dim_consignee.sql — same pattern.

Row counts: 41,338 supplier / 40,629 consignee.

===========================================
STEP 4 — dim_date
===========================================

Build dbt/models/gold/dim_date.sql:

Standard date dimension covering 2018-01-01 through 2026-12-31 (spans the BoL data + tariff-event dates + demo scenario dates):

WITH date_spine AS (
    SELECT DATEADD(day, seq, DATE '2018-01-01') AS date_day
    FROM (SELECT ROW_NUMBER() OVER (ORDER BY 1) - 1 AS seq
          FROM TABLE(GENERATOR(ROWCOUNT => 4000))) t
    WHERE DATEADD(day, seq, DATE '2018-01-01') <= DATE '2026-12-31'
)
SELECT
    date_day AS date_key,
    date_day,
    EXTRACT(YEAR FROM date_day) AS year,
    EXTRACT(QUARTER FROM date_day) AS quarter,
    EXTRACT(MONTH FROM date_day) AS month,
    EXTRACT(DAY FROM date_day) AS day,
    DAYNAME(date_day) AS day_name,
    CASE WHEN DAYOFWEEK(date_day) IN (0, 6) THEN TRUE ELSE FALSE END AS is_weekend,
    CONCAT('Q', EXTRACT(QUARTER FROM date_day), ' ', EXTRACT(YEAR FROM date_day)) AS fiscal_quarter_label
FROM date_spine

Row count: ~3,300.

===========================================
STEP 5 — fact_tariff_events
===========================================

Create dbt/seeds/tariff_events.csv with 10-15 real historical tariff events:

event_date,event_type,hs_scope,country_scope,rate_change_pp,description,source_url
2018-03-23,section_232,72;73,ALL_EXCLUDING_SELECTED,25.0,"Section 232 steel tariffs imposed at 25% on most origin countries",https://ustr.gov/
2018-03-23,section_232,76,ALL_EXCLUDING_SELECTED,10.0,"Section 232 aluminum tariffs imposed at 10%",https://ustr.gov/
2018-07-06,section_301,ELECTRONICS_MACHINERY,CN,25.0,"Section 301 List 1 tariffs on ~$34B China imports",https://ustr.gov/
2018-08-23,section_301,VARIOUS,CN,25.0,"Section 301 List 2 tariffs on ~$16B China imports",https://ustr.gov/
2018-09-24,section_301,VARIOUS,CN,10.0,"Section 301 List 3 tariffs at 10% (later raised to 25%)",https://ustr.gov/
2019-05-10,section_301,VARIOUS,CN,25.0,"Section 301 List 3 tariffs raised from 10% to 25%",https://ustr.gov/
2019-09-01,section_301,APPAREL_MISC,CN,15.0,"Section 301 List 4A tariffs at 15% (later reduced to 7.5%)",https://ustr.gov/
2020-01-15,section_301,APPAREL_MISC,CN,7.5,"Section 301 List 4A tariffs reduced from 15% to 7.5% under Phase One deal",https://ustr.gov/
2022-03-25,section_232,72;73;76,EU,0.0,"Section 232 replaced with tariff-rate quotas for EU steel/aluminum",https://ustr.gov/
2024-05-14,section_301,ELECTRIC_VEHICLES;SEMICONDUCTORS;SOLAR,CN,100.0,"Section 301 increases on EVs (100%), semiconductors (50%), solar cells (50%)",https://ustr.gov/
2025-02-04,section_232,ALL,CN;MX;CA,10.0,"February 2025 additional tariffs on China/Mexico/Canada (10% baseline)",https://ustr.gov/
2025-03-12,section_232,72;73;76,ALL,25.0,"March 2025 Section 232 reinstated at 25% on steel/aluminum globally",https://ustr.gov/

Then build dbt/models/gold/fact_tariff_events.sql that loads this seed as a table.

Also add a dim_date FK: event_date → dim_date.date_key.

Row count target: 12-15 events.

===========================================
STEP 6 — fact_shipments
===========================================

Build dbt/models/gold/fact_shipments.sql — one row per silver_bol_shipments_scoped row:

SELECT
    -- Surrogate key
    MD5(s.identifier || '|' || s.container_number) AS shipment_key,
    
    -- FKs
    s.identifier AS bol_identifier,
    s.container_number,
    s.actual_arrival_date AS date_key,
    s.golden_supplier_id AS supplier_key,
    s.golden_consignee_id AS consignee_key,
    s.hs_code_unified AS hs_6,
    s.shipment_origin_country AS origin_country_code,
    
    -- Measures
    s.harmonized_weight_kg AS weight_kg,
    s.harmonized_value_usd AS shipment_value_usd,
    s.piece_count,
    s.teu,
    
    -- Derived attributes
    s.hs_source_final,
    s.consignee_party_type,
    d.general_duty_rate_pct,
    d.section_232_rate_pct,
    d.section_301_rate_pct,
    -- Effective duty (base + applicable overlays):
    (COALESCE(d.general_duty_rate_pct, 0)
     + CASE WHEN c.is_section_232_target THEN COALESCE(d.section_232_rate_pct, 0) ELSE 0 END
     + CASE WHEN c.is_section_301_target THEN COALESCE(d.section_301_rate_pct, 0) ELSE 0 END
    ) AS effective_duty_rate_pct,
    -- Landed cost estimate (only meaningful when shipment_value_usd is present):
    s.harmonized_value_usd * (1 + (
        COALESCE(d.general_duty_rate_pct, 0)
        + CASE WHEN c.is_section_232_target THEN COALESCE(d.section_232_rate_pct, 0) ELSE 0 END
        + CASE WHEN c.is_section_301_target THEN COALESCE(d.section_301_rate_pct, 0) ELSE 0 END
    ) / 100.0) AS estimated_landed_cost_usd

FROM {{ ref('silver_bol_shipments_scoped') }} s
LEFT JOIN {{ ref('dim_hs_code') }} d
    ON s.hs_code_unified = d.hs_6
LEFT JOIN {{ ref('dim_country') }} c
    ON s.shipment_origin_country = c.country_code

Row count: 89,200.

Note: harmonized_value_usd is sparse in NIST data (~15% populated). Downstream analysis flags this — do not fabricate estimated_landed_cost_usd where value is null.

===========================================
STEP 7 — mart_concentration_metrics
===========================================

Build dbt/models/gold/mart_concentration_metrics.sql:

Pre-computed HHI (Herfindahl-Hirschman Index) per (consignee, hs_6) pair over the full time window. Also flag single-source pairs.

WITH consignee_hs_supplier AS (
    SELECT
        consignee_key,
        hs_6,
        supplier_key,
        origin_country_code,
        SUM(weight_kg) AS supplier_weight,
        SUM(estimated_landed_cost_usd) AS supplier_cost
    FROM {{ ref('fact_shipments') }}
    WHERE weight_kg IS NOT NULL
    GROUP BY 1, 2, 3, 4
),
consignee_hs_totals AS (
    SELECT
        consignee_key, hs_6,
        SUM(supplier_weight) AS total_weight,
        SUM(supplier_cost) AS total_cost,
        COUNT(DISTINCT supplier_key) AS supplier_count,
        COUNT(DISTINCT origin_country_code) AS country_count
    FROM consignee_hs_supplier
    GROUP BY 1, 2
),
supplier_shares AS (
    SELECT
        chs.consignee_key, chs.hs_6, chs.supplier_key,
        chs.supplier_weight * 1.0 / cht.total_weight AS supplier_share
    FROM consignee_hs_supplier chs
    JOIN consignee_hs_totals cht USING (consignee_key, hs_6)
),
country_shares AS (
    SELECT
        chs.consignee_key, chs.hs_6, chs.origin_country_code,
        SUM(chs.supplier_weight) * 1.0 / MAX(cht.total_weight) AS country_share
    FROM consignee_hs_supplier chs
    JOIN consignee_hs_totals cht USING (consignee_key, hs_6)
    GROUP BY 1, 2, 3
),
supplier_hhi AS (
    SELECT consignee_key, hs_6,
           SUM(POWER(supplier_share, 2)) AS supplier_hhi,
           MAX(supplier_share) AS top_supplier_share
    FROM supplier_shares
    GROUP BY 1, 2
),
country_hhi AS (
    SELECT consignee_key, hs_6,
           SUM(POWER(country_share, 2)) AS country_hhi,
           MAX(country_share) AS top_country_share
    FROM country_shares
    GROUP BY 1, 2
)
SELECT
    t.consignee_key, t.hs_6,
    t.supplier_count, t.country_count,
    t.total_weight, t.total_cost,
    sh.supplier_hhi, sh.top_supplier_share,
    ch.country_hhi, ch.top_country_share,
    CASE WHEN sh.top_supplier_share > 0.70 THEN TRUE ELSE FALSE END AS is_single_source,
    CASE WHEN ch.top_country_share > 0.70 THEN TRUE ELSE FALSE END AS is_single_country
FROM consignee_hs_totals t
JOIN supplier_hhi sh USING (consignee_key, hs_6)
JOIN country_hhi ch USING (consignee_key, hs_6)

Row count: probably 30,000-60,000 (consignee × HS_6 pairs).

===========================================
STEP 8 — dbt tests + schema.yml
===========================================

Add dbt/models/gold/schema.yml with tests:

- dim_country: unique(country_code), not_null(country_code, country_name)
- dim_hs_code: unique(hs_6), not_null(hs_6, hs_2)
- dim_supplier: unique(supplier_key), not_null(supplier_key, supplier_name)
- dim_consignee: unique(consignee_key), not_null(consignee_key, consignee_name)
- dim_date: unique(date_key), not_null(date_key, year)
- fact_shipments:
    - not_null: shipment_key, bol_identifier, container_number, supplier_key, consignee_key, hs_6, origin_country_code
    - relationships: supplier_key → dim_supplier.supplier_key, consignee_key → dim_consignee.consignee_key, hs_6 → dim_hs_code.hs_6, origin_country_code → dim_country.country_code, date_key → dim_date.date_key
- fact_tariff_events: not_null(event_date, rate_change_pp), accepted_values event_type IN ('section_232', 'section_301', 'other')
- mart_concentration_metrics: not_null(consignee_key, hs_6, supplier_count), relationships to fact_shipments

Run: dbt test. Report all pass/fail.

===========================================
STEP 9 — Cortex Analyst Semantic View
===========================================

Build semantic/ladinglens_semantic_view.yml:

name: LADINGLENS_SEMANTIC_VIEW
description: >
    LadingLens semantic view over Gold layer. Enables natural-language querying of
    US import bill-of-lading shipments, tariff exposure, and supplier/country
    concentration metrics for HS chapters 84/87/39/73/61/62 across origin countries
    DE/BE/VN/ES/GB/FR/MX/CN. Data spans 2018 CBP AMS filings.

tables:
  - name: fact_shipments
    base_table:
      database: LADINGLENS_DB
      schema: GOLD
      table: FACT_SHIPMENTS
    description: One row per shipment (identifier + container). Contains weight, value, effective duty rate, estimated landed cost.
    dimensions:
      - name: hs_6
        expr: hs_6
        synonyms: [hs code, HS code, harmonized code, tariff code, HTS code]
        description: 6-digit Harmonized System code
      - name: origin_country
        expr: origin_country_code
        synonyms: [country of origin, source country, exporting country]
      - name: hs_source
        expr: hs_source_final
        synonyms: [HS code source, classification method]
        description: Whether the HS code came from source field, regex extraction from text, or LLM classification
      - name: party_type
        expr: consignee_party_type
        synonyms: [consignee type, importer type]
    measures:
      - name: total_shipments
        expr: COUNT(*)
        synonyms: [shipment count, number of shipments]
      - name: total_weight_kg
        expr: SUM(weight_kg)
        synonyms: [total weight, aggregate weight]
      - name: total_value_usd
        expr: SUM(shipment_value_usd)
        synonyms: [total shipment value, total customs value]
      - name: total_landed_cost_usd
        expr: SUM(estimated_landed_cost_usd)
        synonyms: [total landed cost, total cost including duties, total tariff exposure]
      - name: avg_effective_duty_rate
        expr: AVG(effective_duty_rate_pct)
        synonyms: [average duty rate, mean tariff rate]
    time_dimensions:
      - name: shipment_date
        expr: date_key
        synonyms: [arrival date, shipment date, date of shipment]
    joins:
      - table_reference: dim_supplier
        conditions:
          - fact_shipments.supplier_key = dim_supplier.supplier_key
      - table_reference: dim_consignee
        conditions:
          - fact_shipments.consignee_key = dim_consignee.consignee_key
      - table_reference: dim_hs_code
        conditions:
          - fact_shipments.hs_6 = dim_hs_code.hs_6
      - table_reference: dim_country
        conditions:
          - fact_shipments.origin_country_code = dim_country.country_code

  - name: dim_consignee
    base_table:
      database: LADINGLENS_DB
      schema: GOLD
      table: DIM_CONSIGNEE
    description: US-based importers of record (consignees on BoL).
    dimensions:
      - name: consignee_name
        expr: consignee_name
        synonyms: [importer name, consignee, company name]
      - name: is_forwarder
        expr: is_forwarder
        synonyms: [freight forwarder flag, is a forwarder]

  - name: dim_supplier
    base_table:
      database: LADINGLENS_DB
      schema: GOLD
      table: DIM_SUPPLIER
    description: Foreign suppliers (shippers on BoL).
    dimensions:
      - name: supplier_name
        expr: supplier_name
        synonyms: [shipper name, supplier, exporter]
      - name: supplier_country
        expr: supplier_country_code

  - name: dim_hs_code
    base_table:
      database: LADINGLENS_DB
      schema: GOLD
      table: DIM_HS_CODE
    description: HS-6 tariff code lookup with descriptions and duty rates.
    dimensions:
      - name: hs_6_description
        expr: hs_6_description
        synonyms: [product description, HS description, tariff description]
      - name: hs_2
        expr: hs_2
        synonyms: [chapter, HS chapter, tariff chapter]
      - name: hs_2_description
        expr: hs_2_description

  - name: dim_country
    base_table:
      database: LADINGLENS_DB
      schema: GOLD
      table: DIM_COUNTRY
    description: Country reference with region and tariff-status flags.
    dimensions:
      - name: country_name
        expr: country_name
      - name: region
        expr: region
      - name: is_section_232_target
        expr: is_section_232_target
      - name: is_section_301_target
        expr: is_section_301_target

  - name: mart_concentration_metrics
    base_table:
      database: LADINGLENS_DB
      schema: GOLD
      table: MART_CONCENTRATION_METRICS
    description: Pre-computed HHI concentration metrics per consignee × HS-6 pair.
    dimensions:
      - name: is_single_source
        expr: is_single_source
        synonyms: [single-source flag, sole-source, single supplier dependency]
      - name: is_single_country
        expr: is_single_country
        synonyms: [single-country flag, sole country dependency, geographic concentration]
    measures:
      - name: max_supplier_hhi
        expr: MAX(supplier_hhi)
        synonyms: [supplier concentration index, HHI on suppliers]
      - name: max_country_hhi
        expr: MAX(country_hhi)
        synonyms: [country concentration index, HHI on countries]
    joins:
      - table_reference: dim_consignee
        conditions:
          - mart_concentration_metrics.consignee_key = dim_consignee.consignee_key
      - table_reference: dim_hs_code
        conditions:
          - mart_concentration_metrics.hs_6 = dim_hs_code.hs_6

===========================================
STEP 10 — Verified queries
===========================================

Build semantic/verified_queries.yml — 12-15 NL→SQL examples that ground Cortex Analyst's retrieval:

- name: top_10_consignees_by_landed_cost
  question: "Which consignees have the highest total landed cost?"
  sql: |
      SELECT c.consignee_name, SUM(f.estimated_landed_cost_usd) AS total_cost
      FROM fact_shipments f
      JOIN dim_consignee c ON f.consignee_key = c.consignee_key
      WHERE f.estimated_landed_cost_usd IS NOT NULL
      GROUP BY c.consignee_name
      ORDER BY total_cost DESC
      LIMIT 10;

- name: single_source_consignees_hs87
  question: "Which consignees are single-sourced for HS chapter 87 (vehicles)?"
  sql: |
      SELECT c.consignee_name, m.hs_6, m.top_supplier_share, m.supplier_count
      FROM mart_concentration_metrics m
      JOIN dim_consignee c ON m.consignee_key = c.consignee_key
      WHERE LEFT(m.hs_6, 2) = '87'
        AND m.is_single_source = TRUE
      ORDER BY m.top_supplier_share DESC
      LIMIT 20;

- name: china_exposure_by_chapter
  question: "What is our tariff exposure to China imports by HS chapter?"
  sql: |
      SELECT hs.hs_2, hs.hs_2_description, COUNT(*) AS shipment_count,
             SUM(f.estimated_landed_cost_usd) AS total_cost
      FROM fact_shipments f
      JOIN dim_hs_code hs ON f.hs_6 = hs.hs_6
      WHERE f.origin_country_code = 'CN'
      GROUP BY 1, 2
      ORDER BY total_cost DESC NULLS LAST;

- name: german_auto_imports_by_supplier
  question: "Show me German suppliers of automotive parts (HS 8708)"
  sql: |
      SELECT s.supplier_name, COUNT(*) AS shipments, SUM(f.weight_kg) AS total_weight
      FROM fact_shipments f
      JOIN dim_supplier s ON f.supplier_key = s.supplier_key
      WHERE f.origin_country_code = 'DE'
        AND LEFT(f.hs_6, 4) = '8708'
      GROUP BY 1
      ORDER BY shipments DESC
      LIMIT 20;

- name: section_232_exposure
  question: "What's my total Section 232 tariff exposure across steel and aluminum?"
  sql: |
      SELECT hs.hs_2, hs.hs_2_description, SUM(f.weight_kg) AS total_weight,
             SUM(f.estimated_landed_cost_usd) AS total_landed_cost
      FROM fact_shipments f
      JOIN dim_hs_code hs ON f.hs_6 = hs.hs_6
      JOIN dim_country c ON f.origin_country_code = c.country_code
      WHERE hs.hs_2 IN ('72', '73', '76')
        AND c.is_section_232_target = TRUE
      GROUP BY 1, 2;

- name: top_forwarders_by_shipment_count
  question: "Who are our top freight forwarders by shipment count?"
  sql: |
      SELECT c.consignee_name, COUNT(*) AS shipments
      FROM fact_shipments f
      JOIN dim_consignee c ON f.consignee_key = c.consignee_key
      WHERE c.is_forwarder = TRUE
      GROUP BY 1
      ORDER BY shipments DESC
      LIMIT 20;

(Add 6-9 more like these. Cover: monthly trends, country diversification, single-country exposure, top HS chapters, LLM-classified rows filter, consignee with highest supplier count.)

===========================================
STEP 11 — Publish the semantic view
===========================================

Build scripts/publish_semantic_view.sql:

Use Snowflake's semantic view DDL (or REST API via Snow CLI). The exact syntax depends on your Cortex Analyst version — check current Snowflake docs. Approximate pattern:

    CREATE OR REPLACE SEMANTIC MODEL LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW
    FROM @LADINGLENS_DB.STAGE.RAW_STAGE/semantic/ladinglens_semantic_view.yml
    WITH VERIFIED_QUERIES FROM @LADINGLENS_DB.STAGE.RAW_STAGE/semantic/verified_queries.yml;

Or via Python SDK if the SQL syntax isn't available in your account.

If Cortex Analyst semantic view publishing isn't yet GA on this account or region, publish through Snowsight UI as a fallback (upload YAML manually) — document which path was used.

===========================================
STEP 12 — Smoke test
===========================================

Build notebooks/06_semantic_view_smoke_test.ipynb — 10 NL queries submitted via the Cortex Analyst REST API or Python client. Record for each:
- The NL question
- The generated SQL
- The row count / first 5 result rows
- Latency in seconds
- Whether the answer looks plausible (human eyeball)

Sample questions:
1. "Which 5 consignees imported the most from China?"
2. "What is the total landed cost of imports from Germany in HS chapter 87 during 2018?"
3. "Show me the top 10 HS-6 codes by total shipment count."
4. "Which consignees are single-sourced for aluminum products?"
5. "What percentage of shipments went through freight forwarders vs direct importers?"
6. "How much weight came from Vietnam in HS chapter 61?"
7. "Which consignee has the highest supplier concentration index (HHI)?"
8. "Show me a monthly trend of shipment count for 2018."
9. "Which countries are subject to Section 232 tariffs, and how many shipments came from them?"
10. "For consignees with single-source risk on HS 8708, which supplier is the sole source?"

If a query fails or returns wrong SQL, log it and continue — the smoke test's value is the diagnostic, not perfect scores.

Report:
- Success rate (how many of 10 returned correct-looking SQL and results)
- p50 and p95 latency
- Any error messages
- Recommendations for semantic-view iteration if success rate < 8/10

===========================================
STEP 13 — Documentation
===========================================

Append to data/sources.md a Phase 6 wrap section:

    Phase 6 wrap — Gold Star Schema + Semantic View:
    
    Gold layer built as Kimball star schema over silver_bol_shipments_scoped:
    - fact_shipments: 89,200 shipments with effective_duty_rate + estimated_landed_cost
    - dim_country, dim_hs_code, dim_supplier, dim_consignee, dim_date
    - fact_tariff_events: 12 hand-curated Section 232/301 events (2018-2025)
    - mart_concentration_metrics: [X] consignee×HS-6 pairs with HHI + single-source flags
    
    Cortex Analyst semantic view published with:
    - 6 tables (fact_shipments, mart_concentration_metrics, 4 dims)
    - [X] measures (total_shipments, total_landed_cost, avg_effective_duty_rate, etc.)
    - [X] dimensions (hs_6, origin_country, party_type, etc.)
    - 12 verified queries covering concentration, tariff exposure, trends, and party-type breakdowns
    
    Smoke test: [X of 10] NL queries returned correct SQL. p50 latency [X]s, p95 [X]s.
    [Any specific failure patterns worth noting.]

Also add the number of dbt tests total (Phase 4 + Phase 5 + Phase 6 combined).

===========================================
EXECUTION ORDER
===========================================

Build in order:
1. dim_country (must exist for fact_shipments join)
2. dim_hs_code (must exist for fact_shipments join)
3. dim_date, dim_supplier, dim_consignee (must exist for fact_shipments FKs)
4. fact_tariff_events + seed
5. fact_shipments (depends on all dims)
6. mart_concentration_metrics (depends on fact_shipments)
7. schema.yml + dbt tests
8. semantic YAML files
9. Publish semantic view
10. Smoke test

At each step: report row counts, dbt test results, any errors. Do NOT proceed past a failing test.

Do NOT commit until all steps complete and I approve the final review.
```

---

## Your Tasks (Human)

- [ ] **Verify the tariff_events.csv historical accuracy** — Check dates and rates against USTR announcements. 12 events is plenty; don't over-engineer.
- [ ] **Test Cortex Analyst in Snowsight** after publishing. Log in, open Cortex Analyst, point at your semantic view, ask 5 questions of your own. Screenshot the ones that produce great answers.
- [ ] **Screenshot the smoke test results** — the "10 questions, 8 correct SQL" story is a resume line.
- [ ] **Review the top single-source consignees** manually. Query `SELECT * FROM mart_concentration_metrics WHERE is_single_source = TRUE ORDER BY total_cost DESC LIMIT 20`. Do the concentrations look believable given the underlying shipments?

---

## Success Criteria

- All Gold models build successfully
- All dbt tests pass (target: 40+ total across all phases)
- Cortex Analyst semantic view published and visible in Snowsight
- Smoke test: ≥ 8 of 10 questions return correct SQL and plausible answers
- Row counts sanity: fact_shipments = 89,200; mart_concentration_metrics has ~30-60K rows
- Section 232 exposure query returns real numbers (not zero) for HS 72/73/76 origins

## Gotchas

- **Cortex Analyst YAML is indent-sensitive.** Silently drops columns on bad indentation. Validate against Snowflake's YAML schema before publishing.
- **Verified queries teach the model your business language.** 15 good ones is far more valuable than 30 boilerplate ones. Focus each on a distinct query pattern (aggregation vs join vs filter vs concentration).
- **Missing shipment_value_usd** (~85% NULL) affects landed_cost calculations. Document this in the semantic view description so users don't misread the metric.
- **Section 301 rates are approximate.** Real Section 301 has per-HS-6 granularity that we don't fully model. Note this as a limitation.
- **Don't publish more than one semantic view.** Cortex Analyst uses the most recent published version. Old versions can silently confuse the LLM if left around.
