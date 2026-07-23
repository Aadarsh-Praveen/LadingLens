"""Load the NIST FEIII 2019 Bill-of-Lading sample into LADINGLENS_DB.RAW.BOL_SHIPMENTS.

Source: local file data/raw/bol/export_sample_countries_challenge_with_orgs.csv.gz
(3,825,304 rows, 31 columns, 2018 CBP AMS data, ~356MB gzipped).

Attempts an Iceberg table first (Snowflake-managed external volume); falls back
to a regular table if the trial account lacks EXTERNAL VOLUME privileges.
Idempotent: CREATE OR REPLACE TABLE wipes and reloads on every run.
"""

import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import snowflake.connector
from dotenv import load_dotenv

REPO_ROOT = Path(__file__).resolve().parents[2]
load_dotenv(dotenv_path=REPO_ROOT / ".env")

BOL_FILE = REPO_ROOT / "data" / "raw" / "bol" / "export_sample_countries_challenge_with_orgs.csv.gz"
GDRIVE_URL = "https://drive.google.com/open?id=1tMkoOGF9lC6RJXm5DzmFJlvcIprTY0mI"

TABLE = "LADINGLENS_DB.RAW.BOL_SHIPMENTS"
STAGE = "LADINGLENS_DB.STAGE.RAW_STAGE"
ICEBERG_VOLUME = "LADINGLENS_ICEBERG_VOL"

EXPECTED_ROWS = 3_825_304
EXPECTED_HARMONIZED = 2_400_000
EXPECTED_ORGS = 725_000

COLUMNS = [
    ("identifier", "NUMBER"),
    ("trade_update_date", "DATE"),
    ("run_date", "DATE"),
    ("vessel_name", "VARCHAR"),
    ("port_of_unlading", "VARCHAR"),
    ("estimated_arrival_date", "DATE"),
    ("foreign_port_of_lading", "VARCHAR"),
    ("record_status_indicator", "VARCHAR"),
    ("place_of_receipt", "VARCHAR"),
    ("port_of_destination", "VARCHAR"),
    ("foreign_port_of_destination", "VARCHAR"),
    ("secondary_notify_party_1", "VARCHAR"),
    ("actual_arrival_date", "DATE"),
    ("consignee_name", "VARCHAR"),
    ("consignee_address", "VARCHAR"),
    ("consignee_contact_name", "VARCHAR"),
    ("consignee_comm_number_qualifier", "VARCHAR"),
    ("consignee_comm_number", "VARCHAR"),
    ("shipper_party_name", "VARCHAR"),
    ("shipper_address", "VARCHAR"),
    ("shipper_contact_name", "VARCHAR"),
    ("shipper_comm_number_qualifier", "VARCHAR"),
    ("shipper_comm_number", "VARCHAR"),
    ("container_number", "VARCHAR"),
    ("description_sequence_number", "NUMBER"),
    ("piece_count", "NUMBER"),
    ("text", "VARCHAR"),
    ("harmonized_number", "VARCHAR"),
    ("harmonized_value", "NUMBER"),
    ("harmonized_weight", "NUMBER"),
    ("harmonized_weight_unit", "VARCHAR"),
    ("identified_orgs", "VARCHAR"),
]
LOAD_COLUMN_NAMES = [c for c, _ in COLUMNS]


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


def check_prerequisite():
    if not BOL_FILE.exists():
        print(f"ERROR: {BOL_FILE} not found.")
        print(f"Download it from: {GDRIVE_URL}")
        print(f"Then place it at: {BOL_FILE}")
        sys.exit(1)
    size_mb = BOL_FILE.stat().st_size / (1024 * 1024)
    print(f"Found BoL file: {BOL_FILE} ({size_mb:.0f} MB)")


def try_create_iceberg_volume(cur):
    try:
        cur.execute(
            f"""
            CREATE EXTERNAL VOLUME IF NOT EXISTS {ICEBERG_VOLUME}
            STORAGE_LOCATIONS = (
                (
                    NAME = 'ladinglens-managed-storage'
                    STORAGE_PROVIDER = 'S3'
                    STORAGE_BASE_URL = 's3://ladinglens-iceberg/bol/'
                    STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::000000000000:role/ladinglens-iceberg-role'
                )
            )
            """
        )
        print(f"Created (or found existing) external volume {ICEBERG_VOLUME}.")
        return True
    except Exception as exc:
        print(f"WARNING: could not create external volume ({exc}).")
        print("Falling back to a regular (non-Iceberg) table.")
        return False


def create_table(cur, use_iceberg):
    cols_ddl = ",\n    ".join(f"{name} {dtype}" for name, dtype in COLUMNS)
    cols_ddl += ",\n    ingested_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()"

    if use_iceberg:
        try:
            cur.execute(
                f"""
                CREATE OR REPLACE ICEBERG TABLE {TABLE} (
                    {cols_ddl}
                )
                CATALOG = 'SNOWFLAKE'
                EXTERNAL_VOLUME = '{ICEBERG_VOLUME}'
                BASE_LOCATION = 'bol_shipments/'
                """
            )
            print(f"Created Iceberg table {TABLE}.")
            return True
        except Exception as exc:
            print(f"WARNING: Iceberg table creation failed ({exc}). Falling back to regular table.")

    cur.execute(f"CREATE OR REPLACE TABLE {TABLE} (\n    {cols_ddl}\n)")
    print(f"Created regular table {TABLE}.")
    return False


def put_and_copy(cur, multi_line=False):
    cur.execute(
        f"PUT file://{BOL_FILE} @{STAGE}/bol/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE PARALLEL=4"
    )
    put_result = cur.fetchall()
    print(f"PUT complete: {put_result}")

    multi_line_clause = "\n                MULTI_LINE = TRUE" if multi_line else ""
    cur.execute(
        f"""
        COPY INTO {TABLE} ({", ".join(LOAD_COLUMN_NAMES)})
        FROM @{STAGE}/bol/{BOL_FILE.name}
        FILE_FORMAT = (
            TYPE = 'CSV'
            SKIP_HEADER = 1
            FIELD_OPTIONALLY_ENCLOSED_BY = '"'
            NULL_IF = ('', 'NULL')
            EMPTY_FIELD_AS_NULL = TRUE
            COMPRESSION = 'GZIP'{multi_line_clause}
        )
        ON_ERROR = 'CONTINUE'
        PURGE = FALSE
        """
    )
    copy_results = cur.fetchall()
    columns = [d[0] for d in cur.description]
    return [dict(zip(columns, row)) for row in copy_results]


def summarize_copy_results(results):
    total_rows_loaded = 0
    total_errors = 0
    error_messages = set()
    for r in results:
        total_rows_loaded += r.get("rows_loaded", 0) or 0
        total_errors += r.get("errors_seen", 0) or 0
        if r.get("first_error"):
            error_messages.add(str(r["first_error"]))
        print(
            f"  file={r.get('file')} status={r.get('status')} "
            f"rows_parsed={r.get('rows_parsed')} rows_loaded={r.get('rows_loaded')} "
            f"errors_seen={r.get('errors_seen')}"
        )
    return total_rows_loaded, total_errors, error_messages


def needs_multiline_retry(error_messages):
    markers = ("end of record", "multi-line", "number of columns")
    return any(any(m in msg.lower() for m in markers) for msg in error_messages)


def post_load_verify(cur):
    cur.execute(f"SELECT COUNT(*) FROM {TABLE}")
    total = cur.fetchone()[0]
    cur.execute(f"SELECT COUNT(harmonized_number) FROM {TABLE}")
    harmonized = cur.fetchone()[0]
    cur.execute(f"SELECT COUNT(identified_orgs) FROM {TABLE}")
    orgs = cur.fetchone()[0]
    cur.execute(f"SELECT MIN(trade_update_date), MAX(trade_update_date) FROM {TABLE}")
    date_min, date_max = cur.fetchone()

    print(f"\nPost-load verification for {TABLE}:")
    print(f"  COUNT(*)                = {total:,} (expected ~{EXPECTED_ROWS:,})")
    print(
        f"  COUNT(harmonized_number) = {harmonized:,} "
        f"({harmonized / total:.1%}, expected ~{EXPECTED_HARMONIZED:,} / 63%)"
    )
    print(
        f"  COUNT(identified_orgs)   = {orgs:,} "
        f"({orgs / total:.1%}, expected ~{EXPECTED_ORGS:,} / 19%)"
    )
    print(f"  MIN/MAX(trade_update_date) = {date_min} / {date_max} (expected ~2017-12 to 2018-06)")
    return total


def main():
    print(f"[{datetime.now(timezone.utc).isoformat()}] Starting BoL shipments ingest")
    check_prerequisite()

    conn = connect()
    cur = conn.cursor()
    try:
        iceberg_ok = try_create_iceberg_volume(cur)
        used_iceberg = create_table(cur, iceberg_ok)

        results = put_and_copy(cur, multi_line=False)
        rows_loaded, errors_seen, error_messages = summarize_copy_results(results)

        if errors_seen > 0 and needs_multiline_retry(error_messages):
            print(
                f"\n{errors_seen} rows rejected with record-boundary errors — "
                "retrying with MULTI_LINE = TRUE."
            )
            create_table(cur, used_iceberg)
            results = put_and_copy(cur, multi_line=True)
            rows_loaded, errors_seen, error_messages = summarize_copy_results(results)

        total = post_load_verify(cur)

        rejected_pct = errors_seen / EXPECTED_ROWS if EXPECTED_ROWS else 0
        print(f"\nRows rejected by COPY INTO: {errors_seen:,} ({rejected_pct:.2%} of expected total)")
        if rejected_pct > 0.01:
            print("WARNING: rejected-row rate exceeds 1% — investigate error messages above before trusting this load.")
        if error_messages:
            print("Distinct error messages seen:")
            for msg in error_messages:
                print(f"  - {msg}")

        print(f"\nTable type used: {'ICEBERG' if used_iceberg else 'regular TABLE'}")
        print(f"BoL shipments ingest complete. {total:,} rows in {TABLE}.")
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    main()
