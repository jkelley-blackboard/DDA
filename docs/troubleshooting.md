---
meta-viewport: width=device-width,initial-scale=1
title: Troubleshooting DDA Connections
---

# Troubleshooting DDA Connections

[← Back to Overview](index.md)

This page covers the most common problems encountered when connecting to and querying DDA. If you have a real-world example that would help others, contributions are welcome via the [repository](https://github.com/jkelley-blackboard/DDA).

---

## A Note on Network Issues

DDA connects over your institution's network infrastructure — firewalls, proxies, VPNs, and routing rules that Blackboard has no visibility into or control over. Blackboard support can confirm that your credentials are valid and your IP is whitelisted, but they cannot diagnose why your campus firewall is dropping port 5432 traffic or why your VPN is routing connections through the wrong address.

If you have confirmed your IP is whitelisted and your credentials are correct but still cannot connect, the next step is your institution's network or IT team — not Blackboard support.

---

## Connection Problems

### Can't Connect at All

Work through this checklist before contacting support:

- **Is your IP whitelisted?** Visit [checkip.amazonaws.com](http://checkip.amazonaws.com/) from the machine you are connecting from and confirm the IP matches what was submitted to Blackboard. Disable any VPN first.
- **Is SSL enabled?** DDA requires SSL. Connections without it will be rejected silently or with a generic error.
- **Is port 5432 open?** Your institution's firewall may block outbound connections on port 5432. Ask your network team to confirm the port is open to the DDA hostname.
- **Is the hostname correct?** Copy it directly from the credentials Blackboard provided — do not retype it.
- **Is the database name correct?** The database name is case-sensitive. `BB<deployment_id>` must match exactly.

---

### VPN Interference

VPNs are a common source of DDA connection problems in two ways:

- **Wrong IP whitelisted** — if you were on a VPN when you identified your IP address for whitelisting, the VPN's egress IP was submitted rather than your machine's actual IP. When you connect without the VPN, your real IP is different and gets rejected. Always disable your VPN when visiting [checkip.amazonaws.com](http://checkip.amazonaws.com/) to find the IP to whitelist.
- **VPN routes DDA traffic through a different address** — some VPNs route all traffic through a shared egress that changes or differs from your machine's IP. If you need to connect through a VPN, work with your network team to identify the stable egress IP to whitelist, or use one of the cloud service patterns on the [Getting Connected](getting-connected.md) page.

A useful test: if DDA works from one location but not another (office vs. home, VPN on vs. off), the issue is almost certainly IP-related rather than credentials or SSL.

---

### SSL Certificate Errors

- **pgAdmin can't find the certificate** — pgAdmin sometimes loses the path to the `.pem` file after an upgrade. Re-open the server properties, go to the SSL tab, and re-browse to the certificate file.
- **Certificate not trusted** — make sure you are using the current [AWS RDS certificate bundle](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html#UsingWithRDS.SSL.CertificatesAllRegions). Older bundles may have expired.
- **Wrong file** — the file should be `rds-combined-ca-bundle.pem`. pgAdmin will convert it to `.crt` automatically; you do not need to convert it manually.

---

### Credentials Rejected

- Confirm the username and password are exactly as provided — both are case-sensitive
- Confirm you are connecting to the correct database (`BB<deployment_id>`, not `postgres`)
- If credentials have recently been refreshed (due to a schema refresh), make sure all tools and scripts are updated with the new password
- Remember you can have up to 5 separate credential sets — make sure you are using the right one for the environment you are connecting from

---

### Connection Timeout

A silent timeout (connection hangs then drops) is almost always a network issue — a firewall dropping the packets rather than rejecting the connection outright. This is distinct from a refused connection, which fails immediately.

- Confirm port 5432 is open to the DDA hostname on your outbound firewall
- If connecting through a proxy, confirm the proxy supports persistent TCP connections on non-standard ports
- This is network infrastructure territory — Blackboard support cannot diagnose this on your behalf

---

## Data Problems

### Query Returns No Rows

- **Replication lag** — if you are querying data that was just changed in Blackboard, wait a moment and re-run. Lag is usually seconds but can be a few minutes.
- **Wrong database** — `activity_accumulator` exists in both the primary database and `_stats`, but with different retention windows. Make sure you are querying the right one for your time range.
- **Unexpected filter** — check your WHERE clause carefully. A date filter using `NOW()` behaves differently if your client is in a different timezone than expected.

---

### Table Visible But Permission Denied

You can see the table in your client's schema browser but get a permission error when you query it. This means the table was added to the schema after your DDA account was provisioned and your account was not automatically granted access.

A **schema refresh** is needed — see [Schema Refresh and Permissions](index.md#schema-refresh-and-permissions) for how to request this through Blackboard support.

---

### Unexpected Nulls

Many columns in the Blackboard schema are sparsely populated — they exist for all rows but only contain values when a specific feature is in use at your institution. If a column returns mostly nulls, check the schema documentation to understand when it is populated before assuming a data problem.

---

### Results Look Stale

- For recent activity, check the replication lag explanation on the [Read Replica](read-replica.md) page
- For activity older than 180 days missing from your results, you need to query `BB<deployment_id>_stats` via `dblink` — see [Cross-Database Joins](dblink.md)

---

## Tool-Specific Issues

### pgAdmin

- **SSL cert path lost after upgrade** — re-open server properties → SSL tab → re-browse to the `.pem` file
- **Query editor is slow on large tables** — add a `LIMIT` clause while exploring. `activity_accumulator` in particular can be very large.

### Power BI

- **Scheduled refresh fails in Power BI Service** — the most common cause is the on-premises gateway service not running. Check that the gateway machine is online and the gateway service is started. Also confirm the gateway machine's IP has not changed.
- **Npgsql driver missing** — Power BI Desktop's PostgreSQL connector requires the [Npgsql driver](https://github.com/npgsql/npgsql/releases). Install it and restart Power BI Desktop if the PostgreSQL connector is unavailable.
- **DirectQuery times out** — for large datasets, switch to Import mode with scheduled refresh rather than DirectQuery.

### Python

- **Script works interactively but fails as a scheduled job** — check the path to the `.pem` SSL certificate. An absolute path that works in your user session may not resolve correctly when the script runs as a service or cron job. Use an absolute path and confirm the file is readable by the service account running the job.
- **Connection pool exhausted** — if running many concurrent queries, use `psycopg2.pool.ThreadedConnectionPool` and close connections properly after each query.

### DBeaver

- **Connection drops on large queries** — increase the connection timeout in DBeaver's connection settings under **Connection Details → Connection → Keep-Alive**.

---

## Performance

### Query Runs Forever

A few tables in the DDA are very large and will run indefinitely without appropriate filters:

- `activity_accumulator` — always filter by date range: `WHERE timestamp >= NOW() - INTERVAL '30 days'`
- `activity_accumulator` in `_stats` — even more important to filter here as it contains the full historical record
- `bb_bb60_attempt` and similar gradebook tables — filter by course or date where possible

If a query is taking much longer than expected, check whether it is missing a WHERE clause on a high-volume table.

### Diagnosing Slow Queries

Use `EXPLAIN` to understand how PostgreSQL is planning your query before running it on a large dataset:

```sql
EXPLAIN
SELECT user_id, firstname, lastname
FROM users
WHERE row_status = '2';
```

This shows the query plan without executing it, helping identify missing indexes or full table scans.

---

This is a supplemental community resource. Content is the property of Blackboard, Inc. and is provided without official support or endorsement. Always refer to official Blackboard documentation and your institution's agreements.
