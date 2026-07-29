-- Named "udf" in the filename for consistency with the original Phase 8 spec, but
-- this is a STORED PROCEDURE, not a UDF/UDTF. Confirmed empirically (a minimal probe
-- UDTF calling get_active_session() failed with "No default Session is found") that
-- Python UDTFs on this account cannot obtain a session -- the same limitation Phase 5
-- hit, but this time worked around by using a stored procedure instead, since
-- Snowflake passes the session as the first handler argument to a Python stored
-- procedure automatically, no get_active_session() call needed.

CREATE OR REPLACE PROCEDURE LADINGLENS_DB.SEMANTIC.SIMULATE_TARIFF_SCENARIO(
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
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'simulate_scenario'
AS $$
from snowflake.snowpark.types import StructType, StructField, StringType, IntegerType, FloatType

RESULT_SCHEMA = StructType([
    StructField('HS_CHAPTER', StringType()),
    StructField('ORIGIN_COUNTRY', StringType()),
    StructField('TOTAL_SHIPMENTS', IntegerType()),
    StructField('BASELINE_DUTY_RATE_PCT', FloatType()),
    StructField('SCENARIO_DUTY_RATE_PCT', FloatType()),
    StructField('BASELINE_VALUE_USD', FloatType()),
    StructField('BASELINE_LANDED_COST_USD', FloatType()),
    StructField('SCENARIO_LANDED_COST_USD', FloatType()),
    StructField('DELTA_USD', FloatType()),
    StructField('DELTA_PCT', FloatType()),
])


def simulate_scenario(session, consignee_key, scenario):
    additional_rate_pp = float(scenario.get('additional_rate_pp', 0.0))
    hs_chapters = scenario.get('hs_chapters', []) or []
    origin_countries = scenario.get('origin_countries', []) or []

    result_rows = session.sql(f"""
        SELECT
            LEFT(hs_6, 2) AS hs_chapter,
            origin_country_code AS origin_country,
            COUNT(*) AS n_shipments,
            AVG(effective_duty_rate_pct) AS baseline_rate,
            SUM(shipment_value_usd) AS baseline_value,
            SUM(estimated_landed_cost_usd) AS baseline_landed
        FROM LADINGLENS_DB.GOLD.FACT_SHIPMENTS
        WHERE consignee_key = '{consignee_key.replace("'", "''")}'
          AND shipment_value_usd IS NOT NULL
        GROUP BY 1, 2
    """).collect()

    rows = []
    for r in result_rows:
        matches_chapter = (not hs_chapters) or (r['HS_CHAPTER'] in hs_chapters)
        matches_country = (not origin_countries) or (r['ORIGIN_COUNTRY'] in origin_countries)

        baseline_rate = float(r['BASELINE_RATE'] or 0.0)
        rate_increment = additional_rate_pp if (matches_chapter and matches_country) else 0.0
        scenario_rate = baseline_rate + rate_increment

        baseline_value = float(r['BASELINE_VALUE'] or 0.0)
        baseline_landed = float(r['BASELINE_LANDED'] or 0.0)
        # Apply the rate increment as a DELTA on top of the true baseline_landed
        # (SUM of each shipment's own actual landed cost), not by recomputing
        # landed cost from scratch via baseline_value * (1 + scenario_rate/100).
        # baseline_rate is an AVG across shipments in this (chapter, country)
        # group, which can span many HS-6 subheadings with different actual
        # rates -- recomputing from the averaged rate silently produces a
        # phantom nonzero delta even for scenarios that don't match this row
        # at all (confirmed empirically: a non-matching scenario showed a
        # $326K "delta" that should have been exactly $0).
        scenario_landed = baseline_landed + (baseline_value * rate_increment / 100.0)
        delta = scenario_landed - baseline_landed
        delta_pct = (delta / baseline_landed * 100.0) if baseline_landed else 0.0

        rows.append((
            r['HS_CHAPTER'], r['ORIGIN_COUNTRY'],
            int(r['N_SHIPMENTS']),
            baseline_rate, scenario_rate,
            baseline_value, baseline_landed, scenario_landed,
            delta, delta_pct
        ))

    # Explicit typed schema (not just column-name strings) because
    # create_dataframe can't infer a schema from empty data -- and an empty
    # result is a real, expected case here: many large freight-forwarder/
    # consolidator consignees have zero shipments with a populated
    # shipment_value_usd (see Phase 6's documented 54.5% NULL rate).
    return session.create_dataframe(rows, schema=RESULT_SCHEMA)
$$;
