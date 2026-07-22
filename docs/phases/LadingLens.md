# Snowflake CoCo CLI Hackathon 2026 — Recommended Project for Aadarsh Praveen

## TL;DR
- **Build "LadingLens," a Tariff-Exposure & Supplier-Concentration Copilot** in the Supply Chain & Manufacturing domain — it fuses raw, messy U.S. import bill-of-lading shipment data (ImportYeti/CBP FOIA), the USITC Harmonized Tariff Schedule, and unstructured SEC 10-K "Risk Factor" disclosures into a Snowflake-native agent that answers questions like *"what is my landed-cost and single-source risk if Section 301 tariffs rise on HS 8541?"*
- **Choose this over Marketing MMM or CRM churn** because both of those domains are saturated (Robyn/Meridian and churn-prediction repos are everywhere) and Aadarsh already has RFM/A-B-testing/e-commerce on his resume; trade intelligence is genuinely under-built on *real* data, maps cleanly to Data Scientist/Analyst/AI-Engineer job descriptions, and lets him show entity resolution, tariff modeling, and unstructured-data mining that recruiters rarely see.
- **It maps to two of the four hackathon problem statements at once** — "Unstructured Data Intelligence System" (10-K risk mining + free-text product-description → HS mapping) and "Domain-Specific AI Copilot" — and showcases the exact modern Snowflake stack the resume calls for: CoCo CLI, dbt, Iceberg, Cortex Analyst semantic views, Cortex Search, Cortex AISQL (AI_COMPLETE/AI_CLASSIFY/AI_EMBED), Cortex Agents, Streamlit-in-Snowflake, and TruLens AI Observability.

## Key Findings

### What CoCo CLI actually is (and why it matters for scoping)
Snowflake CoCo is the rebrand of **Cortex Code**, announced at the Snowflake Summit 2026 keynote on **June 2, 2026** (Snowflake reports more than 7,100 customers were already building with CoCo before the Summit push). It is a Snowflake-native, agentic AI coding agent that reads your catalog, lineage, and RBAC before generating SQL, dbt models, pipelines, ML code, and Streamlit apps from natural language. The **CoCo CLI** (`cortex` command) is GA and runs in your terminal (macOS/Linux/Windows/WSL), connecting via `~/.snowflake/connections.toml`. Key facts that shape a hackathon build:
- It supports **plan mode** (review each action before it runs), **50+ bundled Skills** plus community Skills (Snowflake-Labs/coco-skills), **MCP** and **Agent Client Protocol** integration, and a `#` table-reference syntax that grounds prompts to specific objects.
- The official CoCo CLI ML quickstart walks through the exact professional loop judges want: **synthetic-data generation → EDA → feature engineering → train two models → evaluate (RMSE/MAE/R²) → log to Model Registry → deploy REST endpoint on Snowpark Container Services**. This is a proven template Aadarsh can lean on.
- On dbt Labs' **ADE-Bench**, per Snowflake's official blog, "CoCo achieved a 72.1% pass rate, outperforming both Anthropic's Claude Code and OpenAI's Codex (each at 65.1%)," and "compared to Claude Code running on Opus 4.7, CoCo uses 51% fewer tokens and takes 8% less time." *(Caveat: these are Snowflake's own benchmark runs, not independently replicated; dbt Labs' live ADE-Bench leaderboard shows a competing harness, Altimate Code on Claude Sonnet 4.6, at 74.4% on Snowflake — so treat "beats everything" as a Snowflake claim, not gospel.)*
- Default models include Claude Opus 4 / Sonnet 4 and OpenAI GPT; the agent displays reasoning steps and can build/deploy dbt projects and Streamlit apps end-to-end.

### The three domains, judged on saturation vs. white space
- **Supply Chain & Manufacturing (RECOMMENDED):** Basic demand forecasting is completely saturated (dozens of near-identical GitHub repos: RandomForest weekly-sales, LightGBM FMCG, three-step clustering, etc.). But Snowflake itself has only published *synthetic-data* reference apps here — the official **"Supply Chain Risk Intelligence for Manufacturing"** quickstart uses a GraphSAGE GNN on **synthetic** ERP+trade data, and a popular Medium series ("AI-Powered Tariff Intelligence System on Snowflake") also uses **synthetic** procurement data. **The white space is doing this on real, messy public data** — which is exactly what the hackathon rewards ("raw messy data, real EDA"). This is the gap LadingLens fills.
- **Marketing Analytics (rejected):** MMM is dominated by mature open-source tools — Meta's **Robyn**, Google's **Meridian** (introduced March 2024, made available to all data scientists/marketers globally in early 2025 alongside a 20+ measurement-partner program; now at v1.7.0 in 2026), and the now-deprecated **LightweightMMM** (users are directed to a Meridian migration guide). Multi-touch attribution and sentiment analysis are heavily done. TikTok/Meta Ad Library data is accessible but building "another MMM" competes against Google/Meta's own frameworks and is a weak differentiation story for a data-science hire.
- **CRM / Sales Ops / Customer Success (rejected):** Churn prediction and ticket classification are the most over-implemented ML tutorials in existence (Bitext, Twitter customer-support, Telco churn). Gong/Gainsight-style copilots are being built by well-funded vendors. Aadarsh already has RFM segmentation and the Caliper A/B platform on his resume, so this adds little new signal.

### Data sourcing reality check (from targeted research)
- **Bill-of-lading raw data is FREE to search on ImportYeti** (importyeti.com). Per Bellingcat's Online Investigation Toolkit, "ImportYeti has acquired all the bills of lading data from January 2015 through a freedom of information request to US Customs"; ImportYeti states "we requested all 70,000,000 BOLs," and its index updates daily from CBP filings. Fields exposed: purchaser/supplier names, supplier country, weight, ports, and HS codes. Free web search works after a free signup (login required after 25 page views per IP); **bulk CSV download requires requesting free "custom plan"/OSINT-researcher access.** Coverage is **vessel shipments only** (no air/land).
- **OEC's BoL bulk download is PAID** (Premium tier), covering **January 2021–April 2026**, in CSV/Excel/JSON with fields for weight, quantity, CIF, container count, and shipment count at port resolution — but there is a **50% academic discount**, so it is a fallback if Aadarsh has a .edu address.
- **USITC Harmonized Tariff Schedule is 100% free** — downloadable as **HTML/CSV/XLS/JSON** at hts.usitc.gov/download. The HTSUS "contains approximately 35,571 individual tariff lines organized into 99 chapters" (10-digit codes), plus Section 301/232 duty overlays; USITC published **2026 HTS Revision 11 on July 1, 2026.** This is the clean reference table to join tariffs onto shipments.
- **SEC EDGAR 10-K "Item 1A Risk Factors" and "Item 7 MD&A" are free** and extractable (the sec-api Python SDK or direct EDGAR full-text search). These give the *unstructured* supply-chain-concentration disclosures ("we source X% from a single supplier in region Y").
- **Documented messiness (Federal Reserve FEDS 2021-066, Flaaen et al., 2021):** per the paper, "the variables for the shipper/consignee IDs and value have the highest probability of being missing, while the HS code and twenty-foot equivalent unit (TEU) fields are missing in a much lower share of observations," and the firm "ID linking variable only exists for 10-15 percent of shippers and consignees in U.S. import data." Raw BoL data also has **no native HS codes** (must be mapped from free-text product descriptions), **widespread company-name spelling inconsistencies** with trade names/subsidiaries, vessel-only coverage, and duplicate BoL numbers. This is a *feature* for the hackathon — it forces genuine EDA, entity resolution, and cleaning.

## Details — The Recommended Project Blueprint

### Project name
**LadingLens** — *"See through your supply chain, one bill of lading at a time."*

### Domain / sub-domain
Supply Chain & Manufacturing Operations → **Trade intelligence, tariff-exposure modeling, and supplier-concentration risk.**

### Elevator pitch
LadingLens ingests millions of raw, messy U.S. import bill-of-lading records, resolves inconsistent shipper/consignee names into clean entities, maps free-text product descriptions to HS codes, and joins them to live USITC tariff schedules and unstructured SEC 10-K risk disclosures. A Cortex Agent copilot then answers procurement questions in plain English — *"Which of my products have >30% single-country sourcing, and what's the landed-cost hit if Section 301 duties rise?"* — with a Streamlit-in-Snowflake command center for concentration-risk visualization.

### Why THIS project (the uniqueness argument)
1. **Real messy data where everyone else uses synthetic.** Snowflake's own N-Tier supply-chain reference app and the widely-shared tariff-intelligence Medium series both explicitly run on *synthetic* data. LadingLens does the same class of problem on **real, FOIA-sourced bill-of-lading data + real tariff schedules + real 10-K filings**, so the EDA, entity resolution, and HS-mapping work is authentic and defensible in an interview.
2. **Multi-modal data fusion.** It combines three fundamentally different data types — structured shipment transactions, a clean tariff reference table, and unstructured regulatory text — which is exactly the "combine unstructured with structured data" language in the hackathon's Unstructured Data Intelligence problem statement.
3. **Entity resolution is a rare, high-signal skill.** Cleaning "ACME CO / Acme Corp. / ACME CORPORATION" into golden records is a problem most portfolio projects never touch, and it maps directly to MDM/data-quality work that enterprises pay for.
4. **It differs from Aadarsh's existing resume.** His tariff-forecasting entry was on Google ADK/BigQuery; doing tariff *exposure* on Snowflake with real customs data is a complementary, non-duplicative second act that broadens his story rather than repeating it.

### Why it boosts interview call-rate (mapping to roles/companies)
- **Data Scientist / Analyst roles:** demonstrates end-to-end EDA → cleaning → feature engineering → modeling → evaluation on genuinely dirty data, plus semantic-layer/BI skills (Cortex Analyst semantic views ≈ the dbt semantic layer / LookML skill hiring managers screen for).
- **AI/ML Engineer roles:** shows agentic orchestration (Cortex Agents), RAG over 10-Ks (Cortex Search), LLM functions, and **production discipline** (TruLens observability, CI/CD, Model Registry, SPCS deployment).
- **Target employers:** the exact skill set used by trade/supply-chain tech firms (Flexport, project44, FourKites, Everstream Analytics, Interos, S&P Global/Panjiva), plus any Snowflake-shop enterprise (Snowflake has publicly showcased Nestlé using AI to anticipate supply-chain disruptions). The Snowflake-native stack also signals readiness for the growing number of "Snowflake + dbt + Cortex" job postings.

### Architecture overview
`Data sources → ingestion → transformation (dbt medallion) → AI/ML layer → serving/agent → Streamlit UI → observability`

1. **Ingestion:** Load raw BoL CSVs (ImportYeti custom-plan export or CBP FOIA feed) into a Snowflake **Iceberg** table (open format = resume signal + realistic lakehouse story). Load USITC HTS CSV/JSON and SEC 10-K text (via sec-api or EDGAR) into raw stages.
2. **Transformation (dbt on Snowflake):** Medallion architecture — **Bronze** (raw), **Silver** (cleaned/deduplicated/entity-resolved), **Gold** (analytics-ready star schema: `fact_shipments`, `dim_supplier`, `dim_product/HS`, `dim_country`, `fact_tariff`). Add dbt tests, freshness checks, and generate the project with CoCo CLI.
3. **AI layer:**
   - **HS-code mapping** of free-text product descriptions using **Cortex AISQL `AI_CLASSIFY`/`AI_COMPLETE`** (LLM maps "cotton knit t-shirt, mens" → HS 6109.10).
   - **Entity resolution** on messy company names using embeddings (`AI_EMBED` / `VECTOR_COSINE_SIMILARITY`) + blocking + fuzzy matching to build golden supplier records and an identity graph.
   - **10-K risk mining** via **Cortex Search** (hybrid vector+keyword) over Item 1A text, with `EXTRACT_ANSWER`/`AI_COMPLETE` to pull single-source/geographic-concentration statements.
   - **Tariff-exposure & concentration modeling:** compute Herfindahl-style supplier-concentration indices, landed-cost = value × (1 + effective duty rate incl. Section 301/232), and a scenario simulator ("+25% duty on China-origin HS 8541").
4. **Serving:** A **Cortex Agent** with a **semantic view** (business-friendly metrics: `landed_cost`, `concentration_index`, `tariff_exposure`) exposes natural-language Q&A; optional REST endpoint on **SPCS**.
5. **UI:** **Streamlit-in-Snowflake** multi-page command center — executive summary, supplier concentration heatmap, tariff scenario simulator, entity-resolution review queue, and an embedded chat to the Cortex Agent.
6. **Observability:** **TruLens / Snowflake AI Observability** for the RAG/agent (groundedness, context relevance, answer relevance, latency, cost); **GitHub Actions CI/CD** running dbt tests and Python unit tests; query tagging for cost monitoring.

### Specific tools (mapped to the resume "hot list")
- **CoCo CLI** — scaffolds the dbt project, generates EDA notebooks, builds the Streamlit app, wires the Cortex Agent (this is the mandatory hackathon tool and the headline resume item).
- **dbt** — medallion transforms, tests, docs.
- **Apache Iceberg** — raw shipment lakehouse table (open-format story).
- **Cortex Analyst + Semantic Views** — governed NL-to-SQL.
- **Cortex Search** — RAG over 10-K risk factors.
- **Cortex AISQL** (`AI_COMPLETE`, `AI_CLASSIFY`, `AI_EMBED`, `AI_FILTER`) — HS mapping, entity resolution, text extraction.
- **Cortex Agents / Snowflake Intelligence (CoWork)** — the copilot orchestration layer.
- **Snowpark / Snowpark Container Services** — Python feature engineering + optional model endpoint.
- **Snowflake ML + Model Registry** — if a supervised HS-classifier or concentration-risk scorer is trained.
- **Streamlit-in-Snowflake** — front end.
- **TruLens AI Observability**, **GitHub Actions**, **Pydantic** — monitoring, CI/CD, validation.

### Data sources (with URLs)
- **Bill of lading (primary, free):** ImportYeti — https://www.importyeti.com/ (~70M sea-import BoLs, Jan 2015+, free search; request custom-plan for CSV export). Fallback bulk: OEC — https://oec.world/en/resources/bulk-download/bill-of-lading (paid Premium, Jan 2021–Apr 2026, 50% academic discount).
- **Tariffs (free):** USITC HTS — https://hts.usitc.gov/download (HTML/CSV/XLS/JSON, ~35,571 lines, Section 301/232 overlays, 2026 Revision 11 as of July 1, 2026); USTR Section 301 search — https://ustr.gov/issue-areas/enforcement/section-301-investigations/search.
- **Unstructured risk disclosures (free):** SEC EDGAR full-text search + Item 1A extraction via sec-api — https://sec-api.io/ or direct EDGAR.
- **Macro/context (free):** FRED, BLS, DOT/BTS, NOAA weather, USITC DataWeb — for demand/seasonality/disruption features.

### Full technical structure (professional lifecycle)
- **EDA:** row/null profiling on BoL data; quantify missingness (expect high missing shipper/consignee IDs and firm-linking IDs present for only 10-15% of parties, per FEDS 2021-066); distribution of HS-code coverage; top consignees/shippers; port and country concentration; free-text description quality analysis.
- **Data cleaning:** normalize company names (case, punctuation, legal-suffix stripping, trade-name resolution), deduplicate BoL numbers, standardize port names to UN/LOCODE, standardize weights/units, handle redacted parties.
- **Feature engineering:** supplier-concentration index (HHI) per product/consignee, single-source flags, geographic-concentration by origin country, effective duty rate (base + 301 + 232), landed-cost, shipment-frequency and lumpiness features, 10-K risk sentiment/severity scores.
- **Modeling:** (a) LLM-based HS classifier (evaluate accuracy vs. a hand-labeled sample); (b) entity-resolution matcher (precision/recall on a labeled pair set); (c) concentration-risk scoring + tariff-scenario simulation. Optionally train a supervised risk-scorer and log to Model Registry.
- **Evaluation:** classification accuracy/F1 for HS mapping; ER precision/recall/F1; RAG groundedness & answer-relevance via TruLens; scenario back-testing against known 2018–2025 tariff events.
- **Deployment:** Streamlit-in-Snowflake app + Cortex Agent (+ optional SPCS REST endpoint).
- **Monitoring/observability:** TruLens dashboards, cost/latency tracking, dbt freshness tests, CI/CD gates.

### Realistic hackathon scope (July 13 – Aug 2 prototype window, ~3 weeks)
- **Week 1:** Data acquisition (start ImportYeti custom-plan request immediately — it can take days); ingest a **bounded slice** (e.g., 2–3 HS chapters like electronics/apparel, or a few hundred consignees) into Iceberg; USITC HTS + ~20–50 relevant 10-Ks loaded; CoCo-generated dbt Bronze/Silver; EDA notebook.
- **Week 2:** Entity resolution + HS mapping (Cortex AISQL); Gold star schema + semantic view; Cortex Search over 10-Ks; core concentration/tariff features.
- **Week 3:** Cortex Agent + Streamlit command center; TruLens observability; CI/CD; polish, demo video, README, metrics. **Descope levers if time-short:** narrow to one industry vertical, use OEC pre-cleaned data instead of raw FOIA, skip the supervised model and rely on rule-based scoring + LLM.

### 3–5 "wow factor" features
1. **Tariff scenario simulator** — slider for "+X% duty on country/HS" that instantly recomputes landed cost and re-ranks supplier risk (visually striking, business-relevant).
2. **Entity-resolution review queue** — shows messy raw names collapsing into golden records with match confidence; proves real data-quality engineering.
3. **Structured+unstructured fusion answer** — the agent cites both a shipment-concentration metric *and* a verbatim 10-K risk-factor sentence in one response.
4. **Free-text → HS auto-classification** with a live "confidence + human-in-the-loop override" panel.
5. **Grounded, observable agent** — a TruLens panel showing groundedness/latency/cost per query, signaling production maturity most hackathon entries lack.

### Concrete metrics / KPIs to report
- **Data:** # BoL records ingested, % with missing shipper/consignee IDs, % descriptions auto-mapped to HS.
- **HS classifier:** accuracy / macro-F1 on a labeled sample.
- **Entity resolution:** precision / recall / F1; # raw names → # golden entities (compression ratio).
- **Business:** # products flagged >30% single-source; total tariff-exposure ($) under a scenario; landed-cost delta.
- **Agent quality (TruLens):** groundedness, context relevance, answer relevance, p50/p95 latency, cost/query.

### Which hackathon problem statement it maps to
Primary: **Unstructured Data Intelligence System** (10-K risk mining + free-text→HS mapping fused with structured shipments) and **Domain-Specific AI Copilot** (manufacturing/procurement copilot). It also partially satisfies **Intelligent Workflow Automation Agent** (the agent triggers scenario analyses and surfaces anomalies) and **AI-Native Data Application** (Streamlit app). Submitting against the Unstructured Data or Copilot statement is the strongest fit.

## Recommendations
1. **Commit to LadingLens now and request ImportYeti custom-plan/OSINT access on Day 1** — data access is the critical-path risk. If access is denied or slow by ~July 16, pivot to OEC (academic discount) or fall back to a CBP FOIA sample; keep USITC HTS + SEC 10-Ks (both instantly free) as the guaranteed backbone.
2. **Scope to one or two industries** (e.g., electronics/semiconductors + apparel) to keep entity resolution and HS mapping tractable in 3 weeks.
3. **Use CoCo CLI as the visible through-line** — generate the dbt project, notebooks, Streamlit app, and agent via CoCo prompts, and capture that in the demo, since judging rewards CoCo-native builds.
4. **Instrument with TruLens from the start**, not as an afterthought — observability is a rare differentiator and a strong interview talking point.
5. **Benchmarks that would change the plan:** if HS auto-mapping accuracy is <70% on your sample, add a small labeled fine-tune set or restrict to HS-6 granularity; if entity-resolution F1 is <0.8, tighten blocking keys and add deterministic rules before probabilistic matching; if agent groundedness is low, add verified queries to the semantic view and tune Cortex Search chunking (~512 tokens).

## Caveats
- **Data access is the biggest risk.** ImportYeti bulk CSV requires granted custom-plan access (free but not instant); its API returns mostly company-level aggregates, not full BoL line detail. OEC bulk is paid. Budget time for this and have the free USITC+EDGAR backbone ready.
- **Snowflake has adjacent reference apps** (the N-Tier GraphSAGE risk app; the tariff-intelligence Medium series). Differentiate explicitly by using **real messy data** and the **structured+unstructured fusion + entity resolution** angle; avoid re-implementing their synthetic GraphSAGE demo.
- **Regional model availability & previews:** several Cortex features (AISQL multimodal, some LLMs, Cortex Sense) are in public preview and region-gated; confirm your trial account's region supports the models you need (cross-region inference may be required).
- **Cost/credits:** Cortex Analyst bills per message (~6.7 credits/100 messages) and LLM/warehouse costs apply; keep the ingested slice bounded during development and use query tags to monitor spend.
- **BoL coverage is vessel-only** (no air/land), so air-shipped goods (e.g., some semiconductors) are under-represented — state this limitation explicitly in the demo rather than overclaiming completeness.
- **Hackathon is APJ-focused with a $10,000 prize pool** and allows teams up to 4; confirm eligibility and team rules before investing, and note the CoCo benchmark superiority is Snowflake's own claim, not independently verified.