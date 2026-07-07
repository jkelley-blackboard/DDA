---
meta-viewport: width=device-width,initial-scale=1
title: Working with activity_accumulator
---

# Working with `activity_accumulator`

[← Back to Overview](index.md)

`activity_accumulator` records nearly every page view and tracked interaction in the Blackboard LMS — logins, logouts, course access, content access, tab/module access, and more. One row is written per event, which makes it the single largest table most institutions will query through DDA.

This page covers the table's columns, common `event_type` values, query patterns, and the performance considerations that come with a table of this size.

> **Before you query this table, know these three things:**
> 1. **Recent activity has a lag.** The LMS feeds records into `activity_accumulator` from `activity_accumulator_queue` in batches every couple of minutes — it is not written synchronously as events occur. If you need up-to-the-second activity, `UNION` the two tables rather than relying on `activity_accumulator` alone.
> 2. **The production copy only goes back 180 days.** Older records live in the `_stats` schema's copy of the table — see [Where the Data Lives](#where-the-data-lives) below.
> 3. **For Ultra interfaces, `activity_accumulator` is not the most detailed source.** Blackboard Illuminate's `CDM_TLM.ultra_events` table maintains a more detailed activity log for users active in the Ultra experience. If you need granular Ultra interaction data, check there first.

---

## Where the Data Lives

- The primary database's `activity_accumulator` is **truncated to approximately 180 days**.
- A permanent copy is retained in the `_stats` database (e.g. `BB<deployment_id>_stats`).
- The two schemas are not identical — the `_stats` copy is a synchronized subset built for long-term reporting.
- Querying across both requires `dblink`, since DDA databases are separate PostgreSQL instances. See [Cross-Database Joins](dblink.md) for connection examples.

For anything beyond a 180-day window — year-over-year comparisons, full-term activity, multi-year audits — you need the `_stats` database.

---

## Column Reference

| Column | Type | Nullable | Notes |
|---|---|---|---|
| `pk1` | bigint | No | Surrogate primary key |
| `event_type` | varchar(30) | No | The category of activity — see [Common event_type Values](#common-event_type-values) |
| `user_pk1` | id | Yes | FK to `users.pk1`. Null if the user could not be determined |
| `course_pk1` | id | Yes | FK to `course_main.pk1`. Null if the activity occurred outside a course |
| `group_pk1` | id | Yes | FK to the group table. Null unless the activity is Course Group related |
| `forum_pk1` | id | Yes | FK to the forum table. Null unless the activity occurred in a Discussion Board forum |
| `internal_handle` | varchar(255) | Yes | FK to `navigation_item.internal_handle`. Populated for `PAGE_ACCESS` / `COURSE_ACCESS` events; often blank if the page has no associated navigation item |
| `content_pk1` | id | Yes | FK to `course_contents.pk1`. Populated when `event_type = 'CONTENT_ACCESS'` |
| `data` | nvarchar(255) | Yes | Structured or free-form content depending on `event_type` — see [Common event_type Values](#common-event_type-values) |
| `timestamp` | datetime | Yes | Date/time the event occurred, stored in UTC. **Always filter on this column** |
| `status` | numeric | Yes | `1` = success, `0` = failure |
| `session_id` | id | Yes | FK to the user session that initiated the event. Groups events within a single browser session |
| `ip_address` | ipaddress | Yes | IP address the event originated from |

`user_pk1`, `course_pk1`, `forum_pk1`, `session_id`, and the combination of `event_type` + `timestamp` are all indexed — filtering or joining on these columns is efficient. `content_pk1` also has a dedicated index (`activity_accumulator_icontent`).

---

## Common `event_type` Values

| Value | Meaning |
|---|---|
| `SESSION_INT` | Session was initialized. By row count, this is by far the most common `event_type` in the table — it fires on most requests within a session, not just login. Exclude it from most reporting queries unless you specifically care about raw request volume |
| `LOGIN_ATTEMPT` | A login attempt — check `status` for success/failure. `data` holds `Login succeeded.` on success, or a multi-line failure block on failure (see below) |
| `LOGOUT` | User logged out. `data` holds `Logout succeeded.` |
| `SESSION_TIMEOUT` | Session ended due to inactivity. `data` holds an underscore-wrapped reference to the session, e.g. `_73043137_1`, matching `session_id` |
| `START_IMPERSONATION` | An admin or instructor started impersonating another user (Login As User). `course_pk1` is populated if the impersonation started from within a course context; `data` holds the `pk1` of the impersonated user |
| `COURSE_ACCESS` | A course frameset was loaded, or a page was accessed within a course |
| `CONTENT_ACCESS` | A specific piece of course content was accessed — `content_pk1` is populated. `data` is JSON (see below) |
| `PAGE_ACCESS` | A non-course system page was accessed (tab, module, institution page) |
| `TAB_ACCESS` | A tab or module was accessed — see the `data` column note below |

This is not an exhaustive list; the full set is defined in the `TrackingEvent.Type` enumeration shipped with the LMS. Use the column-search query in the [PostgreSQL & SQL Guide](postgres-sql-guide.md#search-for-a-column-across-all-tables) approach, or run a distinct-values query, to see what's actually present in your environment:

```sql
SELECT event_type, COUNT(1) AS event_count
FROM activity_accumulator
WHERE timestamp >= NOW() - INTERVAL '7 days'
GROUP BY event_type
ORDER BY event_count DESC
```

**Watch out for `data`:** its structure depends entirely on `event_type`, and it's not consistently free text:

- `CONTENT_ACCESS` — a JSON object: `{"handler":"resource/x-bb-folder","title":"ROOT","synthetic":false}`. Nested content includes a `parent` key referencing the parent content item: `{"handler":"resource/x-bb-lesson","title":"Unit 2: ...","parent":"_546504_1","synthetic":false}`.
- `LOGIN_ATTEMPT` — on failure, a multi-line block including the attempted username, e.g.:
  ```
  Login failed : [Validation Summary]
  Status: UserNotFound
  Message: The username or password you typed is incorrect...
  Attempted Username: jsmith
  User Key: null
  Account Locked: f
  ```
  **Security note:** `Attempted Username` echoes back exactly what was submitted at the login form, unsanitized. It can contain malicious input (e.g. script tags) from automated credential-stuffing or scanning attempts. Treat this field as untrusted text — don't render it unescaped in HTML reports or dashboards.
- `PAGE_ACCESS` — a human-readable page title (e.g. `System Configuration`, `Users`) when `internal_handle` is populated, or a raw URL path (e.g. `/webapps/blackboard/blti/launch.jsp`) when it is not.
- `TAB_ACCESS` — a value like `_29_1`, where the first number is the `pk1` of the tab or module being accessed (the trailing `_1` can be ignored).
- Most other event types — treat `data` as supplementary free text rather than a structured field.

**Watch out for `pk1` ordering:** under concurrent load, `pk1` does not strictly correspond to chronological order — rows can be written slightly out of sequence relative to `timestamp`. Always sort and filter on `timestamp`, not `pk1`, when ordering matters.

**Watch out for `ip_address`:** it's frequently null, but it is populated in practice for some `CONTENT_ACCESS` events (observed on assessment/test-link content) — don't assume it's never set just because it's optional.

---

## Query Patterns

### Always Filter by Date

This is the most important rule for this table — without a `timestamp` filter, a query can run indefinitely:

```sql
WHERE timestamp >= NOW() - INTERVAL '30 days'
```

### Daily Active Users

```sql
SELECT
    timestamp::DATE AS activity_date,
    COUNT(DISTINCT user_pk1) AS active_users
FROM activity_accumulator
WHERE timestamp >= NOW() - INTERVAL '30 days'
  AND user_pk1 IS NOT NULL
GROUP BY activity_date
ORDER BY activity_date
```

### Login Success/Failure Summary

```sql
SELECT
    timestamp::DATE AS login_date,
    SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) AS successful_logins,
    SUM(CASE WHEN status = 0 THEN 1 ELSE 0 END) AS failed_logins
FROM activity_accumulator
WHERE event_type = 'LOGIN_ATTEMPT'
  AND timestamp >= NOW() - INTERVAL '30 days'
GROUP BY login_date
ORDER BY login_date
```

### Most-Accessed Content in a Course

```sql
SELECT
    aa.content_pk1,
    COUNT(1) AS access_count
FROM activity_accumulator aa
JOIN course_main cm ON cm.pk1 = aa.course_pk1
WHERE aa.event_type = 'CONTENT_ACCESS'
  AND aa.timestamp >= NOW() - INTERVAL '30 days'
  AND cm.course_id = 'YOUR-COURSE-ID'
GROUP BY aa.content_pk1
ORDER BY access_count DESC
```

### Last Activity per User

`DISTINCT ON` is the cleanest way to get the most recent event per user (see [PostgreSQL & SQL Guide](postgres-sql-guide.md#distinct-on) for details on this pattern):

```sql
SELECT DISTINCT ON (user_pk1)
    user_pk1, course_pk1, event_type, timestamp
FROM activity_accumulator
WHERE timestamp >= NOW() - INTERVAL '90 days'
  AND user_pk1 IS NOT NULL
ORDER BY user_pk1, timestamp DESC
```

---

## `activity_accumulator_queue`

A staging table used internally by the LMS to buffer activity events before they are written to `activity_accumulator`. The LMS moves records out of this queue and into `activity_accumulator` in batches every couple of minutes, not in real time — so if you see unexpectedly low counts in `activity_accumulator` for very recent activity (the last few minutes), it may still be sitting in the queue. If you need up-to-the-second activity, `UNION` the two tables instead of relying on `activity_accumulator` alone:

```sql
SELECT event_type, user_pk1, course_pk1, timestamp
FROM activity_accumulator
WHERE timestamp >= NOW() - INTERVAL '1 day'
UNION ALL
SELECT event_type, user_pk1, course_pk1, timestamp
FROM activity_accumulator_queue
```

---

## Performance Tips

- Filter on `timestamp` in every query — there is no substitute for this.
- Prefer filtering on indexed columns (`user_pk1`, `course_pk1`, `forum_pk1`, `session_id`, `content_pk1`, `event_type` + `timestamp`) over `data` or `internal_handle`, which are not indexed.
- `user_pk1` and `course_pk1` are both nullable — exclude nulls explicitly if you only want identified or in-course activity.
- For multi-year trend queries, query the `_stats` database directly rather than relying on `dblink` for every row — aggregate remotely and bring back only the summarized result. See Example 2 in [Cross-Database Joins](dblink.md#example-2-course-activity-summary-beyond-180-days).
- Use `EXPLAIN ANALYZE` if a query against this table feels slow — see [Query Performance](postgres-sql-guide.md#query-performance) in the SQL guide.

---

This is a supplemental community resource. Content is the property of Blackboard, Inc. and is provided without official support or endorsement. Always refer to official Blackboard documentation and your institution's agreements.
