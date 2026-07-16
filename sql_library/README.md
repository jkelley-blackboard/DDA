# SQL Library

Standalone SQL scripts for common DDA reporting tasks against Blackboard's primary and `_stats` databases.

Each script is self-contained and includes a header comment describing its purpose. Scripts avoid hardcoded institution-specific values (course IDs, usernames, titles, dates) — adjust the commented-out examples for your environment before running.

## Subdirectories

- [`content_collection/`](content_collection/README.md) — queries against the Content Collection (`_cms_doc` / `_cms`) databases. Note that these schemas are not publicly documented by Blackboard.

---

This is a supplemental community resource. Content is the property of Blackboard, Inc. and is provided without official support or endorsement. Always refer to official Blackboard documentation and your institution's agreements.
