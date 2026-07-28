-- Singular test: fact_10k_risk_chunks row count sanity bound.
-- Original Phase 7 spec estimated 2,000-4,000 chunks at stride=1500/width=1700
-- based on the raw (contaminated) population (~4.46M chars). After fixing 9 of
-- 13 contaminated extractions (removing financial-statement/audit-report text),
-- the real corpus shrank to ~2.5M chars -- 1,674 chunks, legitimately below that
-- original bound. Range widened to (1000, 3000) to reflect the cleaned corpus
-- while still catching a genuine regression (e.g. an accidental full population
-- re-contamination, or the chunking logic breaking).

select count(*) as actual_row_count
from {{ ref('fact_10k_risk_chunks') }}
having count(*) not between 1000 and 3000
