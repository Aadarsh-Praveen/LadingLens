# Phase 6 — Gold Layer + Cortex Analyst Semantic View

**Duration:** ~1 day
**Depends on:** Phase 4 (Silver ER), Phase 5 (HS classifier)
**Goal:** Build the analytics-ready Gold layer star schema and expose it as a Cortex Analyst semantic view. This turns your data into a business-friendly NL-to-SQL surface — the "governed self-serve BI" resume signal.

---

## Context

Cortex Analyst reads a **YAML semantic view file** that defines tables, dimensions, measures, verified queries, and business synonyms. The natural-language interface then generates SQL against that view with governed grounding.

The star schema (Kimball-style):
- `fact_shipments` — one row per shipment
- `fact_tariff_events` — one row per historical tariff change (Section 301 rounds, 232 actions)
- `dim_supplier` — golden supplier records
- `dim_consignee` — golden consignee records
- `dim_hs_code` — HS-6 with descriptions and current rate
- `dim_country` — origin country with region
- `dim_date` — date spine

Key computed measures:
- `landed_cost` = shipment_value × (1 + effective_duty_rate)
- `supplier_hhi` = Herfindahl–Hirschman Index of a consignee's supplier concentration for a given HS category
- `single_source_flag` = TRUE if >70% of a consignee's HS-6 volume comes from one supplier
- `tariff_exposure_usd` = sum of landed_cost across a filter set

---

## Deliverables

- [ ] `dbt/models/gold/dim_supplier.sql`
- [ ] `dbt/models/gold/dim_consignee.sql`
- [ ] `dbt/models/gold/dim_hs_code.sql`
- [ ] `dbt/models/gold/dim_country.sql`
- [ ] `dbt/models/gold/dim_date.sql`
- [ ] `dbt/models/gold/fact_shipments.sql`
- [ ] `dbt/models/gold/fact_tariff_events.sql`
- [ ] `dbt/models/gold/mart_concentration_metrics.sql` — pre-computed HHI/single-source per consignee×HS
- [ ] `semantic/ladinglens_semantic_view.yml` — the Cortex Analyst YAML
- [ ] `semantic/verified_queries.yml` — the reference NL→SQL examples
- [ ] `notebooks/06_semantic_view_smoke_test.ipynb` — asks 10 questions, records answers

---

## Claude Code Prompt

```
You are in Phase 6 of LadingLens. Phases 1-5 are complete. Silver layer with ER and HS classification is ready. Read ./LadingLens.md and ./docs/phases/phase-06-gold-semantic.md before starting.

Your task: build the Gold star schema in dbt AND publish a Cortex Analyst semantic view that makes the data queryable via natural language.

Constraints:
- All dbt Gold models materialize as TABLE (not view) — Cortex Analyst prefers materialized inputs.
- Follow strict Kimball star schema conventions: surrogate keys on dims, no measures on dims, one grain per fact.
- The semantic view YAML must include descriptions, synonyms, and at least 15 verified queries.
- Every measure has a business-friendly description and units.

Please build:

1. dbt/models/gold/dim_country.sql
   - country_code (PK), country_name, region, is_section_301_target BOOLEAN, is_ustr_watch_list BOOLEAN
   - Seed the Section 301 targets: CN=TRUE, others FALSE (initial)

2. dbt/models/gold/dim_hs_code.sql
   - hs_6 (PK), hs_6_description, hs_2, hs_2_description, general_duty_rate, section_301_rate, section_232_rate, effective_duty_rate_default
   - Sourced from bronze_hts aggregated to HS-6 grain

3. dbt/models/gold/dim_supplier.sql / dim_consignee.sql
   - From silver_supplier_golden / silver_consignee_golden with a hashed surrogate key

4. dbt/models/gold/dim_date.sql
   - Standard date dimension: date_key, year, quarter, month, day, is_weekend, fiscal_quarter

5. dbt/models/gold/fact_tariff_events.sql
   - Curated list of historical tariff changes: Section 301 List 1-4A, Section 232 steel/aluminum, 2025 tariff wave events
   - Columns: event_date, event_type, hs_scope (list of HS-2 or HS-6), country_scope, rate_change_bps, description
   - Seed from a hand-curated CSV (create dbt/seeds/tariff_events.csv with 10-15 real events, cite USTR sources in comments)

6. dbt/models/gold/fact_shipments.sql
   - Grain: one row per silver_bol_shipments row (post ER + HS classification)
   - FKs: date_key, supplier_key, consignee_key, hs_6, origin_country_code
   - Measures: weight_kg, quantity, teu, shipment_value_usd (if available; else NULL), estimated_landed_cost_usd
   - Compute: effective_duty_rate = dim_hs_code.section_301_rate WHERE dim_country.is_section_301_target ELSE general_duty_rate
   - Compute: estimated_landed_cost_usd = shipment_value_usd * (1 + effective_duty_rate). If shipment_value_usd is NULL, estimate from Comtrade unit-value × weight.

7. dbt/models/gold/mart_concentration_metrics.sql
   - For each (consignee_key, hs_6) pair over trailing 12 months:
     - supplier_count (distinct suppliers)
     - top_supplier_share = MAX(supplier_share) where supplier_share = supplier_weight / total_weight
     - supplier_hhi = SUM(supplier_share^2)
     - is_single_source = top_supplier_share > 0.70
     - top_country_share, country_hhi (same logic on origin_country)
   - This becomes the primary "risk" table

8. semantic/ladinglens_semantic_view.yml — Cortex Analyst YAML
   - Define tables: fact_shipments, dim_supplier, dim_consignee, dim_hs_code, dim_country, mart_concentration_metrics
   - For each column: name, description, synonyms, data_type
   - Measures section:
     - total_shipments (COUNT), total_weight_kg (SUM), total_landed_cost_usd (SUM), avg_effective_duty_rate (AVG), supplier_hhi (from mart), tariff_exposure_usd (SUM landed_cost with filter)
   - Filters section: date range, hs_chapter, origin_country, consignee
   - Relationships: FK joins between fact and dims

9. semantic/verified_queries.yml — 15+ verified NL-to-SQL examples like:
   - "Which consignees have the highest single-country supplier concentration for HS 85?" → SELECT ... FROM mart_concentration_metrics WHERE hs_2='85' ORDER BY top_country_share DESC LIMIT 10
   - "What's the total tariff exposure for imports from China in Q1 2025?" → SELECT SUM(estimated_landed_cost_usd) FROM fact_shipments WHERE origin_country_code='CN' AND date BETWEEN '2025-01-01' AND '2025-03-31'
   - "Show me suppliers with more than 100 shipments to Apple in 2024" → ...
   - (Draft all 15 — cover concentration, tariffs, top-N, trends, filtering by industry)

10. Publish the semantic view to Snowflake:
    - Use `snow cortex analyst publish` or the equivalent SQL command to register the view
    - Confirm it appears in Snowsight

11. notebooks/06_semantic_view_smoke_test.ipynb
    - Uses the Cortex Analyst REST API or Python client to send 10 NL questions
    - For each: record the generated SQL, the answer, and whether the answer looks plausible
    - Include a mix of easy (single-table aggregations), medium (2-table joins), and hard (concentration metric with filters)

Run `dbt build --select gold.*` then the smoke test notebook and report:
- All Gold table row counts
- Any dbt test failures
- The 10 smoke-test Q&A pairs with an assessment of each
- Any Cortex Analyst errors ("could not resolve," "ambiguous column," etc.) — these need semantic view fixes

Ask before adding synonyms that aren't obvious from the data (e.g., only add "iPhone" as a synonym for AAPL after checking that AAPL actually appears in dim_consignee).
```

---

## Your Tasks (Human)

- [ ] **Populate `dbt/seeds/tariff_events.csv`** with 10-15 real tariff events. Sources: USTR Section 301 announcements (https://ustr.gov/), Federal Register tariff notices. Columns: event_date, event_type, hs_scope, country_scope, rate_change_bps, description. This is 30-45 min of research and looks great in the demo.
- [ ] **Run the semantic view smoke test yourself in Snowsight.** Log into Snowsight, open Cortex Analyst, point it at your semantic view, and ask the 10 questions. Note which ones fail and iterate the YAML.
- [ ] **Screenshot Cortex Analyst answering a hard question.** This is a headline demo asset.
- [ ] **Verify `mart_concentration_metrics`** manually: pick one spotlight consignee, run the raw SQL, and check that the HHI number makes sense.

---

## Success Criteria

- `dbt build` on gold layer succeeds with all tests passing.
- Cortex Analyst semantic view is published and visible in Snowsight.
- ≥ 8 of 10 smoke-test questions return correct SQL and reasonable answers.
- `mart_concentration_metrics` has non-null HHI for at least 500 consignee×HS pairs.

## Gotchas

- **Missing shipment values:** BoL often lacks `shipment_value_usd`. Fall back to Comtrade unit-value (USD per kg per HS-6 per origin country) times shipment weight. Document this estimation in the semantic view description.
- **Cortex Analyst YAML is picky.** Indentation errors will silently drop columns. Validate the YAML against the schema in Snowflake docs before publishing.
- **Verified queries** train the LLM's grounding. Invest in these — 15 good ones ≫ 30 bad ones.
- **Don't over-engineer measures.** Start with the 5 most important. You can add more once the smoke test passes.
