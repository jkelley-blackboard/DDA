"""DDA table -> Parquet -> S3 extraction (proof of concept).

Connection details are read from environment variables, matching the
convention used by tools/dda_query.ps1 elsewhere in this repo:

    Required: DDA_HOST, DDA_DBNAME, DDA_USER
    Optional: DDA_PORT (default 5432), DDA_PASSWORD (prompted if unset)

S3 upload is optional: it only runs if --s3-bucket is passed. Without it,
the script just writes a local Parquet file, which is enough to validate
the DDA connection and extraction logic on its own.

Usage:
    python -m dda_s3_extract.extract --table users --limit 100 --out ./sample.parquet
    python -m dda_s3_extract.extract --table users --where "row_status = 0" \
        --chunk-size 5000 --s3-bucket my-bucket --s3-prefix dda/users/
"""

from __future__ import annotations

import argparse
import getpass
import os
import sys

import psycopg2
import pyarrow as pa
import pyarrow.parquet as pq


def get_connection():
    missing = [name for name in ("DDA_HOST", "DDA_DBNAME", "DDA_USER") if not os.environ.get(name)]
    if missing:
        raise SystemExit(f"Missing required environment variable(s): {', '.join(missing)}")

    password = os.environ.get("DDA_PASSWORD")
    if not password:
        password = getpass.getpass(f"DDA password for {os.environ['DDA_USER']}: ")

    return psycopg2.connect(
        host=os.environ["DDA_HOST"],
        port=os.environ.get("DDA_PORT", "5432"),
        dbname=os.environ["DDA_DBNAME"],
        user=os.environ["DDA_USER"],
        password=password,
    )


def build_query(table: str, columns: str | None, where: str | None, limit: int | None) -> str:
    column_list = columns if columns else "*"
    query = f"SELECT {column_list} FROM {table}"
    if where:
        query += f" WHERE {where}"
    if limit:
        query += f" LIMIT {limit}"
    return query


def extract_to_parquet(
    table: str,
    out_path: str,
    columns: str | None = None,
    where: str | None = None,
    limit: int | None = None,
    chunk_size: int = 10_000,
) -> int:
    query = build_query(table, columns, where, limit)
    print(f"Query: {query}")

    conn = get_connection()
    total_rows = 0
    writer: pq.ParquetWriter | None = None
    try:
        with conn.cursor(name="dda_s3_extract_cursor") as cur:
            cur.itersize = chunk_size
            cur.execute(query)
            colnames = [desc[0] for desc in cur.description]

            while True:
                rows = cur.fetchmany(chunk_size)
                if not rows:
                    break

                table_batch = pa.Table.from_pylist(
                    [dict(zip(colnames, row)) for row in rows]
                )
                if writer is None:
                    writer = pq.ParquetWriter(out_path, table_batch.schema)
                writer.write_table(table_batch)
                total_rows += len(rows)
                print(f"  wrote {total_rows} rows so far...")
    finally:
        if writer is not None:
            writer.close()
        conn.close()

    return total_rows


def upload_to_s3(local_path: str, bucket: str, prefix: str) -> str:
    import boto3

    key = prefix.rstrip("/") + "/" + os.path.basename(local_path) if prefix else os.path.basename(local_path)
    boto3.client("s3").upload_file(local_path, bucket, key)
    return f"s3://{bucket}/{key}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--table", required=True, help="DDA table name, e.g. users")
    parser.add_argument("--columns", help="Comma-separated column list (default: all columns)")
    parser.add_argument("--where", help="Optional WHERE clause (without the WHERE keyword)")
    parser.add_argument("--limit", type=int, help="Row cap, useful for a small sample pull")
    parser.add_argument("--chunk-size", type=int, default=10_000, help="Rows per fetch/write batch")
    parser.add_argument("--out", required=True, help="Local output Parquet file path")
    parser.add_argument("--s3-bucket", help="If set, upload the resulting file to this S3 bucket")
    parser.add_argument("--s3-prefix", default="", help="S3 key prefix (folder path) for the upload")
    args = parser.parse_args()

    total_rows = extract_to_parquet(
        table=args.table,
        out_path=args.out,
        columns=args.columns,
        where=args.where,
        limit=args.limit,
        chunk_size=args.chunk_size,
    )
    print(f"Done: {total_rows} rows written to {args.out}")

    if args.s3_bucket:
        s3_uri = upload_to_s3(args.out, args.s3_bucket, args.s3_prefix)
        print(f"Uploaded to {s3_uri}")


if __name__ == "__main__":
    sys.exit(main())
