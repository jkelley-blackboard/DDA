---
meta-viewport: width=device-width,initial-scale=1
title: PostgreSQL & SQL Guide
---

# PostgreSQL & SQL Guide

[← Back to Overview](index.md)

This guide is for people who know SQL but are new to PostgreSQL. It covers the most common differences from other databases (SQL Server, MySQL, Oracle), useful PostgreSQL-specific features, and practical tips for working with the DDA.

---

## PostgreSQL Quirks vs Other Databases

### Identifier Case Sensitivity

PostgreSQL folds unquoted identifiers to lowercase. This means `Users`, `USERS`, and `users` all refer to the same table. However, if an object was created with quoted identifiers (e.g. `"Users"`), it must always be referenced with that exact casing in quotes.

In practice, all Blackboard DDA table and column names are lowercase, so you will never need to quote them. Just avoid mixing in quoted identifiers unless you know why.

### String Case Sensitivity

Unlike SQL Server, string comparisons in PostgreSQL are **case-sensitive** by default:

```sql
-- This will NOT match 'Admin' or 'ADMIN'
WHERE user_id = 'admin'
```

Use `ILIKE` for case-insensitive pattern matching (the PostgreSQL equivalent of a case-insensitive `LIKE`):

```sql
-- Matches 'Admin', 'ADMIN', 'admin', etc.
WHERE user_id ILIKE 'admin'

-- Wildcard pattern, case-insensitive
WHERE course_name ILIKE '%biology%'
```

Or use `LOWER()` for case-insensitive equality:

```sql
WHERE LOWER(user_id) = 'admin'
```

### String Concatenation

PostgreSQL uses `||` for string concatenation, not `+`:

```sql
-- SQL Server style (won't work in PostgreSQL)
SELECT firstname + ' ' + lastname AS full_name

-- PostgreSQL style
SELECT firstname || ' ' || lastname AS full_name
```

### Limiting Rows

PostgreSQL uses `LIMIT` instead of `TOP` (SQL Server) or `ROWNUM` (Oracle):

```sql
-- SQL Server
SELECT TOP 10 * FROM users

-- PostgreSQL
SELECT * FROM users LIMIT 10

-- With an offset (for pagination)
SELECT * FROM users LIMIT 10 OFFSET 20
```

### Single Quotes vs Double Quotes

This trips up almost everyone coming from SQL Server:

- **Single quotes** `'...'` are for **string values**: `WHERE course_id = 'ENG101'`
- **Double quotes** `"..."` are for **identifiers** (table/column names): `SELECT "my column" FROM ...`

Using double quotes around a string value is a common error that produces confusing results — PostgreSQL will try to interpret it as a column name.

### Casting

PostgreSQL supports the standard `CAST()` syntax but also has its own shorthand using `::`:

```sql
-- Standard SQL
SELECT CAST(pk1 AS VARCHAR)

-- PostgreSQL shorthand (preferred in practice)
SELECT pk1::VARCHAR

-- Common casts
SELECT dtmodified::DATE           -- strip time component
SELECT '2026-01-01'::TIMESTAMP    -- string to timestamp
SELECT available_ind::BOOLEAN     -- 'Y'/'N' won't cast — use CASE instead
```

### Boolean Type

PostgreSQL has a native `BOOLEAN` type (`true` / `false`), unlike SQL Server which uses `BIT` (`1` / `0`). In the Blackboard LMS schema, boolean-style columns use `Y`/`N` character fields (`available_ind`, `primary_ind`, etc.) rather than the native boolean type, so you compare them as strings.

---

## Date and Time

Date handling is one of the biggest differences from other databases.

### Current Date and Time

```sql
NOW()              -- current timestamp with time zone
CURRENT_TIMESTAMP  -- same as NOW()
CURRENT_DATE       -- today's date, no time component
CURRENT_TIME       -- current time only
```

### Date Arithmetic with INTERVAL

```sql
-- Last 30 days
WHERE timestamp >= NOW() - INTERVAL '30 days'

-- Last 6 months
WHERE dtmodified >= NOW() - INTERVAL '6 months'

-- Specific intervals
NOW() - INTERVAL '1 year 2 months 3 days'
NOW() + INTERVAL '7 days'
```

### Truncating Dates

`DATE_TRUNC` is the PostgreSQL way to group by week, month, year, etc.:

```sql
-- Group activity by month
SELECT DATE_TRUNC('month', timestamp) AS month, COUNT(1) AS events
FROM activity_accumulator
WHERE timestamp >= NOW() - INTERVAL '12 months'
GROUP BY DATE_TRUNC('month', timestamp)
ORDER BY month
```

Common truncation levels: `'year'`, `'quarter'`, `'month'`, `'week'`, `'day'`, `'hour'`

### Extracting Parts of a Date

```sql
EXTRACT(YEAR FROM dtmodified)
EXTRACT(MONTH FROM dtmodified)
EXTRACT(DOW FROM dtmodified)   -- day of week: 0=Sunday, 6=Saturday
```

### Time Zones

DDA timestamps are stored in UTC. If your institution is not in UTC, convert for display:

```sql
SELECT timestamp AT TIME ZONE 'UTC' AT TIME ZONE 'America/New_York' AS local_time
FROM activity_accumulator
```

---

## Finding Your Way Around the Schema

### Search for a Table by Name

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name ILIKE '%grade%'
ORDER BY table_name
```

### Search for a Column Across All Tables

One of the most useful queries when exploring an unfamiliar schema — find every table that contains a column matching a name pattern:

```sql
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND column_name ILIKE '%attempt%'
ORDER BY table_name, column_name
```

This is invaluable when you know a field exists somewhere but aren't sure which table it lives in.

### List All Columns for a Table

```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'course_main'
ORDER BY ordinal_position
```

### Check Row Counts Across Tables

```sql
SELECT relname AS table_name, n_live_tup AS estimated_row_count
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC
```

Note these are estimates maintained by the query planner, not exact counts — but they're useful for getting a sense of table sizes quickly without running `COUNT(1)`.

---

## Writing Better Queries

### CTEs (WITH Clauses)

Common Table Expressions make complex queries much more readable by breaking them into named steps. PostgreSQL has excellent CTE support:

```sql
WITH active_courses AS (
  SELECT pk1, course_id, course_name
  FROM course_main
  WHERE row_status = 0
    AND available_ind = 'Y'
    AND service_level IN ('F', 'C')
),
enrolled_counts AS (
  SELECT crsmain_pk1, COUNT(1) AS student_count
  FROM course_users
  WHERE role = 'S'
    AND row_status = 0
  GROUP BY crsmain_pk1
)
SELECT ac.course_id, ac.course_name, COALESCE(ec.student_count, 0) AS students
FROM active_courses ac
LEFT JOIN enrolled_counts ec ON ec.crsmain_pk1 = ac.pk1
ORDER BY students DESC
```

> **Note:** In PostgreSQL, CTEs are optimization fences by default — the planner treats each CTE as a separate execution unit and won't push filters from the outer query into them. For performance-sensitive queries, consider inlining the logic as a subquery, or use `WITH ... AS MATERIALIZED` / `NOT MATERIALIZED` to control this explicitly (available in PostgreSQL 12+).

### DISTINCT ON

`DISTINCT ON` is a PostgreSQL extension that returns one row per distinct value of the specified column(s) — particularly useful for "latest record per group" queries:

```sql
-- Most recent activity per user
SELECT DISTINCT ON (user_pk1)
  user_pk1, course_pk1, timestamp, event_type
FROM activity_accumulator
WHERE timestamp >= NOW() - INTERVAL '90 days'
ORDER BY user_pk1, timestamp DESC
```

The `ORDER BY` must start with the same columns as `DISTINCT ON`. The first row in the ordering for each group is returned.

### Window Functions

Window functions let you compute aggregates alongside individual rows without collapsing the result set:

```sql
-- Rank courses by enrollment within each term
SELECT
  cm.course_id,
  t.name AS term_name,
  COUNT(cu.pk1) AS enrollments,
  RANK() OVER (PARTITION BY ct.term_pk1 ORDER BY COUNT(cu.pk1) DESC) AS rank_in_term
FROM course_main cm
JOIN course_term ct ON ct.crsmain_pk1 = cm.pk1
JOIN term t ON t.pk1 = ct.term_pk1
JOIN course_users cu ON cu.crsmain_pk1 = cm.pk1
WHERE cu.role = 'S'
  AND cu.row_status = 0
GROUP BY cm.course_id, ct.term_pk1, t.name
```

Common window functions: `RANK()`, `ROW_NUMBER()`, `DENSE_RANK()`, `LAG()`, `LEAD()`, `SUM() OVER`, `COUNT() OVER`

### Generating a Date Series

`generate_series` is useful for producing a complete date range, especially when you want to show zero-count days in activity reports:

```sql
-- Generate a row for every day in the last 30 days
SELECT generate_series(
  CURRENT_DATE - INTERVAL '30 days',
  CURRENT_DATE,
  INTERVAL '1 day'
)::DATE AS activity_date
```

Combined with a LEFT JOIN to activity data, this ensures days with no activity still appear in results rather than being omitted.

### COALESCE and NULLIF

```sql
-- Return a default value when a field is null
COALESCE(batch_uid, course_id)        -- use course_id if batch_uid is null
COALESCE(inst_email, email, 'none')   -- first non-null wins

-- Turn a specific value into null (opposite of COALESCE)
NULLIF(available_ind, '')             -- treat empty string as null
NULLIF(student_count, 0)              -- treat zero as null (useful to avoid divide-by-zero)
```

---

## Query Performance

### Always Filter Large Tables by Date

Some tables — particularly `activity_accumulator` — are extremely large. Always include a date filter or queries will run indefinitely:

```sql
-- Always do this
WHERE timestamp >= NOW() - INTERVAL '30 days'
```

### Use EXPLAIN ANALYZE to Diagnose Slow Queries

Prefix any query with `EXPLAIN ANALYZE` to see how PostgreSQL is executing it and where time is being spent:

```sql
EXPLAIN ANALYZE
SELECT COUNT(1) FROM activity_accumulator
WHERE timestamp >= NOW() - INTERVAL '7 days'
```

Key things to look for in the output:
- **Seq Scan** on a large table — means no index is being used, often due to a missing or ineffective filter
- **actual time** vs **estimated rows** — large discrepancies suggest stale statistics
- **Nested Loop** on large row counts — can indicate a missing join condition

### Avoid SELECT *

Specify only the columns you need. On wide tables or large result sets this can meaningfully reduce query time and data transfer, especially when working through tools like Power BI or Python.

### COUNT(1) vs COUNT(column)

```sql
COUNT(1)         -- counts all rows including nulls
COUNT(user_pk1)  -- counts only non-null values
```

Use `COUNT(1)` for row counts rather than `COUNT(*)`. They are functionally identical in PostgreSQL, but some tools — including the Blackboard Reporting Framework — do not handle `COUNT(*)` well due to how they parse SQL before sending it to the database. `COUNT(1)` is the safer default. Use `COUNT(column)` when you specifically want to exclude nulls from the count.

---

## DDA-Specific Notes

### Read-Only Access

DDA access is read-only — `SELECT` only. You cannot `INSERT`, `UPDATE`, `DELETE`, or create permanent objects. However, you can use:

```sql
-- Temporary tables (session-scoped, dropped on disconnect)
CREATE TEMP TABLE my_results AS
SELECT * FROM course_main WHERE service_level = 'F';

-- CTEs (no persistence, but useful for multi-step logic)
```

### Schema Search Path

All LMS tables are in the `public` schema. You do not need to prefix table names with a schema name — `SELECT * FROM course_main` works as-is.

### Cross-Database Queries

The primary DDA database contains approximately 180 days of activity data. For historical activity data, query the `_stats` database via `dblink` — see [Cross-Database Joins](dblink.md).

---

This is a supplemental community resource. Content is the property of Blackboard, Inc. and is provided without official support or endorsement. Always refer to official Blackboard documentation and your institution's agreements.
