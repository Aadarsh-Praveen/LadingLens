import streamlit as st
from panels import executive, heatmap, scenarios, agent_chat, observability

st.set_page_config(
    page_title="LadingLens",
    page_icon="🚢",
    layout="wide",
    initial_sidebar_state="collapsed",
)

st.markdown("# LadingLens")
st.markdown(
    "Tariff exposure and supplier concentration copilot. "
    "Built on Snowflake Cortex + dbt medallion pipeline over 89,200 shipments."
)

tab1, tab2, tab3, tab4, tab5 = st.tabs(
    [
        "Executive Overview",
        "Concentration Heatmap",
        "Scenario Simulator",
        "Ask LadingLens",
        "Observability",
    ]
)

with tab1:
    executive.render()
with tab2:
    heatmap.render()
with tab3:
    scenarios.render()
with tab4:
    agent_chat.render()
with tab5:
    observability.render()

st.markdown("---")
st.caption(
    "Data: NIST FEIII 2019 (~3.8M shipments filtered to 89,200 in-scope), "
    "USITC HTS 2026, SEC 10-K/20-F filings for 24 tickers. "
    "Built on Snowflake Cortex Agents, SEMANTIC VIEW, and Cortex Search."
)
