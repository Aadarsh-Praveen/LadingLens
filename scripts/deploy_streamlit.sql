-- Deploys the LadingLens Streamlit-in-Snowflake app.
--
-- File upload (PUT) isn't expressible as plain SQL -- it was done via the
-- Snowflake Python connector (see the PUT calls issued during Phase 9's
-- build), uploading streamlit/app.py, streamlit/panels/*.py,
-- streamlit/utils/*.py, and streamlit/environment.yml preserving the
-- panels/ and utils/ subdirectory structure on the stage. snowsql or the
-- Snowsight "Upload files" UI work equally well if running this by hand.
--
-- IMPORTANT: environment.yml is required, not optional, despite not being
-- mentioned in the original Phase 9 doc. CREATE STREAMLIT's default package
-- set is only `python==3.11.*,snowflake-snowpark-python,streamlit` -- plotly
-- is NOT included by default and the app will fail on `import plotly.express`
-- without it. Uploading environment.yml (conda-style, `channels: [snowflake]`)
-- to the SAME stage folder as app.py, then re-running CREATE OR REPLACE
-- STREAMLIT, is what actually adds plotly -- confirmed via
-- DESC STREAMLIT's `user_packages` field, and via the deployed app
-- successfully rendering plotly bar/pie/heatmap charts (see docs/screenshots/).
-- There is no ALTER STREAMLIT ... SET PACKAGES -- that property doesn't exist;
-- the environment.yml file on the stage is the only mechanism.

CREATE STAGE IF NOT EXISTS LADINGLENS_DB.SEMANTIC.STREAMLIT_STAGE;

-- After uploading app.py, panels/*.py, utils/*.py, and environment.yml to the
-- stage (preserving directory structure):

CREATE OR REPLACE STREAMLIT LADINGLENS_DB.SEMANTIC.LADINGLENS_APP
    ROOT_LOCATION = '@LADINGLENS_DB.SEMANTIC.STREAMLIT_STAGE'
    MAIN_FILE = 'app.py'
    QUERY_WAREHOUSE = LADINGLENS_WH
    TITLE = 'LadingLens'
    COMMENT = 'Tariff exposure and supplier concentration copilot';

-- Verify:
--   DESC STREAMLIT LADINGLENS_DB.SEMANTIC.LADINGLENS_APP;
--   -- user_packages should show: streamlit,pandas,plotly,snowflake-snowpark-python
--
-- App URL (Snowsight deep link):
--   https://app.snowflake.com/<org>/<account>/#/streamlit-apps/LADINGLENS_DB.SEMANTIC.LADINGLENS_APP
