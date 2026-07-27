{{
    config(
        materialized='table'
    )
}}

-- Top-5 nearest HTS descriptions per distinct product text, by embedding
-- cosine similarity -- the retrieval half of Phase 5's retrieval-augmented
-- HS classifier. product_text here is already 200-char-truncated (see
-- int_product_text_universe.sql header for why the truncation exists).
--
-- SNOWPARK UDTF, not SQL cross join: two prior approaches (a naive single
-- cross join, then a 10-way hash-batched UNION ALL of smaller cross joins)
-- both failed to complete within 30 minutes, on XS and even MEDIUM (4x
-- compute) warehouses -- confirming the bottleneck was CPU-bound vector-math
-- cost (Snowflake's row-by-row VECTOR_COSINE_SIMILARITY inside a windowed
-- sort over ~482M pairs), not memory spill, since more compute and smaller
-- batches both failed to help. LADINGLENS_DB.SILVER.TOP5_HS_CANDIDATES is a
-- Python UDTF that loads all HS-6 embeddings once (via a staged pickle file
-- imported at registration time -- get_active_session() is NOT available
-- inside a UDF's execution context on this account, so the reference data
-- is bundled as an IMPORTS file instead of queried live) and does the
-- top-5 retrieval as a single vectorized numpy matrix multiplication per
-- input row. Smoke-tested at ~1,150 rows/sec (2,000 rows in 1.74s),
-- ~65x-100x+ faster than the SQL approaches, and verified to produce
-- identical results to the original cross-join method on a known input
-- ("COLD ROLLED STAINLESS STEEL COILS" -> same top-5 hs6/sim values).

select
    p.product_text,
    c.hs6,
    c.hs4,
    c.hs2,
    c.description as hts_description,
    c.sim,
    c.rank
from {{ ref('int_product_text_universe') }} p,
     table(LADINGLENS_DB.SILVER.TOP5_HS_CANDIDATES(p.embedding::ARRAY)) c
