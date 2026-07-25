# Data sources — provenance

| Source | URL | License | Retrieval date | Row count | Messiness notes |
|---|---|---|---|---|---|
| NIST FEIII 2019 BoL sample | Local file `data/raw/bol/export_sample_countries_challenge_with_orgs.csv.gz` (originally distributed via Google Drive by NIST for the 2019 FEIII TechSprint) | Public research dataset (US government / NIST) | 2026-07-23 | 3,825,191 loaded of 3,825,304 parsed (113 rows rejected, 0.003%) | `harmonized_number` populated on only 42.4% of rows (1,621,056) vs. the ~63% (2.4M) benchmark expected from earlier exploration — see note below. `identified_orgs` populated on 19.0% (724,973), matching expectation. `trade_update_date` spans 2013-04-11 to 2018-05-29 (wider than the expected 2017-12–2018-06 window; a small number of rows carry much older dates). Free-text `text` (product description) fields contain embedded commas/quoting inconsistencies; 113 rows had description text overflow into numeric columns and were dropped by `ON_ERROR = 'CONTINUE'`. Loaded as a regular Snowflake table, not Iceberg — trial account rejected `CREATE EXTERNAL VOLUME`-backed Iceberg tables (`NUMBER` without explicit precision/scale isn't supported for Iceberg columns on this account). |
| USITC Harmonized Tariff Schedule | https://hts.usitc.gov/reststop/exportList (public REST endpoint) | US government, public domain | 2026-07-23 | 32,455 rows across 97 HS-2 chapters | Clean relative to BoL/SEC sources — flattened JSON->CSV with derived `hs2`/`hs4`/`hs6`/`hs8`/`hs10` prefix columns. Chapter count (97) is slightly below the ~99 nominal HTS chapter count; chapters 77 (reserved for future use) and 98/99 (special classification provisions) are sparsely or not populated in the export, which is expected/documented USITC behavior, not a load defect. |
| SEC EDGAR 10-K filings | https://www.sec.gov/ (via `sec-edgar-downloader`, public HTTPS EDGAR endpoints) | Public domain (US government filings) | 2026-07-23 (Phase 2); backfilled 2026-07-25 (Phase 4) | 19 of 25 target tickers loaded at Phase 2; **24 of 25+ as of Phase 4** (see "SEC 10-K ticker backfill" note below for the full Phase 4 backfill/retry outcome) | 6 tickers failed at Phase 2: `DELL`, `INTC`, `EMR` had Item 1A extraction below the 5,000-char threshold on first pass (regex boundary detection failed for their specific document structure); `JNPR`, `HBI`, `GES` failed ticker→CIK resolution in the downloader library entirely (not attempted further, per phase plan — failures are logged and skipped, not retried). Phase 4 resolved `JNPR`/`HBI`/`GES` via explicit-CIK bypass and added `WMT`/`TTM`; `DELL`/`INTC`/`EMR` and one foreign 20-F filer (`STLA`) remain open (Phase 7). `item_7` (MD&A) extraction is materially weaker than `item_1a` across almost all Phase-2-era filers (several rows show `item_7_length` of 0 or single digits) — Item 7 section-boundary detection needs further regex work in a later phase if MD&A text is required; it was not a load-blocking criterion for Phase 2. |
| D&B Shipping Insights Sample (Snowflake Marketplace) | `DB_SHIPPING_INSIGHTS_SAMPLE.SHARED_SHIPPINGDATA_INSIGHTS_SAMPLE.SHIPPING_INSIGHTS_DATA_SAMPLE` | Snowflake Marketplace listing (sample/free tier) | Subscribed 2026-07-23 (verified same day) | 1,000 | Sample listing, 158 columns; not ingested/transformed this phase — reserved for later cross-validation against BoL-derived supplier data. |
| CEIC Shipping Data (Snowflake Marketplace) | `CEIC_SHIPPING_DATA.MARKETPLACE_LISTINGS.MARKETPLACE_SHIPPING_SERIES` / `MARKETPLACE_SHIPPING_TIMEPOINT` | Snowflake Marketplace listing (sample/free tier) | Subscribed 2026-07-23 (verified same day) | 25 (series) / 6,687 (timepoint) | Port activity / freight-rate time series; not ingested/transformed this phase — reserved for macro-context features in a later phase. |

## Known Data Quality Notes (for Phase 3 EDA to address)

- **Storage: `BOL_SHIPMENTS` landed as a standard Snowflake `TABLE`, not Iceberg** — the trial account lacks `EXTERNAL VOLUME` privileges (`CREATE EXTERNAL VOLUME` failed; separately, Iceberg tables on this account also reject `NUMBER` columns without explicit precision/scale). This is the documented fallback per the Phase 2 spec, not an error. Can be migrated to Iceberg later if the account tier changes.
- **BoL `harmonized_number` coverage: 42.4%** (1,621,056 of 3,825,191 rows) — Snowflake-parsed, and likely more accurate than the naive-awk pre-load estimate of 62.9% quoted in earlier exploration. Investigate in Phase 3 EDA to confirm whether the gap is genuine missingness or a parsing artifact.
- **SEC 10-K failures (6 of 25 tickers):** `DELL`, `INTC`, `EMR` — Item 1A extraction produced <5,000 chars, likely filer-specific document-format quirks; `JNPR`, `HBI`, `GES` — ticker→CIK resolution failed in `sec-edgar-downloader`, possibly a stale ticker cache in the library. Not retried this phase, per plan.
- **SEC Item 7 (MD&A) extraction is inconsistent** — many rows show 0-length or near-0-length `item_7_text`. Not a Phase 2 blocker since only Item 1A had a coverage requirement. Address in Phase 3, or defer to whichever later phase actually needs MD&A text.
- **USITC_DATAWEB_TOKEN / USITC_DATAWEB_API_BASE** (in `.env`) are unused as of Phase 2 — provisioned for a now-superseded plan (UN Comtrade-style aggregate trade flows), left in place pending a decision on whether they're needed later.
- **Bronze BoL dedup key (Phase 4, final):** `(identifier, container_number)` with `ORDER BY trade_update_date DESC`. Three iterations were required to identify the correct grain. Round 1 used `(identifier, description_sequence_number)` — silently collapsed 259K distinct shipments per sentinel value because `description_sequence_number` does not uniquely identify container lines within a BoL; a single BoL can have multiple containers all sharing `seq=1`. Round 2 attempted compound content-key dedup as a workaround but was misdiagnosed. Round 3 (final) uses `(identifier, container_number)`, verified via empirical spot-check on the worst-case group (identifier `2018040647536`): 28 distinct containers preserved (not 1), 47× intra-container exact-duplicate repetition correctly collapsed. Combined with the round-2 sentinel filter (three regex families for three sentinel identifier patterns) and a `container_number IS NOT NULL`/non-empty check, Bronze retains **456,014** genuinely distinct container line-items — the true analytical grain for downstream ER and concentration analysis. HS coverage after regex-from-text extraction: **45.6%** (131K from source field, 76K from regex extraction). `container_number` is 100% populated on sentinel-filtered rows (no fallback key needed). Top BoLs by container count are large freight-forwarder/carrier consolidations (LCL shipments with hundreds of containers under a single master BoL, consignee = the ocean carrier itself — e.g. MSC, Maersk, Hapag-Lloyd), verified as legitimate multi-container shipments, not residual dedup bugs.
- **Party `registered_country` derivation (Phase 4 Silver):** iteratively refined to catch (a) full country names, (b) two-letter codes at end of address, (c) US fallback for CBP AMS convention (US importers omit "USA" from domestic addresses because it's implicit in an inbound-import filing). Final coverage: consignee US 62.7%, consignee NULL 23%; supplier NULL 63.8% (foreign shippers rarely have US-format addresses — this is honest data ambiguity, not a fixable gap). Discovered mid-Phase 4 that all `REGEXP_LIKE` patterns had been dead code due to Snowflake's full-string-match semantic requiring a leading `.*` prefix; fixed once found — this was the single largest driver of low coverage across several iteration rounds. Country accuracy on populated rows verified via spot-checks: no false positives on foreign-named US operations (e.g. `SASOL GERMANY GMBH`'s actual Camden NJ address correctly resolves to US), no false positives on Mexican/Turkish/Italian/Spanish 5-digit-ZIP addresses (a real bug caught and fixed — 59 Mexican consignees were briefly mistagged US via the bare-ZIP fallback before exclusion guards were added; one residual edge case remains where a single truncated address variant lacks any Mexico marker). Accepted at these coverage levels because the `blocking_key` (`LEFT(name_norm, 8) || '|' || country`) subdivides even the NULL bucket by name prefix, keeping downstream pair-generation tractable.
- **Entity resolution final state (Phase 4 Silver):** 44,574 raw supplier names → 41,338
    golden entities (1.20× compression). 43,322 raw consignee names → 40,629 golden
    entities (1.23× compression). Modest compression ratios reflect the honest reality of
    a 5-month customs data slice: ~50-57% of raw names never enter a pair candidate pool
    because they're singletons in their (name-prefix, country) blocking key, and a
    documented ~10-20% recall loss on cross-prefix variants (e.g., Mercedes-Benz variants
    that don't share the first 8 characters after normalization). Top clusters are real
    freight-forwarder and consolidator entities — Kuehne+Nagel, Hellmann, DSV, Panalpina,
    Schenker — with 15-30 raw variants each. Threshold locked at 0.92 to preserve
    precision on same-brand-different-legal-entity pairs (DHL Belgium ↔ DHL Luxembourg,
    Mercedes-Benz U.S. ↔ Mercedes-Benz Vans LLC): merging these would falsely aggregate
    concentration exposure across independent legal entities. Placeholder pollution
    (535 consignee names matching UNKNOWN/TO ORDER/NA/etc.) filtered before ER via
    is_placeholder classifier; excluded from pair-scoring but preserved in silver_bol_
    shipments as unclustered singletons. Eleven distinct data-quality bugs were caught
    and resolved during Phase 4 iterative development (sentinel filters, dedup key grain,
    country substring escapes, port-fallback semantic mismatch, US-implicit CBP AMS
    convention, Snowflake REGEXP_LIKE full-string-match quirk, placeholder pollution).
- **Silver scope (Phase 4 final):** 52,611 in-scope shipments (HS 84/87/39/73 dominate; HS 61/62 apparel has 653 rows total, insufficient for spotlight-consignee concentration analysis; retained in data for aggregate views only). Real analytical base is smaller than earlier phase estimates because Phase 4 corrected Bronze grain to (identifier, container_number) after discovering description_sequence_number wasn't unique per container line. The 52K figure is honest and adequate — 8,835 distinct golden suppliers with real concentration variation across HS 84 (machinery), HS 87 (vehicles), HS 39 (plastics), and HS 73 (steel). Demo narrative pivoted from original Section 301 (China) framing to Section 232 (EU auto/steel + Vietnam apparel) reflecting actual data content.

- **ER F1 vs identified_orgs (Phase 4 final, at threshold 0.92):**
    - Precision: 0.782
    - Recall: 0.354
    - F1: 0.487

    This score is a floor, not a defect signal. Ground truth (identified_orgs) tags
    shipment BRAND ASSOCIATION at the free-text level (all BMW-bound cargo tagged 'BMW'
    regardless of which legal entity is the actual named consignee), while our golden
    IDs resolve consignee LEGAL ENTITY. The two questions have legitimately different
    granularities. Diagnostic breakdown of the 'BMW' label (580 labeled rows): 62 distinct
    golden IDs, including correctly-separate legitimate legal entities (BMW MANUFACTURING
    CORP, BMW CANADA, BMW AUSTRALIA, BMW DE MEXICO) plus rows NIST tagged 'BMW' that are
    genuinely unrelated named consignees on the actual bill of lading (Senator Logistics,
    Swafford Transport, Hellmann, Magna Drive — freight forwarders and independent
    suppliers). Precision (0.78) is the trustworthy half: when we assert two rows share
    a golden entity, we're right 78% of the time on the labeled subset. Recall (0.35) is
    depressed by the label-granularity mismatch, not by threshold or clustering defects.

- **Phase 4 wrap:**
    Eleven distinct data-quality bugs surfaced and resolved during Phase 4 iterative
    development. Each was caught via sanity-check queries between transformations, none
    reached downstream analysis:
    1. Sentinel-identifier filter round 1 (missed 7-trailing-zero variant)
    2. Dedup key over-collapse from combining sentinel filter with (identifier, seq)
    3. Sentinel filter round 2 (found third sentinel family with short-prefix pattern)
    4. Dedup key grain mismatch (description_sequence_number ≠ per-container)
    5. Country-substring escapes on bare 2-letter codes (%DE%, %ES%, %CN%)
    6. Port-of-Spain collision with SPAIN substring
    7. Port-based fallback semantic overload (party registration vs cargo transit)
    8. Missing US-implicit CBP AMS convention (99% NULL fixed to 63% populated)
    9. Snowflake REGEXP_LIKE full-string-match quirk (all 17 patterns dead code)
    10. Placeholder pollution in ER (unknown notify party, to the order of, etc.)
    11. Golden ID threshold interpretation (mercedes-benz 6-way split defended as legit)

    Final artifacts:
    - Bronze BoL: 456,014 clean line-item rows (from 3,825,191 raw, 88% sentinel/duplicate removal)
    - Bronze HTS: 26,750 rows (deduped on hts_number from the 32,455-row raw USITC load --
      ~17.6% of raw rows shared a duplicate hts_number; not investigated further this phase
      since HTS wasn't a Phase 4 focus area, flagged here so the discrepancy is on record)
    - Silver golden: 41,338 unique supplier entities (1.20x compression), 40,629 unique
      consignee entities (1.23x compression)
    - Silver scoped fact: 52,611 in-scope shipments across HS 84/87/39/73 (steel/vehicles/
      machinery/plastics dominate). HS 61/62 apparel at 653 rows: retained but flagged as
      insufficient for spotlight-consignee concentration analysis.
    - Ticker backfill: 24 of 25+ target filings loaded (up from 19 at Phase 2, and from
      23 pre-retry). 5 of the 10 Phase 4 backfill/retry tickers succeeded (GES, HBI, JNPR
      from the retry list; WMT and TTM from the foreign-parent/retail list, TTM via the
      timeboxed 20-F retry below). 5 failed: DELL, INTC, EMR (retry list, Item 1A/7
      extraction still below threshold) and STLA, VWAGY (foreign 20-F parents — see the
      SEC 10-K ticker backfill note below for the retry outcome and why each remains
      unresolved).
    - ER F1: 0.487 (precision 0.78, floor score; label-granularity gap documented)
    - Threshold locked at 0.92 with documented DHL/Mercedes precision-preservation rationale
    - 19/19 dbt tests pass

    Demo narrative pivoted from original Section 301 (China) framing to Section 232
    (EU auto/steel/machinery) reflecting actual data content. HS 84 (machinery) + HS 87
    (vehicles) + HS 39 (plastics) + HS 73 (steel) are the primary spotlight verticals.

- **SEC 10-K ticker backfill (Phase 4 Step 0):**
    - Loaded: 24 of 25+ target filings (up from 19 baseline in Phase 2).
    - Successful retries via explicit CIK bypass of stale sec-edgar-downloader ticker cache:
      GES, HBI, JNPR, WMT (4 of 10 attempted retries).
    - Persistent failures:
        - DELL, INTC, EMR: US 10-K filers with format quirks that resist the current
          longest-span Item 1A extraction heuristic. Deferred; not a foreign-issuer gap.
        - STLA, VWAGY, TTM: foreign 20-F filers (Stellantis, Volkswagen AG, Tata Motors).
          Timeboxed 30-min retry (2026-07-25) resolved 1 of 3 (TTM). Findings:
            - **TTM (Tata Motors) — fixed and loaded.** The CIK on file (0001269823) was
              wrong — it resolved to an unrelated entity ("EV LLC"), not Tata Motors.
              Corrected to 0000926042 (verified against EDGAR's own submissions API,
              which lists Tata Motors' 20-F filings back to 2015). Also fixed a real bug
              found along the way: `strip_html()` wasn't stripping the hidden inline-XBRL
              `<ix:header>` metadata block that large modern filers embed at the top of
              the primary document — on Stellantis's filing this block alone was 998,050
              of ~1.28M stripped characters, pure noise (`iso4217:USD xbrli:shares ...`)
              that could bury or shift real narrative content for any large filer, not
              just these three. Fixed in `strip_html()`. Separately, discovered that 20-F
              filers frequently drop "Item N" prefixes from body section headings
              entirely (keeping them only in an end-of-document regulatory
              cross-reference table), which is why `ITEM_3D_START` (Risk Factors) matched
              zero times in both Stellantis's and Tata Motors' filings even after the
              ix:header fix. Item 5 (Operating and Financial Review) happened to still
              repeat cleanly enough in Tata Motors' filing for the existing longest-span
              logic to extract 126,303 chars of genuine MD&A-style prose (spot-checked:
              reads as real financial discussion, not table-of-contents noise). Relaxed
              the load-gate for `filing_type = '20-F'` to accept a filing if *either*
              Item 3.D or Item 5 clears the 5,000-char threshold, rather than requiring
              Item 3.D specifically — 10-K gating is unchanged.
            - **VWAGY (Volkswagen AG) — confirmed unresolvable, not a bug.** The CIK on
              file (0000723612) was also wrong — verified via direct EDGAR lookup to
              belong to Avis Budget Group, Inc., an unrelated US company. Searched EDGAR
              (company lookup + full-text search) for Volkswagen AG as a 20-F *filer*
              (not merely mentioned in other companies' filings) and found zero results.
              Volkswagen does not file 20-F with the SEC — its VWAGY ADR trades OTC
              without SEC reporting obligations (a real-world fact, not a data-pipeline
              gap). Removed the bogus CIK from `config/target_tickers.yml` with a comment
              explaining why; no further work will resolve this.
            - **STLA (Stellantis) — still fails, deeper issue than a quick regex fix.**
              CIK was already correct and multiple in-window 20-F filings exist (verified
              via EDGAR submissions API). Even after the ix:header fix, neither Item 3.D
              nor Item 5 extracts real content: unlike Tata Motors, Stellantis's filing
              has literally zero repeated "Item N" heading occurrences in the visible
              body text — both only appear once, in the end-of-document cross-reference
              table. The real Risk Factors prose is genuinely present in the document
              (confirmed by direct inspection — e.g. "risks related to..." sub-headings
              starting around char 18,000, continuing for ~280K characters) but has no
              literal "Item 3" / "D." / "Risk Factors" anchor text preceding it in any
              form our regex-on-stripped-text approach can reach. Fixing this would need
              full DOM-aware HTML parsing (e.g. BeautifulSoup on heading tags/styling)
              rather than a regex tweak — out of scope for a 30-minute timebox. **Deferred
              to Phase 7 as a targeted debug task** before wiring Cortex Search over 10-K
              text, if Stellantis-style foreign-parent coverage becomes a priority then.

    Impact on demo narrative:
      - The BoL↔10-K fusion story spotlights US-based consignees plus one confirmed
        foreign parent: Walmart (WMT), Tata Motors (TTM, MD&A-only text), Nike (NKE),
        Apple (AAPL), Caterpillar (CAT), Deere (DE), HP (HPQ), AMD, Lululemon (LULU).
      - Section 232 (steel/machinery/plastics) tariff exposure analysis works for
        US importers directly and doesn't require foreign-parent linkage.
      - The BMW/Mercedes/Volvo/JLR spotlight-consignee-with-10-K-text moment remains
        'future work' pending Stellantis-style 20-F parsing resolution (VWAGY is
        permanently out of reach; STLA is a Phase 7 candidate; BMW/Mercedes/Volvo/JLR
        were never in the ticker list at all and would need their own CIK research).

## Phase 4 open items / future work

- **STLA (Stellantis) 20-F extraction:** filing lacks in-body 'Item N' anchor text
  making regex-based section extraction impossible. Resolution requires DOM-aware
  HTML parsing or ML section-classification. Deferred to Phase 7 (Cortex Search
  wiring) where an alternative parser (sec-api, xbrl-us, or Cortex Extract) may
  be evaluated as a replacement.
- **DELL, INTC, EMR 10-K extraction:** US 10-K filers with format quirks resisting the
  longest-span Item 1A extraction heuristic. Same resolution path as STLA.
- **Cross-prefix ER variants:** ~10-20% projected recall loss on entity variants that
  share no 8-character prefix (e.g., MERCEDES-BENZ ↔ DAIMLER MERCEDES). Requires
  secondary blocking pass via coarse embedding clusters. Documented as a scope
  boundary; production ER systems typically implement this as a second matching pass.
