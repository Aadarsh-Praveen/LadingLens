"""Panel 1: Executive Dashboard -- corpus-at-a-glance overview."""

import plotly.express as px
from utils.snowflake_queries import (
    get_hs_chapter_breakdown,
    get_origin_country_breakdown,
    get_shipment_summary_stats,
    get_top_consignees_by_landed_cost,
)
from utils.theme import ACCENT, HS_CHAPTER_LABELS, PRIMARY

import streamlit as st


def render():
    """Render the Executive Overview panel: summary KPIs, origin-country and
    HS-chapter breakdowns, and a top-consignees-by-landed-cost chart."""
    st.markdown("## Executive Overview")
    st.markdown("A view of the LadingLens analytical corpus at a glance.")

    stats = get_shipment_summary_stats()
    col1, col2, col3, col4 = st.columns(4)
    col1.metric("Total shipments", f"{stats['total_shipments']:,}")
    col2.metric("Unique consignees", f"{stats['unique_consignees']:,}")
    col3.metric("Unique suppliers", f"{stats['unique_suppliers']:,}")
    col4.metric("Single-source pairs", f"{stats['single_source_pairs']:,}")
    st.caption(
        "Single-source pairs: (consignee, HS-6) combinations where one supplier "
        "accounts for >70% of shipment volume. See the Concentration Heatmap for detail."
    )

    col1, col2 = st.columns(2)
    with col1:
        st.markdown("### By Origin Country")
        df = get_origin_country_breakdown()
        fig = px.bar(
            df.sort_values("SHIPMENTS", ascending=False),
            x="COUNTRY",
            y="SHIPMENTS",
            color_discrete_sequence=[PRIMARY],
            labels={"COUNTRY": "Origin country", "SHIPMENTS": "Shipments"},
        )
        st.plotly_chart(fig, use_container_width=True)
    with col2:
        st.markdown("### By HS Chapter")
        df = get_hs_chapter_breakdown()
        df["chapter_label"] = df["HS_2"].map(HS_CHAPTER_LABELS)
        fig = px.pie(
            df,
            names="chapter_label",
            values="SHIPMENTS",
            color_discrete_sequence=px.colors.sequential.Blues_r,
        )
        st.plotly_chart(fig, use_container_width=True)

    st.markdown("### Top 10 Consignees by Landed Cost")
    df = get_top_consignees_by_landed_cost(10)
    fig = px.bar(
        df,
        x="TOTAL_LANDED_COST",
        y="CONSIGNEE_NAME",
        orientation="h",
        color_discrete_sequence=[ACCENT],
        labels={"TOTAL_LANDED_COST": "Total landed cost (USD)", "CONSIGNEE_NAME": ""},
    )
    fig.update_layout(yaxis={"autorange": "reversed"})
    st.plotly_chart(fig, use_container_width=True)
    st.caption(
        "Note: several top entries (e.g. freight forwarders) act as consignee-of-record "
        "for consolidated shipments and may aggregate volume across multiple underlying "
        "importers -- see data/sources.md Phase 4 notes."
    )
