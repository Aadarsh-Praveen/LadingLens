-- Cortex Agent's `generic` tool type has TWO confirmed incompatibilities with
-- the original SIMULATE_TARIFF_SCENARIO procedure, found empirically:
--   1. A VARIANT/object-typed argument (the original `scenario` param) is
--      rejected outright: "generic tool ... uses argument type object which
--      is not supported for execution environment type warehouse".
--   2. Independently, a RETURNS TABLE procedure ALSO fails at invocation time
--      with an opaque "empty error response body for HTTP status 400 Bad
--      Request" -- confirmed by isolating a trivial RETURNS STRING procedure
--      (which the agent invoked successfully with identical scalar params)
--      against an otherwise-identical RETURNS TABLE procedure (which failed
--      the same way regardless of parameter types). Cortex Agent's generic
--      tool appears to only support scalar-returning procedures.
--
-- This wrapper fixes both: scalar-only parameters (STRING/FLOAT) AND a
-- RETURNS STRING signature (JSON-serialized rows) instead of RETURNS TABLE.
-- The original SIMULATE_TARIFF_SCENARIO procedure is untouched and still used
-- directly for mart_scenario_examples and any standalone/CLI use (Step 1's
-- CAT test still applies to it).

CREATE OR REPLACE PROCEDURE LADINGLENS_DB.SEMANTIC.SIMULATE_TARIFF_SCENARIO_AGENT(
    consignee_key STRING,
    additional_rate_pp FLOAT,
    hs_chapters STRING,       -- comma-separated, e.g. '72,73,76'; empty/NULL = all chapters
    origin_countries STRING,  -- comma-separated, e.g. 'CN'; empty/NULL = all countries
    scenario_name STRING
)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'simulate_scenario_agent'
AS $$
import json


def simulate_scenario_agent(session, consignee_key, additional_rate_pp, hs_chapters, origin_countries, scenario_name):
    chapters_list = [c.strip() for c in hs_chapters.split(',') if c.strip()] if hs_chapters else []
    countries_list = [c.strip() for c in origin_countries.split(',') if c.strip()] if origin_countries else []

    scenario_dict = {
        'additional_rate_pp': additional_rate_pp,
        'hs_chapters': chapters_list,
        'origin_countries': countries_list,
        'scenario_name': scenario_name or '',
    }
    scenario_json = json.dumps(scenario_dict).replace("'", "''")
    safe_key = consignee_key.replace("'", "''")

    result_rows = session.sql(f"""
        CALL LADINGLENS_DB.SEMANTIC.SIMULATE_TARIFF_SCENARIO(
            '{safe_key}', PARSE_JSON('{scenario_json}')
        )
    """).collect()

    rows = [
        {
            'hs_chapter': r['HS_CHAPTER'],
            'origin_country': r['ORIGIN_COUNTRY'],
            'total_shipments': int(r['TOTAL_SHIPMENTS']),
            'baseline_duty_rate_pct': float(r['BASELINE_DUTY_RATE_PCT']),
            'scenario_duty_rate_pct': float(r['SCENARIO_DUTY_RATE_PCT']),
            'baseline_value_usd': float(r['BASELINE_VALUE_USD']),
            'baseline_landed_cost_usd': float(r['BASELINE_LANDED_COST_USD']),
            'scenario_landed_cost_usd': float(r['SCENARIO_LANDED_COST_USD']),
            'delta_usd': float(r['DELTA_USD']),
            'delta_pct': float(r['DELTA_PCT']),
        }
        for r in result_rows
    ]
    return json.dumps({'scenario_name': scenario_name, 'rows': rows})
$$;
