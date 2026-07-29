# Phase 9 — Streamlit-in-Snowflake User Interface

**Duration:** ~1-1.5 days
**Depends on:** Phase 6 (SEMANTIC VIEW), Phase 7 (Cortex Search), Phase 8 (Cortex Agent + scenario procedures)
**Goal:** Build the user-facing Streamlit application that makes LadingLens feel like a product. Four panels: an executive dashboard, a concentration heatmap, an interactive tariff scenario picker, and a conversational agent chat.

---

## Context

Phases 4-8 built the analytical foundation. Phase 9 is where that foundation becomes a product a non-technical person can use.

Streamlit-in-Snowflake (SiS) runs a Streamlit app inside Snowflake's compute, with direct access to database objects via the Snowpark session — no external hosting, no authentication overhead beyond the user's Snowflake login. This is the demo surface: the hackathon judge, an interviewer, or you yourself opens Snowsight, clicks the Streamlit app, and interacts with LadingLens as a working product.

Design principles for this phase:
- **Show real data, not synthetic examples.** Every number on screen must be traceable to a specific consignee, HS chapter, tariff event, or 10-K filing.
- **Latency awareness.** Phase 8 established that fusion queries take 40-90 seconds. The UI must communicate progress, not appear frozen.
- **Reproducibility.** Screenshots you take today should be reproducible tomorrow — no hidden random sampling, no time-based drift.
- **Modest scope.** Four panels total. Don't try to build a full BI product. Each panel earns its place by supporting a specific demo moment.

---

## The four panels

**Panel 1: Executive Dashboard** — the "top of the funnel" for the demo. Shows the corpus at a glance so a viewer understands the scale.
- Total shipments in scope (89,200)
- Top 10 consignees by landed cost (bar chart)
- Distribution across HS chapters (pie or bar)
- Origin country breakdown (map or bar)
- A leaderboard of "highest concentration risk" consignees (from mart_concentration_metrics)

**Panel 2: Concentration Heatmap** — the flagship analytical visualization.
- Y-axis: top 30 consignees (sorted by total shipments)
- X-axis: HS chapters (84, 87, 39, 73, 61, 62)
- Cell color: HHI (green = diversified, red = concentrated)
- Cell hover: shows top supplier, top country, single-source flag
- Click a cell → detail panel showing the specific supplier/country breakdown and any linked 10-K risk factor language via Cortex Search

**Panel 3: Scenario Picker** — interactive what-if tariff simulator.
- Consignee dropdown (top 50 by shipments)
- Scenario controls: additional rate percentage points, HS chapter multi-select, origin country multi-select
- Live "Simulate" button calls SIMULATE_TARIFF_SCENARIO procedure
- Results table: before/after landed cost broken down by (chapter, country)
- Total delta USD highlighted at top
- Also shows pre-computed canonical scenarios from mart_scenario_examples as "example scenarios" the user can click to load

**Panel 4: Agent Chat** — conversational interface calling LADINGLENS_AGENT.
- Text input for user question
- Response area showing agent's synthesized answer with citations
- Latency-aware loading state (progress narrative during the 40-90s wait)
- Optional "expand" panel showing which tools the agent called
- Example question buttons to lower the barrier for exploration

---

## Deliverables

- [ ] `streamlit/app.py` — main Streamlit application (single file for SiS deployment)
- [ ] `streamlit/panels/executive.py` — Panel 1
- [ ] `streamlit/panels/heatmap.py` — Panel 2
- [ ] `streamlit/panels/scenarios.py` — Panel 3
- [ ] `streamlit/panels/agent_chat.py` — Panel 4
- [ ] `streamlit/utils/snowflake_queries.py` — cached query functions
- [ ] `streamlit/utils/theme.py` — color palette, styling constants
- [ ] `scripts/deploy_streamlit.sql` — DDL to publish the SiS app
- [ ] `docs/screenshots/` directory with 6-8 demo screenshots
- [ ] `data/sources.md` — Phase 9 wrap section

---

## Claude Code Prompt

```
Phase 9 — Streamlit-in-Snowflake UI. Read ./LadingLens.md,
./docs/phases/phase-09-streamlit.md, and ./data/sources.md before starting.

STATE RECAP (verified, do not re-check):
- Phases 1-8 complete and committed. Cortex Agent LADINGLENS_AGENT live.
- SEMANTIC_VIEW, RISK_FACTORS_SEARCH, SIMULATE_TARIFF_SCENARIO,
  SIMULATE_TARIFF_SCENARIO_AGENT, mart_scenario_examples all functional.
- 85 dbt tests passing. Cumulative catches: 38.
- Cortex spend to date: ~$40-50. Budget remaining: ~$30-50.
- Cortex Agent fusion queries take p50 38s / p95 93s — UI must handle this latency.
- Streamlit-in-Snowflake availability on this account: NOT YET VERIFIED. Confirm in
  Step 0 before proceeding.

YOUR TASK:
Build a 4-panel Streamlit-in-Snowflake application that surfaces the LadingLens
analytical stack through a user-facing interface. Real data, real agent calls,
real latency handling.

CONSTRAINTS:
- Streamlit-in-Snowflake syntax and package availability differ from vanilla
  Streamlit. Verify package availability before importing (e.g., plotly may or
  may not be available; matplotlib always is).
- All queries go through the active Snowpark session provided by SiS. Do not
  use snowflake-connector-python or credential-based auth.
- Panel navigation uses st.tabs() for top-level structure. No multi-page app
  (SiS's multipage support is unreliable at the time of writing).
- Cache aggressively via st.cache_data with (ttl=3600, show_spinner=False)
  on all query functions — the underlying data changes infrequently.
- Total app file size < 500 lines per file. Split into panels/utils modules.
- Do NOT commit until all 4 panels work end-to-end.

===========================================
STEP 0 — Verify SiS availability and package support
===========================================

Streamlit-in-Snowflake is a first-class product on modern Snowflake accounts, but
some accounts have package restrictions. Verify:

    -- Does the CREATE STREAMLIT syntax work?
    SHOW STREAMLITS IN SCHEMA LADINGLENS_DB.SEMANTIC;
    
    -- If that succeeds (empty list, no error), SiS is available.
    -- If it errors, we may need to fall back to vanilla Streamlit deployed
    -- externally with snowflake-connector-python credentials. Report immediately.

Also check package availability by attempting to import in a test cell:

    -- Create a minimal test streamlit app to verify plotly + pandas + snowpark
    -- packages are all available in the SiS Python environment. If plotly is
    -- unavailable, we fall back to altair or matplotlib.

CHECKPOINT — do not proceed until SiS is confirmed available and the target
plotting library is identified (plotly preferred, altair second, matplotlib fallback).

===========================================
STEP 1 — Project structure
===========================================

Create the streamlit/ directory structure:

    streamlit/
    ├── app.py                    # Main entry point, tab navigation
    ├── panels/
    │   ├── __init__.py
    │   ├── executive.py          # Panel 1
    │   ├── heatmap.py            # Panel 2
    │   ├── scenarios.py          # Panel 3
    │   └── agent_chat.py         # Panel 4
    └── utils/
        ├── __init__.py
        ├── snowflake_queries.py  # Cached query functions
        └── theme.py               # Colors, styling constants

===========================================
STEP 2 — Shared utilities
===========================================

Build streamlit/utils/theme.py with:

    # Color palette — muted, professional, colorblind-safe
    PRIMARY = "#2C5282"        # Deep blue
    ACCENT = "#DD6B20"         # Warm orange for callouts
    SUCCESS = "#38A169"        # Diversified/low-risk
    WARNING = "#D69E2E"        # Moderate concentration
    DANGER = "#C53030"         # High concentration/single-source
    NEUTRAL_LIGHT = "#F7FAFC"
    NEUTRAL_DARK = "#2D3748"
    
    # HHI thresholds (from Phase 6 methodology)
    HHI_MODERATE = 0.15
    HHI_HIGH = 0.25
    SINGLE_SOURCE_THRESHOLD = 0.70
    
    # HS chapter labels for user-facing display
    HS_CHAPTER_LABELS = {
        "84": "Machinery",
        "87": "Vehicles",
        "39": "Plastics",
        "73": "Steel articles",
        "61": "Apparel (knit)",
        "62": "Apparel (woven)",
    }

Build streamlit/utils/snowflake_queries.py with cached wrappers:

    import streamlit as st
    from snowflake.snowpark.context import get_active_session
    
    @st.cache_data(ttl=3600, show_spinner=False)
    def get_top_consignees_by_landed_cost(limit: int = 10):
        session = get_active_session()
        return session.sql(f"""
            SELECT c.consignee_name, SUM(f.estimated_landed_cost_usd) AS total_landed_cost
            FROM LADINGLENS_DB.GOLD.FACT_SHIPMENTS f
            JOIN LADINGLENS_DB.GOLD.DIM_CONSIGNEE c ON f.consignee_key = c.consignee_key
            WHERE f.estimated_landed_cost_usd IS NOT NULL
            GROUP BY c.consignee_name
            ORDER BY total_landed_cost DESC NULLS LAST
            LIMIT {limit}
        """).to_pandas()
    
    @st.cache_data(ttl=3600, show_spinner=False)
    def get_concentration_heatmap_data(top_n_consignees: int = 30):
        # Query mart_concentration_metrics joined to dim_consignee + dim_hs_code
        # Return a pivoted dataframe: rows=consignee_name, columns=hs_2, values=supplier_hhi
        ...
    
    @st.cache_data(ttl=3600, show_spinner=False)
    def get_shipment_summary_stats():
        # Total shipments, total distinct suppliers, total distinct consignees,
        # total landed cost (where computable), total single-source pairs
        ...
    
    @st.cache_data(ttl=3600, show_spinner=False)
    def get_origin_country_breakdown():
        # Shipments per origin country, grouped
        ...
    
    @st.cache_data(ttl=3600, show_spinner=False)
    def get_hs_chapter_breakdown():
        # Shipments per HS chapter (2-digit)
        ...
    
    @st.cache_data(ttl=3600, show_spinner=False)
    def get_scenario_examples(limit: int = 20):
        # Read mart_scenario_examples for the display in Panel 3
        ...
    
    def run_scenario_simulation(consignee_key: str, additional_rate_pp: float,
                                 hs_chapters: list, origin_countries: list,
                                 scenario_name: str = "user_scenario"):
        # Direct call to SIMULATE_TARIFF_SCENARIO (VARIANT param version, since
        # this is called from Python where we can construct the VARIANT easily).
        # NOT cached — user-initiated.
        session = get_active_session()
        scenario_json = json.dumps({
            "additional_rate_pp": additional_rate_pp,
            "hs_chapters": hs_chapters,
            "origin_countries": origin_countries,
            "scenario_name": scenario_name
        })
        return session.sql(f"""
            CALL LADINGLENS_DB.SEMANTIC.SIMULATE_TARIFF_SCENARIO(
                '{consignee_key.replace("'", "''")}',
                PARSE_JSON('{scenario_json.replace("'", "''")}')
            )
        """).to_pandas()
    
    def run_agent_query(question: str):
        # Direct call to DATA_AGENT_RUN. Not cached — user-initiated.
        # Returns the full response including tool_use trace.
        session = get_active_session()
        # Construct the JSON payload as a quoted SQL string with careful escaping
        ...
    
    def get_consignee_options(limit: int = 50):
        # Top 50 consignees by shipment count for the scenario picker dropdown
        ...
    
    def get_10k_search_for_ticker(ticker: str, query: str = "tariff exposure", k: int = 3):
        # Call CORTEX.SEARCH_PREVIEW filtered to a specific ticker
        # Used by heatmap click-to-detail
        ...

===========================================
STEP 3 — Panel 1: Executive Dashboard
===========================================

Build streamlit/panels/executive.py:

Layout: 4 KPI cards at top, then 2 charts side-by-side, then top-10 leaderboard.

    def render():
        st.markdown("## Executive Overview")
        st.markdown("A view of the LadingLens analytical corpus at a glance.")
        
        # Top row: 4 KPI cards
        stats = get_shipment_summary_stats()
        col1, col2, col3, col4 = st.columns(4)
        col1.metric("Total shipments", f"{stats['total_shipments']:,}")
        col2.metric("Unique consignees", f"{stats['unique_consignees']:,}")
        col3.metric("Unique suppliers", f"{stats['unique_suppliers']:,}")
        col4.metric("Single-source pairs",
                    f"{stats['single_source_pairs']:,}",
                    delta_color="inverse")
        
        # Second row: origin country + HS chapter breakdowns
        col1, col2 = st.columns(2)
        with col1:
            st.markdown("### By Origin Country")
            df = get_origin_country_breakdown()
            fig = px.bar(df.head(10), x='country', y='shipments',
                         color_discrete_sequence=[PRIMARY])
            st.plotly_chart(fig, use_container_width=True)
        with col2:
            st.markdown("### By HS Chapter")
            df = get_hs_chapter_breakdown()
            df['chapter_label'] = df['hs_2'].map(HS_CHAPTER_LABELS)
            fig = px.pie(df, names='chapter_label', values='shipments',
                         color_discrete_sequence=px.colors.sequential.Blues_r)
            st.plotly_chart(fig, use_container_width=True)
        
        # Third row: leaderboard
        st.markdown("### Top 10 Consignees by Landed Cost")
        df = get_top_consignees_by_landed_cost(10)
        fig = px.bar(df, x='total_landed_cost', y='consignee_name',
                     orientation='h', color_discrete_sequence=[ACCENT])
        fig.update_layout(yaxis=dict(autorange='reversed'))
        st.plotly_chart(fig, use_container_width=True)

===========================================
STEP 4 — Panel 2: Concentration Heatmap
===========================================

Build streamlit/panels/heatmap.py:

Interactive heatmap with click-to-drill. Layout: heatmap in main area, detail
panel on right side.

    def render():
        st.markdown("## Supplier Concentration Heatmap")
        st.markdown(
            "HHI concentration index by consignee × HS chapter. "
            "Red cells indicate high supplier concentration (potential single-source risk). "
            "Click a cell to see the underlying suppliers and any linked 10-K risk factor disclosures."
        )
        
        # Load data
        pivot_df = get_concentration_heatmap_data(top_n_consignees=30)
        # Melt for plotly if needed
        
        # Render heatmap
        fig = px.imshow(
            pivot_df.values,
            x=pivot_df.columns.map(HS_CHAPTER_LABELS.get),
            y=pivot_df.index,
            color_continuous_scale=['#38A169', '#D69E2E', '#C53030'],  # green → yellow → red
            aspect='auto',
            labels={'x': 'HS Chapter', 'y': 'Consignee', 'color': 'HHI'}
        )
        fig.update_layout(height=600)
        st.plotly_chart(fig, use_container_width=True)
        
        # Selection: single dropdown for consignee, one for chapter — since click-events
        # in Streamlit plotly are unreliable, use dropdowns for the drill-down.
        st.markdown("### Detail view")
        col1, col2 = st.columns(2)
        selected_consignee = col1.selectbox("Consignee", pivot_df.index.tolist())
        selected_chapter = col2.selectbox("HS Chapter", list(HS_CHAPTER_LABELS.keys()),
                                          format_func=lambda x: f"{x} - {HS_CHAPTER_LABELS[x]}")
        
        # Show supplier breakdown for the selected cell
        detail_df = get_supplier_breakdown_for_cell(selected_consignee, selected_chapter)
        if not detail_df.empty:
            st.markdown(f"**Supplier breakdown for {selected_consignee}, chapter {selected_chapter}**")
            st.dataframe(detail_df, use_container_width=True)
        
        # If dim_ticker maps this consignee to a ticker, offer 10-K retrieval
        ticker = get_ticker_for_consignee(selected_consignee)
        if ticker:
            with st.expander(f"10-K risk factors from {ticker}"):
                chunks = get_10k_search_for_ticker(ticker, query="supplier concentration tariff", k=3)
                for chunk in chunks:
                    st.markdown(f"**{chunk['ticker']} ({chunk['filing_year']}):**")
                    st.markdown(f"> {chunk['chunk_text'][:500]}...")

===========================================
STEP 5 — Panel 3: Scenario Picker
===========================================

Build streamlit/panels/scenarios.py:

Interactive what-if simulator. Layout: controls in a sidebar-style column,
results in the main area.

    def render():
        st.markdown("## Tariff Scenario Simulator")
        st.markdown("Simulate the impact of tariff changes on a consignee's landed cost.")
        
        # Show canonical example scenarios first
        st.markdown("### Example Scenarios (Pre-computed)")
        examples_df = get_scenario_examples(limit=20)
        st.dataframe(examples_df, use_container_width=True)
        
        st.markdown("---")
        st.markdown("### Build Your Own Scenario")
        
        col1, col2 = st.columns([1, 2])
        with col1:
            # Controls
            consignees = get_consignee_options(limit=50)
            selected_consignee = st.selectbox(
                "Consignee",
                consignees['consignee_name'].tolist()
            )
            selected_consignee_key = consignees[
                consignees['consignee_name'] == selected_consignee
            ]['consignee_key'].iloc[0]
            
            additional_rate = st.slider(
                "Additional tariff rate (percentage points)",
                min_value=0.0, max_value=100.0, value=25.0, step=5.0
            )
            
            hs_chapters = st.multiselect(
                "HS chapters affected (empty = all)",
                options=list(HS_CHAPTER_LABELS.keys()),
                format_func=lambda x: f"{x} - {HS_CHAPTER_LABELS[x]}"
            )
            
            origin_countries = st.multiselect(
                "Origin countries affected (empty = all)",
                options=["DE", "CN", "MX", "VN", "BE", "GB", "FR", "ES", "IT"],
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
                        "user_scenario"
                    )
                
                if result_df.empty:
                    st.info("No shipments match the scenario filters for this consignee.")
                else:
                    total_delta = result_df['DELTA_USD'].sum()
                    st.metric(
                        "Total tariff impact",
                        f"${total_delta:,.0f}",
                        delta=f"{(total_delta / result_df['BASELINE_LANDED_COST_USD'].sum() * 100):.1f}% increase"
                    )
                    st.markdown("### Impact breakdown")
                    st.dataframe(result_df, use_container_width=True)

===========================================
STEP 6 — Panel 4: Agent Chat
===========================================

Build streamlit/panels/agent_chat.py:

Conversational interface calling LADINGLENS_AGENT. Latency-aware loading state
is critical here (40-90s waits).

    EXAMPLE_QUESTIONS = [
        "What does Caterpillar disclose about tariff exposure in their 10-K?",
        "Which consignees have the highest supplier concentration for HS chapter 84?",
        "If Section 232 tariffs doubled, what would BMW's exposure be?",
        "Which of Nike's suppliers are Vietnamese?",
        "For Caterpillar, what happens if Chinese electronics tariffs rise 25 pp?",
    ]
    
    def render():
        st.markdown("## Ask LadingLens")
        st.markdown(
            "Ask questions about supply chain concentration, tariff exposure, or "
            "10-K risk disclosures. The agent orchestrates structured queries, "
            "10-K retrieval, and tariff scenario simulation to answer."
        )
        
        # Initialize chat history in session state
        if 'chat_history' not in st.session_state:
            st.session_state.chat_history = []
        
        # Example questions as clickable buttons
        st.markdown("### Try an example question")
        cols = st.columns(len(EXAMPLE_QUESTIONS))
        for col, question in zip(cols, EXAMPLE_QUESTIONS):
            if col.button(question[:40] + "...", key=f"example_{question[:20]}"):
                st.session_state.pending_question = question
        
        # Chat history display
        st.markdown("### Conversation")
        for entry in st.session_state.chat_history:
            with st.chat_message(entry['role']):
                st.markdown(entry['content'])
                if entry.get('tool_trace'):
                    with st.expander("Tools used"):
                        for tool_call in entry['tool_trace']:
                            st.code(tool_call)
        
        # Input
        user_question = st.chat_input("Ask a question...")
        if 'pending_question' in st.session_state:
            user_question = st.session_state.pending_question
            del st.session_state.pending_question
        
        if user_question:
            # Add user message to history
            st.session_state.chat_history.append({
                'role': 'user',
                'content': user_question
            })
            
            # Progress narrative during agent call
            progress_placeholder = st.empty()
            with progress_placeholder.container():
                progress_bar = st.progress(0, text="Analyzing question...")
                
                # We can't get real-time progress from the agent, so simulate
                # milestones based on typical latency profile:
                # 0-10%: parsing intent
                # 10-40%: querying tools
                # 40-90%: waiting for tool responses
                # 90-100%: synthesizing answer
                
                import time
                import threading
                
                agent_response = {"data": None}
                def call_agent():
                    agent_response["data"] = run_agent_query(user_question)
                
                thread = threading.Thread(target=call_agent)
                thread.start()
                
                progress_texts = [
                    "Analyzing question...",
                    "Selecting tools...",
                    "Querying shipment data...",
                    "Retrieving 10-K excerpts...",
                    "Synthesizing answer...",
                ]
                elapsed = 0
                while thread.is_alive() and elapsed < 120:
                    time.sleep(2)
                    elapsed += 2
                    progress_val = min(int(elapsed / 90 * 100), 90)
                    text_idx = min(int(elapsed / 20), len(progress_texts) - 1)
                    progress_bar.progress(progress_val, text=progress_texts[text_idx])
                
                thread.join(timeout=1)
            
            progress_placeholder.empty()
            
            response = agent_response["data"]
            if response:
                st.session_state.chat_history.append({
                    'role': 'assistant',
                    'content': response['final_answer'],
                    'tool_trace': response.get('tool_calls', [])
                })
                st.rerun()

===========================================
STEP 7 — Main app.py
===========================================

Build streamlit/app.py:

    import streamlit as st
    from panels import executive, heatmap, scenarios, agent_chat
    
    st.set_page_config(
        page_title="LadingLens",
        page_icon="🚢",
        layout="wide",
        initial_sidebar_state="collapsed"
    )
    
    # Header
    st.markdown("# LadingLens")
    st.markdown(
        "Tariff exposure and supplier concentration copilot. "
        "Built on Snowflake Cortex + dbt medallion pipeline over 89,200 shipments."
    )
    
    # Main tabs
    tab1, tab2, tab3, tab4 = st.tabs([
        "Executive Overview",
        "Concentration Heatmap",
        "Scenario Simulator",
        "Ask LadingLens"
    ])
    
    with tab1:
        executive.render()
    with tab2:
        heatmap.render()
    with tab3:
        scenarios.render()
    with tab4:
        agent_chat.render()
    
    # Footer with data provenance
    st.markdown("---")
    st.caption(
        "Data: NIST FEIII 2019 (~3.8M shipments filtered to 89,200 in-scope), "
        "USITC HTS 2026, SEC 10-K/20-F filings for 24 tickers. "
        "Built on Snowflake Cortex Agents, SEMANTIC VIEW, and Cortex Search."
    )

===========================================
STEP 8 — Deploy to Snowflake
===========================================

Build scripts/deploy_streamlit.sql:

    -- Upload streamlit/ folder to a stage
    CREATE STAGE IF NOT EXISTS LADINGLENS_DB.SEMANTIC.STREAMLIT_STAGE;
    
    -- Then use PUT commands from snowsql or the UI to upload:
    -- app.py, panels/*.py, utils/*.py
    
    -- Create the Streamlit app
    CREATE OR REPLACE STREAMLIT LADINGLENS_DB.SEMANTIC.LADINGLENS_APP
        ROOT_LOCATION = '@LADINGLENS_DB.SEMANTIC.STREAMLIT_STAGE'
        MAIN_FILE = 'app.py'
        QUERY_WAREHOUSE = LADINGLENS_WH
        TITLE = 'LadingLens'
        COMMENT = 'Tariff exposure and supplier concentration copilot';

Report the Streamlit app URL after deployment.

===========================================
STEP 9 — Test each panel end-to-end
===========================================

Open the deployed Streamlit app in Snowsight. Test each panel:

Panel 1 (Executive): all KPIs load, all charts render, no null values in key metrics.

Panel 2 (Heatmap): heatmap renders, all cells have colors, detail panel updates on
consignee/chapter selection, 10-K excerpts display for matched tickers.

Panel 3 (Scenarios): pre-computed examples load, custom scenario controls work,
Simulate button triggers procedure call, results display with total delta and
breakdown table.

Panel 4 (Agent Chat): example question buttons work, chat input works, agent
responses stream in with visible progress, tool trace expands correctly.

Report:
- Screenshot each panel in its most demonstrably-populated state
- Note any bugs or slow-loading sections
- Note any content-quality issues (e.g., panels showing NaN, empty state, etc.)

Save screenshots to docs/screenshots/ with names:
- executive_overview.png
- concentration_heatmap.png
- scenario_simulator_with_result.png
- agent_chat_answer.png

Plus 2-4 additional demo-quality screenshots showing interesting individual queries.

===========================================
STEP 10 — Documentation
===========================================

Append to data/sources.md a Phase 9 wrap section:

    Phase 9 wrap — Streamlit-in-Snowflake UI:
    
    Four-panel Streamlit application deployed as LADINGLENS_DB.SEMANTIC.LADINGLENS_APP.
    
    - Panel 1 (Executive Overview): KPI cards + origin/chapter breakdowns + top-10
      leaderboard by landed cost
    - Panel 2 (Concentration Heatmap): interactive heatmap of consignee × HS chapter
      HHI, with drill-down to supplier detail + linked 10-K risk factor excerpts
    - Panel 3 (Scenario Simulator): interactive tariff what-if picker calling
      SIMULATE_TARIFF_SCENARIO with real-time results + pre-computed examples
      from mart_scenario_examples
    - Panel 4 (Ask LadingLens): conversational chat calling LADINGLENS_AGENT with
      latency-aware progress narrative (40-90s waits communicated visually)
    
    Screenshots at docs/screenshots/ (executive_overview, concentration_heatmap,
    scenario_simulator_with_result, agent_chat_answer + others).
    
    Design notes:
    - Streamlit tabs (not multipage) for top-level navigation — SiS multipage
      support was unreliable at the time of writing
    - Aggressive st.cache_data (ttl=3600) on all read queries — data changes
      infrequently, cache reduces perceived latency
    - Custom progress narrative on agent chat panel since Cortex Agent has no
      native streaming — simulates progress based on observed latency profile
    - HS chapter labels mapped to human-friendly names ("Machinery" not "84")
      throughout UI
    - Muted colorblind-safe palette (blue primary, orange accent, green/yellow/red
      for concentration severity)
    
    What Phase 9 unlocks:
    - The full product experience is now a live URL a hackathon judge or interviewer
      can open. This is the demo surface.
    - Phase 10 (observability + demo video) has a working product to record and
      instrument.

===========================================
EXECUTION ORDER & CHECKPOINTS
===========================================

CHECKPOINT 0: SiS availability confirmed, plotting library chosen.

CHECKPOINT 1 (after Steps 1-2): project structure + shared utilities built,
verified by running a minimal test query through the cache.

CHECKPOINT 2 (after Steps 3-6): all 4 panels built and rendering locally-testable.
Report any issues rendering each panel.

CHECKPOINT 3 (after Step 8): deployed to Snowflake, URL accessible.

CHECKPOINT 4 (after Step 9): each panel tested end-to-end, screenshots captured.

STOP AT EACH CHECKPOINT. Report actual state before proceeding.

Do NOT commit until I greenlight the final review.
```

---

## Your Tasks (Human)

- [ ] **Test each panel yourself** in Snowsight after deployment. Type real questions in the agent chat panel; play with the scenario picker; drill into a heatmap cell.
- [ ] **Screenshot the best demo moments** — the "wow" screenshots you'll use in Phase 10's demo video and README.
- [ ] **Note anything that feels slow or broken** — Phase 10 has some room for polish, but obvious bugs should be caught now.
- [ ] **Try a fusion query in agent chat** ("What does Caterpillar disclose about tariffs, and what's their current concentration risk?") — this is the single strongest demo moment. Screenshot the response.

---

## Success Criteria

- SiS app deploys successfully and is accessible via Snowsight URL
- All 4 panels render without errors
- Each panel has at least one "demo-ready" state screenshot in docs/screenshots/
- Agent chat panel handles the 40-90s latency without appearing frozen
- Scenario simulator returns real (non-phantom) delta values for a test scenario
- Concentration heatmap has visible variation (not all cells the same color)

## Gotchas

- **SiS package availability**: plotly is usually available but not guaranteed. If it fails, altair is second choice (also usually available); matplotlib is universal fallback.
- **Agent call latency in Streamlit**: SiS may have session timeouts shorter than the 90s p95 agent latency. If queries timeout, increase warehouse size for the app's QUERY_WAREHOUSE parameter.
- **Chat history state**: st.session_state persists within a single browser session but not across page reloads. That's fine for a demo.
- **Threading in Streamlit** (used for parallel agent call + progress narrative) can be finicky. If it breaks, simplify to a plain `st.spinner("Analyzing...")` and accept the frozen-during-wait UX as acceptable.
- **Screenshots** need to be reproducible. Take them with the SAME queries and filters every time you test — don't leave demo screenshots depending on random data samples.
- **SiS deployment path variations**: the exact CREATE STREAMLIT syntax has changed across Snowflake versions. If the DDL fails, check current docs and iterate.
