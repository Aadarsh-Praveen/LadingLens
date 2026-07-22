# Phase 8 — Cortex Agent + Tariff Scenario Engine

**Duration:** ~1 day
**Depends on:** Phase 6 (Semantic view), Phase 7 (Cortex Search)
**Goal:** Wire up the copilot itself. A Cortex Agent orchestrates Cortex Analyst (structured Q&A) + Cortex Search (unstructured retrieval) + a Python tariff-scenario tool that recomputes exposure under hypothetical rate changes. This is the "wow" moment.

---

## Context

A **Cortex Agent** is a declarative orchestrator that picks between tools per user turn. Snowflake exposes it via a REST API and via Snowflake Intelligence UI.

For LadingLens, three tools:
1. **`analyst_query`** — Cortex Analyst call against the semantic view (structured metrics).
2. **`risk_factors_search`** — Cortex Search call over 10-K chunks (unstructured evidence).
3. **`tariff_scenario`** — a Python SQL UDF that recomputes landed_cost and concentration under "+X% duty on country Y, HS Z" scenarios.

The agent's system prompt is the second most important asset in the whole project (after the semantic view). It must:
- Prefer joined answers (metric + evidence) when the user asks a risk question.
- Cite the 10-K ticker + filing date verbatim when quoting.
- Never fabricate a metric — always route through `analyst_query`.

---

## Deliverables

- [ ] `scripts/scenario_udf.sql` — Python UDF for tariff scenario recomputation
- [ ] `agent/system_prompt.md` — the agent's grounding instructions
- [ ] `agent/tools.yml` — tool declarations for Cortex Agent
- [ ] `scripts/register_agent.sql` — CREATE AGENT DDL (or Python SDK equivalent)
- [ ] `notebooks/08_agent_eval.ipynb` — end-to-end agent test with 15 queries
- [ ] `docs/agent-eval-report.md` — per-query trace + assessment
- [ ] `src/ladinglens/agent_client.py` — Python wrapper for calling the agent (used by Streamlit in Phase 9)

---

## Claude Code Prompt

```
You are in Phase 8 of LadingLens. Phases 1-7 are complete. Semantic view (Phase 6) and Cortex Search service (Phase 7) are both live. Read ./LadingLens.md and ./docs/phases/phase-08-agent-and-scenarios.md before starting.

Your task: build the Cortex Agent, register its tools, write the system prompt, and evaluate end-to-end.

Constraints:
- Every tool has a schema with typed args and a description that the agent's planner can read.
- The system prompt is version-controlled in agent/system_prompt.md — do NOT inline it in the DDL.
- Tariff scenario UDF is pure SQL / Snowpark Python — no external network calls.
- End-to-end latency target: p50 < 4s, p95 < 10s per query.

Please build:

1. scripts/scenario_udf.sql — Snowpark Python UDF
   - Function name: LADINGLENS_DB.GOLD.SIMULATE_TARIFF_SCENARIO
   - Args:
       origin_country VARCHAR,
       hs_scope ARRAY (list of hs_2 or hs_6 strings),
       rate_increase_pct FLOAT (e.g., 0.25 for +25 percentage points),
       consignee_filter ARRAY (optional list of golden_consignee_ids)
   - Returns TABLE (
       consignee_key VARCHAR,
       canonical_consignee_name VARCHAR,
       current_landed_cost_usd NUMBER,
       scenario_landed_cost_usd NUMBER,
       cost_delta_usd NUMBER,
       cost_delta_pct NUMBER,
       shipments_affected NUMBER
     )
   - Reads fact_shipments filtered to the last 12 months and the origin/HS/consignee filters.
   - Computes scenario_effective_duty_rate = current_effective_duty_rate + rate_increase_pct.
   - Returns per-consignee before/after.

2. agent/system_prompt.md
   - Sections:
     ## Role: You are LadingLens, a supply-chain tariff and supplier-concentration copilot.
     ## Tools available:
       - analyst_query: for any question about volumes, values, counts, HHI, single-source flags
       - risk_factors_search: for any question about disclosed risks, verbatim disclosures, or "what does company X say about"
       - tariff_scenario: for hypothetical questions ("what if tariff rises to X")
     ## Response format:
       - Lead with the metric (from analyst_query) when applicable
       - Support with 1-2 verbatim quotes from risk_factors_search when available, always attributed to ticker + filing date
       - Show scenario deltas in a compact table when tariff_scenario ran
       - End with 1-line caveat about data coverage (vessel-only BoL, quarterly Comtrade lag, etc.)
     ## Do NOT:
       - Fabricate a number
       - Speculate on future tariffs beyond user-specified scenarios
       - Answer questions unrelated to imports, tariffs, or supplier concentration

3. agent/tools.yml
   - Full tool declarations:
     tools:
       - name: analyst_query
         description: Runs a governed SQL query against the LadingLens semantic view. Use for any structured metric question.
         type: cortex_analyst
         semantic_view: LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW
       - name: risk_factors_search
         description: Semantic search over SEC 10-K risk factors. Use for any verbatim-disclosure or "what do filers say about" question.
         type: cortex_search
         service: LADINGLENS_DB.SILVER.LADINGLENS_10K_SEARCH
         max_results: 5
       - name: tariff_scenario
         description: Simulates a hypothetical tariff change and returns per-consignee cost delta. Use only when the user asks "what if tariffs rise to X" or similar.
         type: sql_udf
         function: LADINGLENS_DB.GOLD.SIMULATE_TARIFF_SCENARIO

4. scripts/register_agent.sql (or a Python script if the SDK is easier)
   - CREATE OR REPLACE AGENT LADINGLENS_DB.GOLD.LADINGLENS_AGENT
       SYSTEM_PROMPT = <load from agent/system_prompt.md>
       TOOLS = <load from agent/tools.yml>
       MODEL = 'claude-4-sonnet'
       WAREHOUSE = 'LADINGLENS_WH'

5. src/ladinglens/agent_client.py
   - A Python class LadingLensClient with .ask(question: str) -> AgentResponse
   - Calls the Cortex Agent REST endpoint or SQL interface
   - Returns a dataclass with: final_answer, tool_calls (list of {tool, args, result}), latency_ms, tokens_used
   - Includes retry logic and timeout

6. notebooks/08_agent_eval.ipynb
   - Runs 15 evaluation queries covering:
     - 5 structured (should route to analyst_query only)
     - 5 unstructured (should route to risk_factors_search only or combined)
     - 5 scenario (should route to tariff_scenario, possibly with joined analyst context)
   - Records: routing decision, latency, answer, tool trace
   - Flags any routing errors (e.g., structured question routed to search)

7. docs/agent-eval-report.md
   - Table: query | expected route | actual route | correct? | latency | notes
   - Overall routing accuracy
   - p50/p95 latency
   - Cost per query estimate
   - Failure taxonomy: 3 categories with examples

Run everything and report:
- The 15 query results with routing accuracy
- Latency stats
- Any tool errors (bad SQL from analyst, empty search results, UDF failures)
- Recommended prompt refinements if routing accuracy < 85%

Ask before choosing the agent's model (Claude 4 Sonnet vs. Snowflake Arctic vs. OpenAI GPT) — I have a preference.
```

---

## Your Tasks (Human)

- [ ] **Draft the 15 evaluation queries yourself.** Mix easy/hard, structured/unstructured/scenario. These become your demo script. Aim for 3 that are genuinely impressive ("What's Apple's single-source risk for HS 8542 from Taiwan, and what do they say about it?").
- [ ] **Run the agent from Snowflake Intelligence UI (Snowsight)** for a live-feel demo. Screenshot the response with tool traces visible. Prime asset for the demo video.
- [ ] **Review the system prompt.** Does it feel like a real product? Push back on anything that reads as generic AI-boilerplate.
- [ ] **Time yourself asking 5 questions in a row.** Note where p95 latency is painful — that's what you'll optimize in Phase 10.

---

## Success Criteria

- Agent responds to all 15 test queries without errors.
- Routing accuracy ≥ 85% (correct tool chosen for the query type).
- p50 latency < 4s; p95 < 10s.
- At least 3 queries produce a "joined" answer (metric + verbatim quote).
- Tariff scenario UDF returns correct-looking numbers for the demo scenario.

## Gotchas

- **UDF permissions:** the agent role needs USAGE on the UDF. Grant explicitly.
- **Tool routing failures often come from vague descriptions.** If analyst_query is being over-selected for narrative questions, sharpen the risk_factors_search description with better trigger phrases.
- **Cost:** each agent turn can invoke multiple tools — 3-5 LLM calls under the hood. Cap `max_iterations` in the agent config if you see runaway loops.
- **Scenario UDF sanity check:** hard-code a test call with known inputs and verify the math. A wrong delta in the demo is fatal.
