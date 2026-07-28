-- Singular test: every chunk_length must be within [200, 1700] -- the
-- fact_10k_risk_chunks model's own floor filter (>= 200) and ceiling
-- (SUBSTR width = 1700). Any row outside this range indicates the chunking
-- logic itself broke, not a data-content issue.

select chunk_id, chunk_length
from {{ ref('fact_10k_risk_chunks') }}
where chunk_length < 200 or chunk_length > 1700
