-- File storage metrics to match the Insight Report
-- Converts all bytes to GB (/1e9)
-- jeff.kelley@anthology.com 2025-06-10 (updated)
-- In 2025, the measure against entitlement is:
-- Shared + Content Collection Total - Course Archives - Deleted

WITH calc AS (
  SELECT
    DATE(mv.metric_timestamp AT TIME ZONE 'America/Chicago') AS the_date,
    
    SUM(COALESCE(mv.value, 0)) FILTER (
      WHERE m.name = 'total-space' AND d.name = 'location' AND dv.value = 'xythos'
    ) AS cc_total,

    SUM(COALESCE(mv.value, 0)) FILTER (
      WHERE m.name = 'total-space' AND d.name = 'location' AND dv.value = 'shared-content'
    ) AS shared,

    SUM(COALESCE(mv.value, 0)) FILTER (
      WHERE m.name = 'deleted-space' AND d.name = 'location' AND dv.value = 'xythos'
    ) AS cc_deleted,

    SUM(COALESCE(mv.value, 0)) FILTER (
      WHERE m.name = 'total-space' AND d.name = 'location' AND dv.value = '/internal/autoArchive'
    ) AS cc_archives,

    SUM(COALESCE(mv.value, 0)) FILTER (
      WHERE m.name = 'total-space' AND d.name = 'location' AND dv.value = '/internal/logs'
    ) AS cc_logs,

    SUM(COALESCE(mv.value, 0)) FILTER (
      WHERE m.name IN ('total-course-count', 'total-organization-count')
    ) AS cc_crsorg

  FROM metric_value mv
  INNER JOIN metric m ON m.pk1 = mv.metric_pk1
  INNER JOIN metric_unit mu ON mu.pk1 = mv.metric_unit_pk1
  LEFT JOIN metric_value_dimension mdv ON mdv.metric_value_pk1 = mv.pk1
  LEFT JOIN metric_dimension_value dv ON dv.pk1 = mdv.metric_dimension_value_pk1
  LEFT JOIN metric_dimension d ON d.pk1 = dv.metric_dimension_pk1
  WHERE mv.metric_timestamp::DATE > '2023-04-03'  -- Oldest records in US East region
  GROUP BY DATE(mv.metric_timestamp AT TIME ZONE 'America/Chicago')
)

SELECT
  the_date,
  ROUND((shared + cc_total - cc_deleted - cc_archives) / 1e9, 2) AS total_against_entitlement_gb,
  ROUND((shared + cc_total) / 1e9, 2) AS grand_total_gb,
  ROUND(cc_total / 1e9, 2) AS total_content_collection_gb,
  ROUND(shared / 1e9, 2) AS shared_files_gb,
  ROUND(cc_archives / 1e9, 2) AS course_archives_gb,
  ROUND(cc_deleted / 1e9, 2) AS deleted_gb,
  ROUND((cc_total - cc_deleted - cc_logs - cc_archives) / 1e9, 2) AS content_gb,
  ROUND(cc_logs / 1e9, 2) AS logs_gb,
  TRUNC(cc_crsorg) AS course_org_count
FROM calc
ORDER BY the_date ASC;
