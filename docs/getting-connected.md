---
meta-viewport: width=device-width,initial-scale=1
title: Getting Connected to DDA
---

# Getting Connected to DDA

[← Back to Overview](index.md)

DDA gives you read-only access to a near real-time replica of your Blackboard LMS database — never the production database itself. To connect, you'll need credentials provided by Blackboard and a client tool that supports PostgreSQL over SSL.

---

## What You'll Need from Blackboard

When your institution activates DDA, Blackboard provides:

- **Hostname** — the address of your read replica
- **Port** — always `5432`
- **Username and Password** — you can request up to 5 separate credential sets
- **SSL Certificate** — required for all connections ([download from AWS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html#UsingWithRDS.SSL.CertificatesAllRegions))

---

## IP Whitelisting

DDA access is restricted to a fixed list of whitelisted IP addresses. Blackboard will ask you to provide up to five source IP addresses at setup — only connections from those addresses will be accepted.

To find your machine's IP, visit [checkip.amazonaws.com](http://checkip.amazonaws.com/). If you use a VPN such as Zscaler, disable it first or you may get the VPN's egress address instead of your machine's actual IP.

**This is the most important constraint to understand before choosing how to connect.** Tools that run on your machine or a server at a known fixed IP — pgAdmin, DBeaver, Python scripts — work straightforwardly. Cloud-hosted services like Power BI Service, scheduled cloud pipelines, or any SaaS tool use dynamic or shared IP ranges that cannot be whitelisted directly. Those scenarios require a different approach, covered in the [Cloud Services](#cloud-services) section below.

---

## Client Tools

These tools run on your local machine or a server with a fixed IP and connect directly to DDA.

### pgAdmin

pgAdmin is the tool covered in Blackboard's official documentation and is a good starting point. It is free and available for Mac and Windows.

> **Note:** Blackboard does not provide technical support for pgAdmin or any third-party client tool.

**Before you begin:**
- Download and install [pgAdmin](https://www.pgadmin.org/download/)
- Download and save the [AWS SSL certificate bundle](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html#UsingWithRDS.SSL.CertificatesAllRegions) (the `.pem` file — pgAdmin will convert it automatically)

**Create a new server connection:**

1. Open pgAdmin and select the plug icon to add a new server
2. On the **General** tab, give the connection any name you like
3. On the **Connection** tab, enter:
   - **Host:** your DDA hostname from Blackboard
   - **Port:** `5432`
   - **Maintenance DB:** `postgres`
   - **Username / Password:** from Blackboard
4. On the **SSL** tab:
   - Set **SSL** to `Require`
   - Set **Server Root Certificate** to the path of your downloaded `.pem` file
5. Select **Save**

Once connected, select your database from the browser, open the Query Tool, and run a test query such as `SELECT COUNT(*) FROM users;`.

---

### DBeaver

DBeaver is a popular cross-platform client that many report writers prefer for its query editor and data export options.

1. Create a new connection and select **PostgreSQL**
2. Enter your hostname, port (`5432`), database name, username, and password
3. On the **SSL** tab, enable SSL and set the mode to `require`
4. Point the **Root certificate** field to your downloaded `.pem` file
5. Test the connection and save

---

### Python (psycopg2)

For scripted reporting or data pipelines running on a server with a fixed IP, `psycopg2` is the standard PostgreSQL library for Python.

**Install:**
```bash
pip install psycopg2-binary
```

**Connect:**
```python
import psycopg2

conn = psycopg2.connect(
    host="your-dda-hostname",
    port=5432,
    dbname="BB<deployment_id>",
    user="your-username",
    password="your-password",
    sslmode="require",
    sslrootcert="/path/to/rds-combined-ca-bundle.pem"
)

cursor = conn.cursor()
cursor.execute("SELECT user_id, firstname, lastname FROM users LIMIT 10")
rows = cursor.fetchall()
for row in rows:
    print(row)

cursor.close()
conn.close()
```

For longer-running scripts, consider using a connection pool (`psycopg2.pool`) or a library like `SQLAlchemy` to manage connections more efficiently.

---

## Cloud Services

Cloud-hosted tools cannot connect to DDA directly because their outbound IP addresses are dynamic or shared across many customers and cannot be whitelisted. The following patterns solve this.

### Pattern 1: Scheduled Extract to an Intermediate Store

The most common and broadly applicable approach. A script runs on a machine with a whitelisted fixed IP, queries DDA on a schedule, and writes the results to an intermediate store that your cloud tool can access freely.

```
DDA → [fixed-IP server] → intermediate store → Power BI / cloud tool
```

Good intermediate store options depending on your environment:

- **Azure SQL or Azure Blob Storage** — works well with Power BI, straightforward to automate with Python or Azure Data Factory
- **SharePoint / OneDrive** — accessible to most Microsoft 365 environments; works well for smaller datasets delivered as Excel or CSV files
- **AWS S3 or RDS** — if your institution runs workloads in AWS
- **On-premise database or file share** — simplest option if infrastructure already exists

This pattern works for any cloud tool, not just Power BI, and keeps DDA credential management simple since only the extract server needs access.

---

### Pattern 2: Power BI On-Premises Data Gateway

Microsoft's supported solution for connecting Power BI Service to IP-restricted or on-premise databases. The gateway runs as a service on a machine at your institution with a fixed, whitelisted IP. Power BI Service communicates with the gateway, and the gateway handles the DDA connection.

**How it works:**
1. Install the [Power BI On-Premises Data Gateway](https://powerbi.microsoft.com/en-us/gateway/) on a machine with a whitelisted IP
2. Register the gateway with your Power BI tenant
3. In Power BI Desktop, build your report connecting directly to DDA (this works from your local machine if its IP is also whitelisted)
4. Publish the report to Power BI Service
5. Configure the dataset in Power BI Service to use the gateway for scheduled refresh

The gateway machine's IP is what gets whitelisted — not Power BI's cloud infrastructure.

> **Note:** The gateway machine needs to stay online with the gateway service running for scheduled refreshes to work. Treat it as reporting infrastructure, not a personal workstation.

---

### Pattern 3: Fixed Egress via NAT Gateway

If your institution runs workloads in a cloud environment (AWS, Azure, GCP), you can route DDA connections through a NAT gateway configured with a fixed elastic IP. That IP gets whitelisted, and any service in your cloud environment that routes through the NAT can reach DDA.

This is the right approach if you are building automated pipelines in cloud infrastructure rather than running scripts on an on-premise server.

---

## Tips

- **Test with a simple query first** — `SELECT COUNT(*) FROM users;` confirms your connection before running anything complex.
- **Data is near real-time** — there is a short replication lag from production, typically seconds to a few minutes.
- **All connections are read-only** — `INSERT`, `UPDATE`, and `DELETE` statements will be rejected.
- **SSL is required** — connections without SSL will fail.
- **Credential sets are independent** — request separate username/password sets from Blackboard (up to 5 total) to keep audit trails clean across users and services.

---

This is a supplemental community resource. Content is the property of Blackboard, Inc. and is provided without official support or endorsement. Always refer to official Blackboard documentation and your institution's agreements.
