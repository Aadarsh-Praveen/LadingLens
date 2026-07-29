# Hackathon Submission Form — Draft

Drafted against typical hackathon submission form fields (project name, tagline, problem statement, summaries, tech stack, metrics). Adapt on submission day if the actual Hack2Skill form has different fields or character limits.

Fields are plain text, no embedded markdown — most submission forms strip formatting.

---

## 1. PROJECT NAME

**COPY THIS INTO THE FORM:**
```
LadingLens
```

---

## 2. TAGLINE

**RESOLVED** — leads with "tariff exposure" as the primary noun; fusion angle described plainly (the "structured + unstructured fusion" framing is reserved for the LinkedIn post, not this tagline).

**COPY THIS INTO THE FORM** (145 chars):
```
Tariff exposure and supplier concentration copilot fusing US customs records, tariff schedules, and SEC filings into one Snowflake-native answer.
```

Rejected alternatives (kept for reference only):
```
Know your tariff exposure and supplier concentration in seconds, not days — powered by Snowflake Cortex over real customs and SEC data.

A Snowflake-native Cortex Agent that fuses 3.8M customs shipments with SEC 10-K filings to answer tariff exposure questions.
```

---

## 3. PROBLEM STATEMENT SELECTION

**COPY THIS INTO THE FORM:**
```
Primary: Unstructured Data Intelligence System
Secondary (if multi-select allowed): Domain-Specific AI Copilot
```

---

## 4. SHORT SUMMARY (300 char max)

**RESOLVED** — leads with "tariff exposure...copilot," follows with the Cortex-native customs + 10-K fusion, closes with a concrete proof point (89,200 in-scope shipments, 96.6% HS coverage).

**COPY THIS INTO THE FORM** (285 chars):
```
LadingLens is a tariff exposure and supplier concentration copilot, built Snowflake-native: a Cortex Agent fuses 3.8M US customs shipments with 24 SEC 10-K filings into a single conversational answer, backed by a pipeline covering 89,200 in-scope shipments with 96.6% HS-code coverage.
```

---

## 5. LONG DESCRIPTION (1000-3000 char range)

**COPY THIS INTO THE FORM:**
```
THE PROBLEM

US importers navigating a shifting tariff landscape (Section 232 steel/aluminum, Section 301 China measures) need to answer two questions fast: how concentrated is my supplier base for a given product category, and what would a specific tariff change actually cost me? Today, answering either means manually cross-referencing bill-of-lading shipment records, the USITC Harmonized Tariff Schedule, and SEC 10-K risk disclosures — three data sources maintained by different agencies and companies that were never designed to be joined.

WHAT LADINGLENS DOES

LadingLens is a Snowflake-native pipeline that fuses all three sources into one system:

- 3.8M real US customs bill-of-lading records (NIST FEIII 2019 dataset), scoped to 89,200 in-scope shipments across a dbt medallion architecture (Bronze/Silver/Gold)
- Entity-resolved suppliers and consignees (41,338 and 40,629 golden entities) built from noisy free-text shipper/consignee name fields
- An HS tariff-code classifier reaching 96.6% coverage on messy shipment descriptions, combining source-field matches, regex extraction, and LLM-based classification (via a Cortex-powered Snowpark UDTF)
- A native Snowflake SEMANTIC VIEW and Cortex Search index over 24 SEC 10-K/20-F filings (1,674 searchable chunks)
- A Cortex Agent that chains structured semantic-view queries, unstructured 10-K retrieval, and a tariff scenario simulator into single answers to fusion questions like "If Section 232 tariffs doubled, what would BMW's exposure be?"
- A 5-panel Streamlit-in-Snowflake app: Executive Overview, Concentration Heatmap, Scenario Simulator, Ask LadingLens (agent chat), and Observability (live agent trace logging)

WHAT MAKES THIS DIFFERENT

This isn't a demo built on clean synthetic data. It's built on real, messy customs records, and the build log documents 40+ specific data-quality catches with root cause analysis rather than papering over them — including a systematic sentinel-identifier issue affecting 36% of a ticker field and a dormant schema-drift bug in the classification layer. The whole stack — ingestion, transformation, semantic layer, search, agent orchestration, and UI — runs natively on Snowflake with no external services.

KEY METRICS

- 89,200 in-scope shipments processed through the dbt medallion pipeline
- 96.6% HS classification coverage on messy free-text shipment descriptions
- Snowpark UDTF optimization: a naive SQL cross-join that never completed after 10+ hours, replaced with a vectorized approach that runs in 17 seconds
- Cortex Agent smoke test: 9 of 10 test queries fully correct, including both cross-source fusion queries
- 40+ documented data-quality catches with root cause analysis across the build

This project was built solo over roughly 7-8 calendar days, with every non-obvious claim in its documentation checked against the live Snowflake account rather than assumed from planning docs.
```

Character count: ~2,920 (fits a 3,000-char cap; trim the "WHAT MAKES THIS DIFFERENT" paragraph first if the actual form caps lower, e.g. at 2,000).

---

## 6. GITHUB REPO URL

**COPY THIS INTO THE FORM:**
```
[Placeholder — fill in your repo URL]
```

---

## 7. DEMO VIDEO URL

**COPY THIS INTO THE FORM:**
```
[YOUTUBE_URL_HERE]
```

---

## 8. TECH STACK

**COPY THIS INTO THE FORM:**
```
Snowflake Cortex Agent, Snowflake Cortex Search, native Snowflake SEMANTIC VIEW, dbt-core, dbt-snowflake, Snowpark Python (UDFs and stored procedures), Streamlit-in-Snowflake, Python 3.11
```

---

## 9. TEAM SIZE

**COPY THIS INTO THE FORM:**
```
Solo — Aadarsh Praveen
```

---

## 10. KEY METRICS (for judges scanning)

**RESOLVED** — trimmed to 6 headline metrics. Entity counts, warehouse credit usage, and dbt test count were dropped from this scannable list (they remain documented in `docs/metrics.md`).

**COPY THIS INTO THE FORM:**
```
- 89,200 in-scope shipments processed through the dbt medallion pipeline (from 3.8M raw customs records)
- 96.6% HS classification coverage on messy free-text shipment descriptions
- Snowpark UDTF optimization: >10 hours (unresolved, naive approach) reduced to 17 seconds
- Cortex Agent smoke test: 9 of 10 queries fully correct, including both cross-source fusion queries
- 40+ documented data-quality catches with root cause analysis across the build
- 24 SEC 10-K/20-F filings indexed via Cortex Search (1,674 searchable chunks)
```

---

## 11. WHAT MAKES THIS DIFFERENT

**COPY THIS INTO THE FORM:**
```
- Built on real, messy US customs data (NIST FEIII 2019), not synthetic or cleaned-up examples — including a 36% sentinel-identifier data quality issue that had to be diagnosed and worked around, not hidden
- Multi-modal fusion: structured customs/tariff data, unstructured SEC filing text, and computed what-if scenarios, all answerable from one conversational interface
- 40+ documented data-quality catches with root cause analysis, not just a final polished number — the build log treats data problems as findings, not embarrassments
- End-to-end Snowflake-native: ingestion, dbt transformation, semantic layer, search, agent orchestration, and UI all run inside one platform, no external services stitched in
```

---

## 12. WHAT YOU LEARNED / KEY INSIGHTS

*(include only if the actual form has a field for this)*

**COPY THIS INTO THE FORM:**
```
- Managed cloud services often have undocumented or incorrectly-documented behavior (agent invocation syntax, tool-type parameter restrictions, package installation mechanics) — empirical verification against the live account caught several issues the official docs didn't mention.
- Latent bugs can sit dormant through an entire pipeline until a specific downstream workload exercises the exact code path that triggers them — a schema-drift bug in the classification layer only surfaced once Cortex Search was built on top of it.
- Aggregate metrics like concentration indices (HHI) or weighted rates are not composable across grouping levels — averaging pre-computed finer-grained values produces mathematically wrong results; they must be recomputed from raw components at the grain you actually need.
```

---

## 13. FUTURE WORK

*(include only if the actual form has a field for this)*

**COPY THIS INTO THE FORM:**
```
Documented in full at docs/roadmap.md. Highlights: resolving the remaining Bronze-layer extraction gaps for 4 tickers, improving cross-prefix entity resolution, moving concentration analysis from count-based to volume-weighted HHI, and adding streaming responses to the Cortex Agent to reduce perceived latency.
```

---

## Status

All fields resolved — tagline, short summary, and key-metrics list finalized per final review. No open judgment calls remain.
