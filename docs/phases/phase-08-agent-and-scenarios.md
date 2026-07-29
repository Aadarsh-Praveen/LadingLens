# Phase 8 — Cortex Agent + Tariff Scenario Simulator

**Duration:** ~0.5-1 day
**Depends on:** Phase 6 (SEMANTIC VIEW), Phase 7 (Cortex Search)
**Goal:** Wire the SEMANTIC VIEW + Cortex Search + a new tariff scenario Python UDF into a conversational Cortex Agent. This is where the structured and unstructured halves of the project start talking to each other through a single natural-language interface.

---

## Context

Phase 6 published a SEMANTIC VIEW over the star schema (structured analytics). Phase 7 published a Cortex Search service over 10-K risk factor text (unstructured retrieval). Phase 8's job is to give a user *one* interface that draws on both.

The user experience: someone types "which of Walmart's suppliers pose Section 232 exposure risk?" and behind the scenes:

1. The agent parses intent — "concentration analysis on Walmart + Section 232 filter"
2. Queries SEMANTIC VIEW for Walmart's supplier breakdown filtered to S232-eligible countries + steel/aluminum chapters
3. Optionally queries Cortex Search for Walmart's 10-K risk factor language on tariffs
4. Optionally calls the scenario simulator UDF to compute "what if S232 rate doubles"
5. Synthesizes a natural-language answer with structured data references

Snowflake's Cortex Agents product accepts a declarative YAML config that maps tools (like SEMANTIC_VIEW query, CORTEX.SEARCH, custom UDFs) to natural-language intents. The agent's LLM decides which tool to call for a given question, executes it, and composes an answer.

The scenario simulator is a Python UDF: give it a consignee_key + a scenario dict (e.g., `{"hs_chapters": ["72","73","76"], "additional_rate_pp": 25}`), and it returns before/after landed cost breakdown. Encapsulates the "what if" logic so the agent doesn't have to construct complex conditional SQL.

---

## Deliverables

- [ ] `scripts/create_tariff_scenario_udf.sql` — Python UDF `LADINGLENS_DB.SEMANTIC.SIMULATE_TARIFF_SCENARIO`
- [ ] `agent/ladinglens_agent.yaml` — Cortex Agent declarative config
- [ ] `scripts/publish_agent.sql` — DDL to register the agent
- [ ] `scripts/08_agent_smoke_test.sql` — 10 end-to-end agent queries with expected patterns
- [ ] `dbt/models/gold/mart_scenario_examples.sql` — Pre-computed "canonical" scenarios for demo screenshots
- [ ] `data/sources.md` — Phase 8 wrap section

---

## Claude Code Prompt

```
Phase 8 — Cortex Agent + tariff scenario simulator. Read ./LadingLens.md,
./docs/phases/phase-08-agent-and-scenarios.md, and ./data/sources.md before starting.

STATE RECAP (verified, do not re-check):
- Phases 1-7 complete and committed. Latest HEAD includes Phase 7 (Cortex Search
  service RISK_FACTORS_SEARCH + Bronze extraction fix in scripts/ingest/03_sec_10k.py).
- LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW is published and queryable via
  SEMANTIC_VIEW(...) syntax.
- LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH is published, indexed on
  snowflake-arctic-embed-l-v2.0, containing 1,674 chunks across 24 filings.
- Cortex Agent product availability on this account tier is UNKNOWN — verify in
  Step 0 before proceeding.
- 79 dbt tests pass. Cumulative catches: 31.
- Resource monitor LADINGLENS_CAP at ~20-22 credits of 50.

YOUR TASK:
Build the Python UDF that simulates tariff scenarios, then wire up a Cortex Agent
that can call SEMANTIC_VIEW, CORTEX.SEARCH, and the new UDF as tools. Test with 10
end-to-end natural-language queries.

CONSTRAINTS:
- Cortex Agent availability is uncertain on this account. If unavailable, fall back to
  a "hand-rolled agent" using AI_COMPLETE + tool-calling prompt pattern (documented in
  Step 3.5). Do not block phase completion on Cortex Agent gating.
- The tariff scenario UDF must be pure computation — no database side effects. Given
  a consignee_key + scenario dict, it queries fact_shipments once, computes before/after
  landed cost, returns a structured result.
- All Cortex Agent calls run through SNOWFLAKE.CORTEX.AGENT (or equivalent) — do not
  call OpenAI/Anthropic directly. The whole point is Snowflake-native.
- Budget: Phase 8 Cortex spend <$5. Agent calls are metered per LLM invocation, but
  at test-time scale (10-20 queries) this is trivial.

===========================================
STEP 0 — Verify Cortex Agent availability
===========================================

Check whether the Cortex Agent product is available on this account:

    -- Check for the module
    SELECT
        SYSTEM$GET_PRIVATELINK_CONFIG() AS ignored,  -- placeholder
        'testing' AS test_marker;
    
    -- Better check: try listing existing agents
    SHOW AGENTS IN SCHEMA LADINGLENS_DB.SEMANTIC;
    
    -- If that errors "AGENT not recognized" or similar, we're on the fallback path
    
Also check the newer syntax (as of Snowflake's late-2024/2025 releases):

    SHOW CORTEX AGENTS IN SCHEMA LADINGLENS_DB.SEMANTIC;

Report which command works. If NEITHER returns cleanly, we go to the fallback path
in Step 3.5.

Also verify SEMANTIC_VIEW and Cortex Search still work by running one query against
each:

    SELECT * FROM SEMANTIC_VIEW(LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW
        METRICS fact_shipments.total_shipments
        DIMENSIONS dim_country.country_name
    ) ORDER BY total_shipments DESC LIMIT 5;
    
    SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH',
        '{"query": "tariff exposure", "limit": 2}'
    )):results;

Confirm both return non-empty results.

===========================================
STEP 1 — Tariff Scenario UDF
===========================================

Build a Python UDF that simulates tariff scenarios for a given consignee_key.

The scenario input schema (as a VARIANT parameter):

{
  "additional_rate_pp": 25.0,        -- percentage points to add
  "hs_chapters": ["72", "73", "76"],  -- which chapters (empty = all)
  "origin_countries": ["CN"],         -- which countries (empty = all)
  "scenario_name": "S232 doubles"     -- for display
}

The UDF's job: fetch the consignee's shipments from fact_shipments, apply the scenario
delta to matching rows, return before/after aggregates.

Create scripts/create_tariff_scenario_udf.sql:

CREATE OR REPLACE FUNCTION LADINGLENS_DB.SEMANTIC.SIMULATE_TARIFF_SCENARIO(
    consignee_key STRING,
    scenario VARIANT
)
RETURNS TABLE (
    hs_chapter STRING,
    origin_country STRING,
    total_shipments INTEGER,
    baseline_duty_rate_pct FLOAT,
    scenario_duty_rate_pct FLOAT,
    baseline_value_usd FLOAT,
    baseline_landed_cost_usd FLOAT,
    scenario_landed_cost_usd FLOAT,
    delta_usd FLOAT,
    delta_pct FLOAT
)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'ScenarioHandler'
PACKAGES = ('snowflake-snowpark-python')
AS $$
from snowflake.snowpark.context import get_active_session

class ScenarioHandler:
    def __init__(self):
        pass  # Session available at process() time

    def process(self, consignee_key, scenario):
        additional_rate_pp = float(scenario.get('additional_rate_pp', 0.0))
        hs_chapters = scenario.get('hs_chapters', []) or []
        origin_countries = scenario.get('origin_countries', []) or []
        
        # Query fact_shipments for this consignee
        session = get_active_session()
        query = f"""
            SELECT
                LEFT(hs_6, 2) AS hs_chapter,
                origin_country_code AS origin_country,
                COUNT(*) AS n_shipments,
                AVG(effective_duty_rate_pct) AS baseline_rate,
                SUM(shipment_value_usd) AS baseline_value,
                SUM(estimated_landed_cost_usd) AS baseline_landed
            FROM LADINGLENS_DB.GOLD.FACT_SHIPMENTS
            WHERE consignee_key = '{consignee_key}'
              AND shipment_value_usd IS NOT NULL
            GROUP BY 1, 2
        """
        df = session.sql(query).to_pandas()
        
        for _, row in df.iterrows():
            # Does this row match the scenario filter?
            matches_chapter = (not hs_chapters) or (row['HS_CHAPTER'] in hs_chapters)
            matches_country = (not origin_countries) or (row['ORIGIN_COUNTRY'] in origin_countries)
            
            if matches_chapter and matches_country:
                scenario_rate = (row['BASELINE_RATE'] or 0.0) + additional_rate_pp
            else:
                scenario_rate = row['BASELINE_RATE'] or 0.0
            
            baseline_value = row['BASELINE_VALUE'] or 0.0
            baseline_landed = row['BASELINE_LANDED'] or 0.0
            scenario_landed = baseline_value * (1 + scenario_rate / 100.0) if baseline_value else 0.0
            delta = scenario_landed - baseline_landed
            delta_pct = (delta / baseline_landed * 100.0) if baseline_landed else 0.0
            
            yield (
                row['HS_CHAPTER'],
                row['ORIGIN_COUNTRY'],
                int(row['N_SHIPMENTS']),
                float(row['BASELINE_RATE'] or 0.0),
                float(scenario_rate),
                float(baseline_value),
                float(baseline_landed),
                float(scenario_landed),
                float(delta),
                float(delta_pct)
            )
$$;

Note: get_active_session() from a UDTF has been unreliable in some earlier Snowflake
versions (see Phase 5 Snowpark UDTF story). Verify it works here. If not, fall back to
passing the shipment data as a table parameter or using a stored procedure.

Test the UDF:

    -- Pick a well-known consignee for testing
    SELECT c.consignee_name, c.consignee_key
    FROM LADINGLENS_DB.GOLD.DIM_CONSIGNEE c
    WHERE c.consignee_name ILIKE '%WAL-MART%' OR c.consignee_name ILIKE '%WALMART%'
    ORDER BY total_shipments DESC LIMIT 5;

    -- Then test the scenario
    SELECT * FROM TABLE(LADINGLENS_DB.SEMANTIC.SIMULATE_TARIFF_SCENARIO(
        '<paste_walmart_consignee_key>',
        PARSE_JSON('{
            "additional_rate_pp": 25.0,
            "hs_chapters": ["72", "73", "76"],
            "origin_countries": [],
            "scenario_name": "Section 232 doubles on all origins"
        }')
    ));

Expected output: rows showing before/after landed cost for Walmart's steel/aluminum imports.
If Walmart has minimal exposure to those chapters, try another consignee (e.g., BMW,
Mercedes-Benz — auto industry has more chapter 72/73/76 exposure).

REPORT the test output. If it looks sensible (baseline_landed_cost < scenario_landed_cost
by the expected magnitude), UDF is working.

===========================================
STEP 2 — Canonical scenario examples (for demo)
===========================================

Build dbt/models/gold/mart_scenario_examples.sql — pre-computed scenario outputs for
demo screenshots. This lets the Streamlit UI in Phase 9 show interesting example
scenarios without waiting on live UDF calls (UDF calls take 1-3 seconds each).

Five canonical scenarios to precompute:

1. "S232 doubles on steel/aluminum globally" — additional 25pp on HS 72/73/76 for all countries
2. "S232 reinstated on EU auto" — additional 25pp on HS 87 for EU countries
3. "S301 escalation on Chinese electronics" — additional 25pp on HS 84/85 for CN
4. "Mexico tariffs 10pp uplift" — additional 10pp on all HS chapters for MX
5. "Vietnam apparel tariff shift" — additional 15pp on HS 61/62 for VN

For each scenario, iterate over the top 20 consignees by total_shipments, run the UDF,
and materialize the results. Structure:

WITH top_consignees AS (
    SELECT consignee_key, consignee_name
    FROM LADINGLENS_DB.GOLD.DIM_CONSIGNEE
    ORDER BY total_shipments DESC
    LIMIT 20
),
scenarios AS (
    SELECT 'S232 doubles globally' AS scenario_name,
           PARSE_JSON('{"additional_rate_pp": 25.0, "hs_chapters": ["72","73","76"], "origin_countries": []}') AS scenario
    UNION ALL
    SELECT 'S232 EU auto', PARSE_JSON('{"additional_rate_pp": 25.0, "hs_chapters": ["87"], "origin_countries": ["DE","BE","FR","IT","GB","ES"]}')
    UNION ALL
    SELECT 'S301 China electronics', PARSE_JSON('{"additional_rate_pp": 25.0, "hs_chapters": ["84","85"], "origin_countries": ["CN"]}')
    UNION ALL
    SELECT 'Mexico +10pp all chapters', PARSE_JSON('{"additional_rate_pp": 10.0, "hs_chapters": [], "origin_countries": ["MX"]}')
    UNION ALL
    SELECT 'Vietnam apparel +15pp', PARSE_JSON('{"additional_rate_pp": 15.0, "hs_chapters": ["61","62"], "origin_countries": ["VN"]}')
),
combined AS (
    SELECT c.consignee_key, c.consignee_name, s.scenario_name, s.scenario
    FROM top_consignees c CROSS JOIN scenarios s
)
SELECT
    c.consignee_key,
    c.consignee_name,
    c.scenario_name,
    result.hs_chapter,
    result.origin_country,
    result.total_shipments,
    result.baseline_landed_cost_usd,
    result.scenario_landed_cost_usd,
    result.delta_usd,
    result.delta_pct
FROM combined c,
     TABLE(LADINGLENS_DB.SEMANTIC.SIMULATE_TARIFF_SCENARIO(c.consignee_key, c.scenario)) result
WHERE result.delta_usd > 0  -- Only rows where the scenario actually changed cost

Materialize as TABLE.

Row count target: 100-500 rows depending on which scenarios/consignees intersect.

Report the top 20 highest-delta rows — these are the "biggest tariff exposure impact"
scenario cells that Phase 9 will feature prominently.

===========================================
STEP 3 — Cortex Agent (if available)
===========================================

If SHOW CORTEX AGENTS worked in Step 0, proceed with agent creation. If not, jump to
Step 3.5.

Build agent/ladinglens_agent.yaml:

name: LADINGLENS_AGENT
description: >
    Supply chain tariff exposure and concentration risk copilot. Fuses US customs
    bill-of-lading data with SEC 10-K risk disclosures to answer questions about
    consignee-level tariff exposure, supplier/country concentration, and scenario
    what-ifs. Data spans 2018 CBP AMS filings enriched with Q3 2026 tariff schedules.

tools:
  - name: structured_query
    description: Query structured shipment, supplier, consignee, and tariff data.
                 Use this for concentration analysis, aggregations, and filtering
                 by HS chapter, origin country, or consignee.
    type: cortex_semantic_view
    semantic_view: LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW

  - name: risk_factor_retrieval
    description: Retrieve relevant excerpts from SEC 10-K/20-F risk factor
                 disclosures for a specific company. Use this when the user asks
                 what a company "says about" or "discloses about" a risk topic.
                 Filter by ticker attribute if the user names a specific company.
    type: cortex_search
    search_service: LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH

  - name: tariff_scenario_simulator
    description: Simulate what-if tariff scenarios for a specific consignee. Given
                 a consignee_key and a scenario dict specifying additional rate
                 percentage points, HS chapters, and origin countries, returns
                 before/after landed cost breakdown. Use when the user asks
                 "what happens if [tariff change]" or "how much would [company]
                 pay under [scenario]."
    type: sql_function
    function: LADINGLENS_DB.SEMANTIC.SIMULATE_TARIFF_SCENARIO
    parameters:
      - name: consignee_key
        type: STRING
        description: Golden consignee ID from dim_consignee
      - name: scenario
        type: VARIANT
        description: JSON with additional_rate_pp, hs_chapters, origin_countries, scenario_name

system_prompt: >
    You are LadingLens, a supply chain risk copilot. Answer user questions by calling
    the appropriate tool(s). If the user asks about concentration or aggregates, use
    structured_query. If they ask what a company discloses, use risk_factor_retrieval.
    If they ask about tariff scenarios, first look up the consignee_key via
    structured_query, then call tariff_scenario_simulator. Always cite specific
    numbers and, when using retrieval, quote the relevant excerpt.

Publish via scripts/publish_agent.sql. Exact DDL syntax varies by Snowflake version —
adjust based on current docs. Approximate pattern:

    CREATE OR REPLACE CORTEX AGENT LADINGLENS_DB.SEMANTIC.LADINGLENS_AGENT
    FROM '@LADINGLENS_DB.STAGE.RAW_STAGE/agent/ladinglens_agent.yaml';

Or if there's a Python API instead of DDL, use that. Report which path was used.

===========================================
STEP 3.5 — Hand-rolled fallback agent (if Cortex Agent unavailable)
===========================================

If Cortex Agent isn't on this account tier, build a lightweight substitute using
AI_COMPLETE + tool-calling prompt pattern.

Create a stored procedure that:
1. Takes user question as VARCHAR input
2. Sends it to AI_COMPLETE with a system prompt describing available tools
3. Parses the LLM's tool selection from the response
4. Executes the selected tool (SEMANTIC_VIEW query, CORTEX.SEARCH, or UDF call)
5. Feeds results back to AI_COMPLETE for final synthesis
6. Returns natural-language answer

Approximate structure:

CREATE OR REPLACE PROCEDURE LADINGLENS_DB.SEMANTIC.ASK_LADINGLENS(question STRING)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'ask_ladinglens'
AS $$
def ask_ladinglens(session, question):
    # Step 1: Ask LLM which tool to use
    tool_selection_prompt = f"""You have three tools:
    1. structured_query(natural_language_intent) — queries a supply-chain semantic view
    2. risk_factor_retrieval(company_ticker, topic) — retrieves SEC 10-K excerpts
    3. tariff_scenario_simulator(consignee_name, scenario) — simulates tariff what-ifs
    
    User question: {question}
    
    Reply with ONLY a JSON object: {{"tool": "<tool_name>", "reasoning": "<why>"}}"""
    
    tool_choice = session.sql(f"SELECT SNOWFLAKE.CORTEX.AI_COMPLETE('llama3.1-8b', '{tool_selection_prompt.replace(chr(39), chr(39)+chr(39))}')").collect()[0][0]
    
    # Parse, execute the tool, synthesize final answer via AI_COMPLETE
    # (Full implementation ~50 lines)
    ...
$$;

Document the fallback path clearly in data/sources.md: "Cortex Agent was not available
on the account tier; a hand-rolled agent using AI_COMPLETE + tool-calling was built
as substitute."

===========================================
STEP 4 — 10-question end-to-end smoke test
===========================================

Build scripts/08_agent_smoke_test.sql (or a Python notebook) with 10 questions that
exercise all three tools. For each, record the question, the tool(s) the agent
selected, the raw output, and the synthesized answer.

Test questions:

1. "Which are the top 5 consignees by total landed cost?"
   Expected tool: structured_query only

2. "What does Walmart's 10-K say about tariff exposure?"
   Expected tool: risk_factor_retrieval (filter ticker=WMT)

3. "Which of Nike's suppliers are Vietnamese?"
   Expected tool: structured_query only

4. "If Section 232 tariffs doubled on steel and aluminum, what would BMW's exposure be?"
   Expected: structured_query (find BMW consignee_key) → tariff_scenario_simulator

5. "Which companies mention Section 301 risks in their 10-Ks?"
   Expected tool: risk_factor_retrieval (no ticker filter)

6. "What's my total tariff exposure across all steel imports from Germany?"
   Expected tool: structured_query only

7. "For Walmart, what happens if Chinese electronics tariffs go up 25 points?"
   Expected: structured_query → tariff_scenario_simulator

8. "How diversified is Nike's supplier base for apparel?"
   Expected tool: structured_query (mart_concentration_metrics)

9. "What does Caterpillar disclose about supply chain risks and how does that compare
   to their current exposure?"
   Expected tool: risk_factor_retrieval AND structured_query (fusion query)

10. "Show me consignees single-sourced for HS chapter 87 and what their 10-Ks say
    about supplier concentration."
    Expected: structured_query → risk_factor_retrieval (fusion query)

For each: record the question, tool(s) called, raw tool outputs, and final answer.

Report:
- Success rate (how many questions produced coherent, factually-grounded answers)
- Tool-selection accuracy (did the agent choose the right tool?)
- Any hallucinations (agent claiming facts not in the tool outputs)
- Latency per question

Target: 7-9 of 10 questions produce good answers. Fusion queries (Q9, Q10) are the
hardest and may not work perfectly on the first pass.

===========================================
STEP 5 — dbt tests
===========================================

Add tests for:
- mart_scenario_examples:
    - not_null: consignee_key, scenario_name, hs_chapter, origin_country
    - Row count between 100 and 1000 (sanity bound)
    - delta_usd is non-negative (all scenarios add cost, don't subtract)

Run dbt test. Report all pass/fail. Total should be 80+.

===========================================
STEP 6 — Documentation
===========================================

Append to data/sources.md a Phase 8 wrap section:

    Phase 8 wrap — Cortex Agent + Tariff Scenario Simulator:
    
    Built the agent orchestration layer on top of Phase 6/7 primitives.
    
    - Python UDF LADINGLENS_DB.SEMANTIC.SIMULATE_TARIFF_SCENARIO: given a consignee
      and scenario dict, computes before/after landed cost broken down by
      (HS chapter, origin country). Encapsulates the what-if logic.
    - mart_scenario_examples: [X] pre-computed scenario cells for 20 top consignees
      across 5 canonical scenarios (S232 doubles, S232 EU auto, S301 China electronics,
      Mexico +10pp, Vietnam apparel +15pp).
    - Cortex Agent LADINGLENS_DB.SEMANTIC.LADINGLENS_AGENT [OR hand-rolled fallback
      via ASK_LADINGLENS procedure — specify which was used]. Exposes three tools:
      structured_query (SEMANTIC_VIEW), risk_factor_retrieval (Cortex Search),
      tariff_scenario_simulator (UDF).
    
    Smoke test: [X of 10] questions produced coherent, factually-grounded answers.
    Tool-selection accuracy: [X%]. Fusion queries (Q9, Q10 — combining structured
    + unstructured retrieval) [worked / partially worked / need iteration].
    
    Phase 8 Cortex spend: ~$[X] (agent calls + UDF-driven aggregations).
    
    Total dbt tests: [X] pass (up from 79).
    
    What Phase 8 unlocks:
    - Phase 9 (Streamlit): can now embed the agent as a chat panel alongside the
      concentration heatmap and tariff dashboard
    - The full "structured + unstructured + scenario simulation in a single
      conversational interface" story that defines LadingLens as a product

===========================================
EXECUTION ORDER & CHECKPOINTS
===========================================

Report at each checkpoint. Do not silently proceed.

CHECKPOINT 0 — Cortex Agent availability determined + Semantic View + Cortex Search
both re-verified as working.

CHECKPOINT 1 — Scenario UDF built and tested against a known consignee (Walmart or
BMW). Report the test output.

CHECKPOINT 2 — mart_scenario_examples built, top-20 highest-delta cells reported.

CHECKPOINT 3 — Agent published (Cortex Agent or fallback procedure). Confirm creation.

CHECKPOINT 4 — Smoke test executed on all 10 questions. Report per-question outcome
and overall success rate.

CHECKPOINT 5 — dbt tests all pass.

Do NOT commit until I greenlight the final review.
```

---

## Your Tasks (Human)

- [ ] **Verify Cortex Agent availability** in Snowsight before Claude Code starts. Run: `SHOW CORTEX AGENTS IN SCHEMA LADINGLENS_DB.SEMANTIC;` If it errors like Cortex Analyst did, we're on the hand-rolled fallback path — still functional, just documented as "would use Cortex Agent in production."
- [ ] **Test 2-3 agent queries yourself** in Snowsight after publishing. Type real questions relevant to Walmart, Nike, Caterpillar. Screenshot the best ones.
- [ ] **Screenshot the mart_scenario_examples top-20** — the "biggest tariff impact" table is a demo asset for Phase 9.
- [ ] **Note any hallucinations** — if the agent claims facts not in the underlying data, that's important to document as a limitation (fix path is prompt hardening in Phase 9 or 10).

---

## Success Criteria

- Scenario UDF returns correct before/after landed cost values (verify against 1-2 hand-computed cases)
- mart_scenario_examples has 100-500 rows with realistic delta_usd values
- Agent (or fallback) publishes successfully
- Smoke test: 7-9 of 10 questions produce coherent factually-grounded answers
- Fusion queries (Q9, Q10) work at least partially — even acknowledging both tools have been consulted is meaningful
- Total dbt tests: 80+ passing

## Gotchas

- **Cortex Agent syntax has evolved rapidly** across 2024-2025. If the DDL fails, iterate on syntax and check current docs. Fallback path is functional.
- **Agent hallucinations** are the most common failure mode. Ground the system prompt aggressively: "cite exact numbers from tool outputs; do not extrapolate."
- **Fusion queries** requiring both structured + unstructured retrieval are inherently harder. Expect Q9/Q10 to take multiple prompt iterations to work well.
- **UDF invocation from within agent tool-calling** may have session-context issues (recall Phase 5's `get_active_session()` unreliability). Test the UDF standalone first, then test agent-calling-UDF.
- **Latency** for fusion queries can be 5-10 seconds (structured query + Cortex Search + LLM synthesis). This is OK for hackathon demo but the Streamlit UI should show a loading indicator.
