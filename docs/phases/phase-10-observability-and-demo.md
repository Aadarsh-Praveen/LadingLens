# Phase 10 — Observability, CI/CD, Demo, Submission

**Duration:** ~1-2 days
**Depends on:** All prior phases
**Goal:** Add production-grade observability (TruLens), CI/CD (GitHub Actions), polished documentation, and record the demo video. Submit.

---

## Context

This phase is where the project stops being a hackathon prototype and starts looking like something an interviewer would believe you'd shipped at a real company. Two things distinguish LadingLens from most submissions here:
- **TruLens observability panel** inside the Streamlit app (groundedness, context relevance, answer relevance per query).
- **Real CI/CD** running dbt tests and Python unit tests on every push, blocking bad merges.

Both of these are underused by hackathon competitors and highly praised by hiring managers.

---

## Deliverables

- [ ] `src/ladinglens/observability.py` — TruLens instrumentation
- [ ] `streamlit/pages/06_observability.py` — the observability dashboard
- [ ] `.github/workflows/ci.yml` — lint + test on every PR
- [ ] `.github/workflows/dbt-build.yml` — dbt build + tests on main
- [ ] `tests/` — Python unit tests
- [ ] `README.md` (rewritten) — polished, recruiter-ready
- [ ] `docs/architecture.md` — Mermaid diagrams, tool choices, tradeoffs
- [ ] `docs/demo-script.md` — 5-minute demo walkthrough
- [ ] `docs/metrics.md` — final numbers table
- [ ] `docs/DEMO.mp4` (or link) — recorded video
- [ ] Submission form filled out on the Hack2Skill portal

---

## Claude Code Prompt

```
You are in Phase 10 of LadingLens — the final phase. Phases 1-9 are complete. Read ./LadingLens.md and ./docs/phases/phase-10-observability-and-demo.md before starting.

Your task: add TruLens observability, wire CI/CD, polish docs, and prep for submission. Do NOT change dbt models or the agent's system prompt unless a test fails.

Constraints:
- TruLens integration should be non-blocking — if TruLens fails, agent queries still work.
- CI must pass on main before submission. If tests fail, fix them or mark as expected-failure with a comment.
- README is the recruiter's first impression. It gets equal care to the code.

Please build:

1. Install trulens-eval and trulens-providers-cortex into requirements.txt.

2. src/ladinglens/observability.py
   - Wraps the LadingLensClient with TruLens tracking.
   - Feedback functions:
     - Groundedness: does the answer stay faithful to the retrieved 10-K chunks and analyst SQL results?
     - Context Relevance: are the retrieved chunks relevant to the query?
     - Answer Relevance: does the final answer address the query?
   - Uses SNOWFLAKE.CORTEX.COMPLETE as the LLM-as-judge provider.
   - Logs every query to a Snowflake table GOLD.AGENT_TRACES with columns: trace_id, query, response, tool_calls_json, latency_ms, groundedness, context_relevance, answer_relevance, cost_credits, timestamp.

3. Update streamlit/pages/05_copilot_chat.py to wrap the agent call with TruLens instrumentation and write to GOLD.AGENT_TRACES.

4. streamlit/pages/06_observability.py
   - Table of last 100 traces
   - Chart: p50/p95 latency over time
   - Chart: groundedness distribution histogram
   - Table: top 5 low-groundedness queries (for review)
   - KPI: total queries served, avg cost per query, cache hit rate

5. tests/ (create these unit tests):
   - tests/test_normalize_company_name.py — the dbt macro tested via dbt's built-in unit test or a Python re-implementation
   - tests/test_scenario_udf.py — call the UDF with known inputs, assert expected math
   - tests/test_agent_client.py — mock the Snowflake session, assert agent client parses responses correctly
   - tests/test_hs_classifier_eval.py — asserts accuracy from GOLD.HS_CLASSIFIER_METRICS is above threshold (0.65 HS-6)

6. .github/workflows/ci.yml
   - Triggers: pull_request, push to any branch
   - Steps:
     - Set up Python 3.11
     - pip install -r requirements.txt
     - ruff check .
     - black --check .
     - pytest tests/ -v
     - Fail on any of the above

7. .github/workflows/dbt-build.yml
   - Triggers: push to main
   - Steps:
     - Set up Python 3.11 + dbt-snowflake
     - Reads Snowflake creds from GitHub Secrets
     - dbt deps
     - dbt build --target ci (a special ci target that uses a scratch schema)
     - Fails on any dbt test failure
   - Uses concurrency: cancel-in-progress on the branch

8. Rewrite README.md with:
   - Hero section: project name, tagline, screenshot
   - Problem statement (2 paragraphs)
   - Solution overview + architecture diagram (Mermaid)
   - Data sources with licenses
   - Metrics: ER F1, HS classifier accuracy, RAG recall@5, agent routing accuracy, latency, credits used
   - How to run (setup steps referencing phase docs)
   - Screenshots section
   - Tech stack table (with links)
   - Author section: name, LinkedIn, GitHub, portfolio

9. docs/architecture.md
   - Full Mermaid diagram of the data flow
   - Component-by-component explanation
   - "Why these tools" tradeoff discussion for each major choice (Iceberg vs. regular tables, Cortex Analyst vs. hand-written SQL API, TruLens vs. no obs, etc.)

10. docs/demo-script.md — a 5-minute walkthrough
    - 00:00-00:30 problem framing (what tariff-exposure question does this answer?)
    - 00:30-01:00 data messiness EDA screenshot
    - 01:00-02:00 ER + HS classification (compression ratio + accuracy stats)
    - 02:00-03:30 copilot chat with 2 hero queries (metric + verbatim quote answer)
    - 03:30-04:30 scenario simulator running "+25pp on China HS 85"
    - 04:30-05:00 observability + closing

11. docs/metrics.md — table of final numbers:
    - Row counts by layer
    - ER precision/recall/F1
    - HS-2/HS-6 accuracy
    - RAG recall@5, MRR
    - Agent routing accuracy, p50/p95 latency
    - Total credits consumed
    - Cost per query

Run:
- pytest tests/ — report pass count
- ruff check . — report any issues
- Verify GitHub Actions runs pass on main
- Update the metrics.md table with actual final numbers pulled from GOLD.HS_CLASSIFIER_METRICS, GOLD.AGENT_TRACES, ER analysis, etc.

Ask before making stylistic README changes — I'll want to review the tone.
```

---

## Your Tasks (Human)

- [ ] **Record the demo video (5 min max).**
   - Use Loom or QuickTime.
   - Follow `docs/demo-script.md` — don't wing it.
   - Show the Snowsight tabs (Cortex Analyst semantic view, Cortex Search service, Cortex Agent) briefly to prove it's Snowflake-native.
   - Show your Streamlit app in the flow.
   - Upload to YouTube (unlisted) or Loom and paste the link into the README.
- [ ] **Fill out the Hack2Skill submission form** at https://hack2skill.com/event/cococlihack/. Include: GitHub repo link, demo video link, one-page project summary, which problem statement (recommend: "Unstructured Data Intelligence System"), team size.
- [ ] **Push everything to GitHub** and verify CI passes green.
- [ ] **Post a LinkedIn writeup** the day after submission. Recruiters see hackathon-adjacent posts. Include: 3 metrics, one screenshot, and the "what I learned" angle. Tag Snowflake.
- [ ] **Update your resume** with a new bullet under Projects — see the LadingLens resume-line template below.
- [ ] **Prepare interview talking points**: (1) the ER compression ratio story, (2) the HS-classifier prompt-iteration story, (3) the joined structured+unstructured answer story. Write 2-3 sentences on each in a note file you can reference in interviews.

---

## Success Criteria

- CI is green on main.
- TruLens dashboard renders live trace metrics.
- README has 5+ screenshots and clear architecture diagram.
- Demo video uploaded, ≤ 5 min, links from README.
- Submission form submitted with all required fields.
- LinkedIn writeup posted.

## Suggested Resume Bullet

> **LadingLens — Tariff Exposure & Supplier Concentration Copilot** *(Snowflake CoCo CLI Hackathon 2026)*
> Built a Snowflake-native supply-chain copilot fusing FOIA-sourced bill-of-lading data (~X shipments), USITC tariff schedules, and SEC 10-K risk disclosures. Implemented entity resolution using Cortex AI_EMBED + VECTOR_COSINE_SIMILARITY achieving F1 = 0.XX, LLM-based HS-code classification (HS-6 accuracy XX%), Cortex Search RAG over 10-K filings (recall@5 = 0.XX), and a Cortex Agent orchestrating structured + unstructured Q&A with TruLens observability. Delivered as a Streamlit-in-Snowflake command center with a tariff scenario simulator. Full CI/CD via GitHub Actions + dbt build.

## Gotchas

- **TruLens on Cortex:** the trulens-providers-cortex package is newer and may have quirks. If a feedback function fails, log it and continue — don't block the agent.
- **CI secrets:** the dbt-build workflow needs Snowflake credentials as GitHub Secrets. Set these up before first push to main or the workflow will fail.
- **Demo video:** the biggest hackathon mistake is a rambling video. Rehearse twice. If you go over 5 minutes, cut, don't compress.
- **Submission deadline:** confirm the exact time zone. Hack2Skill is APJ-focused, so deadlines are often IST-based. Submit 24 hours early to avoid last-minute drama.
