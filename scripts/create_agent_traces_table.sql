-- Backing table for the Phase 10 observability panel. Schema is intentionally
-- honest about what DATA_AGENT_RUN actually exposes: tool_calls captures
-- {tool_name, arguments} per call (no per-tool latency is available anywhere
-- in the response), total_latency_ms is wall-clock time measured by the
-- Streamlit caller around the whole request, and cost_credits_estimate is
-- derived from response token-usage metadata against published Cortex
-- pricing -- not a measured billing figure, since
-- SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY still returns zero
-- rows on this account (see docs/roadmap.md).

CREATE TABLE IF NOT EXISTS LADINGLENS_DB.GOLD.AGENT_TRACES (
    trace_id STRING DEFAULT UUID_STRING(),
    timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    question STRING,
    response STRING,
    tool_calls VARIANT,
    total_latency_ms NUMBER,
    cost_credits_estimate FLOAT,
    session_id STRING
);
