"""Cached Snowflake query functions for the LadingLens Streamlit-in-Snowflake app.

All queries run through the active Snowpark session provided by SiS
(get_active_session()) -- no snowflake-connector-python, no stored credentials.
"""

import json

import streamlit as st
from snowflake.snowpark.context import get_active_session


@st.cache_data(ttl=3600, show_spinner=False)
def get_top_consignees_by_landed_cost(limit: int = 10):
    session = get_active_session()
    return session.sql(
        f"""
        SELECT c.consignee_name, SUM(f.estimated_landed_cost_usd) AS total_landed_cost
        FROM LADINGLENS_DB.GOLD.FACT_SHIPMENTS f
        JOIN LADINGLENS_DB.GOLD.DIM_CONSIGNEE c ON f.consignee_key = c.consignee_key
        WHERE f.estimated_landed_cost_usd IS NOT NULL
        GROUP BY c.consignee_name
        ORDER BY total_landed_cost DESC NULLS LAST
        LIMIT {limit}
    """
    ).to_pandas()


@st.cache_data(ttl=3600, show_spinner=False)
def get_concentration_heatmap_data(top_n_consignees: int = 30):
    """Supplier HHI recomputed at HS-2 (chapter) grain directly from
    fact_shipments -- NOT derived from mart_concentration_metrics (which is
    HS-6 grain). HHI isn't additive/averageable across subgroups, so combining
    pre-computed HS-6-level HHI values into a chapter-level number would be
    methodologically wrong (the same class of bug caught and fixed in Phase 8's
    scenario procedure, which recomputed landed cost from an averaged rate).
    This uses the identical weighted-shares pattern as
    mart_concentration_metrics, just grouped by LEFT(hs_6, 2) instead of hs_6.

    Returns a pivoted dataframe: index=consignee_name, columns=hs_2, values=supplier_hhi.
    """
    session = get_active_session()
    df = session.sql(
        """
        WITH top_consignees AS (
            SELECT consignee_key, consignee_name
            FROM LADINGLENS_DB.GOLD.DIM_CONSIGNEE
            ORDER BY total_shipments DESC
            LIMIT {top_n}
        ),
        consignee_chapter_supplier AS (
            SELECT f.consignee_key, LEFT(f.hs_6, 2) AS hs_2, f.supplier_key,
                   COUNT(*) AS supplier_shipments
            FROM LADINGLENS_DB.GOLD.FACT_SHIPMENTS f
            JOIN top_consignees tc ON f.consignee_key = tc.consignee_key
            WHERE f.hs_6 IS NOT NULL
              AND LEFT(f.hs_6, 2) IN ('84','87','39','73','61','62')
            GROUP BY 1, 2, 3
        ),
        consignee_chapter_totals AS (
            SELECT consignee_key, hs_2, SUM(supplier_shipments) AS total_shipments
            FROM consignee_chapter_supplier
            GROUP BY 1, 2
        ),
        supplier_shares AS (
            SELECT ccs.consignee_key, ccs.hs_2, ccs.supplier_key,
                   ccs.supplier_shipments * 1.0 / cct.total_shipments AS share
            FROM consignee_chapter_supplier ccs
            JOIN consignee_chapter_totals cct USING (consignee_key, hs_2)
        )
        SELECT tc.consignee_name, s.hs_2, SUM(POWER(s.share, 2)) AS supplier_hhi
        FROM supplier_shares s
        JOIN top_consignees tc ON s.consignee_key = tc.consignee_key
        GROUP BY 1, 2
    """.format(
            top_n=top_n_consignees
        )
    ).to_pandas()

    pivot = df.pivot(index="CONSIGNEE_NAME", columns="HS_2", values="SUPPLIER_HHI")
    return pivot


@st.cache_data(ttl=3600, show_spinner=False)
def get_supplier_breakdown_for_cell(consignee_name: str, hs_2: str):
    """HS-6 drill-down for a selected (consignee, HS-2 chapter) heatmap cell,
    using mart_concentration_metrics at its native HS-6 grain -- gives users
    the underlying detail behind the aggregated chapter-level HHI number."""
    session = get_active_session()
    safe_name = consignee_name.replace("'", "''")
    return session.sql(
        f"""
        SELECT
            m.hs_6, d.hs_6_description,
            m.total_shipment_count AS shipment_count,
            m.supplier_count,
            ROUND(m.supplier_hhi, 3) AS supplier_hhi_hs6,
            m.is_single_source
        FROM LADINGLENS_DB.GOLD.MART_CONCENTRATION_METRICS m
        JOIN LADINGLENS_DB.GOLD.DIM_HS_CODE d ON m.hs_6 = d.hs_6
        JOIN LADINGLENS_DB.GOLD.DIM_CONSIGNEE c ON m.consignee_key = c.consignee_key
        WHERE c.consignee_name = '{safe_name}'
          AND LEFT(m.hs_6, 2) = '{hs_2}'
        ORDER BY shipment_count DESC
    """
    ).to_pandas()


@st.cache_data(ttl=3600, show_spinner=False)
def get_ticker_for_consignee(consignee_name: str):
    """Only 'exact' match_confidence -- 'partial' matches include confirmed
    false positives (e.g. HPQ matching "FORD MOTOR COMPANY (HP05A)" on the
    substring "HP", AAPL matching "ASA APPLE", AMD matching "LUBRIZOL ADVANCED
    MATERIAL INC." on "Advanced"). Showing a 10-K excerpt from the wrong
    company under a confident-looking UI badge is worse than showing fewer
    tickers. 'exact' requires literal canonical_name = company_name equality,
    so it can't produce this failure mode."""
    session = get_active_session()
    safe_name = consignee_name.replace("'", "''")
    rows = session.sql(
        f"""
        SELECT t.ticker
        FROM LADINGLENS_DB.GOLD.DIM_TICKER t
        JOIN LADINGLENS_DB.GOLD.DIM_CONSIGNEE c ON t.matched_consignee_key = c.consignee_key
        WHERE c.consignee_name = '{safe_name}' AND t.match_confidence = 'exact'
    """
    ).collect()
    return rows[0]["TICKER"] if rows else None


@st.cache_data(ttl=3600, show_spinner=False)
def get_shipment_summary_stats():
    session = get_active_session()
    row = session.sql(
        """
        SELECT
            COUNT(*) AS total_shipments,
            COUNT(DISTINCT consignee_key) AS unique_consignees,
            COUNT(DISTINCT supplier_key) AS unique_suppliers,
            SUM(estimated_landed_cost_usd) AS total_landed_cost,
            (SELECT COUNT(*) FROM LADINGLENS_DB.GOLD.MART_CONCENTRATION_METRICS
             WHERE is_single_source) AS single_source_pairs
        FROM LADINGLENS_DB.GOLD.FACT_SHIPMENTS
    """
    ).collect()[0]
    return {
        "total_shipments": row["TOTAL_SHIPMENTS"],
        "unique_consignees": row["UNIQUE_CONSIGNEES"],
        "unique_suppliers": row["UNIQUE_SUPPLIERS"],
        "total_landed_cost": row["TOTAL_LANDED_COST"],
        "single_source_pairs": row["SINGLE_SOURCE_PAIRS"],
    }


@st.cache_data(ttl=3600, show_spinner=False)
def get_origin_country_breakdown():
    session = get_active_session()
    return session.sql(
        """
        SELECT origin_country_code AS country, COUNT(*) AS shipments
        FROM LADINGLENS_DB.GOLD.FACT_SHIPMENTS
        GROUP BY 1
        ORDER BY 2 DESC
    """
    ).to_pandas()


@st.cache_data(ttl=3600, show_spinner=False)
def get_hs_chapter_breakdown():
    session = get_active_session()
    return session.sql(
        """
        SELECT LEFT(hs_6, 2) AS hs_2, COUNT(*) AS shipments
        FROM LADINGLENS_DB.GOLD.FACT_SHIPMENTS
        WHERE hs_6 IS NOT NULL
          AND LEFT(hs_6, 2) IN ('84','87','39','73','61','62')
        GROUP BY 1
        ORDER BY 2 DESC
    """
    ).to_pandas()


@st.cache_data(ttl=3600, show_spinner=False)
def get_scenario_examples(limit: int = 20):
    session = get_active_session()
    return session.sql(
        f"""
        SELECT consignee_name, scenario_name, hs_chapter, origin_country,
               total_shipments, baseline_landed_cost_usd, scenario_landed_cost_usd,
               delta_usd, delta_pct
        FROM LADINGLENS_DB.GOLD.MART_SCENARIO_EXAMPLES
        ORDER BY delta_usd DESC
        LIMIT {limit}
    """
    ).to_pandas()


@st.cache_data(ttl=3600, show_spinner=False)
def get_consignee_options(limit: int = 50):
    session = get_active_session()
    return session.sql(
        f"""
        SELECT consignee_key, consignee_name, total_shipments
        FROM LADINGLENS_DB.GOLD.DIM_CONSIGNEE
        ORDER BY total_shipments DESC
        LIMIT {limit}
    """
    ).to_pandas()


def run_scenario_simulation(
    consignee_key: str,
    additional_rate_pp: float,
    hs_chapters: list,
    origin_countries: list,
    scenario_name: str = "user_scenario",
):
    """Direct call to SIMULATE_TARIFF_SCENARIO (VARIANT param + RETURNS TABLE
    version) -- called from a real Streamlit/Snowpark session, not from inside
    a UDF/procedure sandbox, so the VARIANT-parameter and RETURNS-TABLE
    incompatibilities that forced Phase 8's scalar wrapper for the Cortex
    Agent don't apply here. Not cached -- user-initiated action."""
    session = get_active_session()
    scenario_json = json.dumps(
        {
            "additional_rate_pp": additional_rate_pp,
            "hs_chapters": hs_chapters,
            "origin_countries": origin_countries,
            "scenario_name": scenario_name,
        }
    ).replace("'", "''")
    safe_key = consignee_key.replace("'", "''")
    return session.sql(
        f"""
        CALL LADINGLENS_DB.SEMANTIC.SIMULATE_TARIFF_SCENARIO(
            '{safe_key}', PARSE_JSON('{scenario_json}')
        )
    """
    ).to_pandas()


def run_agent_query(question: str):
    """Direct call to SNOWFLAKE.CORTEX.DATA_AGENT_RUN, using the exact
    invocation pattern verified in Phase 8: the JSON payload must be a literal
    string (not PARSE_JSON()'d -- the function requires a compile-time
    constant second argument), and the response is a `content` array of
    text / tool_use / tool_result blocks (not the simplified
    {'final_answer', 'tool_calls'} shape the original Phase 9 doc's stub
    assumed). Not cached -- user-initiated action.

    Returns {'final_answer': str, 'tool_calls': list[{'tool_name', 'arguments'}],
    'input_tokens': int, 'output_tokens': int, 'model_name': str}.

    Note on tool_calls: no per-tool latency is available anywhere in this
    response -- only total wall-clock time around the whole call (measured by
    the caller). Token counts come from the response's own
    metadata.usage.tokens_consumed block and feed the AGENT_TRACES cost
    estimate (see log_agent_trace) -- this is the real, but incomplete,
    granularity DATA_AGENT_RUN exposes.
    """
    session = get_active_session()
    payload = json.dumps(
        {"messages": [{"role": "user", "content": [{"type": "text", "text": question}]}]}
    ).replace("'", "''")
    raw = session.sql(
        f"""
        SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
            'LADINGLENS_DB.SEMANTIC.LADINGLENS_AGENT', '{payload}'
        )
    """
    ).collect()[0][0]

    data = json.loads(raw)
    text_parts = []
    tool_calls = []
    for block in data.get("content", []):
        t = block.get("type")
        if t == "text":
            text_parts.append(block["text"])
        elif t == "tool_use" and block["tool_use"].get("name") not in (
            None,
            "system_execute_sql",
            "system_agentic_semantic_context",
        ):
            tool_calls.append(
                {
                    "tool_name": block["tool_use"]["name"],
                    "arguments": block["tool_use"].get("input", {}),
                }
            )

    input_tokens = output_tokens = 0
    model_name = None
    usage_list = data.get("metadata", {}).get("usage", {}).get("tokens_consumed", [])
    for usage in usage_list:
        input_tokens += usage.get("input_tokens", {}).get("total", 0) or 0
        output_tokens += usage.get("output_tokens", {}).get("total", 0) or 0
        model_name = usage.get("model_name", model_name)

    return {
        "final_answer": "".join(text_parts).strip() or "(no answer text returned)",
        "tool_calls": tool_calls,
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "model_name": model_name,
    }


# Rough per-token cost, NOT a measured figure. Based on publicly reported
# Cortex AI Functions pricing for Claude Opus (~12 AI Credits per million
# tokens, AI Credits at $2.00/credit global rate) as of mid-2026 -- see
# docs/roadmap.md's Observability section for why this can't be reconciled
# against actual billing (CORTEX_FUNCTIONS_USAGE_HISTORY still returns zero
# rows for this account as of Phase 10). Treated as a single blended
# input+output rate since a precise input/output split wasn't available.
_ESTIMATED_CREDITS_PER_MILLION_TOKENS = 12.0
_ESTIMATED_USD_PER_CREDIT = 2.00


def log_agent_trace(question: str, response: dict, total_latency_ms: int):
    """Writes one row to AGENT_TRACES after a successful agent call. Best-
    effort -- failures here must never break the chat UI, so callers should
    wrap this in a try/except and ignore errors."""
    session = get_active_session()
    total_tokens = response.get("input_tokens", 0) + response.get("output_tokens", 0)
    cost_credits_estimate = (total_tokens / 1_000_000.0) * _ESTIMATED_CREDITS_PER_MILLION_TOKENS

    tool_calls_json = json.dumps(response.get("tool_calls", [])).replace("'", "''")
    safe_question = question.replace("'", "''")
    safe_answer = response.get("final_answer", "").replace("'", "''")

    session.sql(
        f"""
        INSERT INTO LADINGLENS_DB.GOLD.AGENT_TRACES
            (question, response, tool_calls, total_latency_ms, cost_credits_estimate)
        SELECT '{safe_question}', '{safe_answer}', PARSE_JSON('{tool_calls_json}'),
               {int(total_latency_ms)}, {cost_credits_estimate}
    """
    ).collect()


@st.cache_data(ttl=300, show_spinner=False)
def get_agent_trace_stats():
    """KPIs for the observability panel: total queries, p50/p95 latency, avg
    estimated cost (both credits and USD at the same estimated rate used in
    log_agent_trace)."""
    session = get_active_session()
    row = session.sql(
        """
        SELECT
            COUNT(*) AS total_queries,
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_latency_ms) AS p50_latency_ms,
            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY total_latency_ms) AS p95_latency_ms,
            AVG(cost_credits_estimate) AS avg_cost_credits_estimate
        FROM LADINGLENS_DB.GOLD.AGENT_TRACES
    """
    ).collect()[0]
    return {
        "total_queries": row["TOTAL_QUERIES"] or 0,
        "p50_latency_ms": row["P50_LATENCY_MS"] or 0,
        "p95_latency_ms": row["P95_LATENCY_MS"] or 0,
        "avg_cost_credits_estimate": row["AVG_COST_CREDITS_ESTIMATE"] or 0,
        "avg_cost_usd_estimate": (row["AVG_COST_CREDITS_ESTIMATE"] or 0)
        * _ESTIMATED_USD_PER_CREDIT,
    }


@st.cache_data(ttl=300, show_spinner=False)
def get_recent_traces(limit: int = 20):
    session = get_active_session()
    return session.sql(
        f"""
        SELECT timestamp, question, total_latency_ms, cost_credits_estimate,
               tool_calls
        FROM LADINGLENS_DB.GOLD.AGENT_TRACES
        ORDER BY timestamp DESC
        LIMIT {limit}
    """
    ).to_pandas()


@st.cache_data(ttl=300, show_spinner=False)
def get_latency_distribution():
    session = get_active_session()
    return session.sql(
        """
        SELECT total_latency_ms FROM LADINGLENS_DB.GOLD.AGENT_TRACES
    """
    ).to_pandas()


@st.cache_data(ttl=300, show_spinner=False)
def get_tool_usage_breakdown():
    """Flattens tool_calls across all traces to count how often each tool
    was invoked."""
    session = get_active_session()
    return session.sql(
        """
        SELECT tc.value:tool_name::STRING AS tool_name, COUNT(*) AS n_calls
        FROM LADINGLENS_DB.GOLD.AGENT_TRACES,
             LATERAL FLATTEN(input => tool_calls) tc
        GROUP BY 1
        ORDER BY 2 DESC
    """
    ).to_pandas()


@st.cache_data(ttl=3600, show_spinner=False)
def get_10k_search_for_ticker(ticker: str, query: str = "tariff exposure", k: int = 3):
    """Cortex Search filtered to a specific ticker (see Phase 7 for the
    @eq filter syntax)."""
    session = get_active_session()
    payload = json.dumps(
        {
            "query": query,
            "limit": k,
            "columns": ["chunk_text", "ticker", "filing_year"],
            "filter": {"@eq": {"ticker": ticker}},
        }
    ).replace("'", "''")
    raw = session.sql(
        f"""
        SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
            'LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH', '{payload}'
        )):results
    """
    ).collect()[0][0]
    return json.loads(raw)
