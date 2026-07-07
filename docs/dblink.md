---
meta-viewport: width=device-width,initial-scale=1
title: Cross-Database Joins with dblink
---

# Cross-Database Joins with `dblink`

[← Back to Overview](index.md)

Blackboard's DDA databases are physically separated PostgreSQL instances. The `dblink` extension allows you to query across them from within a single connection. In most Blackboard LMS environments, connections are permitted **from the main database (`BB<deployment_id>`) to others** — not the reverse.

Replace `BB<deployment_id>` with your actual database prefix (for example, `BB5c1c67a3c99fc`) and supply your DDA credentials wherever shown.

---

## Setup

Enable the extension in your session if it is not already active:

```sql
CREATE EXTENSION IF NOT EXISTS dblink;
```

---

## Example 1: Long-Term Activity Reporting

The `activity_accumulator` table in the production database is truncated to 180 days. The `_stats` database retains a permanent copy. This query joins user data from the primary database with historical activity from `_stats`:

```sql
SELECT
    u.user_id,
    u.firstname,
    u.lastname,
    aa.course_pk1,
    aa.timestamp
FROM users u
JOIN dblink(
    'dbname=BB<deployment_id>_stats user=bbuser password=bbpassword',
    'SELECT user_pk1, course_pk1, timestamp FROM activity_accumulator'
) AS aa(user_pk1 INT, course_pk1 INT, timestamp TIMESTAMP)
    ON u.pk1 = aa.user_pk1
ORDER BY aa.timestamp DESC;
```

---

## Example 2: Course Activity Summary Beyond 180 Days

Aggregate total activity events per course over the full historical record:

```sql
SELECT
    cm.course_id,
    cm.course_name,
    aa.activity_count
FROM course_main cm
JOIN dblink(
    'dbname=BB<deployment_id>_stats user=bbuser password=bbpassword',
    'SELECT course_pk1, COUNT(*) AS activity_count
     FROM activity_accumulator
     GROUP BY course_pk1'
) AS aa(course_pk1 INT, activity_count BIGINT)
    ON cm.pk1 = aa.course_pk1
ORDER BY aa.activity_count DESC;
```

---

## Example 3: Identify Active Users Not Active in Production Window

Find users who have activity older than 180 days in `_stats` but no recent activity in the production `activity_accumulator`:

```sql
SELECT DISTINCT
    u.user_id,
    u.firstname,
    u.lastname
FROM users u
JOIN dblink(
    'dbname=BB<deployment_id>_stats user=bbuser password=bbpassword',
    'SELECT DISTINCT user_pk1 FROM activity_accumulator
     WHERE timestamp < NOW() - INTERVAL ''180 days'''
) AS old_aa(user_pk1 INT)
    ON u.pk1 = old_aa.user_pk1
WHERE u.pk1 NOT IN (
    SELECT DISTINCT user_pk1 FROM activity_accumulator
);
```

---

## Notes

- `dblink` requires a valid username and password for the target database — these are your DDA credentials for that database.
- Each `dblink` call opens a new connection. For complex queries, consider using a CTE to call `dblink` once and reference it multiple times.
- Column names and types in the `AS` clause must exactly match what the remote query returns.
- The remote query string is passed as plain text — double any single quotes inside it (e.g., `''180 days''`).

---

This is a supplemental community resource. Content is the property of Blackboard, Inc. and is provided without official support or endorsement. Always refer to official Blackboard documentation and your institution's agreements.
