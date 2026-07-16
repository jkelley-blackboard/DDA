# Content Collection (CMS_DOC) Queries

This subdirectory holds SQL scripts for reporting against the Content Collection databases — `BB<deployment_id>_cms_doc` and `BB<deployment_id>_cms`.

## Important: No Official Schema Documentation

Unlike the primary and `_stats` databases, the CMS schemas are **not publicly documented** by Blackboard. There is no published schema package covering `_cms_doc` or `_cms` tables and columns.

As a result, any DDA work against these databases is done without official Blackboard support — table structures here have been inferred through exploration, not confirmed against documentation. Treat scripts in this directory with extra caution, validate against your own instance before relying on them, and expect that structure may vary or change between versions without notice.

---

This is a supplemental community resource. Content is the property of Blackboard, Inc. and is provided without official support or endorsement. Always refer to official Blackboard documentation and your institution's agreements.
