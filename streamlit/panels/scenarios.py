"""Panel 3: Tariff Scenario Simulator -- interactive what-if picker."""

import streamlit as st

from utils.snowflake_queries import (
    get_scenario_examples,
    get_consignee_options,
    run_scenario_simulation,
)
from utils.theme import HS_CHAPTER_LABELS, ORIGIN_COUNTRIES


def render():
    st.markdown("## Tariff Scenario Simulator")
    st.markdown("Simulate the impact of tariff changes on a consignee's landed cost.")

    st.markdown("### Example Scenarios (Pre-computed)")
    st.caption(
        "24 pre-computed cells across the top 20 consignees by volume x 5 canonical "
        "scenarios. Coverage is EU-auto-forwarder-heavy since it's built from the "
        "top-20-by-shipment-count consignees -- use the live simulator below for "
        "any consignee/scenario combination, including ones not represented here."
    )
    examples_df = get_scenario_examples(limit=20)
    st.dataframe(examples_df, use_container_width=True)

    st.markdown("---")
    st.markdown("### Build Your Own Scenario")

    col1, col2 = st.columns([1, 2])
    with col1:
        consignees = get_consignee_options(limit=50)
        selected_consignee = st.selectbox("Consignee", consignees["CONSIGNEE_NAME"].tolist())
        selected_consignee_key = consignees[consignees["CONSIGNEE_NAME"] == selected_consignee][
            "CONSIGNEE_KEY"
        ].iloc[0]

        additional_rate = st.slider(
            "Additional tariff rate (percentage points)",
            min_value=0.0,
            max_value=100.0,
            value=25.0,
            step=5.0,
        )

        hs_chapters = st.multiselect(
            "HS chapters affected (empty = all)",
            options=list(HS_CHAPTER_LABELS.keys()),
            format_func=lambda x: f"{x} - {HS_CHAPTER_LABELS[x]}",
        )

        origin_countries = st.multiselect(
            "Origin countries affected (empty = all)",
            options=ORIGIN_COUNTRIES,
        )

        simulate = st.button("Simulate", type="primary")

    with col2:
        if simulate:
            with st.spinner("Simulating scenario..."):
                result_df = run_scenario_simulation(
                    selected_consignee_key,
                    additional_rate,
                    hs_chapters,
                    origin_countries,
                    "user_scenario",
                )

            if result_df.empty:
                st.info("No shipments match the scenario filters for this consignee.")
            else:
                total_delta = result_df["DELTA_USD"].sum()
                baseline_total = result_df["BASELINE_LANDED_COST_USD"].sum()
                pct = (total_delta / baseline_total * 100.0) if baseline_total else 0.0
                st.metric(
                    "Total tariff impact",
                    f"${total_delta:,.0f}",
                    delta=f"{pct:.1f}% increase" if total_delta else "no change",
                )
                st.markdown("### Impact breakdown")
                st.dataframe(result_df, use_container_width=True)
                if total_delta == 0:
                    st.caption(
                        "Zero impact usually means either no shipments matched the "
                        "chapter/country filters, or the matching shipments have no "
                        "declared customs value in this dataset -- not necessarily "
                        "that there's no real-world exposure. See data/sources.md."
                    )
