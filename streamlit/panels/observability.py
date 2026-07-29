"""Panel 5: Observability -- agent trace logging and quality signal.

Path B observability (see docs/roadmap.md): TruLens (trulens-eval) was tested
directly against this account and found unavailable -- installing it as a
Snowflake UDF package fails because a transitive dependency (psutil) requires
native code compilation, unsupported in the Python UDF sandbox. This panel
reports on real logged traces (latency, tool usage, estimated cost) without
an automated groundedness/relevance scoring layer on top.
"""

import json

import plotly.express as px
from utils.snowflake_queries import (
    get_agent_trace_stats,
    get_latency_distribution,
    get_recent_traces,
    get_tool_usage_breakdown,
)

import streamlit as st


def render():
    """Render the Observability panel: KPI cards, latency and tool-usage
    charts, and a recent-traces table, all sourced from AGENT_TRACES. Shows
    an empty-state message if no queries have been logged yet."""
    st.markdown("## Observability")
    st.markdown(
        "Real traces logged from every Ask LadingLens query. Estimated cost is "
        "derived from response token-usage metadata against published Cortex "
        "pricing -- **not** a measured billing figure (see `docs/roadmap.md`)."
    )

    stats = get_agent_trace_stats()
    if stats["total_queries"] == 0:
        st.info(
            "No agent queries logged yet. Ask a question in the "
            "**Ask LadingLens** tab to populate this panel."
        )
        return

    col1, col2, col3, col4 = st.columns(4)
    col1.metric("Total queries served", f"{stats['total_queries']:,}")
    col2.metric("p50 latency", f"{stats['p50_latency_ms'] / 1000:.1f}s")
    col3.metric("p95 latency", f"{stats['p95_latency_ms'] / 1000:.1f}s")
    col4.metric(
        "Avg cost / query (est.)",
        f"${stats['avg_cost_usd_estimate']:.4f}",
        help="Estimated from token counts, not measured billing -- see docs/roadmap.md.",
    )

    col1, col2 = st.columns(2)
    with col1:
        st.markdown("### Latency distribution")
        latency_df = get_latency_distribution()
        latency_df["seconds"] = latency_df["TOTAL_LATENCY_MS"] / 1000.0
        fig = px.histogram(latency_df, x="seconds", nbins=20, labels={"seconds": "Latency (s)"})
        st.plotly_chart(fig, use_container_width=True)
    with col2:
        st.markdown("### Tool usage breakdown")
        tool_df = get_tool_usage_breakdown()
        if tool_df.empty:
            st.caption("No tool calls logged yet.")
        else:
            fig = px.bar(
                tool_df,
                x="TOOL_NAME",
                y="N_CALLS",
                labels={"TOOL_NAME": "Tool", "N_CALLS": "Calls"},
            )
            st.plotly_chart(fig, use_container_width=True)

    st.markdown("### Recent traces")
    traces_df = get_recent_traces(limit=20)
    display_df = traces_df.copy()
    display_df["latency_s"] = (display_df["TOTAL_LATENCY_MS"] / 1000.0).round(1)
    display_df["tools_used"] = display_df["TOOL_CALLS"].apply(
        lambda tc: ", ".join(sorted({t["tool_name"] for t in json.loads(tc)})) if tc else ""
    )
    st.dataframe(
        display_df[["TIMESTAMP", "QUESTION", "latency_s", "tools_used", "COST_CREDITS_ESTIMATE"]],
        use_container_width=True,
    )
