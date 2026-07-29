-- Publishes the LadingLens Cortex Agent. See agent/ladinglens_agent.yaml for
-- the full commentary on why this spec's structure diverges from the
-- original Phase 8 doc's draft (verified empirically against the real
-- account, not guessed). Keep the two files in sync.
--
-- Actual invocation syntax (also differs from the doc's guess of
-- SNOWFLAKE.CORTEX.AGENT_RUN): SNOWFLAKE.CORTEX.DATA_AGENT_RUN, taking the
-- agent name and a JSON string (not PARSE_JSON'd -- must be passed as a
-- literal string) with a `messages` array in the REST chat-completions shape.

CREATE OR REPLACE AGENT LADINGLENS_DB.SEMANTIC.LADINGLENS_AGENT
FROM SPECIFICATION $$
instructions:
  response: >
    Answer concisely, citing exact numbers from tool outputs. Do not
    extrapolate beyond what tools return. When quoting 10-K excerpts,
    include the ticker and filing year.
  orchestration: >
    Use query_shipments for aggregate, concentration, and filtering
    questions over shipment/supplier/consignee/tariff data. Use
    retrieve_10k_risk_factors when the user asks what a company discloses
    or says about a risk topic; filter by ticker if the user names a
    company. For tariff what-if scenarios, first identify the
    consignee_key via query_shipments (do not guess it), then call
    simulate_tariff_scenario with scalar arguments -- hs_chapters and
    origin_countries are comma-separated strings, empty string means "all".
    Prefer short answers with exact citations over long generalizations.

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "query_shipments"
      description: >
        Query structured shipment, supplier, consignee, and tariff data
        for LadingLens. Use this for aggregation questions, concentration
        analysis, and filtering by HS chapter, origin country, or
        consignee.

  - tool_spec:
      type: "cortex_search"
      name: "retrieve_10k_risk_factors"
      description: >
        Retrieve relevant excerpts from SEC 10-K/20-F risk factor
        disclosures for a specific company. Use this when the user asks
        what a company "says about" or "discloses about" a risk topic.
        Filter by ticker attribute if the user names a specific company.

  - tool_spec:
      type: "generic"
      name: "simulate_tariff_scenario"
      description: >
        Simulate a what-if tariff scenario for a specific consignee_key
        (obtain it from query_shipments first -- do not guess it).
        hs_chapters and origin_countries are comma-separated strings
        (e.g. "72,73,76"); an empty string means "all". Returns JSON with
        before/after landed cost broken down by (HS chapter, origin
        country). Use when the user asks "what happens if [tariff
        change]" or "how much would [company] pay under [scenario]."
      input_schema:
        type: object
        properties:
          consignee_key:
            type: string
            description: Golden consignee ID from dim_consignee.
          additional_rate_pp:
            type: number
            description: Percentage points to add to the duty rate for matching rows.
          hs_chapters:
            type: string
            description: Comma-separated HS-2 chapters to match, e.g. "72,73,76"; empty string = all chapters.
          origin_countries:
            type: string
            description: Comma-separated origin country codes to match, e.g. "CN"; empty string = all countries.
          scenario_name:
            type: string
            description: Human-readable label for this scenario.
        required:
          - consignee_key
          - additional_rate_pp
          - hs_chapters
          - origin_countries
          - scenario_name

tool_resources:
  query_shipments:
    semantic_view: "LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW"
    execution_environment:
      warehouse: "LADINGLENS_WH"

  retrieve_10k_risk_factors:
    name: "LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH"
    max_results: 5

  simulate_tariff_scenario:
    type: "procedure"
    identifier: "LADINGLENS_DB.SEMANTIC.SIMULATE_TARIFF_SCENARIO_AGENT"
    execution_environment:
      type: "warehouse"
      warehouse: "LADINGLENS_WH"
$$;
