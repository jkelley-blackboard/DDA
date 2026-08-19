# DDA → S3 Parquet Extraction (Proof of Concept)

**Status:** Proof of concept — not a production pipeline
**Last updated:** August 19, 2026

---

## 1. Goal

A script/tool that connects to Blackboard's **DDA (Direct Data Access)** — a read-only PostgreSQL replica of the Blackboard transactional database — and extracts one or more tables (full or partial) as **Parquet files delivered to an S3 bucket**, for downstream loading into a data warehouse (e.g. Snowflake) for reporting and analysis.

This is a **proof of concept**: the near-term goal is a working, repeatable extraction method — not real-time sync or change data capture (CDC).

---

## 2. Background / context

- This pattern applies to institutions building a centralized data warehouse/lakehouse that ingests Blackboard LMS data alongside other source systems (SIS, CRM, advancement, etc.).
- Blackboard offers three data-access paths: **DDA** (raw PostgreSQL read replica), **Illuminate/CDM** (Snowflake-native, curated/reporting-optimized), and **Streams** (packaged SQL extracts built on top of Illuminate).
- **Raw, student-level data** — not Illuminate/Streams' pre-calculated model output — is needed when an institution wants to build a custom model (e.g. retention/momentum) combining Blackboard engagement data with other source systems. This is what confirms **DDA** as the right source over Illuminate/Streams.
- The common near-term need in this scenario: a method to pull **full or partial DDA tables** directly, land them as **Parquet files in S3**, then run reporting/analysis on the replicated data in a cloud warehouse.

---

## 3. Critical constraint: fixed IP requirement

**DDA requires the connecting client to present a fixed IP address**, which Blackboard whitelists on their end. This applies regardless of which extraction method is used.

- Whatever runs the extraction (a script, a scheduled job, a service) must run from an environment with a **static, non-rotating outbound IP** — e.g., a dedicated virtual server (EC2 instance) with an Elastic IP, or a NAT gateway with a fixed address.
- It **cannot** run reliably from a typical desktop/home network (dynamic IP) or from ephemeral/serverless compute without a fixed egress point.
- Reference: [DDA Getting Connected — Cloud Services](https://jkelley-blackboard.github.io/DDA/getting-connected.html#:~:text=connections%20more%20efficiently.-,Cloud%20Services,-Cloud%2Dhosted%20tools)

**Action item before development:** confirm the fixed-IP environment (e.g., a specific EC2 instance) that will host this script, and get that IP submitted to Blackboard for DDA whitelisting before attempting a live connection.

---

## 4. Proposed approach

A Python script that:

1. Connects to DDA using a native PostgreSQL driver (not JDBC — no Java dependency needed in Python).
2. Reads a specified table (or a filtered subset of it) in **chunks**, to avoid loading very large tables entirely into memory.
3. Writes each chunk to a **Parquet file** incrementally.
4. Uploads the resulting Parquet file(s) to a specified **S3 bucket/prefix**.

### Why this approach
- Avoids unnecessary infrastructure (e.g., AWS DMS or Fivetran connector setup) for a first proof of concept — a single script is fastest to stand up and validate the concept end-to-end.
- Chunked reads + incremental Parquet writes handle large DDA tables without requiring the whole table to fit in memory at once.
- This can later be replaced or supplemented by a managed connector (e.g. Fivetran, which already supports PostgreSQL sources and has an S3/Parquet destination) or AWS DMS if the POC proves out and a production-grade, possibly CDC-based, pipeline is needed.

---

## 5. Requirements

### 5.1 Environment
- A host with a **fixed outbound IP**, whitelisted with Blackboard for DDA access (see Section 3). This must be resolved before any live connection attempt will succeed.
- Python 3.9+
- Network access to both the DDA PostgreSQL endpoint and AWS S3.

### 5.2 Python dependencies
```
psycopg2-binary   # native PostgreSQL driver
pandas            # tabular data handling
pyarrow           # Parquet read/write
boto3             # AWS S3 upload
```

### 5.3 Credentials & configuration (do not hardcode)
- DDA connection: host, port, database name, username, password
- AWS: S3 bucket name, target prefix/path, and AWS credentials (via environment variables, an AWS credentials file, or an IAM role if running on EC2 — prefer IAM role if the host is an EC2 instance, since it avoids storing static AWS keys)
- Store DDA credentials in environment variables or a local `.env` file excluded from version control — never commit credentials to a script or repo.

### 5.4 Table selection
- Support both:
  - **Full table pull** — `SELECT * FROM schema.table`
  - **Partial/filtered pull** — a configurable `WHERE` clause or column list, for cases where only a subset of a table is needed
- Table(s) in scope for a given POC should be confirmed with the institution/partner stakeholders before development — this document does not specify which DDA tables are in scope; that is engagement-specific.

---

## 6. Implementation tasks

1. **Environment setup**
   - Provision or identify the fixed-IP host (e.g., EC2 instance).
   - Submit the IP to Blackboard for DDA whitelisting; confirm DDA account credentials are provisioned.
   - Set up an S3 bucket (or confirm the target bucket/prefix) and appropriate write permissions.

2. **Core extraction script**
   - Implement DDA connection using `psycopg2`.
   - Implement chunked read via `pandas.read_sql(..., chunksize=N)`.
     - For very large tables, evaluate whether a **server-side (named) cursor** is needed in `psycopg2` to avoid the driver buffering the full result set before chunking — recommended if any target table is in the tens of millions of rows.
   - Implement incremental Parquet writing via `pyarrow.parquet.ParquetWriter`.
   - Implement S3 upload via `boto3`.
   - Make table name, filter/`WHERE` clause, chunk size, and S3 destination path configurable (e.g., via command-line arguments or a config file) rather than hardcoded.

3. **Validation**
   - Run against at least one small/medium DDA table end-to-end; confirm the Parquet file lands correctly in S3 and is readable (e.g., loadable into Snowflake or via `pandas.read_parquet()`).
   - Spot-check column data types in the output against the source DDA schema — pandas' type inference can occasionally diverge from PostgreSQL's original types (e.g., `NUMERIC` columns), which matters for financial or ID fields.
   - Test with a larger table to confirm chunking behaves as expected and memory stays within acceptable bounds.

4. **Documentation**
   - Document how to run the script (parameters, environment variables required).
   - Document the fixed-IP/whitelisting dependency clearly, since it's an operational prerequisite outside the script itself.

---

## 7. Out of scope for this POC

- Change data capture (CDC) / incremental sync of only changed rows
- Automated scheduling (this plan covers a manually-run or ad hoc script; scheduling can be added later, e.g., via cron or an orchestration tool)
- Production-grade error handling, retries, and monitoring
- Choosing between this custom script vs. a managed connector vs. AWS DMS for a long-term production pipeline — that decision should be revisited after the POC validates the approach

---

## 8. Open questions to confirm before/during development

- Which specific DDA table(s) are in scope for the initial POC?
- What fixed-IP hosting environment will be used, and who provisions it?
- What is the exact target S3 bucket name and prefix/path structure expected downstream?
- Should AWS access use an IAM role (if hosted on EC2) or static credentials?
- Any row-count/size estimates for the target table(s), to help tune chunk size in advance?

---

*This is a supplemental community resource. Content is the property of Blackboard, Inc. and is provided without official support or endorsement. Always refer to official Blackboard documentation and your institution's agreements.*
