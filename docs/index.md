---
meta-viewport: width=device-width,initial-scale=1
title: Working with DDA
---

# Working with DDA

[View Repository](https://github.com/jkelley-blackboard/DDA)

### Navigation

- [Getting Connected](getting-connected.md)
- [Understanding the Read Replica](read-replica.md)
- [Key Tables Guide](key-tables.md)
- [PostgreSQL & SQL Guide](postgres-sql-guide.md)
- [Troubleshooting](troubleshooting.md)
- [Community & Resources](community.md)

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

You can explore the expanded v4000.17 schema package here: [Browse Schema v4000.17](https://jkelley-blackboard.github.io/DDA/schema-4000.17.0/schema/index.html)

## Security Considerations

When working with DDA, ensure that access credentials are stored securely and use encrypted connections. Queries should not expose sensitive student or institutional data. Follow your organization's data governance policies. Access can be restricted by whitelisting the IP addresses permitted to connect to your DDA instance — this is the primary network-level control available.

## Schema Refresh and Permissions

Occasionally new tables are added to the schema and your DDA account may not have permission to read them. If you receive a table-specific permission error, you can work with Blackboard support to refresh your DDA account — this typically involves copying the username and password, deleting the account, and recreating it with the same credentials. Coordinate this with support before proceeding, as it will briefly interrupt access.

## DDA Database Overview

<iframe id="dda-db-frame" src="dda-databases.html" width="100%" height="800" frameborder="0" scrolling="no" style="border:none; display:block;"></iframe>
<script>
  window.addEventListener('message', function(e) {
    if (e.data && e.data.iframeHeight) {
      document.getElementById('dda-db-frame').style.height = (e.data.iframeHeight + 20) + 'px';
    }
  });
</script>

Some older systems may have been configured with individual `_cms` databases for each root folder in the Content Collection (for example, `BB<deployment_id>_cms_users` or `BB<deployment_id>_cms_orgs`). The schema for these is the same as `_cms_doc`.

## Cross-Database Joins with `dblink`

Blackboard's DDA databases are physically separated, so direct joins between them require PostgreSQL's `dblink` extension. A common use case is combining user or course data from the primary database with long-term activity data in `BB<deployment_id>_stats` — for example, reporting on course activity beyond the 180-day window available in the production database.

Note that in most Blackboard environments, connections are only permitted **from the main database to others**, not the reverse. This is a standard production security configuration.

For detailed examples, see the [Cross-Database Joins](dblink.md) page.

---

This is a supplemental community resource. Content is the property of Blackboard, Inc. and is provided without official support or endorsement. Always refer to official Blackboard documentation and your institution's agreements.
