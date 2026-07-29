"""Panel 2: Concentration Heatmap -- the flagship analytical visualization.

HHI is recomputed at HS-2 (chapter) grain directly from fact_shipments (see
utils/snowflake_queries.get_concentration_heatmap_data for why this can't be
derived by combining pre-computed HS-6-level mart_concentration_metrics
values). The HS-6 drill-down below the heatmap uses mart_concentration_metrics
at its native grain to give users the underlying detail.
"""

import streamlit as st
import plotly.express as px

from utils.snowflake_queries import (
    get_concentration_heatmap_data,
    get_supplier_breakdown_for_cell,
    get_ticker_for_consignee,
    get_10k_search_for_ticker,
)
from utils.theme import HS_CHAPTER_LABELS


def render():
    st.markdown("## Supplier Concentration Heatmap")
    st.markdown(
        "HHI concentration index by consignee x HS chapter (0-1 scale; 1.0 = fully "
        "single-sourced). Red cells indicate high supplier concentration. Blank cells "
        "mean this consignee has no shipments in that chapter. Use the dropdowns below "
        "to drill into a cell."
    )

    pivot_df = get_concentration_heatmap_data(top_n_consignees=30)
    chapter_order = [c for c in HS_CHAPTER_LABELS if c in pivot_df.columns]
    pivot_df = pivot_df[chapter_order]

    fig = px.imshow(
        pivot_df.values,
        x=[HS_CHAPTER_LABELS[c] for c in pivot_df.columns],
        y=pivot_df.index,
        color_continuous_scale=["#38A169", "#D69E2E", "#C53030"],  # green -> yellow -> red
        aspect="auto",
        labels={"x": "HS Chapter", "y": "Consignee", "color": "HHI"},
        zmin=0,
        zmax=1,
    )
    fig.update_layout(height=700, margin=dict(l=10, r=10, t=10, b=10))
    st.plotly_chart(fig, use_container_width=True)

    st.markdown("### Detail view")
    col1, col2 = st.columns(2)
    selected_consignee = col1.selectbox("Consignee", pivot_df.index.tolist())
    selected_chapter = col2.selectbox(
        "HS Chapter",
        chapter_order,
        format_func=lambda x: f"{x} - {HS_CHAPTER_LABELS[x]}",
    )

    detail_df = get_supplier_breakdown_for_cell(selected_consignee, selected_chapter)
    if detail_df.empty:
        st.info(f"No shipments for {selected_consignee} in HS chapter {selected_chapter}.")
    else:
        st.markdown(
            f"**HS-6 breakdown for {selected_consignee}, "
            f"chapter {selected_chapter} ({HS_CHAPTER_LABELS[selected_chapter]})**"
        )
        st.dataframe(detail_df, use_container_width=True)

    ticker = get_ticker_for_consignee(selected_consignee)
    if ticker:
        with st.expander(f"10-K risk factors from {ticker}"):
            results = get_10k_search_for_ticker(ticker, query="supplier concentration tariff", k=3)
            if not results:
                st.caption("No matching risk-factor excerpts found.")
            for chunk in results:
                st.markdown(f"**{chunk.get('ticker')} ({chunk.get('filing_year')}):**")
                st.markdown(f"> {chunk.get('chunk_text', '')[:500]}...")
    else:
        st.caption(
            f"No confidently-matched 10-K filer for {selected_consignee} "
            "(only exact name matches are linked -- see data/sources.md Phase 9 notes "
            "on why fuzzy/partial ticker matches are excluded here)."
        )
