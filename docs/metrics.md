# LadingLens — Canonical Metrics

Every number below is traceable to a specific phase doc or `data/sources.md` entry — see the Source column. Where a figure required correction from an earlier planning estimate, the correction and its basis are noted.

| Metric | Value | Source |
|---|---|---|
| Raw shipment rows parsed | 3,825,304 | Phase 2 |
| Raw shipment rows loaded (0.003% reject rate) | 3,825,191 | Phase 2 |
| Distinct container line-items after Bronze dedup | 456,014 | Phase 4 |
| In-scope shipments after Silver/Gold scoping | 89,200 | Phase 5/6 |
| Golden supplier entities | 41,338 (from 44,574 raw names, 1.20x compression) | Phase 4 |
| Golden consignee entities | 40,629 (from 43,322 raw names, 1.23x compression) | Phase 4 |
| Entity resolution F1 (vs. `identified_orgs`, threshold 0.92) | 0.487 (precision 0.782, recall 0.354) — a **floor score**: ground truth tags brand association at the free-text level, our golden IDs resolve legal entity; the two questions have different granularities, so this understates true ER quality | Phase 4 |
| USITC HTS rows ingested | 32,455 (6,630 distinct HS-6 codes in `bronze_hts`) | Phase 2 / Phase 6 |
| HS classification coverage (usable HS-6 or HS-4 code assigned) | 96.6% (43.3% llm_classified_hs6 + 31.9% source_field + 15.9% regex_from_text + 5.5% llm_classified_hs4, of the full 333,739-shipment origin-scoped population) | Phase 5 — corrected from an initially-cited 96.4%, which didn't match the underlying distribution it was supposedly derived from |
| HS-2 (chapter) accuracy on 30-row eval seed | 46.7% (14/30) | Phase 5 |
| HS-4 (heading) accuracy on eval seed | 33.3% (10/30) | Phase 5 |
| HS-6 (subheading) accuracy on eval seed | 16.7% (5/30) | Phase 5 |
| Gold `mart_concentration_metrics` rows | 27,041 consignee × HS-6 pairs | Phase 6 |
| 10-K/20-F filings indexed | 24 | Phase 7 |
| Cortex Search chunks (stride=1500/width=1700, 200-char overlap) | 1,674 | Phase 7 |
| Cortex Search smoke test | 6 strong / 2 partial / 2 weak of 10 | Phase 7 |
| `mart_scenario_examples` rows (20 top consignees × 5 canonical scenarios, delta > 0) | 24 | Phase 8 |
| Cortex Agent tools | 3 (`query_shipments`, `retrieve_10k_risk_factors`, `simulate_tariff_scenario`) | Phase 8 |
| Cortex Agent smoke test | 9 strong / 1 partial of 10, including both fusion queries | Phase 8 |
| Cortex Agent latency | p50 38.3s / p95 93.2s | Phase 8 |
| dbt tests total | 85 (83 pass, 2 intentional warns, 0 errors) | Phase 9 |
| Data quality catches, tallied | 40+ across Phases 4-5 and 7-9 (25 + 6 + 7 + 2); Phase 6's real catches (column substitutions, semantic-view DDL fixes, a fact-grain join constraint) were documented individually but never consolidated into a single number, so this total is a floor, not a complete count | Phases 4-9 |
| Snowpark UDTF optimization (HS classification retrieval) | **>10 hours, unresolved** (naive SQL cross-join never completed) **→ 17 seconds** (vectorized numpy UDTF) — corrected phrasing from an earlier "10hr → 17s" framing that implied the naive approach finished at the 10-hour mark, when it in fact never completed at all | Phase 5 |
| Warehouse compute credits used | 24.17 of 50 (48%), measured directly via `SHOW RESOURCE MONITORS` | Phase 10 regression check |
| Cortex serverless AI spend | Estimated ~$20-40 from token-usage metadata in agent responses; **not independently measurable** — `SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY` still returns zero rows as of Phase 10, well beyond the reporting lag Phase 5 first observed | Phase 5 note; Phase 10 re-check |
| Streamlit panels | 4 (Executive Overview, Concentration Heatmap, Scenario Simulator, Ask LadingLens) | Phase 9 |
| Screenshots captured from the live app | 8 | Phase 9 |
| Project duration | ~7-8 calendar days (first commit 2026-07-22, Phase 9 commit 2026-07-29) | git log — corrected from an initial "~14 days" planning estimate that was never reconciled against actual elapsed time |

## On the "40+ catches" framing

This number is intentionally a floor, not a polished KPI. Phases 4, 5, 7, 8, and 9 each gave an explicit tallied count (25, folded into the Phase 4+5 combined figure; 6; 7; 2 respectively — 25+6+7+2 = 40). Phase 6 documented comparably substantive findings (see `data/sources.md`) but its wrap section never rolled them into a single discrete count, and rather than retroactively invent one, every subsequent phase's documentation has explicitly noted the omission. The discipline being demonstrated is catching and root-causing real issues — the exact count is secondary to that, and this file would rather be honest about its own incompleteness than present a falsely-precise total.
