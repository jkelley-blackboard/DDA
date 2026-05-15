# Content System Queries

## Summary

The following queries provide details on content system files in the CMS_DOC database and their related linking references in the Core Blackboard database. This is not an exhaustive list of all possible links between the two storage methods, but serves as a starting point for expanding queries into other areas.

---

## Architecture Note: Cross-Database Access

The Core Blackboard and Content System data live in **separate PostgreSQL databases**. Database names follow a predictable pattern based on a shared instance identifier:

| Database | Name Pattern | Example |
|---|---|---|
| Core Blackboard | `BB` + 13 lowercase alphanumeric characters | `BBa3f8c12e90b4d` |
| Content System | Core Blackboard database name + `_cms_doc` | `BBa3f8c12e90b4d_cms_doc` |

The identifier portion is identical across both databases — the CMS database name is always the Core Blackboard database name with `_cms_doc` appended.

Because PostgreSQL does not support direct cross-database joins, queries that span both databases require one of the approaches described below.

---

## Approach 1: Separate Queries (Recommended)

The safest and most broadly applicable approach is to run queries against each database independently and reconcile the results outside the database — for example in a spreadsheet, a reporting tool, or a scripting environment. The queries in this document are written for this approach: each query targets a single database and returns results that can be matched on `entry_id` or `file_name` externally.

This approach avoids credential exposure and works regardless of how the client environment is configured.

---

## Approach 2: `dblink` with Inline Credentials

PostgreSQL's `dblink` extension is installed in the Blackboard managed environment and can be used to execute a remote query against the Content System database inline within a Core Blackboard database session. However, because the environment runs as a non-superuser in a read-only transaction, `dblink` requires credentials to be supplied explicitly in the connection string.

> ⚠️ **Security warning:** Embedding credentials directly in SQL is a security risk. Connection strings containing passwords may be visible in query logs, session history, and shared tooling. Use this approach only in controlled environments and never in production automation or shared scripts.

The general form of a `dblink` call is:

```sql
SELECT *
FROM dblink(
    'host=<host> dbname=BBa3f8c12e90b4d_cms_doc user=<user> password=<password>',
    '<remote SQL>'
) AS alias(col1 type1, col2 type2, ...);
```

The remote SQL runs in the context of the Content System database. Column names and types must be explicitly declared in the `AS` clause — PostgreSQL cannot infer them from the remote query.

Where `dblink` queries appear in this document, they are shown as CTEs for readability so that the remote and local portions of the query remain clearly separated.

---

## Credential Handling in Scripts

When using `dblink` queries from Python, PowerShell, or other scripting environments, credentials can be stored in secure variables rather than hardcoded in SQL — eliminating the most common exposure risks. However, some residual risks remain regardless of approach.

### Residual Risks

Even with secure credential handling, be aware of the following:

- **Process listing** — connection strings passed as command-line arguments may be visible to other users via `ps aux` or Task Manager. Always assemble connection strings within the script rather than passing them as arguments.
- **Error logging** — if an exception is caught and logged, take care not to include the connection string object in the log output.
- **Memory** — credentials exist in process memory for the duration of the session. This is generally acceptable but worth noting in high-security environments.
- **The script file itself** — any script that reads credentials from environment variables or a secrets manager is only as safe as the access controls on the file.

### Preferred: Environment Variables

Store credentials outside the script and read them at runtime. The connection string is assembled in memory and never written to disk.

**Python**

```python
import os
import psycopg2

conn = psycopg2.connect(
    host=os.environ["BB_CMS_HOST"],
    dbname=os.environ["BB_CMS_DBNAME"],   # e.g. BBa3f8c12e90b4d_cms_doc
    user=os.environ["BB_CMS_USER"],
    password=os.environ["BB_CMS_PASSWORD"]
)
```

**PowerShell**

```powershell
$connString = "host=$env:BB_CMS_HOST dbname=$env:BB_CMS_DBNAME " +
              "user=$env:BB_CMS_USER password=$env:BB_CMS_PASSWORD"
```

Set environment variables in your shell session or via your OS/platform secrets facility — never in the script itself.

### Also Acceptable: Prompt at Runtime

For interactive scripts, prompt for credentials so they are never stored anywhere.

**Python**

```python
import getpass

password = getpass.getpass("CMS database password: ")
```

**PowerShell**

```powershell
$credential = Get-Credential -Message "Enter CMS database credentials"
$password = $credential.GetNetworkCredential().Password
```

### Better: Secrets Manager

For production or automated workflows, retrieve credentials from a secrets manager at runtime. The credential never appears in any file or environment variable.

**Python (AWS Secrets Manager example)**

```python
import boto3
import json

client = boto3.client("secretsmanager")
secret = json.loads(client.get_secret_value(SecretId="bb-cms-db-creds")["SecretString"])

host     = secret["host"]
dbname   = secret["dbname"]
user     = secret["user"]
password = secret["password"]
```

Similar patterns exist for Azure Key Vault (`azure-keyvault-secrets`) and HashiCorp Vault. The specific implementation will depend on your institution's infrastructure.

### Avoid

| Pattern | Risk |
|---|---|
| Hardcoded credentials in SQL | Visible in query history, logs, and shared files |
| Hardcoded credentials in script files | Exposed if the file is shared, committed to version control, or improperly access-controlled |
| Credentials passed as command-line arguments | Visible in process listings to other users on the same host |

---

## Verifying the Environment

The following read-only checks confirm that the necessary components are in place. All four should return results in any standard Blackboard managed deployment.

**1. Is `postgres_fdw` installed?**

```sql
SELECT extname, extversion
FROM pg_extension
WHERE extname = 'postgres_fdw';
```

**2. Is `dblink` installed?**

```sql
SELECT extname, extversion
FROM pg_extension
WHERE extname = 'dblink';
```

**3. Is a foreign server defined for the Content System database?**

```sql
SELECT srvname, srvoptions
FROM pg_foreign_server
WHERE srvname LIKE '%cms_doc%';
```

Expect to see both a read-write (`srv_rw_`) and read-only (`srv_ro_`) variant.

**4. Is a user mapping in place for your role?**

```sql
SELECT usename, srvname
FROM pg_user_mappings
WHERE srvname LIKE '%cms_doc%';
```

---

## Primary Tables

| Table | Database | Description |
|---|---|---|
| `xyf_files` | CMS_DOC | Metadata for files stored in the content system. Does **not** contain the file name (found in `xyf_urls`), but does contain the external identifier (`xid`) via the `entry_id` column. |
| `xyf_urls` | CMS_DOC | Stores the location of files in the content system. Each directory and file is stored as a separate entry. |
| `files` | Core Blackboard | Files referenced by content items on the Core Blackboard side. |
| `course_contents_files` | Core Blackboard | Provides the linking information between a content item and a file. |
| `course_contents` | Core Blackboard | Stores content item information for a course or organization. File data may be embedded in the textual content of an item in addition to having an explicit link in `course_contents_files`. Capturing embedded links requires a regular expression to parse the `entry_id` (`xid`) from the text. |
| `course_main` | Core Blackboard | Course identity data; provides `course_id`. |

---

## Files in the Content System Linked to Content Items

### Core Blackboard Database Query

This query returns the Core Blackboard-side linking data. Match results to the CMS query below on `file_name` / `entry_id`.

```sql
SELECT
    cm.course_id,
    cc.title,
    lf.file_name,
    ccf.files_pk1
FROM files lf
JOIN course_contents_files ccf   ON ccf.files_pk1 = lf.pk1
JOIN course_contents cc          ON cc.pk1 = ccf.course_contents_pk1
JOIN course_main cm              ON cm.pk1 = cc.crsmain_pk1
WHERE lf.file_name LIKE '/xid-%_1'
ORDER BY lf.file_name;
```

### Content System Database Query

Run this separately against the Content System database. Match to the Core Blackboard query above on `entry_id` (extracting the numeric portion from `file_name` as `/xid-<entry_id>_1`).

```sql
SELECT
    f.entry_id,
    u.full_path,
    u.file_name
FROM xyf_files f
JOIN xyf_urls u ON u.file_id = f.file_id
WHERE f.file_type_code = 'F'
ORDER BY f.entry_id;
```

### Combined Query via `dblink`

If inline cross-database querying is available, the following combines both into a single result. Replace the connection string placeholders before running.

```sql
WITH cms_files AS (
    SELECT *
    FROM dblink(
        'host=<host> dbname=BBa3f8c12e90b4d_cms_doc user=<user> password=<password>',
        'SELECT f.entry_id, u.full_path, u.file_name
         FROM xyf_files f
         JOIN xyf_urls u ON u.file_id = f.file_id
         WHERE f.file_type_code = ''F'''
    ) AS f(entry_id bigint, full_path text, file_name text)
)
SELECT
    cm.course_id,
    cc.title,
    cf.entry_id,
    cf.full_path,
    cf.file_name
FROM cms_files cf
JOIN files lf                    ON '/xid-' || cf.entry_id::text || '_1' = lf.file_name
JOIN course_contents_files ccf   ON ccf.files_pk1 = lf.pk1
JOIN course_contents cc          ON cc.pk1 = ccf.course_contents_pk1
JOIN course_main cm              ON cm.pk1 = cc.crsmain_pk1
ORDER BY lf.file_name;
```

---

## Files Embedded in Content Item Descriptions

Files can also be referenced inline within content item description text (`main_data`). The query below uses `SUBSTRING` with a regex capture group to extract the `xid` value, which can then be matched to `entry_id` in the Content System database.

> **Note:** This query extracts only the **first** embedded link per row. Use the `REGEXP_MATCHES` variant below to return all embedded links per item.

```sql
-- Run against the Core Blackboard database
-- First embedded xid per content item
SELECT
    cm.course_id,
    cc.title,
    SUBSTRING(cc.main_data FROM '.*/xid-(\d+)_1"') AS entry_id
FROM course_contents cc
JOIN course_main cm ON cm.pk1 = cc.crsmain_pk1
WHERE cc.main_data LIKE '%bbcswebdav%';
```

### Variant: All Embedded Links Per Content Item

```sql
-- Run against the Core Blackboard database
SELECT
    cm.course_id,
    cc.title,
    matches[1] AS entry_id
FROM course_contents cc
JOIN course_main cm ON cm.pk1 = cc.crsmain_pk1
CROSS JOIN LATERAL REGEXP_MATCHES(cc.main_data, '.*/xid-(\d+)_1"', 'g') AS matches
WHERE cc.main_data LIKE '%bbcswebdav%';
```

---

## Files in the Content System Without Links

The following queries identify content system files that have **no** corresponding reference in the Core Blackboard database.

> **Note:** Depending on your Blackboard usage, you may need to extend this logic to cover embedded files in other areas such as discussion forums or blogs — search for `'%bbcswebdav%'` in the relevant table's text column.

### Separate Query Approach

**Step 1** — Run against the Content System database to get all files:

```sql
SELECT
    f.entry_id,
    u.full_path,
    u.file_name
FROM xyf_files f
JOIN xyf_urls u ON u.file_id = f.file_id
WHERE f.file_type_code = 'F';
```

**Step 2** — Run against the Core Blackboard database to get all referenced file names:

```sql
SELECT file_name
FROM files
WHERE file_name LIKE '/xid-%_1';
```

Reconcile externally: any `entry_id` from Step 1 that does not appear (as `/xid-<entry_id>_1`) in the Step 2 results is unlinked.

### Combined Query via `dblink`

```sql
-- Run against the Core Blackboard database
WITH cms_files AS (
    SELECT *
    FROM dblink(
        'host=<host> dbname=BBa3f8c12e90b4d_cms_doc user=<user> password=<password>',
        'SELECT f.entry_id, u.full_path, u.file_name
         FROM xyf_files f
         JOIN xyf_urls u ON u.file_id = f.file_id
         WHERE f.file_type_code = ''F'''
    ) AS f(entry_id bigint, full_path text, file_name text)
)
SELECT
    cf.entry_id,
    cf.full_path,
    cf.file_name
FROM cms_files cf
WHERE NOT EXISTS (
    SELECT 1
    FROM files lf
    WHERE '/xid-' || cf.entry_id::text || '_1' = lf.file_name
);
```

### Unlinked Files Including Embedded References — ⚠️ May Not Complete Timely

Extending the above to also exclude files embedded in `course_contents.main_data` adds significant query cost. The materialized approach below is strongly recommended over an inline CTE for any dataset of meaningful size.

```sql
-- Step 1: Run against the Core Blackboard database and save results
CREATE TEMP TABLE embedded_xids AS
SELECT DISTINCT matches[1]::bigint AS entry_id
FROM course_contents
CROSS JOIN LATERAL REGEXP_MATCHES(main_data, '.*/xid-(\d+)_1"', 'g') AS matches
WHERE main_data LIKE '%bbcswebdav%';

CREATE INDEX ON embedded_xids (entry_id);

-- Step 2: Combined unlinked query via dblink
WITH cms_files AS (
    SELECT *
    FROM dblink(
        'host=<host> dbname=BBa3f8c12e90b4d_cms_doc user=<user> password=<password>',
        'SELECT f.entry_id, u.full_path, u.file_name
         FROM xyf_files f
         JOIN xyf_urls u ON u.file_id = f.file_id
         WHERE f.file_type_code = ''F'''
    ) AS f(entry_id bigint, full_path text, file_name text)
)
SELECT
    cf.entry_id,
    cf.full_path,
    cf.file_name
FROM cms_files cf
WHERE NOT EXISTS (
    SELECT 1
    FROM files lf
    WHERE '/xid-' || cf.entry_id::text || '_1' = lf.file_name
)
AND NOT EXISTS (
    SELECT 1 FROM embedded_xids e WHERE e.entry_id = cf.entry_id
);
```

> **Note:** The `CREATE TEMP TABLE` step requires write access to the session's temp schema. If this fails in a read-only session, extract the embedded xids via the Core Blackboard database query above and perform the final reconciliation externally.
