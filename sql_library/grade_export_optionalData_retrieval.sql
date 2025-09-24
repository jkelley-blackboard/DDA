/*
jeff.kelley@anthology.com  2025-06-28
provided without warranty or support

validate data for grade columns created via Grade Extract
see documentation
        https://help.blackboard.com/Blackboard_Extensions/Grades_Journey/Configuration/incoming_settings/REST_specifications
        https://help.blackboard.com/Learn/Administrator/SaaS/Tools_Management/Grade_Export/Incoming_Settings/Flat_File_Specifications
*/

-- CTE to get extended data from bbc_gradecolumn_ext table specific to Grade Extrac/Journey
WITH gbExtendedData AS(
        SELECT 
          gradebook_main_pk1,
          string_agg(
            CASE 
              WHEN extended_data_key NOT IN ('extract_ind', 'confirmed_ind', 'integration_ind' ) --these three keys are not part of optionalData
              THEN extended_data_key || '=' || extended_data_value
              ELSE NULL END,':') AS optionalData,
          MAX(CASE WHEN extended_data_key = 'extract_ind' THEN extended_data_value ELSE NULL END) AS extract_ind,
          MAX(CASE WHEN extended_data_key = 'confirmed_ind' THEN extended_data_value ELSE NULL END) AS confirmed_ind,
          MAX(CASE WHEN extended_data_key = 'integration_ind' THEN extended_data_value ELSE NULL END) AS integration_ind
        FROM bbc_gradecolumn_ext
        GROUP BY gradebook_main_pk1
)

-- main query joining gradebook_main
SELECT
  gm.date_added,
  gm.date_modified,
  gm.pk1 as gm_pk1,
  --gm.deleted_ind,   --columns deleted in the gui are retained
  cm.course_id,
  gm.title as "name",
  CASE -- convert to type values from REST specification
    WHEN gm.calculated_ind = 'C' THEN 'CALCULATED_COLUMN'
    WHEN gm.calculated_ind = 'N' THEN 'MANUAL_COLUMN'
    WHEN gm.calculated_ind = 'W' THEN 'WEIGHTED_COLUMN'
    ELSE 'other' END "itemType",
  CASE WHEN gm.anonymous_grading_ind = 'Y' then 'true' ELSE 'false' END "anonymous",
  gm.multiple_attempts "attempts",
  gm.due_date,
  gm.visible_in_book_ind "available",
  gce.optionalData "optionalData",
  gce.extract_ind "extract",
  gce.confirmed_ind,
  gce.integration_ind,
  gm.possible::INT as points
  --,gm.* --uncomment this if you want to explore the rest of gradebook_main
FROM gbExtendedData gce
  JOIN gradebook_main gm on gm.pk1 = gce.gradebook_main_pk1
  JOIN course_main cm on cm.pk1 = gm.crsmain_pk1
WHERE cm.course_id like '%' --'MAT1520.A.12345'  choose a course
   AND gm.deleted_ind = 'N'  --columns deleted in the gui are retained
   --AND DATE(cm.date_added) > '2025-06-25'  choose a date filter if you want