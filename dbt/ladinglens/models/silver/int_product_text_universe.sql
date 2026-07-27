{{
    config(
        materialized='table'
    )
}}

-- Distinct, per-shipment-noise-stripped product texts that need HS
-- classification: rows in silver_bol_shipments (origin-country scoped, NOT
-- yet HS-chapter scoped -- see that model's header comment for why) with no
-- HS code from source field or regex extraction.
--
-- Naive DISTINCT on raw `text` produced 84,284 rows, not the ~3,300
-- originally estimated -- this dataset's text field bakes in per-shipment
-- metadata (PO numbers, style/SKU codes, container IDs, weights,
-- quantities) that makes otherwise-identical product descriptions look
-- unique on every shipment. This model strips that metadata BEFORE deduping
-- so "same product, different PO/qty/container" shipments collapse to one
-- normalized text -- chained as named steps (not one nested expression) so
-- each stripping rule stays independently readable/debuggable.
--
-- No upper-length filter on normalized_text_full: an earlier version
-- excluded anything over 200 chars entirely, which silently dropped 24,080
-- rows (multi-category concatenated descriptions) from ever being
-- classified at all -- they'd have landed as 'unresolved' downstream with
-- no chance at even an HS-2 guess. Those rows are kept here and truncated
-- to normalized_text (200 chars) for embedding/retrieval/LLM input;
-- normalized_text_full is retained for debugging/inspection.

with source_rows as (

    select text
    from {{ ref('silver_bol_shipments') }}
    where harmonized_number_final is null
      and text is not null

),

normalized as (
    -- see macros/normalize_product_text.sql -- shared with
    -- silver_bol_shipments_classified.sql's lookup join, so both sides of
    -- that join apply the exact same transformation.
    select {{ normalize_product_text('text') }} as normalized_text
    from source_rows
),

filtered as (

    select distinct normalized_text
    from normalized
    where length(normalized_text) >= 5

)

select
    normalized_text as normalized_text_full,
    left(normalized_text, 200) as normalized_text,
    left(normalized_text, 200) as product_text,
    snowflake.cortex.embed_text_768('e5-base-v2', left(normalized_text, 200)) as embedding
from filtered
