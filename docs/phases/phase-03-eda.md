# Phase 3 — Exploratory Data Analysis

**Duration:** ~1 day
**Depends on:** Phase 2 (all three raw tables loaded and verified in `LADINGLENS_DB.RAW`)
**Goal:** Profile the raw data rigorously, quantify the messiness, choose the target industry vertical(s) for the demo, and produce an EDA report that becomes both a Phase 4 input and a portfolio artifact.

---

## Context — what Phase 2 gave us

Phase 2 landed three tables in `LADINGLENS_DB.RAW`:

| Table | Rows | Notes from ingestion |
|---|---|---|
| `HTS_TARIFF_SCHEDULE` | 32,455 | USITC HTS Rev 11 (July 2026), 97 chapters |
| `BOL_SHIPMENTS` | 3,825,191 | Regular table (Iceberg fallback), 0.003% CSV reject rate |
| `SEC_10K_FILINGS` | 19 (out of 25 tickers) | DELL/INTC/EMR failed on <5000 char Item 1A; JNPR/HBI/GES failed on ticker→CIK lookup |

Two Snowflake Marketplace shares also in-account:
- `DB_SHIPPING_INSIGHTS_SAMPLE.SHARED_SHIPPINGDATA_INSIGHTS_SAMPLE.SHIPPING_INSIGHTS_DATA_SAMPLE` (1000 rows, premium schema for cross-validation)
- `CEIC_SHIPPING_DATA.MARKETPLACE_LISTINGS.MARKETPLACE_SHIPPING_SERIES` / `MARKETPLACE_SHIPPING_TIMEPOINT` (port activity, macro context)

## Preliminary signals to investigate

From a quick top-20 consignees query already run, the BoL slice appears **automotive-heavy**:
- BMW MANUFACTURING CORP alone = 100,849 shipments (2.6% of all rows)
- Mercedes-Benz appears under 4+ name variants totaling ~104K shipments (an obvious entity resolution win)
- Volvo, Jaguar Land Rover, Schaeffler (auto parts), BASF (chemicals for auto) all in top 20
- Freight forwarders (DHL, Schenker, Expeditors, Yusen) also dominate — some rows are shipment intermediaries, not final consignees
- Two known open questions from Phase 2 to resolve here:
  - `harmonized_number` populated in only 42.4% of rows (below the 62.9% pre-load naive estimate). Investigate: is this genuine missingness, a CSV parsing artifact, or filer-specific?
  - Item 7 (MD&A) text in `SEC_10K_FILINGS` is inconsistent (many 0-length). Decide if usable.

## Key questions this phase must answer

1. **How messy is the BoL data?** Quantify missingness per column, name-variant duplicates, HS-code coverage, duplicate BoL numbers, non-standard country/port names.
2. **Which industry verticals should we focus the demo on?** The data leans automotive; original plan targeted electronics + apparel. Update `config/target_scope.yml` based on evidence, not assumption.
3. **Which SEC 10-K filers have the richest supply-chain risk-factor text?** Not all 19 filers wrote about supply chain the same way. Identify 5-10 "spotlight companies" for the demo copilot.
4. **What are the top consignees / shippers / origin countries in scope?** These become the demo's characters.
5. **Is the tariff-exposure narrative visible?** For the top spotlight consignees, is there enough tariff variation (Section 301, 232) across HS codes and origin countries to make the Phase 8 scenario simulator meaningful?
6. **Do the sources join?** Can we fuzzy-match top BoL consignees to SEC 10-K ticker company names? What's the match rate — because that's the Phase 4 entity resolution KPI.

---

## Deliverables

- [ ] `notebooks/01_eda_bol.ipynb` — BoL profiling
- [ ] `notebooks/02_eda_hts_and_trade.ipynb` — Tariff schedule profiling + Section 301/232 coverage
- [ ] `notebooks/03_eda_sec_10k.ipynb` — 10-K text stats & risk factor sampling
- [ ] `notebooks/04_eda_synthesis.ipynb` — Cross-source join feasibility check
- [ ] `docs/eda-findings.md` — Written report summarizing findings + decisions
- [ ] `docs/eda-report.html` — Exported HTML of the synthesis notebook
- [ ] `docs/sample-risk-passages.md` — 3-5 verbatim 10-K risk passages saved for demo use
- [ ] `data/labels/hs_eval_seed.csv` — 20+ hand-labeled BoL description → HS-6 pairs (human task)
- [ ] `config/target_scope.yml` — Locked in scope: HS chapters, origin countries, spotlight tickers

---

## Claude Code Prompt

```
You are in Phase 3 of LadingLens. Phase 2 is complete — three raw tables live in LADINGLENS_DB.RAW. Read ./LadingLens.md, ./docs/phases/phase-03-eda.md, and ./data/sources.md (the Phase 2 output with known data-quality notes) before starting.

Your task: build four EDA notebooks that profile the raw data rigorously, resolve the open data-quality questions from Phase 2, and produce a written findings report that locks in the scope for Phases 4-8.

Constraints:
- Use snowflake-snowpark-python or snowflake-connector-python to query. Use pandas + polars for local analysis. Use plotly for all charts (no plain matplotlib).
- Every SQL query is shown in the notebook markdown before its result so a reader learns from it.
- Every claim (e.g., "42% of rows missing shipper_country") must be reproducible from a cell above it in the notebook.
- Save notebook outputs as EXECUTED .ipynb files (with cell outputs preserved), not just the code.
- Use LADINGLENS_WH (XS warehouse) throughout. Do NOT scale up.

Please build:

===========================================
1. notebooks/01_eda_bol.ipynb — BoL profiling
===========================================

Sections (each a markdown header + code cells + a one-paragraph interpretation cell at the end of each section):

a. Overview: row count (should be 3,825,191), date range (min/max on trade_update_date and actual_arrival_date), column list.

b. Missingness heatmap: use missingno or a plotly heatmap. For each of the 31 columns, compute null % on a stratified sample (100k rows) and full-scan just the important columns.

c. Investigate the harmonized_number gap: Phase 2 reported 42.4% coverage vs. a naive pre-load estimate of 62.9%. Determine which is correct:
   - Count rows where harmonized_number IS NULL vs '' vs '0' vs actual code
   - Sample 50 rows where harmonized_number is NULL — is the text field populated with HS references buried inside? (Look for regex 'HS[ -]?CODE|HS[ -]?\\d{4,10}' in the text column.)
   - Report: "true HS coverage = X%; additional Y% mentioned in text field, could be regex-extracted"
   - This resolves the open data quality item from Phase 2.

d. Shipments-per-consignee distribution: log-scale histogram. Report power-law statistics (top 1%, 10%, 50% share of all shipments).

e. Company name variation analysis:
   - For the top 200 consignees by shipment count, look for near-duplicates using a simple heuristic (LOWER, strip punctuation, first 15 chars).
   - Report the compression ratio (raw_names / grouped_names).
   - Show the top 10 messiest clusters (most raw variants collapsing to one canonical) — Mercedes-Benz will be one of these.
   - Do the same for the top 200 shippers.

f. Origin country distribution: top 20 foreign_port_of_lading values with shipment count + total weight (harmonized_weight). Note countries with wide name variation (e.g., "Anvers,Belgium" vs "Antwerp, BE").

g. HS-chapter distribution (from the 42% of rows with harmonized_number): top 15 chapters by row count. This confirms the automotive-heavy hypothesis or refutes it.

h. Port coverage: top 20 port_of_unlading values, top 20 foreign_port_of_lading, note any that appear as raw strings needing UN/LOCODE normalization.

i. Duplicate BoL detection: how many identifier values appear more than once? Same-day duplicates vs different-day? Are they legitimate multi-line BoLs or actual duplicates?

j. identified_orgs coverage: confirm the 19% number, show distribution of what values look like (5 sample rows), assess whether it can serve as ground-truth ER labels for Phase 4.

===========================================
2. notebooks/02_eda_hts_and_trade.ipynb — Tariff schedule profiling
===========================================

Sections:

a. HTS table row count (32,455), chapter coverage (97 chapters), indent-level distribution (how deep is the hierarchy?).

b. Rate parsing: general_rate_text contains mixed formats ("Free", "3.4%", "1.5¢/kg", "See 9902..."). Extract a numeric rate_ad_valorem_pct where possible; report the % of lines that parse cleanly vs. those that need special handling.

c. Section 301 / 232 detection: search description and footnote-referenced HTS chapter 99 subheadings for Section 301 (China lists 1-4A, HTS 9903.88.XX) and Section 232 (steel/aluminum, HTS 9903.80.XX) additional duties. Report how many base HS lines are affected.

d. Rate distribution: histogram of ad valorem rates for lines that parse. Median, 90th percentile.

e. Cross-check with BoL: for the top 15 HS chapters observed in BoL (from notebook 01), pull the average general rate from HTS. Which chapters have high tariffs (>5% MFN) vs. free entry?

===========================================
3. notebooks/03_eda_sec_10k.ipynb — 10-K text stats
===========================================

Sections:

a. Filings loaded: show the 19 tickers with filing_date, item_1a_length, item_7_length. Explicitly note the 6 failures (DELL/INTC/EMR content-extraction, JNPR/HBI/GES CIK-lookup) from Phase 2.

b. Item 1A length distribution: which tickers have the richest risk-factor sections (>10k chars)?

c. Item 7 (MD&A) assessment: how many have usable MD&A text (>3000 chars)? If most are broken, note that and mark item_7 as deferred-to-later.

d. Keyword frequency in Item 1A: count occurrences of these terms per ticker:
   ["tariff", "Section 301", "Section 232", "China", "single supplier", "sole source", "concentration", "geopolitical", "supply chain disruption", "component shortage", "customs", "import duty"]
   Rank tickers by total supply-chain-risk mentions. Top 5-10 become "spotlight companies."

e. Sample 3-5 verbatim risk-factor passages that mention supplier concentration explicitly. Save to docs/sample-risk-passages.md with ticker + filing_date attribution. These will be Cortex Search demo material in Phase 7.

===========================================
4. notebooks/04_eda_synthesis.ipynb — Cross-source join feasibility
===========================================

Sections:

a. BoL consignee → SEC 10-K ticker match rate:
   - Take the top 50 BoL consignees.
   - Fuzzy-match to the 19 SEC 10-K filers (use rapidfuzz or a simple ratio-based match).
   - Report: how many top consignees have a matching 10-K? Which ones? Which don't?
   - This is Phase 4's ER KPI baseline.
   - Note: BMW / Mercedes / Volvo / JLR won't match to loaded 10-Ks (foreign parents). WMT should match if Walmart appears. Explicitly document the gap so Phase 3 output tells us whether to add tickers (like TTM for JLR, BASFY for BASF, VOLVY, MBGAF) in Phase 4 iteration.

b. BoL product_description → HS code mapping (Phase 5 seed set preparation):
   - Sample 30 random product_description values from BOL_SHIPMENTS where harmonized_number IS NULL and description is non-empty.
   - Save them to data/labels/hs_eval_seed.csv with columns: product_description, correct_hs_6, notes. Leave correct_hs_6 blank — the user will fill it in (their manual task).
   - The user will need this in Phase 5 to measure LLM classifier accuracy.

c. Rough tariff-exposure sanity check:
   - For the top 5 spotlight consignees (by shipment count), estimate current tariff exposure using the naive formula:
     tariff_exposure_usd = SUM(harmonized_weight × unit_value × general_rate)
     where unit_value can be approximated as (harmonized_value / harmonized_weight) averaged across rows with values.
   - Does the number look plausible ($M-scale for large importers)? Explicit sanity check.

d. Scope recommendation for `config/target_scope.yml`:
   - Based on the automotive-heavy sample, propose: HS chapters 87 (vehicles), 85 (electronics), 61-62 (apparel), 84 (machinery).
   - Origin countries: propose top-10 by weight in scope chapters.
   - Spotlight tickers: propose 5-10 that both (a) have rich 10-K text from notebook 03 and (b) have a plausible BoL consignee link (or note if link is via parent ticker like TTM/JLR).

===========================================
5. docs/eda-findings.md — 2-3 page report
===========================================

Structure:

## Data Volume Summary
Row counts per table, date ranges, distinct entity counts.

## BoL Data Quality Findings
- HS code coverage: X% direct + Y% regex-extractable from text (resolves Phase 2 open item)
- Company name variation: raw → grouped compression ratio, top messy clusters
- Missingness patterns: which columns are systematically null vs. filer-specific
- Duplicate BoL patterns
- Country/port name inconsistencies

## HTS & Tariff Landscape
- Parsable rate distribution, Section 301/232 coverage
- Which HS chapters carry the highest exposure

## SEC 10-K Text Landscape
- 19 filers profiled; top 5-10 by supply-chain-risk keyword density identified
- Item 7 (MD&A) assessment — usable or defer
- Sample risk passages saved

## Cross-Source Joinability
- BoL consignee ↔ 10-K ticker match rate
- BoL description ↔ HS6 sample labeled (seed set for Phase 5)
- Feasibility verdict for the "structured + unstructured" agent story

## Chosen Scope (locked)
- HS chapters in scope: [list]
- Origin countries in scope: [list]
- Spotlight tickers: [list]

## Risks & Mitigations
- Any surprises. Any pivots needed for Phase 4+.

## Phase 4 Inputs
- Cleaning rules to implement
- ER label source (identified_orgs from BoL + fuzzy-match evidence)
- Recommended tickers to backfill if match rate is low

===========================================
6. config/target_scope.yml — machine-readable scope lock
===========================================

hs_chapters_focus:
  - 87  # vehicles (primary — richest data)
  - 85  # electronics
  - 61  # apparel knitted
  - 62  # apparel woven
  - 84  # machinery
origin_countries_focus:  # populate from notebook 01f
  - CN
  - DE  # Germany — auto imports
  - MX
  - JP
  - KR
  - VN
  - TW
spotlight_tickers:  # populate from notebook 03d
  # (final list based on notebook analysis — do NOT hardcode without checking)
notes:
  - "Automotive over-represented in NIST sample; primary demo vertical."
  - "BMW/Mercedes/Volvo/JLR have no US-listed 10-K; may need parent tickers (BMWYY, MBGAF, VLVLY, TTM) for Phase 7 join."

===========================================
7. docs/eda-report.html
===========================================

Export the synthesis notebook via `jupyter nbconvert --to html notebooks/04_eda_synthesis.ipynb --output-dir docs/`.

===========================================
Execution & reporting
===========================================

Run all four notebooks end-to-end. Report:
- Surprising findings (unexpectedly clean, unexpectedly messy)
- Resolution of the two Phase 2 open items (harmonized_number gap; Item 7 usability)
- The scope decision (chapters + countries + tickers)
- Whether the chosen scope has enough BoL volume (target ≥50k shipments in scope)
- Whether at least 5 spotlight tickers have both rich 10-K text AND plausible BoL linkage

If a notebook cell fails on data quality (e.g., a column value that breaks a query), do NOT silently fix it — log it in eda-findings.md as a real finding.

Do NOT modify existing files: .env, .env.example, dbt/profiles.yml, .gitignore, docs/phases/*.md, LadingLens.md.

Ask me before making any assumption not covered above. In particular, ask before:
- Changing the scope beyond what notebook 04d recommends
- Adding new tickers to config/target_tickers.yml (Phase 4 territory)
- Overwriting data/sources.md (append only)
```

---

## Your Tasks (Human)

- [ ] **Manually label the 20-30 BoL product descriptions** with correct HS-6 codes in `data/labels/hs_eval_seed.csv` (Claude Code writes the file with blank labels; you fill in the codes). Use https://hts.usitc.gov/search as your lookup tool. ~30-45 min. This is critical — Phase 5's accuracy metric depends on it.
- [ ] **Skim `docs/eda-findings.md`** after Claude Code generates it. Challenge anything that looks too pat. Do the numbers pass the smell test?
- [ ] **Approve or edit `config/target_scope.yml`.** This locks in scope for Phases 4-8. If you want a different vertical mix (e.g., drop apparel entirely, add chemicals), edit here.
- [ ] **Screenshot the missingness heatmap and shipments-per-consignee histogram** — great for the final demo video.
- [ ] **Read `docs/sample-risk-passages.md`** — these verbatim 10-K quotes are the "hero" content for the Cortex Search demo in Phase 7.
- [ ] **Optional: decide whether to add parent tickers** (BMWYY, MBGAF, VLVLY, TTM) to `config/target_tickers.yml` for Phase 4-7. Not required now — can defer.

---

## Success Criteria

- All 4 notebooks execute top-to-bottom without errors.
- `docs/eda-findings.md` cites ≥ 10 numeric findings from the notebooks.
- `config/target_scope.yml` is committed with ≥ 3 HS chapters, ≥ 5 countries, ≥ 5 tickers.
- Chosen scope covers ≥ 50k BoL shipments (should be easy — automotive alone is >150k).
- `data/labels/hs_eval_seed.csv` has ≥ 20 rows (blank labels are fine after Phase 3 — user fills in).
- Both Phase 2 open items resolved (HS coverage explained; Item 7 verdict rendered).

## Gotchas

- **Don't over-tune the scope to make numbers pretty.** The demo is stronger if you honestly say "consignee X has 78% single-country exposure to HS 8541 from China" than if you cherry-pick around imperfect data.
- **Sample-size for name-variation analysis:** doing pairwise fuzzy match across all 3.8M rows is expensive. Restrict to top-N consignees/shippers as specified. Full ER runs in Phase 4 with proper blocking.
- **The 42% HS coverage may hide extractable HS codes in the `text` field.** The regex sub-analysis in notebook 01c is the resolution — don't skip it.
- **NIST sample is Feb-June 2018.** If the notebook shows dates outside that range, investigate — could indicate CSV parsing shifted rows.
- **XS warehouse only.** Full-scan aggregates on 3.8M rows will take 10-30 seconds. That's expected. Do NOT scale up to save time.
- **BMW/Mercedes/Volvo are foreign parents with no US 10-K filed with SEC EDGAR under those tickers.** The join feasibility check will show a low ticker-match rate — that's a REAL finding, not a bug. Document it clearly; Phase 4 will decide whether to backfill parent tickers.
- **Freight forwarders (DHL, Schenker, Expeditors, Yusen) in top consignees:** these are 3PLs, not final importers. Note this in findings; Phase 4 may want to distinguish "true consignee" from "notify party / freight forwarder" using the shipper vs. consignee address consistency signal.
