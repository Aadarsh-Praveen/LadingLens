-- Chunks each 10-K/20-F's item_1a_text into ~1700-character chunks with a
-- 200-character overlap (stride 1500, width 1700). The original spec used
-- stride=800/width=1000, but the real population (24 filings, avg 185.7K
-- chars, total 4.46M chars -- more than double the spec's assumed ~2M/~80K
-- average) would produce ~5,350 chunks at that stride, blowing past the
-- target row-count range. Scaling stride AND width together (not just
-- stride) preserves the 200-char overlap -- bumping stride alone while
-- leaving width at 1000 would flip the design into a 500-char GAP between
-- consecutive chunks instead of an overlap, silently dropping any content
-- that falls entirely inside that gap from the search index.

with filings as (
    select
        ticker,
        cik,
        filing_type,
        filing_date,
        extract(year from filing_date) as filing_year,
        item_1a_text,
        length(item_1a_text) as total_chars
    from {{ source('raw', 'sec_10k_filings') }}
    where item_1a_text is not null
      and length(item_1a_text) >= 5000
),

chunk_positions as (
    select
        f.ticker, f.cik, f.filing_type, f.filing_date, f.filing_year,
        f.item_1a_text, f.total_chars,
        seq.value * 1500 + 1 as chunk_start   -- stride 1500 chars
    from filings f,
         lateral flatten(input => array_generate_range(0, ceil(f.total_chars / 1500.0))) seq
),

chunks as (
    select
        md5(ticker || '|' || filing_date || '|' || chunk_start) as chunk_id,
        ticker,
        cik,
        filing_type,
        filing_date,
        filing_year,
        chunk_start,
        least(chunk_start + 1699, total_chars) as chunk_end,
        substr(item_1a_text, chunk_start, 1700) as chunk_text   -- width 1700
    from chunk_positions
    where chunk_start <= total_chars
)

select
    chunk_id,
    ticker,
    cik,
    filing_type,
    filing_year,
    filing_date,
    chunk_start,
    chunk_end,
    length(chunk_text) as chunk_length,
    chunk_text
from chunks
-- filter out tiny tail chunks (last chunk of a doc may be short, not useful)
where length(chunk_text) >= 200
