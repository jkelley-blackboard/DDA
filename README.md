# Direct Data Access (DDA) Resource Guide

![Status](https://img.shields.io/badge/status-active-brightgreen) ![Platform](https://img.shields.io/badge/platform-Blackboard%20DDA-blue)

**Author:** [jkelley-blackboard](https://github.com/jkelley-blackboard)  
**Disclaimer:** Provided without support or warranty

## 📢 Public Site

Visit the GitHub Pages site for documentation, guides, and reference material:  
**[jkelley-blackboard.github.io/DDA](https://jkelley-blackboard.github.io/DDA/)**

---

## 📘 Overview

This repository contains SQL scripts, schema references, and documentation for working with **Blackboard's Direct Data Access (DDA)** service. DDA provides read-only access to a replica of the Blackboard database — never the production database — allowing report writers and administrators to safely extract, analyze, and report on institutional data.

> ⚠️ Scripts and documentation are shared as-is and may require adaptation for your institution's schema or environment.

### A Note on Legacy Database Names

Older documentation, community SQL examples, and schema references may use `bb_bb60` or `BBLEARN` as the database name. These were used in self-hosted and managed-hosted Blackboard deployments. In SaaS environments, they are equivalent to your `BB<deployment_id>` primary DDA database.

---

## 📂 Repository Contents

### docs/
Documentation site source files — served via GitHub Pages.

- **[index.md](docs/index.md)** — DDA overview, database descriptions, and navigation
- **[getting-connected.md](docs/getting-connected.md)** — How to connect using pgAdmin, DBeaver, Python, and Power BI; IP whitelisting and cloud service patterns
- **[read-replica.md](docs/read-replica.md)** — What a read replica is, data lag, the 180-day activity window, and common misconceptions
- **[key-tables.md](docs/key-tables.md)** — Guide to the most important tables for reporting: courses, users, enrollment, and activity
- **[dblink.md](docs/dblink.md)** — Cross-database joins using PostgreSQL's `dblink` extension with worked examples
- **[troubleshooting.md](docs/troubleshooting.md)** — Connection problems, data issues, tool-specific fixes, and performance tips

### sql_library/
SQL scripts for common reporting needs. Scripts are organized by subject area and are designed to work with Blackboard SaaS DDA environments.

---

## 🚀 Usage

- Browse the [docs site](https://jkelley-blackboard.github.io/DDA/) for guides and reference material
- Review the `sql_library/` folder for ready-to-use queries
- Customize scripts for your institution's environment and schema version
- Always test queries before using results in production reports

---

## 🔗 Helpful Resources

- 📚 **Official Blackboard DDA Documentation**  
  [help.anthology.com — Direct Data Access](https://help.anthology.com/blackboard/administrator/en/integrations/direct-data-access.html)

- 📦 **Schema Downloads**  
  [Browse Schema Releases on bbprepo](https://bbprepo.blackboard.com/#browse/browse:releases:bbdn%2Fschema)

- 💬 **Blackboard Techies Slack — DDA Channel**  
  [#direct-data-access](https://blackboardtechies.slack.com/archives/CFAEA8KD3)

---

## 🧭 Related Repositories

- [zenandjuice/bbLearnDDA](https://github.com/zenandjuice/bbLearnDDA)
- [carolynponce/Bb-DBQueryRepository](https://github.com/carolynponce/Bb-DBQueryRepository)
- [lloydabell4/Blackboard-Feature-SQL-Query](https://github.com/lloydabell4/Blackboard-Feature-SQL-Query)

---

## 🤝 Contributing

Contributions are welcome. If you have useful SQL scripts, corrections, or DDA tips, feel free to open a pull request or submit an issue.

---

## 📄 License

This repository is covered by a company-owned, modified MIT License provided by Blackboard.  
See [LICENSE.txt](LICENSE.txt) for full terms, including restrictions, warranty disclaimer, and requirements for redistribution.

---

*This is an unofficial community resource. Not affiliated with or endorsed by Blackboard, Inc. Always refer to official Blackboard documentation and your institution's agreements.*
