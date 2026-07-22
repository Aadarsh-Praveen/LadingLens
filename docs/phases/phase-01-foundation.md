# Phase 1 — Foundation & Environment Setup

**Duration:** ~1 day
**Depends on:** Nothing (this is the start)
**Goal:** Get CoCo CLI installed, Snowflake wired up, GitHub repo scaffolded, and the ImportYeti data request submitted so it can process in parallel with later phases.

---

## Context

You are building **LadingLens** — a Tariff-Exposure & Supplier-Concentration Copilot for the Snowflake CoCo CLI Hackathon 2026. The project fuses U.S. import bill-of-lading data + USITC Harmonized Tariff Schedule + SEC 10-K risk factors into a Snowflake-native copilot. Full architecture spec is in the project root as `LadingLens.md`.

This phase is pure plumbing. No data yet. No models yet. Just make sure every tool starts.

---

## Deliverables

- [ ] Git repo created (local + GitHub) with clean structure
- [ ] Python 3.11+ virtual environment with baseline dependencies
- [ ] Snowflake CoCo CLI installed and authenticated to your trial account
- [ ] `snow` CLI (Snowflake CLI) installed and connected
- [ ] `dbt-snowflake` installed and `dbt debug` passes
- [ ] Snowflake objects created: database `LADINGLENS_DB`, schemas `RAW`, `BRONZE`, `SILVER`, `GOLD`, `SEMANTIC`; warehouse `LADINGLENS_WH` (XS, auto-suspend 60s)
- [ ] `.env.example` and `.gitignore` in place; no secrets committed
- [ ] ImportYeti custom-plan / OSINT researcher access request submitted (human task)
- [ ] `docs/phases/` directory with all 10 phase MDs copied in

---

## Claude Code Prompt

```
You are setting up the foundation for LadingLens, a Snowflake-native supply chain copilot for the CoCo CLI Hackathon 2026. The full project spec is at ./LadingLens.md — read it first for context.

Your task for this phase is scoped to environment and repo scaffolding only. Do NOT write any data pipelines, dbt models, or Streamlit code yet.

Please:

1. Create the following directory structure at the project root:
   - src/
   - dbt/
   - notebooks/
   - streamlit/
   - tests/
   - scripts/
   - docs/phases/
   - .github/workflows/

2. Create a Python virtual environment (`.venv`) using Python 3.11+ and install these packages into requirements.txt:
   - snowflake-cli (the `snow` command)
   - dbt-core
   - dbt-snowflake
   - snowflake-connector-python[pandas]
   - snowflake-snowpark-python
   - pydantic
   - python-dotenv
   - pandas
   - polars
   - jupyter
   - streamlit
   - pytest
   - ruff
   - black
   - Do NOT install trulens yet — that comes in Phase 10.

3. Create a pyproject.toml or setup.cfg with ruff + black config (line length 100, target py311).

4. Create a .gitignore that excludes .venv/, .env, *.pyc, __pycache__/, .dbt/, dbt_packages/, target/, .snowflake/, data/raw/, data/interim/, .DS_Store, .ipynb_checkpoints/.

5. Create a .env.example (NOT .env) with these keys blank:
   SNOWFLAKE_ACCOUNT=
   SNOWFLAKE_USER=
   SNOWFLAKE_PASSWORD=
   SNOWFLAKE_ROLE=
   SNOWFLAKE_WAREHOUSE=LADINGLENS_WH
   SNOWFLAKE_DATABASE=LADINGLENS_DB
   SNOWFLAKE_SCHEMA=RAW

6. Create a scripts/bootstrap_snowflake.sql that when run creates:
   - Warehouse LADINGLENS_WH (XSMALL, AUTO_SUSPEND=60, AUTO_RESUME=TRUE)
   - Database LADINGLENS_DB
   - Schemas RAW, BRONZE, SILVER, GOLD, SEMANTIC, STAGE inside LADINGLENS_DB
   - An internal stage LADINGLENS_DB.STAGE.RAW_STAGE
   Include COMMENT on each object explaining its purpose.

7. Create a dbt/ subdirectory with `dbt init ladinglens` scaffolding (profile name `ladinglens`), but leave models empty. Configure profiles.yml.example that reads from env vars. Add a dbt_project.yml with models/ folders named bronze, silver, gold matching the medallion layout.

8. Create a README.md at the project root with:
   - Project name, one-line pitch
   - Architecture diagram (ASCII or Mermaid)
   - Setup instructions (clone, venv, snow login, coco login, bootstrap SQL, dbt debug)
   - Link to LadingLens.md and to docs/phases/

9. Create an initial commit with message "phase 1: foundation and environment scaffolding".

Verification steps you should run and report back on:
- `snow --version`
- `dbt --version`
- `dbt debug` from inside dbt/ (should show "All checks passed!" once user fills .env)
- Directory tree using `tree -L 2 -I '.venv|__pycache__'`

If you can't verify one of these because a credential is missing, print the exact command the user needs to run and skip that check.

Do NOT install CoCo CLI (the `cortex` command) — the user will install that themselves following the official Snowflake instructions since it may require Snowflake account authentication.

Ask me before making any assumption you can't verify against LadingLens.md.
```

---

## Your Tasks (Human)

- [ ] **Install CoCo CLI yourself.** Go to Snowflake docs → Cortex Code / CoCo CLI installation. The `cortex` command is Snowflake-authenticated, easier if you do it manually. Run `cortex --version` to verify.
- [ ] **Fill in `.env`** with your Snowflake trial credentials (copy from `.env.example`, add real values, never commit).
- [ ] **Run `scripts/bootstrap_snowflake.sql`** in Snowsight (paste in a worksheet, execute) to create the warehouse/database/schemas. Takes 30 seconds.
- [ ] **Set up `~/.snowflake/connections.toml`** so CoCo CLI can find your account. Example:
   ```toml
   [connections.ladinglens]
   account = "your-account-locator"
   user = "your-username"
   password = "your-password"
   warehouse = "LADINGLENS_WH"
   database = "LADINGLENS_DB"
   role = "ACCOUNTADMIN"
   ```
   Then `cortex use connection ladinglens`.
- [ ] **Verify `dbt debug` shows "All checks passed!"** from inside `dbt/`.
- [ ] **Submit the ImportYeti custom-plan request.**
   1. Go to importyeti.com, sign up for a free account.
   2. On the pricing or contact page, request "custom plan" or "OSINT researcher access."
   3. In the message, explain: "Building a public educational supply-chain risk analysis project for a data hackathon. Need CSV export of bill-of-lading records for HS chapters 61 (apparel) and 85 (electronics/semiconductors), 2023-2025. Non-commercial, will credit ImportYeti in the demo."
   4. Note the response ETA and check email daily.
- [ ] **Push repo to GitHub** as a public repo named `ladinglens` (recruiters will look at it).

---

## Success Criteria

- Running `snow sql -q "SELECT CURRENT_WAREHOUSE(), CURRENT_DATABASE(), CURRENT_SCHEMA()"` returns `LADINGLENS_WH / LADINGLENS_DB / RAW`.
- Running `cortex --version` returns a version string.
- Running `dbt debug` inside `dbt/` returns "All checks passed!".
- GitHub repo is live, README renders correctly, no `.env` committed.

## Gotchas

- CoCo CLI region-gating: some regions don't yet support all Cortex models. If `cortex` login errors out about "region not supported for this model," fall back to a supported region in your `connections.toml` (US-East-1 or AWS-US-West-2 are safest for trial accounts).
- ImportYeti response times vary. Do NOT wait for their reply before starting Phase 2 — the free backbone data is enough to move.
- Snowflake trial credits are ~$400 for 30 days. Do NOT use anything larger than XS warehouse in this phase. Verify `AUTO_SUSPEND=60` in the bootstrap SQL so the warehouse stops when idle.
