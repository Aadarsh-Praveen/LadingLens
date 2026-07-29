# Phase 10 — Observability, CI/CD, Demo Video, Submission

**Duration:** ~1 day (0.5 day if lucky, 1.5 days if unlucky)
**Depends on:** All prior phases
**Goal:** Turn a technically-complete project into a polished, submittable product. Record the demo video, polish the README to recruiter-grade, add lightweight observability, wire GitHub Actions CI/CD, and file the hackathon submission.

---

## Context

Phases 1-9 built a working product. Phase 10 makes it *findable, watchable, and defensible*. Order matters here — the demo video and README are the single most-consumed artifacts (by hackathon judges, recruiters, interviewers), so they get the most care. Everything else is polish.

Design principles for this phase:

- **Video > text > code for first impressions.** Most viewers watch the demo video, skim the README, and never open the code. Optimize accordingly.
- **Reproducibility.** Every claim in the README should be traceable to a screenshot, a repo file, or an evidence artifact.
- **Honesty about scope.** Document deferrals as scope discipline, not gaps. Every "future work" note should have a specific production path forward.
- **CI/CD is a signal.** Even if the tests pass locally, wiring GitHub Actions demonstrates production readiness in a way that "runs on my machine" doesn't.

---

## Deliverables

- [ ] `docs/DEMO.md` — demo video script + recording checklist
- [ ] Uploaded demo video (Loom or YouTube unlisted, 3-6 minutes)
- [ ] `README.md` — rewritten to recruiter-grade with hero screenshot, architecture diagram, metrics, quickstart
- [ ] `.github/workflows/dbt-tests.yml` — CI running dbt tests on push
- [ ] `.github/workflows/lint.yml` — Python linting on push
- [ ] `docs/architecture.md` — deeper architecture writeup with Mermaid diagrams
- [ ] `docs/metrics.md` — the numeric summary table (89,200 shipments, 40 catches, etc.)
- [ ] `docs/roadmap.md` — deferred items with production paths
- [ ] Lightweight observability panel (either TruLens if available, or a simple in-Snowflake `agent_traces` table)
- [ ] Hackathon submission form completed on Hack2Skill
- [ ] LinkedIn writeup drafted

---

## Claude Code Prompt

```
Phase 10 — final phase. Observability, CI/CD, demo video prep, README polish,
submission. Read ./LadingLens.md, ./docs/phases/phase-10-observability-and-demo.md,
and ./data/sources.md before starting.

STATE RECAP (verified, do not re-check):
- Phases 1-9 complete and committed. All 4 Streamlit panels working with
  8 demo screenshots in docs/screenshots/.
- 85 dbt tests pass (with 2 warn from Phase 6). Cumulative catches: 40.
- Cortex spend to date: ~$40-50. Budget remaining: ~$30-50.
- Trial account expiration: ~25 days from build day. Comfortable buffer.
- Streamlit app deployed as LADINGLENS_DB.SEMANTIC.LADINGLENS_APP.

YOUR TASK:
Ship the project. Order of operations:
1. Verify Streamlit app still works end-to-end (regression check)
2. Add lightweight observability (TruLens if available; otherwise simple
   agent_traces table)
3. Wire GitHub Actions CI/CD for dbt tests + Python linting
4. Rewrite README to recruiter-grade
5. Author docs/architecture.md, docs/metrics.md, docs/roadmap.md
6. Prepare demo video script + recording checklist (user records the actual video)
7. Prepare hackathon submission form entries + LinkedIn writeup draft

CONSTRAINTS:
- The user records the demo video themselves. Do not try to record video from
  the agent environment; produce the script and checklist only.
- CI/CD must not require Snowflake credentials for basic linting (Python-only
  checks). dbt tests in CI can be a "dbt compile" check without live warehouse,
  or be marked as `on: workflow_dispatch` only (manual trigger).
- README target length: 400-800 lines. Long enough to be substantive, short
  enough that recruiters skim it fully.
- Do NOT touch dbt models, Snowflake objects, or Streamlit code except for
  the observability addition. This phase is polish + packaging.

===========================================
STEP 0 — Regression check
===========================================

Before touching anything, verify the Streamlit app still works. Query the
critical endpoints:

    -- Semantic view still queryable
    SELECT * FROM SEMANTIC_VIEW(LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW
        METRICS fact_shipments.total_shipments
    );

    -- Cortex Search still works
    SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH',
        '{"query": "tariff exposure", "limit": 2}'
    )):results;

    -- Scenario procedure still works
    CALL LADINGLENS_DB.SEMANTIC.SIMULATE_TARIFF_SCENARIO(
        '<paste_a_known_consignee_key>',
        PARSE_JSON('{"additional_rate_pp": 25.0, "hs_chapters": ["73"], "origin_countries": ["DE"]}')
    );

    -- Agent still works
    SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
        'LADINGLENS_DB.SEMANTIC.LADINGLENS_AGENT',
        '{"question": "How many shipments total?"}'
    );

Ask the user to also open LADINGLENS_APP in Snowsight and verify all 4 panels
render. This is a critical regression check — if anything's broken, we fix it
here, not during demo video recording.

CHECKPOINT — do not proceed until all 4 endpoints verified working.

===========================================
STEP 1 — Lightweight observability
===========================================

Two paths, choose based on account availability:

PATH A (preferred if available): TruLens via snowflake-native install.

    -- Check if TruLens is available
    -- Likely requires a Python UDF/procedure importing trulens_eval
    -- If not available, jump to PATH B

    -- If available, wire it around the agent call to capture:
    -- - groundedness (answer faithful to retrieved chunks + SQL results?)
    -- - context relevance (retrieved chunks relevant to query?)
    -- - answer relevance (final answer addresses query?)

PATH B (fallback): Simple in-Snowflake agent_traces table + a Streamlit
observability panel.

Create a trace-logging table:

    CREATE TABLE IF NOT EXISTS LADINGLENS_DB.GOLD.AGENT_TRACES (
        trace_id STRING DEFAULT UUID_STRING(),
        timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
        question STRING,
        response STRING,
        tool_calls VARIANT,  -- array of {tool, args, latency_ms}
        total_latency_ms NUMBER,
        cost_credits_estimate NUMBER,
        session_id STRING
    );

Modify streamlit/panels/agent_chat.py to write to AGENT_TRACES after each
successful agent call. Capture: question, response, tool_calls array (from
DATA_AGENT_RUN's content array), total_latency_ms, and estimated cost.

Add a 5th Streamlit panel: streamlit/panels/observability.py.
    - KPI cards: total queries served, p50 latency, p95 latency, avg cost
    - Table: last 20 traces with question + latency + tool_calls preview
    - Chart: latency distribution histogram
    - Chart: tool-usage breakdown (which tools were called how often)

Update streamlit/app.py to add the 5th tab.

Redeploy the Streamlit app with the new panel.

If PATH A works, still write to AGENT_TRACES as the underlying data source —
TruLens becomes an additional layer of feedback scoring on top of the trace
data, not a replacement for it.

===========================================
STEP 2 — GitHub Actions CI/CD
===========================================

Create .github/workflows/lint.yml:

    name: Python Lint
    on:
      push:
        branches: [main]
      pull_request:
        branches: [main]
    jobs:
      lint:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: actions/setup-python@v5
            with:
              python-version: "3.11"
          - name: Install linters
            run: pip install ruff black
          - name: Ruff check
            run: ruff check . --exclude .venv --exclude dbt_packages
          - name: Black format check
            run: black --check . --exclude '(\.venv|dbt_packages)'

Create .github/workflows/dbt-compile.yml:

    name: dbt Compile Check
    on:
      push:
        branches: [main]
      pull_request:
        branches: [main]
    jobs:
      dbt-compile:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: actions/setup-python@v5
            with:
              python-version: "3.11"
          - name: Install dbt
            run: |
              pip install dbt-core dbt-snowflake
          - name: dbt parse (compile without connection)
            env:
              SNOWFLAKE_ACCOUNT: ${{ secrets.SNOWFLAKE_ACCOUNT || 'dummy' }}
              SNOWFLAKE_USER: ${{ secrets.SNOWFLAKE_USER || 'dummy' }}
              SNOWFLAKE_ROLE: ${{ secrets.SNOWFLAKE_ROLE || 'dummy' }}
              SNOWFLAKE_WAREHOUSE: ${{ secrets.SNOWFLAKE_WAREHOUSE || 'dummy' }}
              SNOWFLAKE_DATABASE: ${{ secrets.SNOWFLAKE_DATABASE || 'dummy' }}
            run: |
              cd dbt/ladinglens
              dbt deps
              dbt parse  # Syntactic check without live warehouse
      dbt-test-live:
        # Only runs on workflow_dispatch (manual trigger) to avoid burning
        # credits on every push
        if: github.event_name == 'workflow_dispatch'
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: actions/setup-python@v5
            with:
              python-version: "3.11"
          - name: Install dbt
            run: pip install dbt-core dbt-snowflake
          - name: Run dbt tests
            env:
              SNOWFLAKE_ACCOUNT: ${{ secrets.SNOWFLAKE_ACCOUNT }}
              SNOWFLAKE_USER: ${{ secrets.SNOWFLAKE_USER }}
              SNOWFLAKE_PRIVATE_KEY: ${{ secrets.SNOWFLAKE_PRIVATE_KEY }}
              SNOWFLAKE_ROLE: ${{ secrets.SNOWFLAKE_ROLE }}
              SNOWFLAKE_WAREHOUSE: ${{ secrets.SNOWFLAKE_WAREHOUSE }}
              SNOWFLAKE_DATABASE: ${{ secrets.SNOWFLAKE_DATABASE }}
            run: |
              cd dbt/ladinglens
              dbt deps
              dbt test

Two workflows: fast lint on every push, dbt compile on every push, live dbt
tests only on manual trigger. This avoids burning Cortex credits on every
commit while still providing CI signal.

Report the workflow file locations. User will need to add GitHub Secrets
before the workflows run successfully — document what secrets are needed in
docs/roadmap.md.

===========================================
STEP 3 — README rewrite
===========================================

Rewrite README.md to recruiter-grade. Structure (roughly):

    # LadingLens
    
    [Tagline: Tariff exposure and supplier concentration copilot built on
    Snowflake Cortex + dbt medallion pipeline.]
    
    [Hero screenshot: docs/screenshots/concentration_heatmap.png or the
    most visually striking one]
    
    [Demo video link — Loom or YouTube]
    
    ## The Problem
    
    [2 paragraphs: US importers face concentrated tariff exposure. Manual
    analysis of BoL + tariff schedules + 10-K risk disclosures is expensive
    and slow. LadingLens automates the fusion of these three data types into
    a natural-language copilot.]
    
    ## What It Does
    
    [3-4 bullets with screenshots:
     - Concentration heatmap — supplier/country HHI by consignee × HS chapter
     - Tariff scenario simulator — what-if landed cost under hypothetical
       tariff changes
     - 10-K risk factor retrieval — retrieves verbatim SEC disclosure language
     - Conversational agent — synthesizes structured + unstructured + scenario
       into natural-language answers]
    
    ## Architecture
    
    [Mermaid diagram — see docs/architecture.md for full version.
     Bronze -> Silver -> Gold dbt medallion pipeline feeding a SEMANTIC VIEW
     and a Cortex Search service, both consumed by a Cortex Agent and
     Streamlit UI.]
    
    ## Data Sources
    
    [Table: source name, description, size, license, retrieval date]
    
    ## Key Metrics
    
    [From docs/metrics.md:
     - 89,200 in-scope shipments
     - 41,338 golden suppliers, 40,629 golden consignees
     - 96% classification coverage on HS codes
     - 1,674 chunks indexed from 24 SEC filings
     - Cortex Agent: 9/10 smoke test success, p50 38s / p95 93s
     - 85 dbt tests, 40 documented data-quality catches
     - Total Cortex spend: ~$50]
    
    ## Tech Stack
    
    [Table linking to each tool: Snowflake Cortex, dbt-core, Streamlit-in-
    Snowflake, Snowpark Python UDFs, Cortex Search, native SEMANTIC VIEW,
    Cortex Agent]
    
    ## How to Run
    
    [Prerequisites: Snowflake account, Cortex enabled, 50 credits.
     Clone repo. Bootstrap script. dbt deps. dbt build.
     Deploy Streamlit. See individual phase docs for details.]
    
    ## Data Quality Discipline
    
    [Highlight: 40 documented data-quality catches across phases with root cause
    analysis. Link to data/sources.md and individual phase docs.]
    
    ## Deferred Work
    
    [Link to docs/roadmap.md]
    
    ## Author
    
    [Name, LinkedIn, GitHub, portfolio site link]

Do NOT include marketing fluff. Every claim in the README should link to
evidence — a screenshot, a phase doc, a code file, or a metric in
docs/metrics.md.

===========================================
STEP 4 — docs/architecture.md
===========================================

Deeper writeup than README allows. Sections:

1. **High-level architecture** (Mermaid diagram showing 5 layers)
2. **Data flow** (3.8M raw BoL rows -> 89,200 in-scope shipments through
   Bronze/Silver/Gold transformations)
3. **Layer-by-layer detail**
   - Bronze: raw ingestion + typing + dedup
   - Silver: entity resolution (Phase 4) + HS classification (Phase 5)
   - Gold: Kimball star schema + concentration mart
   - Semantic: SEMANTIC VIEW + Cortex Search
   - Application: Cortex Agent + Streamlit UI
4. **Tool choices with tradeoffs**
   - Why Kimball star schema vs Data Vault
   - Why native SEMANTIC VIEW vs Cortex Analyst
   - Why Cortex Search vs hand-rolled retrieval
   - Why Cortex Agent vs LangChain
5. **Compute optimization highlights**
   - Snowpark UDTF for embedding retrieval (10hr -> 17s)
   - Stored procedure vs UDTF for scenario simulator
6. **Known limitations and production paths**
   - Link to docs/roadmap.md

===========================================
STEP 5 — docs/metrics.md
===========================================

The canonical numbers table:

    | Metric | Value |
    |--------|-------|
    | Raw shipment rows ingested | 3,825,304 |
    | In-scope shipments after Bronze/Silver | 89,200 |
    | Golden supplier entities | 41,338 |
    | Golden consignee entities | 40,629 |
    | HS classification coverage | 96.4% |
    | HS-2 accuracy on eval seed | 46.7% |
    | HS-4 accuracy on eval seed | 33.3% |
    | HS-6 accuracy on eval seed | 16.7% |
    | Entity resolution F1 | 0.487 |
    | 10-K filings indexed | 24 |
    | 10-K chunks in Cortex Search | 1,674 |
    | Cortex Search smoke test success | 6 strong / 2 partial / 2 weak of 10 |
    | Cortex Agent smoke test success | 9 strong / 1 partial of 10 |
    | Agent latency p50 | 38.3s |
    | Agent latency p95 | 93.2s |
    | dbt tests total | 85 |
    | Data quality catches documented | 40 |
    | Total Cortex spend | ~$50 |
    | Snowpark UDTF optimization | 10hr -> 17s (2000x speedup) |
    | Phase duration total | ~14 days |

===========================================
STEP 6 — docs/roadmap.md
===========================================

Every deferred item across all phases, with production path forward:

Bronze extraction limitations:
- 4 tickers (LULU, MU, NKE, WMT) still have contaminated 10-K text; requires
  DOM-aware parsing not fixable via regex broadening
- STLA, DELL, INTC, EMR extraction fails entirely; requires filer-specific
  parsing logic

HS classification limitations:
- Short-input embeddings under-encode single-word product descriptions;
  production would add BM25 hybrid retrieval
- Bronze regex false-positive on P.O. reference numbers looking like HS codes;
  requires stricter regex with prefix-keyword requirement
- LLM refusal rate 0/4 on ambiguous seed rows; prompt hardening trades
  coverage for precision

Entity resolution:
- Walmart consignee resolution gap: real Walmart import volume not in dataset
  under recognizable names; requires cross-referencing FMC importer-of-record
  data in production

Concentration analysis:
- HHI based on shipment counts (not weight) due to 60% NULL weight in NIST
  FEIII 2019; would use weight in production if weight data completeness
  improved

Cortex Agent:
- p95 latency 93s meaningful for interactive use; would optimize via reduced
  tool round-trips or caching frequent queries
- No streaming response; agent returns after all tool calls complete
- Cortex Analyst standalone API unavailable on this account tier despite
  Cortex Agent's embedded use working

CI/CD:
- Live dbt tests only on manual workflow_dispatch trigger; would run on push
  in production once test warehouse costs are budgeted
- GitHub Secrets required: SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER,
  SNOWFLAKE_PRIVATE_KEY, SNOWFLAKE_ROLE, SNOWFLAKE_WAREHOUSE,
  SNOWFLAKE_DATABASE

Observability:
- Basic AGENT_TRACES logging in place; production would add TruLens
  groundedness/relevance scoring per query

For each item: root cause + specific production fix path + estimated effort.

===========================================
STEP 7 — Demo video script
===========================================

Create docs/DEMO.md with a rehearsal script for a 5-minute demo video.

Structure:

    # LadingLens Demo Video Script (5 minutes)
    
    ## Setup
    - Snowsight open with LADINGLENS_APP loaded
    - Screen recording ready (Loom or QuickTime)
    - Audio checked
    - Cortex Agent warmed up (run one query beforehand so first demo query
      isn't a cold start)
    
    ## Opening (0:00-0:30)
    "Hi, I'm [name]. This is LadingLens — a supply-chain tariff exposure copilot
    built on Snowflake Cortex. It fuses 3.8 million US customs shipment records
    with SEC 10-K risk disclosures to answer questions like 'if Section 232
    tariffs double, what's Caterpillar's exposure?' Let me show you."
    
    [Show README hero + tagline]
    
    ## Panel 1: Executive Overview (0:30-1:00)
    [Open Streamlit app, land on Executive Overview]
    "89,200 in-scope shipments, top 10 consignees by landed cost, breakdown by
    origin country and HS chapter. All from real NIST customs data, entity-
    resolved through a dbt medallion pipeline."
    
    ## Panel 2: Concentration Heatmap (1:00-2:00)
    [Click to heatmap tab, show visualization]
    "HHI concentration by consignee × HS chapter. Red = concentrated supplier
    base, green = diversified. Let me click BMW steel imports..."
    [Drill down, show detail]
    "Here's the underlying supplier breakdown, plus BMW's 10-K risk factor
    language on exactly this topic — retrieved live from Cortex Search."
    
    ## Panel 3: Scenario Simulator (2:00-3:00)
    [Click to scenario tab]
    "Interactive tariff what-if. Pick a consignee, dial up the tariff, choose
    chapters and countries. Let me simulate Section 232 doubling for BMW..."
    [Run simulation, show result]
    "$130K -> $156K landed cost. $25K delta, 19.6% increase. This calls a
    Snowflake stored procedure that computes the delta on top of the true
    weighted baseline — not by recomputing from averaged rates, which would
    silently produce wrong numbers due to rate heterogeneity across HS
    subheadings."
    
    ## Panel 4: Ask LadingLens (3:00-4:30)
    [Click to chat tab]
    "The conversational layer. Cortex Agent orchestrates three tools:
    structured queries on the SEMANTIC VIEW, retrieval on Cortex Search over
    the 10-Ks, and the scenario simulator. Let me ask a fusion query..."
    [Type: "What does Caterpillar disclose about tariffs in their 10-K, and
    how does that compare to their current concentration risk?"]
    "Loading state shows real progress — this fusion query takes about 60
    seconds because the agent chains multiple tool calls."
    [Wait for response]
    "Note how it cites specific numbers from the shipment data AND quotes
    verbatim from Caterpillar's 10-K. That structured + unstructured fusion
    is the hardest architectural claim in this project, and it works."
    
    ## Closing (4:30-5:00)
    "Full details in the GitHub repo — dbt medallion pipeline, entity
    resolution with 40 documented data-quality catches, retrieval-augmented
    HS classifier using Snowpark UDTFs, native Semantic View, Cortex Search,
    Cortex Agent. All Snowflake-native. Thanks for watching."
    
    [Show GitHub URL on screen at end]
    
    ## Rehearsal tips
    - Practice 2-3 times before recording
    - Keep it under 5 minutes; anything over feels rambly
    - Cortex Agent latency varies — pre-warm it, and if the fusion query is
      taking too long, cut before completion and cut back after
    - Record in 1080p minimum
    - Upload as Loom (unlisted) or YouTube unlisted; embed link in README

===========================================
STEP 8 — Hackathon submission draft
===========================================

Create docs/submission-form-draft.md with the pre-filled Hack2Skill form
entries so the user just copies them into the actual form:

    # Hack2Skill CoCo CLI Hackathon 2026 — Submission Entries
    
    ## Project Name
    LadingLens
    
    ## Tagline
    Tariff exposure and supplier concentration copilot built on Snowflake Cortex.
    
    ## Problem Statement Alignment
    [Which of the 4 problem statements — recommend "Unstructured Data
    Intelligence System" as primary, "Domain-Specific AI Copilot" as
    secondary]
    
    ## Summary (300 chars max)
    A Snowflake-native copilot fusing 3.8M US customs shipment records with
    SEC 10-K risk disclosures via retrieval-augmented Cortex classification,
    entity resolution, semantic layer, and Cortex Agent orchestration.
    
    ## GitHub Repo URL
    [Aadarsh's repo URL]
    
    ## Demo Video URL
    [Loom/YouTube URL after recording]
    
    ## Team Size
    Solo
    
    ## Tech Stack (short)
    Snowflake Cortex Agent, Cortex Search, native SEMANTIC VIEW, dbt-core,
    Snowpark Python UDFs, Streamlit-in-Snowflake.
    
    ## Key Metrics (for judges)
    - 89,200 in-scope shipments through dbt medallion pipeline
    - 41K+ entity-resolved suppliers and consignees
    - 96.4% HS classification coverage on messy free-text descriptions
    - 24 SEC filings indexed via Cortex Search
    - 9/10 agent smoke test success including both fusion queries
    - 40 documented data-quality catches with root cause analysis
    - ~$50 total Cortex spend
    
    ## What makes this different from other submissions
    Real messy data (not synthetic). Multi-modal fusion (structured customs
    + unstructured 10-K + computed scenarios). Documented engineering
    discipline (40 catches). End-to-end Snowflake-native stack.

===========================================
STEP 9 — LinkedIn writeup draft
===========================================

Create docs/linkedin-draft.md with a 200-word post to be shared the day after
submission:

    Just shipped LadingLens — a tariff exposure and supplier concentration
    copilot built for the Snowflake CoCo CLI Hackathon 2026.
    
    The stack: dbt medallion pipeline (Bronze → Silver → Gold) transforming
    3.8M US customs shipment records into 89,200 in-scope shipments,
    entity-resolved via Cortex embeddings, HS-classified via retrieval-
    augmented Cortex + Snowpark UDTFs, exposed through a native Semantic
    View and Cortex Search over 24 SEC 10-K filings, and orchestrated by
    a Cortex Agent behind a 4-panel Streamlit UI.
    
    3 things I'm proud of:
    
    [1] A Snowpark UDTF that dropped embedding retrieval from 10 hours
    (native SQL cross-join) to 17 seconds via numpy matrix multiplication.
    
    [2] 40 documented data-quality catches across the phases, each with
    root cause analysis — including a dormant Bronze extraction bug that
    contaminated 13 of 24 10-K filings, caught by downstream Cortex Search
    retrieval quality diagnostics.
    
    [3] Agent fusion queries actually work: 'what does Caterpillar
    disclose about tariffs and how does that compare to current
    concentration' correctly chains structured + unstructured retrieval.
    
    GitHub: [URL]
    Demo: [URL]
    
    #Snowflake #Cortex #DataEngineering #AI

===========================================
EXECUTION ORDER & CHECKPOINTS
===========================================

CHECKPOINT 0 (Step 0): all 4 endpoints regression-verified working.

CHECKPOINT 1 (Steps 1-2): observability panel + CI/CD workflows built.
Report AGENT_TRACES schema, workflow file locations, and required GitHub
Secrets list.

CHECKPOINT 2 (Steps 3-6): README + architecture + metrics + roadmap docs
written. Report file paths and any specific facts that need verification
against actual numbers.

CHECKPOINT 3 (Steps 7-9): demo script + submission draft + LinkedIn draft
written. Report file paths.

DO NOT commit until user greenlights the final review.

USER RESPONSIBILITIES (not the agent's):
1. Extend Snowflake trial if needed (~5 min in Snowsight)
2. Add GitHub Secrets for the dbt-live workflow (~5 min)
3. Record the demo video following docs/DEMO.md (~30-60 min including
   rehearsals)
4. Upload video to Loom/YouTube, get URL, paste into README + submission
   form (~5 min)
5. Submit the Hack2Skill form using docs/submission-form-draft.md (~10 min)
6. Post the LinkedIn writeup the day after submission (~5 min)
7. Update resume with the LadingLens line
```

---

## Your Tasks (Human)

- [ ] **Extend Snowflake trial** if needed. Log into Snowsight → account info → check expiration. If tight, extend now (Snowflake typically extends for legitimate hackathon use — contact support if needed).
- [ ] **Add GitHub Secrets** for the dbt-live workflow: `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PRIVATE_KEY`, `SNOWFLAKE_ROLE`, `SNOWFLAKE_WAREHOUSE`, `SNOWFLAKE_DATABASE`.
- [ ] **Record the demo video** following `docs/DEMO.md`. 30-60 min including rehearsals. Loom is easiest; YouTube unlisted works too.
- [ ] **Upload video, paste URL** into README hero section and `docs/submission-form-draft.md`.
- [ ] **Submit the Hack2Skill form** using `docs/submission-form-draft.md`. ~10 min.
- [ ] **Post LinkedIn writeup** day after submission. Tag Snowflake. Include screenshot.
- [ ] **Update resume** with the LadingLens project bullet.
- [ ] **Prepare 3-5 interview stories** from your study guides. Rehearse each one.

---

## Success Criteria

- Streamlit app still works end-to-end (regression check passes)
- Observability panel deployed and captures agent traces
- CI workflows visible in GitHub (Actions tab shows lint + dbt-compile passing on push)
- README rewritten with hero screenshot, demo video link, architecture diagram, metrics
- Demo video 3-6 minutes, uploaded, linked from README
- Hackathon submission filed on Hack2Skill
- LinkedIn writeup posted the day after submission

## Gotchas

- **Cortex Agent cold start:** if you demo right after warehouse suspension, first query has a 5-10 second warehouse-resume delay before the 40-90s agent latency. **Pre-warm by running one throwaway query 30 seconds before recording.**
- **Demo video length creep:** first drafts always run long. Cut ruthlessly. Under 5 minutes is a discipline signal.
- **Loom vs YouTube unlisted:** Loom is faster to record and share, YouTube has better long-term durability for portfolio. If unsure, do Loom for hackathon submission + YouTube unlisted for LinkedIn/resume references.
- **GitHub Actions credit budget:** the manual-trigger-only design of dbt-test-live workflow means the demo passes CI without ever running against real Snowflake. If a judge specifically checks "does CI include real dbt tests?" they'll see the manual trigger, which is honest but not automatic. Document this explicitly in `docs/roadmap.md`.
- **README hero screenshot choice:** pick the concentration heatmap or the agent fusion query response — those are the most demo-differentiating visuals. Do NOT use the executive overview as the hero — too generic.
- **Submission deadline timing:** confirm the Aug 2 deadline's exact time zone. Hack2Skill is APJ-focused, deadlines are usually IST. **Submit 24 hours early** to avoid last-minute drama.
