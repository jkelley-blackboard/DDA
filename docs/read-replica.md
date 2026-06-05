---
meta-viewport: width=device-width,initial-scale=1
title: Understanding the Read Replica
---

# Understanding the Read Replica

[← Back to Overview](index.md)

DDA does not give you access to the Blackboard production database. Instead, it connects you to a **read replica** — a continuously updated copy that runs on separate hardware. Understanding what that means will save you a lot of confusion when writing queries and interpreting results.

---

## What Is a Read Replica?

A read replica is a database that automatically receives changes from the production database in near real-time. Blackboard uses AWS RDS read replicas, which means:

- Data is typically a few seconds to a few minutes behind production
- The replica is always read-only — you cannot insert, update, or delete data
- It runs on production-equivalent hardware, so query performance is generally good
- It is a complete copy of the production database — all tables and columns are present, even those not documented in the schema packages

The separation between production and the replica is intentional. Your queries, even expensive ones, cannot impact the performance of the live Blackboard environment your users are accessing.

---

## Data Lag

The replication lag is usually small — often just seconds — but it is not zero. For most reporting purposes this is irrelevant. However, it is worth keeping in mind when:

- Comparing DDA results to something you just changed in the Blackboard UI
- Running reports immediately after a large data load or SIS sync
- Investigating a very recent event (within the last few minutes)

If your results look slightly off, wait a moment and re-run. The data will catch up.

---

## Read-Only Access

Every DDA connection is read-only by design. Any attempt to run `INSERT`, `UPDATE`, `DELETE`, or DDL statements will be rejected. This is a hard constraint enforced at the database level, not just a policy.

Practical implications:

- You cannot create tables, views, or indexes in the DDA database
- You cannot use DDA to fix or modify data — changes must go through the Blackboard UI or a supported integration
- Temporary tables may work in some client tools within a session, but should not be relied upon

---

## The 180-Day Activity Window

The `activity_accumulator` table in the primary database is **truncated to approximately 180 days**. This is the most important data retention limit to know about.

If you need activity data older than 180 days, it lives in the `BB<deployment_id>_stats` database, which retains a permanent copy. Querying across databases requires `dblink` — see the [Cross-Database Joins](dblink.md) page for examples.

---

## What Is and Isn't Documented

The schema packages document the majority of tables and columns, but not everything. Notably absent from the official documentation:

- Stored procedures, views, triggers, and database jobs
- Detailed commentary for some tables and columns
- Some internal system tables

This does not mean those objects don't exist — they do. It means you may encounter undocumented tables when exploring. Use the [Expanded Schema Explorer](https://jkelley-blackboard.github.io/DDA/schema-4000.17.0/schema/index.html) for the most complete picture, and the community resources below when you hit a gap.

### Tables You Can See But Cannot Query

When browsing the schema in a client tool, you may see tables that return a permission error when you attempt to query them. This typically happens when Blackboard has added new tables to the schema since your DDA account was provisioned — your account was not automatically granted access to them.

If you encounter this, a **schema refresh** of your DDA account is needed. See the [Schema Refresh and Permissions](index.md#schema-refresh-and-permissions) section on the main page for how to request this through Blackboard support.

---

## Multiple Databases

Your DDA access spans five databases, not one. Each has a distinct purpose and must be connected to separately. See the [DDA Database Overview](index.md#dda-database-overview) on the main page for a full breakdown.

The most commonly used are:

- **`BB<deployment_id>`** — primary database, used for almost all reporting
- **`BB<deployment_id>_stats`** — long-term activity data, ODS tables for analytics

---

## Common Misconceptions

**"I changed something in Blackboard — why doesn't it show up yet?"**
Replication lag. Wait a minute and re-run your query.

**"I can see a table in my client but get a permission error when I query it."**
This usually means the table was added after your DDA account was provisioned. A schema refresh from Blackboard support will resolve it. See [Schema Refresh and Permissions](index.md#schema-refresh-and-permissions).

**"I can't find this table in the schema docs."**
Not all tables are documented. Try browsing the Schema Explorer directly, or ask in the [Blackboard Techies Slack](https://blackboardtechies.slack.com/archives/CFAEA8KD3).

**"My query is affecting Blackboard performance."**
It cannot. The replica is completely separate from production. Run your queries freely.

**"I need activity data from two years ago."**
Query `activity_accumulator` in `BB<deployment_id>_stats` via `dblink`. See [Cross-Database Joins](dblink.md).

**"I need to write data back to Blackboard via DDA."**
Not possible. Use the Blackboard REST API or a supported SIS integration instead.

---

This is a supplemental community resource. Content is the property of Blackboard, Inc. and is provided without official support or endorsement. Always refer to official Blackboard documentation and your institution's agreements.
