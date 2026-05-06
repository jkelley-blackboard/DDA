---
meta-viewport: width=device-width,initial-scale=1
title: Working with DDA
---

# Working with DDA

[View Repository](https://github.com/jkelley-blackboard/DDA)

### Navigation

- [Official Docs](#official-docs)
- [Schema Packages](#schema-changes)
- [Schema Explorer](#schema-explorer)
- [Repository](#repository)
- [DDA Database Overview](#dda-overview)
- [Cross-Database Joins](#dblink-joins)
- [Getting Connected](getting-connected.md)
- [Understanding the Read Replica](read-replica.md)
- [Key Tables Guide](key-tables.md)
- [Troubleshooting](troubleshooting.md)

This site provides documentation and resources for working with Blackboard's **Direct Data Access (DDA)** service.

## Official Documentation

Visit the official Blackboard Help page for DDA:  
[Direct Data Access - Blackboard Help](https://help.anthology.com/blackboard/administrator/en/integrations/direct-data-access.html)

**Important Note:**  
Nothing in this repository supersedes your institution's contract or Blackboard's official documentation. Always consult official documentation and your agreements before making decisions based on this content.

## Schema and Changes Packages

You can browse and download the latest database documentation packages here:

- [Schema Packages (bbprepo)](https://bbprepo.blackboard.com/#browse/browse:releases:bbdn%2fschema)
- [Changes Packages (bbprepo)](https://bbprepo.blackboard.com/#browse/browse:releases:bbdn%2fjdiff)

## Expanded Schema Explorer

You can explore the expanded v4000.10 schema package here: [Browse Schema v4000.10](https://jkelley-blackboard.github.io/DDA/schema-4000.10.0/schema/index.html)

## Security Considerations

When working with DDA, ensure that access credentials are stored securely and use encrypted connections. Queries should not expose sensitive student or institutional data. Follow your organization's data governance policies. Access can be restricted by whitelisting the IP addresses permitted to connect to your DDA instance — this is the primary network-level control available.

## Schema Refresh and Permissions

Occasionally new tables are added to the schema and your DDA account may not have permission to read them. If you receive a table-specific permission error, you can work with Blackboard support to refresh your DDA account — this typically involves copying the username and password, deleting the account, and recreating it with the same credentials. Coordinate this with support before proceeding, as it will briefly interrupt access.

## DDA Database Overview

Blackboard SaaS deployments use five distinct PostgreSQL databases to support core application functionality, reporting, and content management. This summary outlines their purpose and relevance for reporting and integration work. Schema details are primarily documented in the Expanded Schema Explorer section above.

- **BB\<deployment_id\>**
  * Primary production database
  * Contains all core application tables (courses, users, enrollments, grades, hierarchy, tools, etc.)
  * Most reporting and integration work will use this database
  * Schema is mostly documented in the Expanded Schema Explorer above
- **BB\<deployment_id\>_admin**
  * System coordination database
  * Stores internal configuration and metadata
  * Rarely accessed for reporting or integrations
- **BB\<deployment_id\>_stats**
  * Reporting and analytics database
  * Includes a permanent copy of `activity_accumulator`, which is truncated to 180 days in the production database
  * `ODS` tables contain transformed data specifically for activity reporting
- **BB\<deployment_id\>_cms_doc**
  * Content Collection document store
  * Powers file storage and retrieval for the Content Collection
  * Not documented and generally not used for reporting
- **BB\<deployment_id\>_cms**
  * Content Collection admin database
  * Manages metadata and configuration for the Content Collection
  * Rarely accessed and not typically relevant for reporting

**Note:**  
Replace `BB<deployment_id>` with your actual database prefix (for example, `BB5c1c67a3c99fc`).
Some older systems may have been configured with individual `_cms` databases for each of the various root
folders in the Content Collection (for example, `BB<deployment_id>_cms_users` or `BB<deployment_id>_cms_orgs`).
The schema for these databases is the same as `_cms_doc`.

**A note on legacy database names:**
Older documentation, community SQL examples, and schema references may use `bb_bb60` or `BBLEARN` as the database name. These were used in self-hosted and managed-hosted Blackboard deployments. In SaaS environments, they are equivalent to your `BB<deployment_id>` database. If you encounter either name in a query or external resource, treat it as referring to your primary DDA database.

## Cross-Database Joins with `dblink`

Blackboard's DDA databases are physically separated, so direct joins between them require PostgreSQL's `dblink` extension. A common use case is combining user or course data from the primary database with long-term activity data in `BB<deployment_id>_stats` — for example, reporting on course activity beyond the 180-day window available in the production database.

Note that in most Blackboard environments, connections are only permitted **from the main database to others**, not the reverse. This is a standard production security configuration.

For detailed examples, see the [Cross-Database Joins](dblink.md) page.

---

This is an unofficial community resource. Not affiliated with or endorsed by Blackboard, Inc. Always refer to official Blackboard documentation and your institution's agreements.
