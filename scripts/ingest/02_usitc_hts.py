"""Download the current USITC Harmonized Tariff Schedule and load it into
LADINGLENS_DB.RAW.HTS_TARIFF_SCHEDULE.

Source: https://hts.usitc.gov/reststop/exportList (public, no auth required).
Idempotent: CREATE OR REPLACE TABLE on every run.
"""

import csv
import json
import sys
from datetime import UTC, date, datetime
from pathlib import Path

import requests
from dotenv import load_dotenv

REPO_ROOT = Path(__file__).resolve().parents[2]
load_dotenv(dotenv_path=REPO_ROOT / ".env")

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _snowflake_conn import connect

HTS_URL = "https://hts.usitc.gov/reststop/exportList?from=0&to=99&format=JSON&styles=false"
HTS_FALLBACK_URL = "https://hts.usitc.gov/reststop/file?filename=htsdata.json"
RAW_DIR = REPO_ROOT / "data" / "raw" / "hts"

TABLE = "LADINGLENS_DB.RAW.HTS_TARIFF_SCHEDULE"
STAGE = "LADINGLENS_DB.STAGE.RAW_STAGE"


def download_hts():
    """Fetch the current HTS export, trying the primary reststop endpoint
    first and falling back to the static file endpoint if it fails.

    Returns:
        (data, dest_path) -- the parsed JSON records and the path they were
        saved to under data/raw/hts/.
    """
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    dest = RAW_DIR / f"hts_{date.today().isoformat()}.json"  # noqa: DTZ011 -- a run-date
    # filename label, not a point-in-time timestamp; timezone-awareness isn't meaningful here.

    for url in (HTS_URL, HTS_FALLBACK_URL):
        try:
            print(f"Downloading HTS from {url} ...")
            resp = requests.get(url, timeout=120)
            resp.raise_for_status()
            data = resp.json()
            dest.write_text(json.dumps(data))
            print(f"Saved {len(data)} HTS records to {dest}")
            return data, dest
        except Exception as exc:  # noqa: BLE001 -- try the fallback URL on any failure
            print(f"  failed: {exc}")

    print("Both HTS endpoints failed. Aborting.")
    sys.exit(1)


def flatten(records):
    """Flatten raw HTS JSON records into flat rows, deriving the hs2/hs4/hs6/
    hs8/hs10 code prefixes from the dotted htsno field (e.g. "8471.30.01"
    -> hs2="84", hs6="847130")."""
    rows = []
    for r in records:
        hts_number = (r.get("htsno") or "").strip()
        footnotes = r.get("footnotes")
        if isinstance(footnotes, list):
            footnotes = "; ".join(
                f.get("value", "") if isinstance(f, dict) else str(f) for f in footnotes
            )
        digits = hts_number.replace(".", "")
        rows.append(
            {
                "hts_number": hts_number,
                "description": r.get("description"),
                "indent": r.get("indent"),
                "units": (
                    ",".join(r.get("units") or [])
                    if isinstance(r.get("units"), list)
                    else r.get("units")
                ),
                "general_rate_text": r.get("general"),
                "special_rate_text": r.get("special"),
                "column2_rate_text": r.get("other"),
                "footnotes": footnotes,
                "hs2": digits[0:2] or None,
                "hs4": digits[0:4] or None,
                "hs6": digits[0:6] or None,
                "hs8": digits[0:8] or None,
                "hs10": digits[0:10] or None,
            }
        )
    return rows


def write_csv(rows):
    csv_path = RAW_DIR / f"hts_{date.today().isoformat()}.csv"  # noqa: DTZ011 -- filename
    # label, not a point-in-time timestamp; see download_hts for the same rationale.
    fieldnames = [
        "hts_number",
        "description",
        "indent",
        "units",
        "general_rate_text",
        "special_rate_text",
        "column2_rate_text",
        "footnotes",
        "hs2",
        "hs4",
        "hs6",
        "hs8",
        "hs10",
    ]
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} rows to {csv_path}")
    return csv_path


def load_to_snowflake(csv_path):
    conn = connect()
    cur = conn.cursor()
    try:
        cur.execute(
            f"""
            CREATE OR REPLACE TABLE {TABLE} (
                hts_number VARCHAR,
                description VARCHAR,
                indent NUMBER,
                units VARCHAR,
                general_rate_text VARCHAR,
                special_rate_text VARCHAR,
                column2_rate_text VARCHAR,
                footnotes VARCHAR,
                hs2 VARCHAR,
                hs4 VARCHAR,
                hs6 VARCHAR,
                hs8 VARCHAR,
                hs10 VARCHAR,
                ingested_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
            )
            """
        )
        cur.execute(f"PUT file://{csv_path} @{STAGE}/hts/ AUTO_COMPRESS=TRUE OVERWRITE=TRUE")

        cur.execute(
            f"""
            COPY INTO {TABLE} (
                hts_number, description, indent, units, general_rate_text,
                special_rate_text, column2_rate_text, footnotes,
                hs2, hs4, hs6, hs8, hs10
            )
            FROM @{STAGE}/hts/{csv_path.name}.gz
            FILE_FORMAT = (
                TYPE = 'CSV'
                SKIP_HEADER = 1
                FIELD_OPTIONALLY_ENCLOSED_BY = '"'
                NULL_IF = ('', 'NULL')
                EMPTY_FIELD_AS_NULL = TRUE
            )
            ON_ERROR = 'CONTINUE'
            PURGE = FALSE
            """
        )

        cur.execute(f"SELECT COUNT(*) FROM {TABLE}")
        total = cur.fetchone()[0]
        cur.execute(f"SELECT COUNT(DISTINCT hs2) FROM {TABLE}")
        distinct_hs2 = cur.fetchone()[0]
        cur.execute(f"SELECT hts_number, description, hs2 FROM {TABLE} LIMIT 5")
        sample = cur.fetchall()

        print(f"\nLoaded {total} rows into {TABLE}")
        print(f"Distinct hs2 chapters: {distinct_hs2}")
        print("Sample rows:")
        for row in sample:
            print(f"  {row}")

        return total, distinct_hs2
    finally:
        cur.close()
        conn.close()


def main():
    """Run the full HTS ingest: download, flatten to CSV, load to Snowflake,
    and sanity-check the loaded row/chapter counts against expected ranges."""
    print(f"[{datetime.now(UTC).isoformat()}] Starting USITC HTS ingest")
    data, _ = download_hts()
    rows = flatten(data)
    csv_path = write_csv(rows)
    total, distinct_hs2 = load_to_snowflake(csv_path)

    if total < 30000:
        print(f"WARNING: expected 35,000+ rows, got {total}")
    if distinct_hs2 < 95:
        print(f"WARNING: expected ~99 distinct hs2 chapters, got {distinct_hs2}")

    print("USITC HTS ingest complete.")


if __name__ == "__main__":
    main()
