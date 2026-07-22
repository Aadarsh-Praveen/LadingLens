# Phase 9 — Streamlit-in-Snowflake Command Center

**Duration:** ~1 day
**Depends on:** Phase 6 (Gold + semantic view), Phase 7 (Cortex Search), Phase 8 (Agent)
**Goal:** Ship a polished multi-page Streamlit-in-Snowflake app that becomes the demo. Every core capability of LadingLens is exposed through a UI a non-technical person could use.

---

## Context

Streamlit-in-Snowflake (SiS) runs the app inside Snowflake's compute, with automatic auth and native access to everything you built (semantic view, search service, agent, UDFs). It's the ideal serving surface for this project because there's zero external hosting to manage.

Five pages:
1. **Executive Summary** — headline KPIs, "single-source alerts" count, top-exposure consignees
2. **Concentration Heatmap** — consignee × HS-6 grid with color-coded HHI, drill-down on click
3. **Tariff Scenario Simulator** — sliders for country/HS/rate, live re-computation
4. **Entity Resolution Review Queue** — golden records with expandable raw-variant lists
5. **Copilot Chat** — the Cortex Agent embedded

---

## Deliverables

- [ ] `streamlit/app.py` — multi-page entry point
- [ ] `streamlit/pages/01_executive_summary.py`
- [ ] `streamlit/pages/02_concentration_heatmap.py`
- [ ] `streamlit/pages/03_scenario_simulator.py`
- [ ] `streamlit/pages/04_er_review_queue.py`
- [ ] `streamlit/pages/05_copilot_chat.py`
- [ ] `streamlit/utils/data_loaders.py` — cached Snowflake queries
- [ ] `streamlit/utils/theme.py` — consistent colors, fonts
- [ ] `scripts/deploy_streamlit.sql` — DDL to register the app in Snowflake
- [ ] `docs/screenshots/` — one screenshot per page

---

## Claude Code Prompt

```
You are in Phase 9 of LadingLens. Phases 1-8 are complete. Read ./LadingLens.md and ./docs/phases/phase-09-streamlit.md before starting.

Your task: build a 5-page Streamlit-in-Snowflake app that exposes every LadingLens capability through a professional UI.

Constraints:
- Runs as Streamlit-in-Snowflake (SiS), not standalone Streamlit — use snowpark.session inside the app, not snowflake-connector.
- Every data-loading function is @st.cache_data with TTL=300 seconds.
- Design language: clean, minimal, business-appropriate. No emojis in chart titles. Use one primary color (a muted blue like #1f4e79) and one accent (a warm orange like #d97706) for alerts.
- Every page has a title, a 1-sentence subtitle, and a "last refreshed" timestamp.
- Every chart uses plotly and is responsive.

Please build:

1. streamlit/app.py
   - Sets page config (wide layout, favicon)
   - Sidebar: LadingLens logo (use a simple SVG or text), navigation links, "last data refresh" timestamp from GOLD.fact_shipments
   - Landing content: a 3-paragraph overview of what LadingLens does, with links to each page

2. streamlit/pages/01_executive_summary.py
   - KPI row: total shipments in scope, unique consignees, unique suppliers, total landed cost (USD), % single-sourced pairs
   - Chart: monthly landed-cost trend (line chart, last 24 months)
   - Chart: top 10 consignees by tariff exposure (horizontal bar)
   - Table: single-source alerts (consignee, hs_6, top supplier, share, country) — red badge if country is Section 301 target

3. streamlit/pages/02_concentration_heatmap.py
   - Filters: HS chapter multiselect, origin country multiselect, date range
   - Main viz: heatmap where rows = consignees (top 30), columns = hs_6 (top 20), cell color = HHI, cell hover shows top supplier and share
   - Click a cell → shows a details panel with the underlying shipments (last 20 rows), a mini bar chart of supplier shares, and any linked 10-K risk quote from mart_10k_extracted_facts

4. streamlit/pages/03_scenario_simulator.py
   - Controls (in the sidebar): origin country dropdown, hs scope multiselect, rate_increase_pct slider (0 to +50pp), consignee filter
   - "Run Scenario" button
   - On click: calls LADINGLENS_DB.GOLD.SIMULATE_TARIFF_SCENARIO and renders:
     - Total cost delta ($ and %) as a big number
     - Waterfall chart: current cost → +duty impact → scenario cost
     - Table: per-consignee impact sorted by delta_usd descending
     - "Save Scenario" button that writes the scenario + result to a Snowflake table GOLD.SAVED_SCENARIOS for later retrieval

5. streamlit/pages/04_er_review_queue.py
   - Filters: match_score threshold slider, country filter, "show review only"
   - Table: candidate pairs from int_supplier_pair_scored with match_label='review'
   - Each row expandable to show: canonical name A, canonical name B, all raw variants, all shipments each has, embedding similarity, jaccard score
   - Approve/Reject buttons that write to a REVIEW_DECISIONS table (feedback loop for Phase 10)
   - Metric at top: total pairs reviewed, approval rate, review backlog count

6. streamlit/pages/05_copilot_chat.py
   - Standard chat UI with st.chat_input / st.chat_message
   - Every user message → call src.ladinglens.agent_client.ask()
   - Render:
     - The final answer as markdown
     - An expandable "Tool trace" showing which tools ran with what args
     - An expandable "SQL" showing any analyst-generated SQL
     - An expandable "Sources" showing the 10-K chunks the agent pulled
   - Preload 4 suggested questions as clickable buttons above the input

7. streamlit/utils/data_loaders.py
   - Cached wrappers for:
     - get_kpi_summary()
     - get_top_consignees_by_exposure(n)
     - get_concentration_heatmap_data(hs_chapters, countries, date_range)
     - get_er_review_queue(threshold, country)
     - get_agent_client()  (returns a memoized LadingLensClient)

8. streamlit/utils/theme.py
   - Color constants
   - Plotly template config
   - Helper: format_currency(value), format_percentage(value), risk_badge(hhi_value)

9. scripts/deploy_streamlit.sql
   - CREATE STREAMLIT LADINGLENS_APP
       ROOT_LOCATION = '@LADINGLENS_DB.STAGE.RAW_STAGE/streamlit'
       MAIN_FILE = 'app.py'
       QUERY_WAREHOUSE = LADINGLENS_WH
   - PUT streamlit/**/* into the stage first

Run `snow streamlit deploy` (or the equivalent) and report:
- URL of the deployed app
- Any deployment errors
- Screenshots (please save them to docs/screenshots/) of each page
- Load time per page (measure the initial render)
- Recommended optimizations if any page takes >5s

Do not skip the docs/screenshots/ step — those are demo assets.
Ask before choosing UI library additions beyond streamlit + plotly (e.g., streamlit-aggrid). I have a preference.
```

---

## Your Tasks (Human)

- [ ] **Test the app end-to-end** by clicking through every page. Note anything that feels slow or confusing.
- [ ] **Ask 4 questions in the Copilot Chat** page and screenshot each response. These are your demo video moments.
- [ ] **Save 2-3 scenarios** in the simulator (e.g., "+25pp on China HS 85", "+50pp on Vietnam HS 61") — you'll reference these in the demo.
- [ ] **Approve/reject 10 ER review pairs** to demonstrate the human-in-the-loop workflow.
- [ ] **Show the app to a non-technical friend** and ask what's confusing. Fix the top 2 issues before recording the demo.
- [ ] **Screenshot each page in "hero" state** — after filters applied, with real numbers visible. Save all to `docs/screenshots/`.

---

## Success Criteria

- All 5 pages load without errors.
- Each page's initial render < 5 seconds.
- The copilot chat page produces answers that include both a metric and a verbatim 10-K quote in at least one demo query.
- The scenario simulator produces plausible numbers (e.g., +25pp on China HS 85 shows a positive cost delta for known-affected consignees).
- 5 screenshots saved in `docs/screenshots/`.

## Gotchas

- **SiS package versions:** SiS supports a curated Python package set. Confirm plotly and pandas versions are in the allowed list. Some newer versions may fail.
- **Cross-page state:** Streamlit reruns on every interaction; use st.session_state to preserve chat history and scenario results.
- **Caching bugs:** `@st.cache_data` doesn't refresh across page reloads by default. If a page shows stale numbers, explicitly clear cache or reduce TTL.
- **The chat page is the demo star.** Invest extra time on its response formatting (nice tables, quoted text, source cards) even if other pages are utilitarian.
