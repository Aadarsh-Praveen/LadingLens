"""Download the most recent 10-K/20-F (2023-2025) for each ticker in
config/target_tickers.yml, extract the risk-factors and MD&A-equivalent
sections, and load into LADINGLENS_DB.RAW.SEC_10K_FILINGS.

Library choice: sec-edgar-downloader, not sec-api — it's free, requires no API
key, and pulls directly from SEC EDGAR's public HTTPS endpoints (sec-api.io
requires a paid key beyond a small free tier).

Extraction is regex-based against the plain-text document (HTML tags
stripped). Formatting varies by filer, so failures are expected and
logged/skipped rather than retried — see docs/phases/phase-02-data-acquisition.md
and docs/phases/phase-04-dbt-and-er.md.

Phase 4 additions:
- config/target_tickers.yml entries may be plain ticker strings (legacy Phase 2
  groups) or dicts with explicit `cik`/`filing_type` (foreign_parents_and_retail,
  retry_with_explicit_cik). An explicit CIK bypasses sec-edgar-downloader's
  ticker->CIK lookup, which was stale for JNPR/HBI/GES in Phase 2.
- filing_type '20-F' (foreign private issuers) extracts Item 3.D (Risk Factors)
  and Item 5 (Operating and Financial Review) into the same item_1a_text/
  item_7_text columns as the 10-K equivalents (Item 1A / Item 7) -- they serve
  the same semantic role. filing_type is logged so downstream can tell them apart.
- Where a ticker appears in more than one config section (e.g. EMR: a plain
  Phase 2 entry AND a Phase 4 retry-with-CIK entry), the explicit-CIK entry wins.

Idempotent: MERGE upsert on (cik, filing_date).
"""

import re
import sys
from datetime import UTC, datetime
from pathlib import Path

import yaml
from dotenv import load_dotenv
from sec_edgar_downloader import Downloader

REPO_ROOT = Path(__file__).resolve().parents[2]
load_dotenv(dotenv_path=REPO_ROOT / ".env")

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _snowflake_conn import connect

TICKERS_FILE = REPO_ROOT / "config" / "target_tickers.yml"
SEC_DIR = REPO_ROOT / "data" / "raw" / "sec"
COMPANY_NAME = "LadingLens"
CONTACT_EMAIL = "praveen.aadarsh@gmail.com"

TABLE = "LADINGLENS_DB.RAW.SEC_10K_FILINGS"
MIN_ITEM_1A_CHARS = 5000

# 10-K section markers.
ITEM_1A_START = re.compile(r"item\s*1a\.?\s*risk\s*factors", re.IGNORECASE)
ITEM_1B_END = re.compile(r"item\s*1b\.?\s*unresolved", re.IGNORECASE)
ITEM_7_START = re.compile(
    r"item\s*7\.?\s*management.{0,10}s\s*discussion\s*and\s*analysis", re.IGNORECASE
)
ITEM_7A_END = re.compile(r"item\s*7a\.?\s*quantitative", re.IGNORECASE)
ITEM_8_END = re.compile(r"item\s*8\.?\s*financial\s*statements", re.IGNORECASE)

# Phase 7 catch: ITEM_1B_END alone silently failed to match on 13 of 24 filers
# (no "Item 1B" heading in a form the regex recognized), and extract_section's
# fallback -- "no end match -> take the rest of the document" -- meant item_1a_text
# ran through governance/MD&A/financial-statements/the audit opinion letter for
# those rows. Broadened with three fallback end-boundaries so a missing Item 1B
# heading doesn't blow the extraction out to end-of-document; extract_section
# already takes the earliest match across the whole end_pats list.
UNRESOLVED_STAFF_COMMENTS = re.compile(r"unresolved\s*staff\s*comments", re.IGNORECASE)
ITEM_2_LINE_START = re.compile(r"^\s*item\s*2\b", re.IGNORECASE | re.MULTILINE)
ITEM_2_PROPERTIES = re.compile(r"item\s*2\.?\s*properties", re.IGNORECASE)

# Runaway-extraction guard: if item_1a_text is long AND contains an audit firm's
# name, the section almost certainly ran through the auditor's report (i.e. past
# Item 8 entirely) -- truncate at the earliest of an audit-firm mention or an
# Item 8 Financial Statements marker.
AUDIT_FIRM_NAMES = re.compile(
    r"ernst\s*&\s*young|deloitte|kpmg|pricewaterhousecoopers|\bpwc\b", re.IGNORECASE
)
RUNAWAY_LENGTH_THRESHOLD = 50000


def apply_runaway_guard(text):
    """Truncate item_1a_text if it likely ran past Item 1A into later items.

    Only triggers above RUNAWAY_LENGTH_THRESHOLD chars AND an audit-firm name
    present -- short filings and filings that legitimately quote an audit firm
    name in passing (rare, but possible) are left untouched.
    """
    if len(text) <= RUNAWAY_LENGTH_THRESHOLD:
        return text
    audit_match = AUDIT_FIRM_NAMES.search(text)
    if not audit_match:
        return text
    item8_match = ITEM_8_END.search(text)
    cut_positions = [audit_match.start()]
    if item8_match:
        cut_positions.append(item8_match.start())
    return text[: min(cut_positions)].strip()


# 20-F section markers (foreign private issuers). Item 3.D = risk factors,
# the 20-F equivalent of 10-K Item 1A. Item 5 = Operating and Financial
# Review and Prospects, the 20-F equivalent of 10-K Item 7 (MD&A).
ITEM_3D_START = re.compile(r"item\s*3\.?\s*d\.?\s*risk\s*factors", re.IGNORECASE)
ITEM_4_END = re.compile(r"item\s*4\.?\s*information\s*on\s*the\s*company", re.IGNORECASE)
ITEM_5_START = re.compile(r"item\s*5\.?\s*operating\s*and\s*financial\s*review", re.IGNORECASE)
ITEM_6_END = re.compile(r"item\s*6\.?\s*directors", re.IGNORECASE)

SECTION_MARKERS = {
    "10-K": {
        "primary": (
            ITEM_1A_START,
            [
                ITEM_1B_END,
                UNRESOLVED_STAFF_COMMENTS,
                ITEM_2_LINE_START,
                ITEM_2_PROPERTIES,
                ITEM_7_START,  # last-resort backstop: several filers' Item 1B/2
                # headings didn't match any pattern above, letting
                # extraction run through Item 7A market-risk tables
                # and financial-statement notes before the runaway
                # guard's audit-firm check finally caught it.
            ],
        ),
        "secondary": (ITEM_7_START, [ITEM_7A_END, ITEM_8_END]),
    },
    "20-F": {
        "primary": (ITEM_3D_START, [ITEM_4_END]),
        "secondary": (ITEM_5_START, [ITEM_6_END]),
    },
}


def load_tickers():
    """Flatten config/target_tickers.yml into {ticker: {cik, filing_type}}.

    Plain string entries (legacy Phase 2 groups) get cik=None, filing_type='10-K'.
    Dict entries (Phase 4 foreign_parents_and_retail / retry_with_explicit_cik)
    carry an explicit cik/filing_type and override a same-ticker plain entry
    from another section, since they're the more specific/authoritative config.
    """
    with open(TICKERS_FILE) as f:
        groups = yaml.safe_load(f)

    tickers = {}
    explicit_tickers = set()
    for group_entries in groups.values():
        for entry in group_entries:
            if isinstance(entry, str):
                ticker = entry
                if ticker in explicit_tickers:
                    continue  # an explicit-CIK entry for this ticker already won
                tickers[ticker] = {"cik": None, "filing_type": "10-K"}
            else:
                ticker = entry["ticker"]
                tickers[ticker] = {
                    "cik": str(entry["cik"]),
                    "filing_type": entry.get("filing_type", "10-K"),
                }
                explicit_tickers.add(ticker)
    return tickers


def strip_html(text):
    """Strip tags, inline-XBRL metadata, and HTML entities from a raw filing
    document, leaving plain narrative text for section-boundary regexes."""
    text = re.sub(r"(?is)<(script|style).*?</\1>", " ", text)
    # Inline-XBRL header block: a hidden metadata blob (context/unit
    # declarations for every tagged fact) that modern large filers embed at
    # the top of the primary document. It's not visible to a human reader but
    # survives naive tag-stripping as ~1MB of "iso4217:USD xbrli:shares ..."
    # noise, diluting/burying the real narrative text that follows. Found via
    # direct inspection of Stellantis's 2025 20-F (Phase 4 20-F retry): this
    # single block was 998,050 of the doc's ~1.28M stripped chars.
    text = re.sub(r"(?is)<ix:header.*?</ix:header>", " ", text)
    text = re.sub(r"(?s)<[^>]+>", " ", text)
    text = text.replace("&nbsp;", " ").replace("&amp;", "&").replace("&#160;", " ")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n\s*\n+", "\n\n", text)
    return text


def extract_primary_document(full_submission_text, filing_type):
    """Pull the <TEXT> of the first <DOCUMENT> whose <TYPE> matches filing_type."""
    doc_blocks = re.split(r"(?i)<DOCUMENT>", full_submission_text)[1:]
    for block in doc_blocks:
        type_match = re.search(r"(?i)<TYPE>([^\r\n<]+)", block)
        if type_match and type_match.group(1).strip().upper().startswith(filing_type):
            text_match = re.search(r"(?is)<TEXT>(.*?)</TEXT>", block)
            if text_match:
                return text_match.group(1)
    # Fallback: no <DOCUMENT>/<TYPE> markers found — treat whole file as text.
    return full_submission_text


def extract_section(plain_text, start_pat, end_pats):
    """Return the longest span across all (start, end) match combinations.

    Filings list section headings in the Table of Contents before the real
    section body — a naive first-match pairing grabs that TOC gap (a few
    chars) instead of the actual multi-page section. Scanning all start
    occurrences and keeping the longest resulting span sidesteps this.
    """
    starts = [m.end() for m in start_pat.finditer(plain_text)]
    if not starts:
        return ""
    ends = []
    for end_pat in end_pats:
        ends.extend(m.start() for m in end_pat.finditer(plain_text))

    best = ""
    for s in starts:
        candidate_ends = [e for e in ends if e > s]
        e = min(candidate_ends) if candidate_ends else len(plain_text)
        candidate = plain_text[s:e]
        if len(candidate) > len(best):
            best = candidate
    return best.strip()


def extract_cik_and_date(full_submission_text, accession_folder_name):
    """Parse CIK and filing date from the submission header, falling back to
    deriving the CIK from the accession folder name if the header field is
    missing."""
    cik = None
    cik_match = re.search(r"CENTRAL INDEX KEY:\s*(\d+)", full_submission_text)
    if cik_match:
        cik = str(int(cik_match.group(1)))
    else:
        cik = str(int(accession_folder_name.split("-")[0]))

    filing_date = None
    date_match = re.search(r"FILED AS OF DATE:\s*(\d{8})", full_submission_text)
    if date_match:
        # SEC's "FILED AS OF DATE" is a calendar date with no associated
        # timezone in the source data, and .date() discards time anyway.
        filing_date = datetime.strptime(date_match.group(1), "%Y%m%d").date()  # noqa: DTZ007
    return cik, filing_date


def download_and_parse(ticker, cik, filing_type):
    """Download the most recent filing_type filing for a ticker (2023-2025
    window), extract its primary/secondary risk-disclosure sections, and
    return a dict ready for load_filing -- or None if download, file
    location, or parsing fails at any step."""
    dl = Downloader(COMPANY_NAME, CONTACT_EMAIL, SEC_DIR)
    identifier = cik if cik else ticker
    try:
        n = dl.get(filing_type, identifier, limit=1, after="2023-01-01", before="2025-12-31")
    except Exception as exc:  # noqa: BLE001 -- log and skip this ticker rather than
        # aborting the whole multi-ticker ingest run over one filer's failure.
        print(f"  {ticker}: download failed ({exc})")
        return None
    if n == 0:
        print(f"  {ticker}: no {filing_type} found in 2023-2025 window")
        return None

    ticker_dir = SEC_DIR / "sec-edgar-filings" / identifier / filing_type
    accession_dirs = sorted(ticker_dir.glob("*"))
    if not accession_dirs:
        print(f"  {ticker}: download reported success but no files on disk at {ticker_dir}")
        return None
    accession_dir = accession_dirs[-1]
    submission_file = accession_dir / "full-submission.txt"
    if not submission_file.exists():
        print(f"  {ticker}: full-submission.txt missing at {submission_file}")
        return None

    raw = submission_file.read_text(errors="ignore")
    parsed_cik, filing_date = extract_cik_and_date(raw, accession_dir.name)
    primary_doc = extract_primary_document(raw, filing_type)
    plain_text = strip_html(primary_doc)

    primary_pat, primary_ends = SECTION_MARKERS[filing_type]["primary"]
    secondary_pat, secondary_ends = SECTION_MARKERS[filing_type]["secondary"]
    item_primary = extract_section(plain_text, primary_pat, primary_ends)
    item_primary = apply_runaway_guard(item_primary)
    item_secondary = extract_section(plain_text, secondary_pat, secondary_ends)

    accession_nodash = accession_dir.name.replace("-", "")
    filing_url = (
        f"https://www.sec.gov/Archives/edgar/data/{parsed_cik}/{accession_nodash}/"
        f"{accession_dir.name}-index.htm"
    )

    return {
        "cik": parsed_cik,
        "ticker": ticker,
        "filing_type": filing_type,
        "filing_date": filing_date,
        "filing_url": filing_url,
        "item_1a_text": item_primary,
        "item_7_text": item_secondary,
        "item_1a_length": len(item_primary),
        "item_7_length": len(item_secondary),
    }


def load_filing(cur, filing):
    cur.execute(
        f"""
        MERGE INTO {TABLE} AS tgt
        USING (
            SELECT
                %(cik)s AS cik,
                %(ticker)s AS ticker,
                %(filing_type)s AS filing_type,
                %(filing_date)s AS filing_date,
                %(filing_url)s AS filing_url,
                %(item_1a_text)s AS item_1a_text,
                %(item_7_text)s AS item_7_text,
                %(item_1a_length)s AS item_1a_length,
                %(item_7_length)s AS item_7_length
        ) AS src
        ON tgt.cik = src.cik AND tgt.filing_date = src.filing_date
        WHEN MATCHED THEN UPDATE SET
            ticker = src.ticker,
            filing_type = src.filing_type,
            filing_url = src.filing_url,
            item_1a_text = src.item_1a_text,
            item_7_text = src.item_7_text,
            item_1a_length = src.item_1a_length,
            item_7_length = src.item_7_length,
            ingested_at = CURRENT_TIMESTAMP()
        WHEN NOT MATCHED THEN INSERT (
            cik, ticker, filing_type, filing_date, filing_url,
            item_1a_text, item_7_text, item_1a_length, item_7_length, ingested_at
        ) VALUES (
            src.cik, src.ticker, src.filing_type, src.filing_date, src.filing_url,
            src.item_1a_text, src.item_7_text, src.item_1a_length, src.item_7_length,
            CURRENT_TIMESTAMP()
        )
        """,
        filing,
    )


def main():
    """Run the full SEC ingest: load target tickers, download and extract
    each filing, gate on a minimum extracted-section length, upsert passing
    filings, and print a per-ticker pass/fail summary."""
    print(f"[{datetime.now(UTC).isoformat()}] Starting SEC 10-K/20-F ingest")
    tickers = load_tickers()
    print(f"Loaded {len(tickers)} target tickers from {TICKERS_FILE}")

    conn = connect()
    cur = conn.cursor()
    try:
        cur.execute(
            f"""
            CREATE TABLE IF NOT EXISTS {TABLE} (
                cik VARCHAR,
                ticker VARCHAR,
                filing_date DATE,
                filing_url VARCHAR,
                item_1a_text VARCHAR,
                item_7_text VARCHAR,
                item_1a_length NUMBER,
                item_7_length NUMBER,
                ingested_at TIMESTAMP_NTZ
            )
            """
        )
        cur.execute(f"ALTER TABLE {TABLE} ADD COLUMN IF NOT EXISTS filing_type VARCHAR")

        loaded = []
        failed = []
        for ticker, cfg in tickers.items():
            print(
                f"\n{ticker} (cik={cfg['cik'] or 'lookup-by-ticker'}, filing_type={cfg['filing_type']}):"
            )
            filing = download_and_parse(ticker, cfg["cik"], cfg["filing_type"])
            if filing is None:
                failed.append((ticker, "download or file-location failure"))
                continue
            # 20-F filers: some (e.g. Stellantis, Tata Motors -- Phase 4 20-F
            # retry) drop "Item N" prefixes from body headings entirely,
            # keeping them only in a regulatory cross-reference table at the
            # end of the document, which breaks ITEM_3D_START matching even
            # though the actual Item 5 (MD&A-equivalent) heading repeats
            # cleanly. Gate 20-F filings on whichever of the two sections
            # extracted successfully, since either is valid supply-chain-risk
            # content for our purposes (see module docstring) -- 10-K gating
            # is unchanged (still requires item_1a specifically).
            if filing["filing_type"] == "20-F":
                best_length = max(filing["item_1a_length"], filing["item_7_length"])
            else:
                best_length = filing["item_1a_length"]
            if best_length < MIN_ITEM_1A_CHARS:
                print(
                    f"  {ticker}: item_1a_length={filing['item_1a_length']} "
                    f"item_7_length={filing['item_7_length']} "
                    f"(best={best_length}) < {MIN_ITEM_1A_CHARS} — likely failed extraction, skipping"
                )
                failed.append(
                    (
                        ticker,
                        f"item_1a_length={filing['item_1a_length']}, item_7_length={filing['item_7_length']}",
                    )
                )
                continue

            load_filing(cur, filing)
            loaded.append(filing)
            print(
                f"  loaded: cik={filing['cik']} filing_type={filing['filing_type']} "
                f"filing_date={filing['filing_date']} item_1a_length={filing['item_1a_length']} "
                f"item_7_length={filing['item_7_length']}"
            )

        conn.commit()

        cur.execute(f"SELECT COUNT(*) FROM {TABLE}")
        total = cur.fetchone()[0]
        cur.execute(f"SELECT COUNT(*) FROM {TABLE} WHERE item_1a_length >= {MIN_ITEM_1A_CHARS}")
        good = cur.fetchone()[0]

        print(f"\n{'=' * 60}")
        print(f"Loaded {len(loaded)}/{len(tickers)} tickers this run.")
        print(
            f"Table {TABLE}: {total} total rows, {good} with item_1a_length >= {MIN_ITEM_1A_CHARS}"
        )
        if failed:
            print(f"\nFailed/skipped tickers ({len(failed)}):")
            for ticker, reason in failed:
                print(f"  - {ticker}: {reason}")
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    main()
