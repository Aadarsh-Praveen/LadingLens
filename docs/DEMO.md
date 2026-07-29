# LadingLens Demo Video Script (5 minutes)

All numbers and examples below are pulled directly from verified screenshots
and live regression-tested queries (Phase 9 `docs/screenshots/`, Phase 10
Step 0 regression check) -- nothing in this script is aspirational or
unverified.

## Setup

- Snowsight open, `LADINGLENS_APP` loaded and warmed up
- **Run one throwaway agent question 30+ seconds before recording** (e.g.
  "How many shipments total?") to absorb the warehouse-resume delay so the
  first on-camera query isn't a cold start on top of the 40-90s fusion latency
- Screen recording ready (Loom or QuickTime), 1080p minimum
- Audio checked
- Browser zoom at a level where table text is legible on camera

**Known gotcha, confirmed during Phase 10 prep**: the Concentration Heatmap's
"10-K risk factors" drill-down (Panel 2) is restricted to `exact`-confidence
ticker matches only (a deliberate Phase 9 correctness decision -- Phase 7's
fuzzy matches include confirmed false positives like HPQ->Ford Motor
Company). None of the 4 exact-match tickers (DE, PH, LEVI, RL) rank in the
heatmap's top-30-by-volume consignee list, so **the 10-K expander in Panel 2
will show "no confidently-matched 10-K filer" for every consignee actually
visible there.** Do NOT demo that expander live -- it won't fail, it'll just
be empty, which reads worse on camera than not showing it at all. The
10-K-retrieval story is told in Panel 4 instead, where the agent's search
tool isn't restricted to exact matches.

## Opening (0:00-0:30)

"Hi, I'm [name]. This is LadingLens -- a supply-chain tariff exposure copilot
built on Snowflake Cortex. It fuses 3.8 million US customs shipment records
with SEC 10-K risk disclosures to answer questions like 'if Section 232
tariffs double, what's a company's exposure?' Let me show you."

[Show README hero + tagline]

## Panel 1: Executive Overview (0:30-1:00)

[Open Streamlit app, land on Executive Overview]

"89,200 in-scope shipments, 14,155 consignees, 14,986 suppliers, 25,173
single-source supplier pairs. Origin country and HS chapter breakdowns. All
from real NIST customs data, entity-resolved through a dbt medallion
pipeline -- Bronze, Silver, Gold."

## Panel 2: Concentration Heatmap (1:00-2:00)

[Click to heatmap tab, show visualization]

"HHI concentration index by consignee times HS chapter -- recomputed at the
chapter grain directly from the fact table, not by combining pre-aggregated
sub-chapter numbers, because HHI doesn't average across subgroups. Red means
a concentrated supplier base, green means diversified."

[Select a consignee/chapter pair with real variation -- e.g. BMW
MANUFACTURING CORP, chapter 87 (Vehicles), HHI ~0.98 per the Phase 9
screenshot]

"Here's the HS-6 subheading breakdown behind that number -- which specific
parts drive the concentration."

[Do NOT click the 10-K expander live -- see gotcha above. Move straight to
Panel 3.]

## Panel 3: Scenario Simulator (2:00-3:00)

[Click to scenario tab]

"Interactive tariff what-if. Pick a consignee, dial up the rate, choose
chapters and countries."

[Use DHL GLOBAL FORWARDING -- verified working: +15pp on chapters 73/87/84/39,
Germany-heavy exposure]

"$5,264,226 total impact, a 14.5% increase. Every row in this breakdown adds
the rate increment on top of the shipment's true baseline landed cost -- not
by recomputing from an averaged rate, which I found during Phase 8 silently
produces wrong numbers when a single HS chapter spans subheadings with
different actual duty rates. That's a real bug I caught and fixed, not a
hypothetical."

## Panel 4: Ask LadingLens (3:00-4:30)

[Click to chat tab]

"The conversational layer. Cortex Agent orchestrates three tools: structured
queries against a native Snowflake Semantic View, retrieval over the 10-Ks
via Cortex Search, and the tariff scenario simulator. Let me ask a fusion
question."

[Type: "If Section 232 tariffs doubled, what would BMW's exposure be?"]

"This chains two tools: it looks up BMW's consignee record, finds the
material entity -- BMW Manufacturing Corp -- then runs the scenario. Loading
state shows real progress; this takes 40-90 seconds because the agent makes
multiple tool calls in sequence."

[Wait for response]

"Duty rate 27.5% to 52.5%, landed cost $130,968 to $156,584 -- a $25,616
increase, 19.6%. And notice it correctly scoped this to just the HS-73 steel
exposure from Germany, and explicitly noted that BMW's other entities have
zero recorded landed cost on that exposure, so their numbers don't move.
That kind of self-aware scoping is what separates a real agent from a
canned demo."

[Optional, if time allows: show the "Tools used" expander -- query_shipments,
simulate_tariff_scenario]

"That structured-plus-scenario fusion -- and in other queries, structured
plus unstructured 10-K retrieval -- is the hardest architectural claim in
this project, and it works."

## Closing (4:30-5:00)

"Full details in the GitHub repo -- dbt medallion pipeline, entity resolution
with 40-plus documented data-quality catches, a retrieval-augmented HS
classifier using a Snowpark UDTF that cut an unresolved 10-plus-hour query
down to 17 seconds, a native Semantic View, Cortex Search, and a Cortex
Agent tying it all together. All Snowflake-native. Thanks for watching."

[Show GitHub URL on screen at end]

## Rehearsal tips

- Practice 2-3 times before recording
- Keep it under 5 minutes; anything over feels rambly
- Cortex Agent latency varies -- pre-warm it (see Setup), and if the fusion
  query runs long, cut away and cut back in after it resolves rather than
  sitting in dead air
- Record in 1080p minimum
- Upload as Loom (unlisted) or YouTube unlisted; embed link in README
- If the submission deadline is genuinely tight, a clean 3-minute cut of
  Panels 1, 3, and 4 (skipping the heatmap drill-down entirely) is a
  reasonable fallback -- Panel 3 and 4 carry the strongest demo moments
