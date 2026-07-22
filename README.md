# LadingLens

**Tariff-Exposure & Supplier-Concentration Copilot** — built for the Snowflake CoCo CLI Hackathon 2026.

LadingLens fuses raw U.S. import bill-of-lading data (ImportYeti/CBP FOIA), the USITC Harmonized
Tariff Schedule, and unstructured SEC 10-K risk disclosures into a Snowflake-native agent that
answers questions like *"what is my landed-cost and single-source risk if Section 301 tariffs rise
on HS 8541?"*

Full project spec: [`docs/phases/LadingLens.md`](docs/phases/LadingLens.md)
Phase-by-phase build plan: [`docs/phases/`](docs/phases/)

## Architecture

```
Data sources → ingestion → transformation (dbt medallion) → AI/ML layer → serving/agent → Streamlit UI → observability

  ImportYeti BoL ─┐
  USITC HTS ──────┼─▶ RAW (Iceberg/stage) ─▶ BRONZE ─▶ SILVER ─▶ GOLD ─▶ SEMANTIC ─▶ Cortex Agent ─▶ Streamlit-in-Snowflake
  SEC 10-K text ──┘         (dbt)          (typed)  (cleaned,  (star                 (NL Q&A)      (command center)
                                                      entity-   schema)
                                                      resolved)
                                                                                  │
                                                                                  ▼
                                                                          TruLens observability
```

## Repo layout

```
src/                Python source (ingestion, entity resolution, feature engineering)
dbt/ladinglens/      dbt project — models/{bronze,silver,gold}
notebooks/          EDA and analysis notebooks
streamlit/          Streamlit-in-Snowflake app
tests/              pytest suite
scripts/            One-off setup/utility scripts (e.g. bootstrap_snowflake.sql)
docs/phases/        Phase-by-phase build plan (LadingLens.md + phase-XX-*.md)
.github/workflows/  CI/CD (dbt tests, pytest)
```

## Setup

1. **Clone the repo**
   ```
   git clone <this-repo-url>
   cd LadingLens
   ```

2. **Create the Python environment**
   ```
   python3.11 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

3. **Configure Snowflake credentials**
   ```
   cp .env.example .env
   # fill in SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PASSWORD, SNOWFLAKE_ROLE
   ```

4. **Log in to the Snowflake CLI**
   ```
   snow connection add   # or configure ~/.snowflake/connections.toml directly
   snow connection test
   ```

5. **Log in to CoCo CLI** (installed separately per Snowflake's official instructions)
   ```
   cortex use connection <your-connection-name>
   cortex --version
   ```

6. **Run the bootstrap SQL** to create the warehouse/database/schemas
   ```
   snow sql -f scripts/bootstrap_snowflake.sql
   ```
   (or paste it into a Snowsight worksheet and run it there)

7. **Configure and verify dbt**
   ```
   cp dbt/profiles.yml.example ~/.dbt/profiles.yml
   set -a && source .env && set +a
   cd dbt/ladinglens && dbt debug
   ```
   Should print `All checks passed!`.

## Status

Phase 1 (foundation & environment) — see [`docs/phases/phase-01-foundation.md`](docs/phases/phase-01-foundation.md).
