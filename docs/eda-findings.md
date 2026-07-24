# Phase 3 — EDA Findings

Source notebooks: `notebooks/01_eda_bol.ipynb`, `02_eda_hts_and_trade.ipynb`,
`03_eda_sec_10k.ipynb`, `04_eda_synthesis.ipynb`. Figures: `docs/eda-figures/`.

## Data Volume Summary

| Table | Rows | Notes |
|---|---|---|
| `BOL_SHIPMENTS` | 3,825,191 | `trade_update_date` spans 2013-04-11 to 2018-05-29 (wider than the nominal Feb-Jun 2018 window — see identifier finding below, not a parsing shift) |
| `HTS_TARIFF_SCHEDULE` | 32,455 | 97 of 99 nominal chapters (chapter 99 entirely absent from the free export) |
| `SEC_10K_FILINGS` | 19 (of 25 target tickers) | all filed in 2025 |

Distinct entities: 128,448 distinct `consignee_name` values across 3,231,581 non-null-consignee
shipments; 292,122 distinct "specific-looking" `identifier` values (see below).

## BoL Data Quality Findings

**HS code coverage (resolves the Phase 2 open item):** true coverage of the structured
`harmonized_number` field is confirmed at **42.4%** (not an artifact of empty-string/`'0'`
placeholder handling — the field is genuinely absent for the rest). An additional **13.8%** of
all rows carry an extractable HS code inside the free-text `text` field (e.g. `"...HS CODE:
8438.1010"`), giving a **56.2% combined ceiling** if regex-based text extraction is built in a
later phase. The Snowflake-parsed 42.4% is more trustworthy than the naive pre-load 62.9% estimate,
which likely picked up HS-like digit patterns anywhere in the raw line, including inside free text.

**Company name variation:** naive heuristic grouping (lowercase, strip punctuation, first 15
chars) over the top 200 consignees/shippers by volume gives compression ratios of only **1.14x**
(consignees, 200→175 groups) and **1.12x** (shippers, 200→178 groups). These numbers *understate*
true fragmentation — the known 4-way Mercedes-Benz split (`MERCEDES-BENZ U.S.` / `MERCEDES BENZ,
USA (PDC DALLAS)` / `MERCEDES BENZ USA LLC` / `MERCEDES BENZ`) only partially collapsed under this
heuristic because a hyphen vs. space difference broke the first-15-char match for one variant.
This is itself evidence that Phase 4 needs real fuzzy/blocking-based ER, not string-prefix
matching — messiest clusters found: `SHIPCO TRANSPORT` (4 variants), `DHL GLOBAL FORWARDING` (4
variants), `MERCEDES BENZ` (3 of 4 variants), `EXPEDITORS INTERNATIONAL` (3 variants), `KUEHNE +
NAGEL` (3 variants).

**Missingness patterns:** 10 operationally-important columns full-scanned exactly; `identified_orgs`
is null on 81.0%, `harmonized_number`/`harmonized_weight`/`harmonized_value` in the 54-58% range,
`shipper_party_name` 21.4%, `consignee_name` 15.5%. `trade_update_date`, `foreign_port_of_lading`,
`port_of_unlading`, and `container_number` are essentially fully populated (<0.1% null). No
dedicated `shipper_country`/`consignee_country` column exists — country is only derivable from
`shipper_address`/`consignee_address` free text or from parsing `foreign_port_of_lading`, which is
itself a data-quality finding: **country will need to be extracted during Silver-layer cleaning**
for use as an entity-resolution blocking key in Phase 4.

**Duplicate/sentinel `identifier` values — a real finding, not the expected "multi-line BoL"
story:** the top `identifier` values by row count are suspiciously round numbers (`2020000000000`,
`2018020000000`, ...) decoding to a `YYYY`+`MM`+`00000` placeholder pattern. **36.2% of all rows
(1,383,935) carry one of these sentinel-like identifiers** — meaning for roughly a third of the
table, `identifier` is a missing-value placeholder, not a genuine per-shipment key. Only the
remaining 63.8% (2,439,134 rows, 292,122 distinct values) look like real, specific BoL identifiers.
**Implication for Phase 4: `identifier` cannot be used as a shipment/line-item grouping key without
first excluding this sentinel pattern**, or it will silently merge over a million unrelated
shipments.

**Country/port name inconsistencies:** `foreign_port_of_lading` and `port_of_unlading` are both
free text (not UN/LOCODE-normalized) — e.g. `"Bremerhaven,Federal Republic of Germany"` vs. a
plain city name elsewhere. Normalization is Phase 4 work.

**`identified_orgs` as weak ER ground truth:** confirmed at 19.0% coverage (matches Phase 2).
Sample values are short clean tokens (e.g. `BMW`), distinct from `consignee_name`, suggesting a
pre-computed named-entity extraction — usable as a partial sanity-check signal for Phase 4's ER
output, not a complete labeled set.

## HTS & Tariff Landscape

**Rate parsing:** of the 11,593 rows with non-null `general_rate_text`, **88.8% parse cleanly** as
a plain ad-valorem percentage (or `Free` → 0%); the remaining 11.2% need unit-aware parsing
(specific rates like `1¢/kg`, `0.9¢ each`, compound rates). Median parsed rate is **2.7%**, 90th
percentile **10.0%**, and 43.0% of parsed lines are `Free`.

**Section 301/232 coverage — medium, empirically measured, per the agreed three-bucket plan:**
chapter 99 (where Section 301/232 overlay rates would live as their own rows) is **entirely
absent** from the free USITC export (0 rows). However, **31.2% of HTS lines (10,114)** carry a
footnote cross-reference to a `9903.88.XX` code (the Section 301 China-tariff family), and a
further ~450 lines reference `9903.90/9903.91` (plausibly Section 232 steel/aluminum derivatives).
So the export can identify *which* base HS lines are flagged for an overlay, but not the overlay's
own duty rate. **Per the agreed medium-coverage plan: Phase 6 should supplement with a
hand-curated Section 301/232 CSV** (e.g. `dbt/seeds/tariff_events.csv`) rather than attempting to
back-infer overlay rates from raw duty amounts.

**Chapter-level rate cross-check** against the top BoL HS chapters: footwear (64, 15.7% avg) and
apparel (61, 12.5%) carry the highest average duty among chapters observed in BoL; vehicles (87,
5.8%), plastics (39, 5.2%), furniture (94, 5.5%) are mid-range; chapter 48 (paper) shows no
measurable ad-valorem rate in the parsed sample (effectively duty-free entry).

## SEC 10-K Text Landscape

19 of 25 target tickers loaded (6 failures carried over unchanged from Phase 2: `DELL`/`INTC`/`EMR`
on Item 1A length, `JNPR`/`HBI`/`GES` on ticker→CIK resolution). **All 19 loaded filings clear
10k+ characters of Item 1A text** — the Phase 2 regex fix (longest-span-across-all-matches instead
of first-match) generalized well. **Item 7 (MD&A) verdict: not usable as-is** — only 6 of 19
tickers (`CAT`, `LULU`, `NKE`, `NVDA`, `PH`, `RL`) have >3,000 chars; the rest show near-zero
length from the same Table-of-Contents-match failure mode that was fixed for Item 1A but not
re-applied to Item 7. **Deferred**, not a Phase 2/3 blocker.

**Spotlight companies** (top 10 by supply-chain-risk keyword density across 12 terms in Item 1A):
`ANET`, `LULU`, `PVH`, `LEVI`, `DE`, `HPQ`, `NKE`, `RL`, `WDC`, `AMD`. Five verbatim risk passages
saved to `docs/sample-risk-passages.md` (`ANET`, `LULU`, `LEVI`, `DE`, `HPQ`) — all genuinely
supplier/geographic-concentration language after fixing a false-positive match (an initial PVH
candidate matched on "concentrat*" but was actually about *pension plan* risk, not supply chain;
excluded via a context filter).

## Cross-Source Joinability

**BoL consignee ↔ 10-K ticker match rate: 0 of the top 50 consignees, and it's a genuine gap, not
a threshold artifact.** Fuzzy-matching (RapidFuzz token-set ratio) the top 50 BoL consignees
against the 19 loaded tickers' company names produced a best score of ~31/100 — nowhere near the
85-point confidence bar. `config/target_tickers.yml` was built from a plausibility guess
("electronics + apparel importers") before real BoL data existed; the actual top consignees are
foreign automakers (BMW, Mercedes-Benz, Volvo, JLR), global freight forwarders (Schenker, DHL,
Expeditors, Yusen, Maersk, Panalpina, CEVA), and retail/CPG names (Walmart Canada, IKEA, Adidas,
Gap, Red Bull, Anheuser-Busch) — essentially disjoint from the ticker list. **This makes ticker
backfill a Phase 4 requirement, not an optional nice-to-have**, if the demo wants a "structured
shipment + unstructured 10-K risk" fusion answer built around an actual top consignee. Candidate
backfill tickers: `BMWYY`, `MBGAF`, `VLVLY`, `TTM` (JLR's parent Tata Motors), `WMT`, `ADDYY`.

**HS label seed set:** 30 rows sampled from BoL descriptions with no structured `harmonized_number`,
saved to `data/labels/hs_eval_seed.csv` with `correct_hs_6` left blank — your manual task before
Phase 5 (use https://hts.usitc.gov/search).

**Tariff-exposure sanity check** (naive formula, top 5 consignees by volume): mixed results, not
uniformly clean. BMW Manufacturing shows a plausible $4.67M declared value / ~$210K naive exposure
(~4.5% effective); Schenker Inc (a freight forwarder acting as consignee-of-record for many
underlying shippers) shows $652M declared value / ~$32M exposure — large numbers that reflect its
role aggregating many shipments, not one importer's true exposure. Three of the five (the Mercedes
variants) show **$0** — those specific name-variant rows apparently lack populated
`harmonized_value`/`harmonized_weight` pairs required by the formula. This is a genuine partial
result, reported honestly rather than smoothed over; Phase 6's real landed-cost calculation will
need to handle freight-forwarder-as-consignee separately from true importers (see Gotchas below).

**Feasibility verdict:** the structured+unstructured fusion story is achievable, but not for free —
it requires either (a) backfilling parent/ADR tickers for the actual top consignees, or (b)
choosing the demo's "spotlight consignee" from a company that already exists in both datasets
after backfill. The unstructured side (10-K risk text) is strong on its own merits (rich Item 1A
text, real supplier-concentration language); the join is the weak link, not the content.

## Chosen Scope (locked in `config/target_scope.yml`)

- **HS chapters in scope:** 87 (vehicles), 84 (machinery), 39 (plastics), 61 (apparel, knit), 62
  (apparel, woven), 73 (steel) — 598,449 BoL shipments fall in these chapters (target was ≥50k).
- **Origin countries in scope:** DE, BE, VN, ES, GB, FR, MX, CN — **pivoted away from the original
  China-centric draft** to reflect actual volume (Germany 1.13M shipments, Belgium 889K, Vietnam
  454K vs. China's 74,780 / ~2% — China ranks 9th, not 1st).
- **Spotlight tickers:** `ANET`, `LULU`, `PVH`, `LEVI`, `DE`, `HPQ`, `NKE`, `RL`, `WDC`, `AMD`.

This deviates from the Phase 3 doc's illustrative draft (which listed CN first and included JP/KR,
neither of which appear meaningfully in the real top-20 origin list) — per the agreed
evidence-over-assumption approach, the notebook 04d analysis, not the draft, is authoritative.

## Risks & Mitigations

- **Automotive dominance may be a sampling artifact of this specific NIST slice**, not a
  representative picture of US imports generally — worth stating explicitly in any demo narrative
  rather than implying it generalizes.
- **The China/Section 301 narrative doesn't fit this data slice well.** The stronger, honest
  tariff story here is EU auto-parts/steel (Section 232) and Vietnam apparel/footwear exposure.
  Pivoting the demo narrative accordingly avoids forcing a mismatched story onto the evidence.
- **BoL consignee ↔ 10-K join is currently 0%.** Without ticker backfill, the flagship
  "structured+unstructured fusion" demo answer has no natural subject. This is the single biggest
  risk carried into Phase 4.
- **Freight forwarders as consignee-of-record** (Schenker, DHL, Expeditors, Yusen, Maersk,
  Panalpina, CEVA — several in the top 20) aren't the true importer; any concentration-risk or
  tariff-exposure metric computed naively against them will be misleading. Phase 4 should consider
  distinguishing "true consignee" from "notify party / freight forwarder" using shipper-address
  consistency, per the Phase 3 doc's own gotcha.
- **`identifier`'s sentinel-value pattern (36.2% of rows)** must be filtered before any grouping/
  join logic uses it as a shipment key.

## Phase 4 Inputs

- **Cleaning rules:** normalize company names (legal-suffix stripping, punctuation) with real
  fuzzy/blocking-based ER, not prefix matching; extract country from address/port-of-lading text;
  exclude sentinel `identifier` values before any BoL-number-based grouping; standardize port names
  toward UN/LOCODE.
- **ER label source:** `identified_orgs` (19% coverage) as a partial sanity-check signal.
- **Recommended ticker backfill (high priority, not optional):** `BMWYY`, `MBGAF`, `VLVLY`, `TTM`,
  `WMT`, `ADDYY` — needed to lift the 0% BoL↔10-K match rate for any consignee the demo wants to
  feature.
- **HS regex-extraction opportunity:** the 13.8%-of-total-rows "HS code mentioned in free text but
  not in `harmonized_number`" gap (notebook 01c) is a concrete, already-scoped feature-engineering
  task.
