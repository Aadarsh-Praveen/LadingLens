"""Shared Snowflake connection helper for ingest scripts.

Uses key-pair (SNOWFLAKE_JWT) authentication -- this account requires MFA for
human/password logins as of the trial->on-demand upgrade in Phase 4, so
scripted/unattended connections use an RSA key pair registered on the user
instead (see docs/phases/phase-04-dbt-and-er.md).
"""

import os

import snowflake.connector
from cryptography.hazmat.primitives import serialization


def connect():
    private_key_path = os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"]
    with open(private_key_path, "rb") as key_file:
        p_key = serialization.load_pem_private_key(key_file.read(), password=None)
    private_key_der = p_key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )

    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        private_key=private_key_der,
        role=os.environ.get("SNOWFLAKE_ROLE"),
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE"),
        database=os.environ.get("SNOWFLAKE_DATABASE"),
        schema=os.environ.get("SNOWFLAKE_SCHEMA"),
    )
