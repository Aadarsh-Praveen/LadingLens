# Phase 3 — Exploratory Data Analysis

**Duration:** ~1 day
**Depends on:** Phase 2 (all raw tables loaded)
**Goal:** Profile the raw data rigorously, quantify the messiness, choose the target industry vertical(s) to focus on, and produce an EDA report that becomes both a Phase 4 spec input and a portfolio artifact.

---

## Context

This phase is the "real EDA on real messy data" story. Recruiters care about this. Do NOT skip or rush it. The output is a Jupyter notebook + a rendered HTML report + a `docs/eda-findings.md` that summarizes what you learned and locks in your Phase 4 cleaning strategy.

Key questions this phase must answer:
1. How messy is the BoL data? Quantify missingness per column, name-variant duplicates, and HS-code coverage.
2. Which 1-2 industry verticals should we focus on for the demo? (E.g., electronics HS chapter 85 + apparel HS chapters 61-62.)
3. Which SEC 10-K filers have the richest supply-chain risk-factor text? (Not all 10-Ks are equally detailed.)
4. What are the top consignees / shippers / origin countries in the sample? These become the "spotlight companies" in the demo.
5. Is there enough tariff variation across HS codes and origin countries to make the scenario simulator meaningful?

---

## Deliverables

- [ ] `notebooks/01_eda_bol.ipynb` — BoL profiling
- [ ] `notebooks/02_eda_hts_and_comtrade.ipynb` — Tariff schedule + Comtrade profiling
- [ ] `notebooks/03_eda_sec_10k.ipynb` — 10-K text stats & risk factor sampling
- [ ] `notebooks/04_eda_synthesis.ipynb` — Cross-source join feasibility check
- [ ] `docs/eda-findings.md` — Written report summarizing findings + decisions
- [ ] `docs/eda-report.html` — Exported HTML version of the synthesis notebook
- [ ] `config/target_scope.yml` — Locked in: which HS chapters, which countries, which tickers we focus on

---

## Claude Code Prompt

```
You are in Phase 3 of LadingLens. Phases 1 and 2 are complete — raw data is loaded in LADINGLENS_DB.RAW. Read ./LadingLens.md and ./docs/phases/phase-03-eda.md for context.

Your task: build four EDA notebooks that profile the raw data rigorously and produce a written findings report that locks in the scope for Phase 4.

Constraints:
- Use snowflake-snowpark-python or snowflake-connector-python to query, and pandas + polars for local analysis.
- Every chart uses plotly or seaborn (no plain matplotlib unless it's a quick histogram).
- Every SQL query is shown in the notebook markdown before its result so the reader learns from it.
- Every claim in the notebooks (e.g., "42% of rows missing shipper_country") must be reproducible from a cell above it.
- Save notebook outputs as executed .ipynb files, not just the code.

Please build:

1. notebooks/01_eda_bol.ipynb — BoL profiling
   Sections (each a markdown header + code cells + interpretation cell):
   a. Row count, date range, columns overview
   b. Missingness heatmap by column (use missingno or plotly)
   c. Distribution of shipments per consignee (log-scale histogram) — identifies power-law
   d. Company name variation analysis: for the top 100 consignees, how many raw name variants exist per "canonical" name? Use a simple similarity heuristic (lowercase, strip punctuation, first 15 chars) to group. Report the compression ratio (raw_names / grouped_names).
   e. Origin country distribution — top 20 countries by shipment count and total weight
   f. HS-code coverage: what % of rows have a non-null hs_code_raw? Of those, what's the distribution of HS chapters? For rows WITHOUT hs_code_raw, is the product_description_raw usable (avg length, non-null rate)?
   g. Port coverage: top loading/unloading ports, coverage gaps
   h. Duplicate BoL detection: how many BoL numbers appear more than once? What's the pattern (same date / different date)?

2. notebooks/02_eda_hts_and_comtrade.ipynb
   Sections:
   a. HTS table row count, chapter coverage, and rate distribution
   b. How many HTS lines carry Section 301 duties (China)? Section 232? Show the rate distributions.
   c. UN Comtrade: US import value by top 20 partners × 2023, 2024, 2025. Which HS-6 categories have the biggest trade values? Which have the biggest year-over-year swings (proxy for tariff-shock exposure)?
   d. Cross-check: for the top 10 HS-6 categories by trade value, join to HTS to show the effective rate. Are there mismatches where the HTS says "free" but Comtrade shows Section 301 exposure? Investigate.

3. notebooks/03_eda_sec_10k.ipynb
   Sections:
   a. Filings loaded: ticker × filing_date matrix
   b. Item 1A length distribution — which tickers have the richest risk-factor sections (>10k chars)?
   c. Keyword frequency in Item 1A: count occurrences of ["tariff", "Section 301", "China", "single supplier", "sole source", "concentration", "geopolitical", "supply chain disruption", "component shortage"]. Which tickers over-index on supply-chain risk language? These become "spotlight" companies for the demo.
   d. Sample 3 verbatim risk-factor passages from 3 different tickers that mention supplier concentration explicitly — save to docs/sample-risk-passages.md for later use in the Cortex Search demo.

4. notebooks/04_eda_synthesis.ipynb — the join-feasibility check
   Sections:
   a. Can we link BoL consignees to SEC 10-K tickers? Try fuzzy-matching the top 50 BoL consignees to the ticker company names. Report the match rate (this is the KPI for Phase 4 entity resolution).
   b. Can we link BoL product descriptions to HS codes? Sample 20 product descriptions and manually assign the "correct" HS-6; save as data/labels/hs_eval_seed.csv. This is your Phase 5 eval seed set.
   c. Scenario feasibility: for the top 5 spotlight companies, compute a rough "current tariff exposure" using naive rules (BoL weight × origin country's average duty rate from HTS). Does the number look reasonable ($M-scale for large importers)?

5. docs/eda-findings.md — 2-3 page report structured as:
   ## Data Volume Summary
   ## Messiness Findings (with %s)
   ## Chosen Scope (HS chapters, countries, tickers)
   ## Risks & Mitigations
   ## Phase 4 Input: cleaning rules to implement

6. config/target_scope.yml — machine-readable version of the scope decision:
   hs_chapters_focus: [61, 62, 85]  # apparel + electronics (or whatever the EDA says)
   origin_countries_focus: [CN, VN, MX, TW, KR]  # or based on data
   spotlight_tickers: [AAPL, NKE, ...]  # 5-10 tickers with rich 10-K content

7. docs/eda-report.html — export the synthesis notebook via `jupyter nbconvert --to html`.

Run the notebooks end-to-end and report:
- Any surprising findings (unexpectedly clean, unexpectedly messy)
- Which cleaning rules you recommend for Phase 4
- Whether the chosen scope has enough BoL volume (target: at least 50k shipments in scope) and enough 10-K text to be interesting

If a notebook cell fails on data quality (e.g., column missing that we expected), do not silently fix it — log it in eda-findings.md as a real finding.
```

---

## Your Tasks (Human)

- [ ] **Manually label 20 BoL product descriptions** with correct HS-6 codes for the eval seed set. Use https://hts.usitc.gov/search as your lookup tool. This should take ~30 minutes and is critical — Phase 5's accuracy metric depends on it.
- [ ] **Skim `docs/eda-findings.md`** and challenge anything that looks too pat. Do the numbers pass the smell test?
- [ ] **Approve or edit `config/target_scope.yml`**. This locks in Phase 4-8 scope.
- [ ] **Screenshot the missingness heatmap and the shipment-per-consignee histogram** — you'll use these in the final demo video.
- [ ] **Save `docs/sample-risk-passages.md`** as demo material — the verbatim 10-K quotes make great voiceover in the final video.
- [ ] **Check ImportYeti status again.** If the CSV arrived, note whether the row count matches expectations vs. the sample.

---

## Success Criteria

- All 4 notebooks execute top-to-bottom without errors.
- `docs/eda-findings.md` cites at least 10 numeric findings from the notebooks.
- `config/target_scope.yml` is committed and covers at least 2 HS chapters, 5 countries, 5 tickers.
- At least 50k BoL shipments fall inside the chosen scope (if the sample dataset is smaller, that's fine for prototype — flag it in findings).
- `data/labels/hs_eval_seed.csv` has 20 human-labeled rows.

## Gotchas

- **Don't over-tune the scope to make numbers pretty.** The demo is stronger if you honestly say "we found consignee X has 78% single-country exposure to HS 8541 from China" than if you cherry-pick.
- **The BoL sample might not overlap perfectly with the 10-K tickers.** That's fine — the demo can show "consignees like Apple / Nike / X Corp" without a perfect overlap. Note it explicitly.
- **20 hand-labeled HS codes is the minimum.** More is better if you have time; consider labeling 50 if the ImportYeti data arrived.
- **Watch for date-boundary issues.** UN Comtrade 2025 data may be incomplete (year-in-progress). Document this and use 2023-2024 as the "stable" comparison years.
