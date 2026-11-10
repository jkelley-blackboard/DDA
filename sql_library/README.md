# SQL Library

Standalone SQL scripts for common DDA reporting tasks against Blackboard's primary and `_stats` databases.

Each script is self-contained and includes a header comment describing its purpose. Scripts avoid hardcoded institution-specific values (course IDs, usernames, titles, dates) — adjust the commented-out examples for your environment before running.

## Subdirectories

- [`content_collection/`](content_collection/README.md) — queries against the Content Collection (`_cms_doc` / `_cms`) databases. Note that these schemas are not publicly documented by Blackboard.

## Index

Each description is the first line of the script's header. *Last changed* is the date of the script's last commit.

<!-- sql-index:start -->
| File | Description | Last changed |
|---|---|---|
| [`aacsb_question_grades.sql`](aacsb_question_grades.sql) | AACSB-tagged question grades by student, for assurance-of-learning reporting. | 2026-08-12 |
| [`auto_zero_analysis.sql`](auto_zero_analysis.sql) | Check where courses have auto-zero enabled or have grades that were auto-zeroed | 2026-07-10 |
| [`demo_users_no_enrollments.sql`](demo_users_no_enrollments.sql) | Users tagged to a "demo" data source who have zero course enrollments. | 2026-10-13 |
| [`enterprise_survey_response_rates.sql`](enterprise_survey_response_rates.sql) | Enterprise survey response rates: recipients and returned responses per survey deployment | 2026-11-10 |
| [`feedback_recordings.sql`](feedback_recordings.sql) | gets links to all feedback videos | 2026-07-10 |
| [`FileStorage_Insight_summary_20250610.sql`](FileStorage_Insight_summary_20250610.sql) | File storage metrics to match the Insight Report | 2026-07-10 |
| [`grade_export_optionalData_retrieval.sql`](grade_export_optionalData_retrieval.sql) | Grade Export / Grades Journey: validate optionalData and integration flags on grade columns | 2026-11-10 |
| [`grade_extract_extended_data.sql`](grade_extract_extended_data.sql) | Gradebook columns with formula, grading schema and Grade Extract extended data (key=value list) | 2026-11-10 |
| [`grades_status_by_course.sql`](grades_status_by_course.sql) | grade status count by course | 2026-02-23 |
| [`IH_node_admins.sql`](IH_node_admins.sql) | List of Node admins and roles | 2026-07-10 |
| [`log_summary_by_month.sql`](log_summary_by_month.sql) | sumarizes a count of log files and their total size by month | 2026-07-10 |
| [`lti11_content_items_by_course.sql`](lti11_content_items_by_course.sql) | LTI 1.1 content items per course: which LTI 1.1 tools are present in each course, and how many items | 2026-11-10 |
| [`node_tools_extract.sql`](node_tools_extract.sql) | Tool availability settings at an institutional hierarchy node, with the node's full path | 2026-11-10 |
| [`recursive_node_list.sql`](recursive_node_list.sql) | Full path of every institutional hierarchy node (name, pk1, batch_uid from root to leaf) | 2026-11-10 |
| [`sis_integration_logs.sql`](sis_integration_logs.sql) | SIS Framework data integration logs: per-data-set summary and detail log lines | 2026-11-10 |
| [`subjects_and_programs.sql`](subjects_and_programs.sql) | Each course with its subject and program from the course hierarchy | 2026-11-10 |
| [`system_role_audit.sql`](system_role_audit.sql) | List of users with ANY system role other than 'None' | 2026-07-10 |
| [`users_by_institution_role.sql`](users_by_institution_role.sql) | look up users by institution role (primary and secondary) | 2026-07-10 |
| [`content_collection/_BASE_course_purge_storage_impact.sql`](content_collection/_BASE_course_purge_storage_impact.sql) | BASE QUERY: storage impact of purging one or more courses (Content Collection) | 2026-07-16 |
| [`content_collection/_BASE_orphaned_unlinked_content_collection.sql`](content_collection/_BASE_orphaned_unlinked_content_collection.sql) | BASE QUERY: Content Collection orphaned & unlinked file inventory | 2026-07-16 |
<!-- sql-index:end -->

To refresh this index after adding or changing a script, run `python tools/build_sql_index.py` from the repo root. Do not edit the table by hand. Every script's first non-blank line must be a `--` comment describing it.

---

This is a supplemental community resource. Content is the property of Blackboard, Inc. and is provided without official support or endorsement. Always refer to official Blackboard documentation and your institution's agreements.
