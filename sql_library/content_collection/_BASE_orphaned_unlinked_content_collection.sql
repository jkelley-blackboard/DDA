-- BASE QUERY: Content Collection orphaned & unlinked file inventory
--
-- © 2026 Blackboard Inc. All rights reserved.
-- This software is provided "as is" without warranty or support
-- jeff.kelley@blackboard.com   2026-07-16
--
-- Consolidates the various one-off "orphaned_internal*" and "*linked_status*"
-- scripts in this repo into a single reusable starting point. Identifies two
-- DIFFERENT things - don't conflate them:
--
--   (a) ORPHANED - the course_id parsed from the Content Collection file path
--                   no longer exists in course_main (course was deleted, but
--                   its files were never cleaned up).
--
--   (b) UNLINKED - the course still exists, but the file is not referenced
--                   ("linked") into any content item via cms_resource_link.
--                   CAVEAT: "linked" is not a perfect proxy for "in use".
--                   Files can be reached by direct URL, embedded via mashup/
--                   building-block tools, or referenced from another course
--                   without a cms_resource_link row. Treat UNLINKED as
--                   "worth reviewing", not "safe to delete".
--
-- Run against the MAIN Learn database. Requires a DBLINK to the paired
-- *_cms_doc database (server-side dblink extension/FDW - confirm with DBA if
-- not already provisioned on the target instance).
--
-- HOW TO ADAPT THIS FOR OTHER INQUIRIES
-- 1. PATH SCOPE (marked >>> PATH SCOPE below):
--      '/courses/%'          -> live/visible course content
--      '/internal/courses/%' -> "deleted"/protected/archived course content
--    The course_id sits at a different path segment depending on which scope
--    you use - SPLIT_PART index is called out at each occurrence.
--      /courses/<course_id>/...           -> SPLIT_PART(..., 3)
--      /internal/courses/<course_id>/...  -> SPLIT_PART(..., 4)
--
-- 2. GRANULARITY (marked >>> GRANULARITY below):
--      file_type_code = 'F'  -> individual files (default; needed for
--                                size/linked-status calcs)
--      file_type_code = 'D'  -> directories only (cheap orphan-only sweep,
--                                skip the cms_resource_link join entirely)
--
-- 3. ORPHAN vs UNLINKED vs BOTH: uncomment exactly one filter in the WHERE
--    clause at the bottom.
--
-- 4. SIZE / DATE THRESHOLDS (marked >>> FILTERS below): tune to avoid
--    scanning the entire content collection - always test with a size, date,
--    or course-name filter first on large installations to avoid timeouts.
--
-- 5. DBLINK connection string: replace dbname/user/password for the target
--    client database.
--
-- PERFORMANCE NOTE: the DBLINK subquery runs entirely on the cms_doc side, so
-- push as much filtering as possible into that inner SELECT before it
-- crosses the link - filtering after DBLINK returns pulls the full result
-- set across first.

SELECT
  cc.course_id_from_path,
  cm.course_id                                               AS existing_course,     -- NULL => orphaned
  cc.full_path,
  ROUND(cc.file_size / 1024.0 / 1024.0, 2)                   AS size_mb,
  cc.creation_date,
  cc.last_update_date,
  linkcrs.course_id                                          AS linked_into_course,  -- NULL => unlinked
  CASE WHEN cm.course_id IS NULL THEN TRUE ELSE FALSE END    AS is_orphaned,
  CASE WHEN cm.course_id IS NOT NULL
        AND linkcrs.course_id IS NULL THEN TRUE ELSE FALSE END AS is_unlinked

FROM DBLINK(
  'dbname=REPLACE_ME_cms_doc user=REPLACE_ME password=REPLACE_ME',
  $$
    SELECT
      furl.file_id,
      SPLIT_PART(furl.full_path, '/', 3) AS course_id_from_path,  -- >>> PATH SCOPE: 3 for /courses/, 4 for /internal/courses/
      furl.full_path,
      ffile.file_size,
      ffile.creation_date,
      ffile.last_update_date
    FROM xyf_urls furl
    INNER JOIN xyf_files ffile ON ffile.file_id = furl.file_id
    WHERE ffile.file_type_code = 'F'                     -- >>> GRANULARITY: 'F' files / 'D' directories
      AND furl.full_path LIKE '/courses/%'               -- >>> PATH SCOPE: live/visible course content (use '/internal/courses/%' for deleted/protected)
      -- AND ffile.file_size > 100*1024*1024              -- >>> FILTERS: e.g. files over 100MB
      -- AND ffile.creation_date < CURRENT_DATE - INTERVAL '2 years'
      -- AND SPLIT_PART(furl.full_path, '/', 3) ILIKE '%test%'  -- e.g. scope to specific course(s) first
  $$
) AS cc (
  file_id bigint,
  course_id_from_path text,
  full_path text,
  file_size bigint,
  creation_date timestamptz,
  last_update_date timestamptz
)

LEFT JOIN course_main cm
  ON cm.course_id = cc.course_id_from_path

-- Only meaningful when GRANULARITY = 'F' above; skip this join for directory sweeps
LEFT JOIN cms_resource_link crl
  ON LEFT(crl.resource_id, POSITION('_' IN crl.resource_id) - 1)::bigint = cc.file_id

LEFT JOIN course_main linkcrs
  ON linkcrs.pk1 = crl.crsmain_pk1

WHERE 1 = 1
  -- AND cm.course_id IS NULL                                          -- orphaned only
  -- AND (cm.course_id IS NOT NULL AND linkcrs.course_id IS NULL)      -- unlinked only (course still exists)
  -- AND (cm.course_id IS NULL OR linkcrs.course_id IS NULL)           -- either orphaned OR unlinked

ORDER BY size_mb DESC;
