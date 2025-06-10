-- File storage metrics to match the Insight Report
-- converts all bytes to GB (/1e9)
-- jeff.kelley@anthology.com  2025-06-10  (updated)
-- in 2025 the measure against entitlement is Shared + Content Collection Total - Course Archives - Deleted 



WITH calc AS (
  SELECT
    mydata.the_date,
    SUM(CASE WHEN mydata.record_type = 'total-space_location_xythos' THEN COALESCE(mydata.the_value, 0) END) AS cc_total,
    SUM(CASE WHEN mydata.record_type = 'total-space_location_shared-content' THEN COALESCE(mydata.the_value, 0) END) AS shared,
    SUM(CASE WHEN mydata.record_type = 'deleted-space_location_xythos' THEN COALESCE(mydata.the_value, 0) END) AS cc_deleted,
    SUM(CASE WHEN mydata.record_type = 'total-space_location_/internal/autoArchive' THEN COALESCE(mydata.the_value, 0) END) AS cc_archives,
    SUM(CASE WHEN mydata.record_type = 'total-space_location_/internal/logs' THEN COALESCE(mydata.the_value, 0) END) AS cc_logs,
    SUM(CASE WHEN mydata.record_type IN ('total-course-count__', 'total-organization-count__') THEN COALESCE(mydata.the_value, 0) END) AS cc_crsorg
  FROM (
    SELECT 
      COALESCE(m.name, '') || '_' || COALESCE(d.name, '') || '_' || COALESCE(dv.value, '') AS record_type,
      COALESCE(mv.value, 0) AS the_value,
      DATE(mv.metric_timestamp::TIMESTAMP AT TIME ZONE 'America/Chicago') AS the_date
    FROM metric_value mv
    INNER JOIN metric m ON m.pk1 = mv.metric_pk1
    INNER JOIN metric_unit mu ON mu.pk1 = mv.metric_unit_pk1
    LEFT OUTER JOIN metric_value_dimension mdv ON mdv.metric_value_pk1 = mv.pk1
    LEFT OUTER JOIN metric_dimension_value dv ON dv.pk1 = mdv.metric_dimension_value_pk1
    LEFT OUTER JOIN metric_dimension d ON d.pk1 = dv.metric_dimension_pk1
    WHERE DATE(mv.metric_timestamp) > '2023-04-03'  --oldest records in US East region
  ) mydata
  GROUP BY mydata.the_date
)
SELECT
  calc.the_date,
  ROUND((calc.shared + calc.cc_total - calc.cc_deleted - calc.cc_archives) / 1e9, 2) AS "Total_Against_Entitlement_GB",
  ROUND((calc.shared + calc.cc_total) / 1e9, 2) AS "grand_total_gb",
  ROUND(calc.cc_total / 1e9, 2) AS "+total_content_collection_gb",  
  ROUND(calc.shared / 1e9, 2) AS "+shared_files_gb",
  ROUND(calc.cc_archives / 1e9, 2) AS "-course_archives_gb",
  ROUND(calc.cc_deleted / 1e9, 2) AS "-deleted_gb",
  ROUND((calc.cc_total - calc.cc_deleted - calc.cc_logs - calc.cc_archives) / 1e9, 2) AS "content_gb",
  ROUND(calc.cc_logs / 1e9, 2) AS "logs_gb",
  TRUNC(calc.cc_crsorg) AS "COURSE+ORG_COUNT"
FROM calc
ORDER BY calc.the_date ASC;
