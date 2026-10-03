---
meta-viewport: width=device-width,initial-scale=1
title: Schema Changes
---

# Schema Changes

[← Back to Overview](index.md)

This page records how the DDA schema changes from one release to the next, based on Blackboard's published schema documentation. Newest changes are at the top.

**How releases are compared.** Blackboard publishes a schema package to [bbprepo](https://bbprepo.blackboard.com/#browse/browse:releases:bbdn%2fschema) for every build, but not every build is a release. Only some builds are released to Test/Stage and then Production (see the [Blackboard release schedule](https://help.anthology.com/blackboard/)). This site follows the Test/Stage releases, so the [Schema Explorer](index.md#expanded-schema-explorer) is never ahead of what institutions can see on their own Test/Stage servers. Each entry below compares one Test/Stage release with the next one published here, so any builds in between are folded into that entry.

**What is compared.** Tables, columns (name, data type, nullability and allowed values), foreign keys and indexes. Changes to descriptions are not listed. The schema group is the folder Blackboard's documentation files a table under; it is not a PostgreSQL schema (every DDA table is in `public`).

**Content that may need review.** When a table or column is removed, the entry lists any SQL scripts or pages on this site that mention it.

<!-- New entries are added below this line by tools/update_schema.py -->

## 4001.2.0 (from 4000.19.0)

Updated 2026-09-29. Compares the 4000.19.0 and 4001.2.0 Test/Stage releases. The 4000.21.0 and 4001.0.0 releases, and the builds between them, were not published here on their own, so their changes are included here.

758 → 760 tables: 3 added, 1 removed, 0 moved, 8 changed.

### Tables added

| Table | Schema group | Description |
|---|---|---|
| `lti_pns_deliveries` | blti | This table tracks asynchronous delivery attempts for LTI Platform Notification Service notices. |
| `lti_pns_subscriptions` | blti | This table stores per-tool, per-deployment handler registrations for LTI Platform Notification Service notice types. |
| `course_contents_jf_links_description_backup` | crs_content | Backup table to preserve description data from journal link, forum link, and course link (discussion) content items before removal by RemoveDescriptionFromJournalForumLinksUpgradeListener. AB-685876: Drop this table once clients confirm the data is not needed. |

### Tables removed

| Table | Schema group |
|---|---|
| `dead_node` | as_core |

### Tables changed

| Table | Change |
|---|---|
| `rubric` (as_core) | Added column `content_hash` (varchar(64)) |
| `users` (as_core) | Added index `idx_users_lastname_lc_icu` |
| `proctoring_service` (assessment) | Added column `respondus_lti13_dash_handle` (varchar(32))<br>Added index `proc_service_ak3` |
| `blti_domain_config` (blti) | Added column `issuer` (varchar(1024)) |
| `course_msg` (course_messages) | Added column `receivers_jsonb` (jsonb) |
| `gradebook_settings` (gradebook) | Added column `show_last_access_ind` (char(1))<br>Added column `show_user_name_ind` (char(1)) |
| `eud_item` (nautilus) | Added column `secondary_date` (datetime) |
| `scormregistration` (scormengine_b2) | Added index `scormregistration_bmh2` |

---

This is a supplemental community resource. Content is the property of Blackboard, Inc. and is provided without official support or endorsement. Always refer to official Blackboard documentation and your institution's agreements.
