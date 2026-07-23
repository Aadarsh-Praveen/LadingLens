"""Download the most recent 10-K (2023-2025) for each ticker in
config/target_tickers.yml, extract Item 1A (Risk Factors) and Item 7 (MD&A),
and load into LADINGLENS_DB.RAW.SEC_10K_FILINGS.

Library choice: sec-edgar-downloader, not sec-api — it's free, requires no API
key, and pulls directly from SEC EDGAR's public HTTPS endpoints (sec-api.io
requires a paid key beyond a small free tier).

Extraction is regex-based against the plain-text 10-K document (HTML tags
stripped). 10-K formatting varies by filer, so failures are expected and
logged/skipped rather than retried — see docs/phases/phase-02-data-acquisition.md.

Idempotent: MERGE upsert on (cik, filing_date).
"""

import os
import re
from datetime import datetime, timezone
from pathlib import Path

import snowflake.connector
import yaml
from dotenv import load_dotenv
from sec_edgar_downloader import Downloader

REPO_ROOT = Path(__file__).resolve().parents[2]
load_dotenv(dotenv_path=REPO_ROOT / ".env")

TICKERS_FILE = REPO_ROOT / "config" / "target_tickers.yml"
SEC_DIR = REPO_ROOT / "data" / "raw" / "sec"
COMPANY_NAME = "LadingLens"
CONTACT_EMAIL = "praveen.aadarsh@gmail.com"

TABLE = "LADINGLENS_DB.RAW.SEC_10K_FILINGS"
MIN_ITEM_1A_CHARS = 5000

ITEM_1A_START = re.compile(r"item\s*1a\.?\s*risk\s*factors", re.IGNORECASE)
ITEM_1B_END = re.compile(r"item\s*1b\.?\s*unresolved", re.IGNORECASE)
ITEM_7_START = re.compile(
    r"item\s*7\.?\s*management.?s\s*discussion\s*and\s*analysis", re.IGNORECASE
)
ITEM_7A_END = re.compile(r"item\s*7a\.?\s*quantitative", re.IGNORECASE)
ITEM_8_END = re.compile(r"item\s*8\.?\s*financial\s*statements", re.IGNORECASE)


def connect():
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        password=os.environ.get("SNOWFLAKE_PASSWORD"),
        authenticator=os.environ.get("SNOWFLAKE_AUTHENTICATOR", "snowflake"),
        role=os.environ.get("SNOWFLAKE_ROLE"),
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE"),
        database=os.environ.get("SNOWFLAKE_DATABASE"),
        schema=os.environ.get("SNOWFLAKE_SCHEMA"),
    )


def load_tickers():
    with open(TICKERS_FILE) as f:
        groups = yaml.safe_load(f)
    tickers = []
    for group_tickers in groups.values():
        tickers.extend(group_tickers)
    return tickers


def strip_html(text):
    text = re.sub(r"(?is)<(script|style).*?</\1>", " ", text)
    text = re.sub(r"(?s)<[^>]+>", " ", text)
    text = text.replace("&nbsp;", " ").replace("&amp;", "&").replace("&#160;", " ")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n\s*\n+", "\n\n", text)
    return text


def extract_primary_document(full_submission_text):
    """Pull the <TEXT> of the first <DOCUMENT> whose <TYPE> is 10-K."""
    doc_blocks = re.split(r"(?i)<DOCUMENT>", full_submission_text)[1:]
    for block in doc_blocks:
        type_match = re.search(r"(?i)<TYPE>([^\r\n<]+)", block)
        if type_match and type_match.group(1).strip().upper().startswith("10-K"):
            text_match = re.search(r"(?is)<TEXT>(.*?)</TEXT>", block)
            if text_match:
                return text_match.group(1)
    # Fallback: no <DOCUMENT>/<TYPE> markers found — treat whole file as text.
    return full_submission_text


def extract_section(plain_text, start_pat, end_pats):
    """Return the longest span across all (start, end) match combinations.

    10-Ks list "Item 1A ... Item 1B" in the Table of Contents before the real
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
    cik = None
    cik_match = re.search(r"CENTRAL INDEX KEY:\s*(\d+)", full_submission_text)
    if cik_match:
        cik = str(int(cik_match.group(1)))
    else:
        cik = str(int(accession_folder_name.split("-")[0]))

    filing_date = None
    date_match = re.search(r"FILED AS OF DATE:\s*(\d{8})", full_submission_text)
    if date_match:
        filing_date = datetime.strptime(date_match.group(1), "%Y%m%d").date()
    return cik, filing_date


def download_and_parse(ticker):
    dl = Downloader(COMPANY_NAME, CONTACT_EMAIL, SEC_DIR)
    try:
        n = dl.get("10-K", ticker, limit=1, after="2023-01-01", before="2025-12-31")
    except Exception as exc:
        print(f"  {ticker}: download failed ({exc})")
        return None
    if n == 0:
        print(f"  {ticker}: no 10-K found in 2023-2025 window")
        return None

    ticker_dir = SEC_DIR / "sec-edgar-filings" / ticker / "10-K"
    accession_dirs = sorted(ticker_dir.glob("*"))
    if not accession_dirs:
        print(f"  {ticker}: download reported success but no files on disk")
        return None
    accession_dir = accession_dirs[-1]
    submission_file = accession_dir / "full-submission.txt"
    if not submission_file.exists():
        print(f"  {ticker}: full-submission.txt missing at {submission_file}")
        return None

    raw = submission_file.read_text(errors="ignore")
    cik, filing_date = extract_cik_and_date(raw, accession_dir.name)
    primary_doc = extract_primary_document(raw)
    plain_text = strip_html(primary_doc)

    item_1a = extract_section(plain_text, ITEM_1A_START, [ITEM_1B_END])
    item_7 = extract_section(plain_text, ITEM_7_START, [ITEM_7A_END, ITEM_8_END])

    accession_nodash = accession_dir.name.replace("-", "")
    filing_url = (
        f"https://www.sec.gov/Archives/edgar/data/{cik}/{accession_nodash}/"
        f"{accession_dir.name}-index.htm"
    )

    return {
        "cik": cik,
        "ticker": ticker,
        "filing_date": filing_date,
        "filing_url": filing_url,
        "item_1a_text": item_1a,
        "item_7_text": item_7,
        "item_1a_length": len(item_1a),
        "item_7_length": len(item_7),
    }


def load_filing(cur, filing):
    cur.execute(
        f"""
        MERGE INTO {TABLE} AS tgt
        USING (
            SELECT
                %(cik)s AS cik,
                %(ticker)s AS ticker,
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
            filing_url = src.filing_url,
            item_1a_text = src.item_1a_text,
            item_7_text = src.item_7_text,
            item_1a_length = src.item_1a_length,
            item_7_length = src.item_7_length,
            ingested_at = CURRENT_TIMESTAMP()
        WHEN NOT MATCHED THEN INSERT (
            cik, ticker, filing_date, filing_url,
            item_1a_text, item_7_text, item_1a_length, item_7_length, ingested_at
        ) VALUES (
            src.cik, src.ticker, src.filing_date, src.filing_url,
            src.item_1a_text, src.item_7_text, src.item_1a_length, src.item_7_length,
            CURRENT_TIMESTAMP()
        )
        """,
        filing,
    )


def main():
    print(f"[{datetime.now(timezone.utc).isoformat()}] Starting SEC 10-K ingest")
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

        loaded = []
        failed = []
        for ticker in tickers:
            print(f"\n{ticker}:")
            filing = download_and_parse(ticker)
            if filing is None:
                failed.append((ticker, "download or file-location failure"))
                continue
            if filing["item_1a_length"] < MIN_ITEM_1A_CHARS:
                print(
                    f"  {ticker}: item_1a_length={filing['item_1a_length']} "
                    f"< {MIN_ITEM_1A_CHARS} — likely failed extraction, skipping"
                )
                failed.append((ticker, f"item_1a_length={filing['item_1a_length']}"))
                continue

            load_filing(cur, filing)
            loaded.append(filing)
            print(
                f"  loaded: cik={filing['cik']} filing_date={filing['filing_date']} "
                f"item_1a_length={filing['item_1a_length']} item_7_length={filing['item_7_length']}"
            )

        conn.commit()

        cur.execute(f"SELECT COUNT(*) FROM {TABLE}")
        total = cur.fetchone()[0]
        cur.execute(f"SELECT COUNT(*) FROM {TABLE} WHERE item_1a_length >= {MIN_ITEM_1A_CHARS}")
        good = cur.fetchone()[0]

        print(f"\n{'=' * 60}")
        print(f"Loaded {len(loaded)}/{len(tickers)} tickers this run.")
        print(f"Table {TABLE}: {total} total rows, {good} with item_1a_length >= {MIN_ITEM_1A_CHARS}")
        if failed:
            print(f"\nFailed/skipped tickers ({len(failed)}):")
            for ticker, reason in failed:
                print(f"  - {ticker}: {reason}")
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    main()
