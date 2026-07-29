"""Builds LADINGLENS_DB.GOLD.MART_SCENARIO_EXAMPLES by CALLing the
SIMULATE_TARIFF_SCENARIO stored procedure once per (top-20 consignee, canonical
scenario) pair -- 100 invocations total.

Not a dbt model: stored procedures can't be invoked per-row from a SELECT's FROM
clause the way a UDTF can (CROSS JOIN + TABLE(...) doesn't work here), so this
table is built by a plain Python driver and referenced from dbt as a source
(see dbt/ladinglens/models/gold/_gold_external_sources.yml), not a ref()'d model.

Idempotent: CREATE OR REPLACE TABLE, safe to re-run.
"""

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "ingest"))
from _snowflake_conn import connect

SCENARIOS = [
    (
        "S232 doubles globally",
        {"additional_rate_pp": 25.0, "hs_chapters": ["72", "73", "76"], "origin_countries": []},
    ),
    (
        "S232 EU auto",
        {
            "additional_rate_pp": 25.0,
            "hs_chapters": ["87"],
            "origin_countries": ["DE", "BE", "FR", "IT", "GB", "ES"],
        },
    ),
    (
        "S301 China electronics",
        {"additional_rate_pp": 25.0, "hs_chapters": ["84", "85"], "origin_countries": ["CN"]},
    ),
    (
        "Mexico +10pp all chapters",
        {"additional_rate_pp": 10.0, "hs_chapters": [], "origin_countries": ["MX"]},
    ),
    (
        "Vietnam apparel +15pp",
        {"additional_rate_pp": 15.0, "hs_chapters": ["61", "62"], "origin_countries": ["VN"]},
    ),
]

TABLE = "LADINGLENS_DB.GOLD.MART_SCENARIO_EXAMPLES"


def main():
    """Rebuild MART_SCENARIO_EXAMPLES: CALL SIMULATE_TARIFF_SCENARIO for
    every (top-20 consignee, canonical scenario) pair and keep only rows
    where the scenario produced a positive cost delta."""
    conn = connect()
    cur = conn.cursor()

    cur.execute(f"""
        CREATE OR REPLACE TABLE {TABLE} (
            consignee_key STRING,
            consignee_name STRING,
            scenario_name STRING,
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
    """)

    cur.execute("""
        SELECT consignee_key, consignee_name
        FROM LADINGLENS_DB.GOLD.DIM_CONSIGNEE
        ORDER BY total_shipments DESC
        LIMIT 20
    """)
    consignees = cur.fetchall()

    all_rows = []
    n_calls = 0
    for consignee_key, consignee_name in consignees:
        for scenario_name, scenario_dict in SCENARIOS:
            n_calls += 1
            scenario_json = json.dumps(scenario_dict).replace("'", "''")
            cur.execute(f"""
                CALL LADINGLENS_DB.SEMANTIC.SIMULATE_TARIFF_SCENARIO(
                    '{consignee_key}',
                    PARSE_JSON('{scenario_json}')
                )
            """)
            for r in cur.fetchall():
                (
                    hs_chapter,
                    origin_country,
                    total_shipments,
                    baseline_rate,
                    scenario_rate,
                    baseline_value,
                    baseline_landed,
                    scenario_landed,
                    delta_usd,
                    delta_pct,
                ) = r
                if delta_usd is None or delta_usd <= 0:
                    continue  # only rows where the scenario actually changed cost
                all_rows.append(
                    (
                        consignee_key,
                        consignee_name,
                        scenario_name,
                        hs_chapter,
                        origin_country,
                        total_shipments,
                        baseline_rate,
                        scenario_rate,
                        baseline_value,
                        baseline_landed,
                        scenario_landed,
                        delta_usd,
                        delta_pct,
                    )
                )
        print(
            f"  {consignee_name}: {n_calls}/{len(consignees) * len(SCENARIOS)} calls done, {len(all_rows)} rows so far"
        )

    print(f"Total CALL invocations: {n_calls}")
    print(f"Total rows to insert: {len(all_rows)}")

    if all_rows:
        placeholders = ", ".join(["%s"] * 13)
        cur.executemany(
            f"INSERT INTO {TABLE} VALUES ({placeholders})",
            all_rows,
        )
    conn.commit()

    cur.execute(f"SELECT COUNT(*) FROM {TABLE}")
    print("Final row count in table:", cur.fetchone()[0])


if __name__ == "__main__":
    main()
