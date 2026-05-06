---
meta-viewport: width=device-width,initial-scale=1
title: Key Tables Guide
---

# Key Tables Guide

[← Back to Overview](index.md)

The Blackboard database contains hundreds of tables. This guide covers the most important ones for the four most common reporting areas. Each section describes what the table contains, what to watch out for, and the most common tables it joins to.

> **A note on database naming:** Older documentation, community resources, and SQL examples — including some in this repository — may reference database names like `bb_bb60` or `BBLEARN`. These were the database names used in self-hosted and managed-hosted Blackboard deployments. In SaaS environments, these are equivalent to your `BB<deployment_id>` database. If you see `bb_bb60` or `BBLEARN` in a query or schema reference, treat it as referring to your primary DDA database.

For ready-to-use queries, see the [SQL Library](https://github.com/jkelley-blackboard/DDA/tree/main/sql_library).

For full column-level detail, use the [Expanded Schema Explorer](https://jkelley-blackboard.github.io/DDA/schema-4000.15.0/schema/index.html).

---

## Common Fields

Many tables in the Blackboard schema share a consistent set of columns. Understanding these fields once will save time when working across the schema. These fields are most consistently found on **entity tables** (courses, users, terms, enrollments). Simpler relationship and mapping tables may have only a subset, or none of them.

---

### PK1

Every table uses `pk1` as its surrogate primary key — a system-generated integer with no inherent business meaning. It is the standard join column across the schema.

`pk1` values surface in other contexts you may already be familiar with:
- In the **browser address bar**, the format `_##_1` corresponds directly to the `pk1` value. For example, a course with `pk1 = 42` will appear as `_42_1` in the URL.
- In the **REST API**, the `id` field returned for most objects is the `pk1` in this same `_##_1` format.

> Do not rely on `pk1` values being consistent across environments (e.g., production vs. test). Use `batch_uid` or natural keys like `course_id` / `user_id` for cross-environment references.

---

### ROW_STATUS

Controls the lifecycle state of a record.

| Value | Meaning |
|-------|---------|
| 0 | Enabled — normal active record |
| 1 | Undefined — treat as inactive |
| 2 | Disabled — record exists but is inactive |
| 3 | In process of being deleted — transient, do not rely on records in this state persisting |

Most queries should filter on `row_status = 0` unless you specifically need disabled or inactive records. Status 3 is temporary and records in this state are expected to be removed shortly.

---

### AVAILABLE_IND

A `Y`/`N` flag indicating availability to end users. Distinct from `row_status` — a record can be enabled (`row_status = 0`) but still unavailable. The precise meaning depends on the table:

- On `course_main` — controls whether the course is visible to students. Ignored if `honor_term_avail_ind = 'Y'`, in which case the associated term's availability takes precedence.
- On `users` — determines whether the user can log in.
- On `course_users` — determines whether the user can access the specific course.

For active course queries, filtering on both is common:
```sql
WHERE cm.row_status = 0
  AND cm.available_ind = 'Y'
```

To surface a human-readable status combining both fields:
```sql
CASE
  WHEN row_status = 2 THEN 'Disabled'
  WHEN row_status = 3 THEN 'Deleting'
  WHEN row_status = 0 AND available_ind = 'Y' THEN 'Available'
  WHEN row_status = 0 AND available_ind = 'N' THEN 'Unavailable'
  ELSE 'Undefined'
END AS status
```

---

### DTCREATED / DTMODIFIED

Audit timestamps recording when a record was created and last modified. Both are stored in UTC.

- `dtcreated` is present on most entity tables but not all — notably absent from `term` and `course_users`.
- `dtmodified` is more consistently present across tables.
- On `course_users`, be aware that `dtmodified` is updated by `last_access_date` changes. A separate `date_last_modified` column exists that excludes access-date updates if you need to track true record changes.

```sql
WHERE dtmodified >= CURRENT_DATE - INTERVAL '7 days'
```

---

### BATCH_UID

A stable external identifier, primarily used for SIS integration. On entity tables like `course_main` and `users`, it represents the record's ID in the external system. For internally-created records it typically matches the natural key (e.g., `course_id`).

On relationship tables like `course_hierarchy`, `batch_uid` is only populated when the record was created by a SIS feed — it will be `NULL` for records created within Learn.

> Prefer `batch_uid` over `pk1` for any cross-environment references or SIS-related queries.

---

### DATA_SRC_PK1

A foreign key to the `data_source` table, indicating the origin of the record (e.g., a specific SIS feed, manual entry, or API). Useful for filtering records by their source or auditing data provenance. The default value of `2` represents the internal Blackboard data source.

---

### UUID

A system-generated unique identifier present on key entity tables including `course_main` and `users`. Used in LTI integrations — sent as `context_id` in course LTI launches and as `user_id` in user LTI launches. Less commonly needed for general reporting queries.

---

## Courses & Terms

### `course_main`

The primary table for all courses and organizations in Blackboard. Every course has one row here.

Key columns:
- `pk1` — internal primary key, used to join to most other course-related tables
- `course_id` — the human-readable course identifier (e.g. `ENG101-2026SP`)
- `course_name` — display name of the course
- `row_status` — `0` (enabled), `2` (disabled), `3` (deleted)
- `available_ind` — `Y` or `N`, whether the course is available to students
- `service_level` — the type of record stored in this row (see below)
- `ultra_status` — `U` (Ultra), `C` (Classic/Original), `N` (no decision yet)

**`service_level` values — this is the critical filter column:**

| Value | Type |
|---|---|
| `F` or `C` | Course or Organization |
| `J` | Subject |
| `P` | Program |
| `S` | System (pk1 = 1) |
| `O` | Learning Object Repository (LOR) |

For most academic reporting, filter by `service_level IN ('F', 'C')` to return courses and organizations, excluding programs, subjects, LORs, and system records.

**Watch out for:** `course_type` exists in this table but refers to academic classification (Undergraduate, Graduate, etc.) — it is **not** the column to use for filtering out non-course records. Use `service_level` for that.

Commonly joined to: `course_users`, `course_hierarchy`, `term` (via `course_term`), `domain_course_coll`, `mi_node`

---

### `course_hierarchy`

Defines the hierarchical relationships between records in `course_main` — connecting Programs, Subjects, and Courses. This is the table that lets you navigate the curricular structure.

Key columns:
- `container_crsmain_pk1` — foreign key to `course_main` for the **parent** record
- `contained_crsmain_pk1` — foreign key to `course_main` for the **child** record
- `distance` — level of containment: `1` = direct, `2` = indirect

The hierarchy works like this:

```
Program (P)
│
├── Subject (J) [distance = 1 from Program]
│   └── Course/Org (F/C) [distance = 1 from Subject]
│
└── Course/Org (F/C) [distance = 2 from Program, via Subject]
```

So a Course appears twice in `course_hierarchy` relative to its Program — once at distance 1 from its Subject, and once at distance 2 from the Program. Use `distance = 1` for direct parent-child relationships only.

**Example — find all courses directly under a subject:**
```sql
SELECT cm.course_id, cm.course_name
FROM course_hierarchy ch
JOIN course_main cm ON cm.pk1 = ch.contained_crsmain_pk1
WHERE ch.container_crsmain_pk1 = (SELECT pk1 FROM course_main WHERE course_id = 'YOUR-SUBJECT-ID')
  AND ch.distance = 1
  AND cm.service_level IN ('F', 'C')
```

**Example — find the program a course belongs to:**
```sql
SELECT program.course_id AS program_id, program.course_name AS program_name
FROM course_hierarchy ch
JOIN course_main program ON program.pk1 = ch.container_crsmain_pk1
WHERE ch.contained_crsmain_pk1 = (SELECT pk1 FROM course_main WHERE course_id = 'YOUR-COURSE-ID')
  AND program.service_level = 'P'
```

**Watch out for:** Because a course relates to its program at distance 2 (via subject), joining without a `distance` filter will return duplicate rows — one for the subject relationship and one for the program relationship. Always filter on `distance` for the level of hierarchy you need.

Commonly joined to: `course_main`

---

### `term`

Defines the terms (semesters) configured in Blackboard.

Key columns:
- `pk1` — primary key
- `name` — display name of the term
- `sourcedid_id` — the external identifier, set by SIS feed or autogenerated for terms created within Learn
- `start_date`, `end_date` — term date range

**Watch out for:** Courses are linked to terms via the `course_term` junction table, not via a direct foreign key on `course_main`. Not all courses are assigned to a term — organization courses, shell courses, and older content that predates term configuration at your institution will have no entry in `course_term`.

Commonly joined to: `course_main` (via `course_term`)

---

### `domain_course_coll` and `domain`

These two tables together connect courses to the institutional hierarchy (nodes). `domain_course_coll` is a junction table between courses and domains; `domain` links domains to `mi_node`.

Key columns on `domain_course_coll`:
- `course_main_pk1` — foreign key to `course_main`
- `domain_pk1` — foreign key to `domain`
- `primary_ind` — `Y` if this is the primary node assignment for the course; add `WHERE primary_ind = 'Y'` to avoid duplicate course rows when joining

**Watch out for:** Courses can be associated with multiple nodes. Without filtering on `primary_ind = 'Y'` you will get one row per node assignment, which multiplies your course counts.

Commonly joined to: `course_main`, `domain`, `mi_node`

---

## Users & Enrollment

### `users`

The primary table for all user accounts in Blackboard.

Key columns:
- `pk1` — internal primary key
- `user_id` — the username used to log in
- `firstname`, `lastname` — display name
- `email` — personal email address
- `inst_email` — institutional email address
- `student_id` — institution-assigned student ID (not enforced as unique)
- `row_status` — numeric: `0` (enabled), `1` (undefined/deleted), `2` (disabled)
- `available_ind` — `Y` or `N`, whether the user can log in
- `system_role` — system-level role: `N` (none), `Z` (system administrator), `BB_LE_ADMIN` (learning environment administrator), `U` (guest), `O` (observer), and others
- `last_login_date` — last time the user logged in
- `institution_roles_pk1` — foreign key to `institution_roles` for the user's primary institutional role

**Watch out for:** Like `course_main` and `course_users`, `row_status` is numeric — filter on `row_status = 0` for enabled accounts. `available_ind` is separate — an account can be enabled but unavailable (`available_ind = 'N'`), which prevents login. System accounts, integration accounts, and guest accounts all live in this table alongside real users. The `email` and `inst_email` fields are separate — many institutions populate one but not the other.

Commonly joined to: `course_users`, `activity_accumulator`

---

### `course_users`

The enrollment table — one row per user per course enrollment.

Key columns:
- `pk1` — primary key
- `crsmain_pk1` — foreign key to `course_main`
- `users_pk1` — foreign key to `users`
- `role` — enrollment role: `S` (student), `P` (instructor), `T` (teaching assistant), `G` (grader), `B` (course builder), `U` (guest)
- `row_status` — numeric: `0` (enabled), `1` (pending delete), `2` (disabled)
- `available_ind` — `Y` or `N`, whether the user can currently access the course
- `enrollment_date` — when the user was enrolled
- `last_access_date` — last time the user accessed the course via the Blackboard UI
- `child_crsmain_pk1` — if the user is enrolled in a child course within a cross-listed set, this references the actual child course

**Watch out for:** `row_status` is numeric — filter on `row_status = 0` for active enrollments. Also note `available_ind` is separate from `row_status` — a user can have `row_status = 0` but `available_ind = 'N'`, meaning the enrollment exists but the user cannot access the course. For most reporting, filter both: `row_status = 0 AND available_ind = 'Y'`.

For cross-listed courses, enrolled users appear in the master course record. `child_crsmain_pk1` identifies which child course they actually enrolled in directly.

Commonly joined to: `users`, `course_main`

---

## Grades & Assessments

> ⚠️ Grade table names and column names have not yet been verified against the schema. This section will be added once confirmed. Use the [Schema Explorer](https://jkelley-blackboard.github.io/DDA/schema-4000.15.0/schema/index.html) in the meantime.

---

## Activity & Engagement

### `activity_accumulator`

Records every tracked user interaction in Blackboard — page views, content access, logins, logouts, and more. One row per event.

Key columns:
- `pk1` — primary key (bigint — this is a very large table)
- `user_pk1` — foreign key to `users` (nullable — can be null if the user cannot be determined)
- `course_pk1` — foreign key to `course_main` (nullable — null for activity outside a course)
- `content_pk1` — foreign key to course content accessed (nullable — populated for `CONTENT_ACCESS` events)
- `timestamp` — date and time the event occurred
- `event_type` — the type of activity, e.g. `COURSE_ACCESS`, `CONTENT_ACCESS`, `LOGIN_ATTEMPT`, `LOGOUT`, `TAB_ACCESS`, `PAGE_ACCESS`, `SESSION_TIMEOUT`
- `session_id` — groups events within a single user session
- `status` — `1` (success) or `0` (failure)
- `ip_address` — IP address from which the event was generated

**Watch out for:** The date column is `timestamp`, not `activity_date` — always use `timestamp` in your filters. This is the largest table in the database and must always be filtered by date range or queries will run indefinitely:

```sql
WHERE timestamp >= NOW() - INTERVAL '30 days'
```

`user_pk1` and `course_pk1` are both nullable. Exclude nulls when joining to `users` or `course_main` if you only want identified, in-course activity. In the primary database this table is truncated to approximately 180 days. For historical data, query `activity_accumulator` in `BB<deployment_id>_stats` via `dblink` — see [Cross-Database Joins](dblink.md).

Commonly joined to: `users`, `course_main`

---

## Common Join Patterns

These are the most frequently used joins across all four areas:

**Enrolled students in a course:**
```sql
SELECT u.user_id, u.firstname, u.lastname
FROM course_users cu
JOIN users u ON u.pk1 = cu.users_pk1
JOIN course_main cm ON cm.pk1 = cu.crsmain_pk1
WHERE cm.course_id = 'ENG101-2026SP'
  AND cu.role = 'S'
  AND cu.row_status = 0
  AND cu.available_ind = 'Y'
```

**Recent activity by course:**
```sql
SELECT cm.course_id, COUNT(*) AS event_count
FROM activity_accumulator aa
JOIN course_main cm ON cm.pk1 = aa.course_pk1
WHERE aa.timestamp >= NOW() - INTERVAL '30 days'
  AND aa.course_pk1 IS NOT NULL
GROUP BY cm.course_id
ORDER BY event_count DESC
```

---

This is a supplemental community resource. Content is the property of Blackboard, Inc. and is provided without official support or endorsement. Always refer to official Blackboard documentation and your institution's agreements.
