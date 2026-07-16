-- BASE QUERY: storage impact of purging one or more courses (Content Collection)
--
-- © 2026 Blackboard Inc. All rights reserved.
-- This software is provided "as is" without warranty or support
-- jeff.kelley@blackboard.com   2026-07-16
--
-- Consolidates the various "UniqueFiles_CoursesByID*" scripts in this repo
-- into a single reusable starting point. Answers: if a given set of courses
-- were purged/deleted, how much Content Collection storage would ACTUALLY be
-- freed?
--
-- Every file in the selection falls into one of two buckets:
--
--   - UNIQUE (crs_unique_ind = 'Y') - every reference to this blob lives
--             inside the course selection. Purging the selection frees this
--             space.
--
--   - SHARED (crs_unique_ind = 'N') - the blob is ALSO referenced by at least
--             one course outside the selection (course copies, rollovers,
--             cross-listings, shared template content). Purging the selection
--             will NOT free this space - the content stays on disk for the
--             other course(s).
--
-- CORE TRICK: xyf_blobs.ref_count is a SYSTEM-WIDE reference counter Content
-- Collection maintains for de-duplication (one physical blob can back many
-- file/version rows). Comparing ref_count to the number of references found
-- WITHIN the selected course set tells you, per blob, whether the selection
-- holds every reference to that content or only some of them.
--
-- Run directly against the *_cms_doc database - self-contained, no DBLINK
-- needed (unlike the orphaned/unlinked check, which needs course_main from
-- the main Learn database).
--
-- CAVEATS
-- - ref_count is instance-wide. If this cms_doc is shared across multiple
--   orgs/domains, a "shared" result doesn't distinguish "shared with another
--   course in the same org" from "shared with an unrelated org" - use the
--   optional WHO-ELSE-HOLDS-IT block below to see specifically which courses.
-- - This measures blob-level content de-dup only. It says nothing about
--   permissions, adaptive release, grade center links, or other course
--   dependencies - it's a storage estimate to inform a purge decision, not a
--   substitute for the standard course-delete process.
-- - Directories (file_type_code = 'D') aren't counted - only individual files.
-- - Natural companion to _BASE_orphaned_unlinked_content_collection.sql: use
--   that script to find candidate courses/files first, then this one to
--   quantify the actual storage payoff before acting.
--
-- HOW TO ADAPT THIS FOR OTHER INQUIRIES
-- 1. COURSE SELECTION (marked >>> SELECTION below): the WHERE clause on
--    course_id_from_path IS the definition of "courses being considered for
--    purge". Replace REPLACE_ME_TERM% with whatever fits the request:
--      - a pattern on term/semester, e.g. '16fall%', '%_2018%_CR_%'
--      - an explicit list:  ... IN ('COURSE_ID_1','COURSE_ID_2')
--      - a subquery against course_main, e.g. courses past a retention
--        cutoff, zero enrollments, or flagged inactive
--    NOTE: '/internal' is stripped from full_path before parsing, so one
--    filter covers BOTH live ('/courses/...') and deleted/protected
--    ('/internal/courses/...') content in a single pass.
--
-- 2. OUTPUT GRAIN (marked >>> GRAIN below): default is a whole-selection
--    Y/N summary (matches the original scripts). Uncomment the per-course
--    block instead to see WHERE the "won't actually be freed" storage lives
--    course by course - useful when purging a batch and prioritizing which
--    ones give the most real payoff.
--
-- 3. WHO ELSE HOLDS IT (optional block at the very bottom, commented out):
--    for SHARED blobs only, lists the other course_id(s) outside the
--    selection still referencing the content. Check the 'N' row's file_count
--    from the summary first - only run this once that shared set looks small
--    enough to be worth inspecting row-by-row.

WITH course_selection_files AS (
  SELECT
    fver.blob_id,
    blob.blob_size AS bytes,
    blob.ref_count AS system_wide_ref_count,
    SPLIT_PART(REPLACE(furl.full_path, '/internal', ''), '/', 3) AS course_id_from_path
  FROM xyf_urls furl
  JOIN xyf_files ffile        ON ffile.file_id = furl.file_id
  JOIN xyf_file_versions fver ON fver.file_id  = furl.file_id
  JOIN xyf_blobs blob         ON blob.blob_id  = fver.blob_id
  WHERE ffile.file_type_code = 'F'                                        -- files only, not directories
    -- >>> SELECTION: replace REPLACE_ME_TERM% with whatever defines "courses being purged"
    AND SPLIT_PART(REPLACE(furl.full_path, '/internal', ''), '/', 3) ILIKE 'REPLACE_ME_TERM%'
    -- AND SPLIT_PART(REPLACE(furl.full_path, '/internal', ''), '/', 3) IN ('COURSE_ID_1', 'COURSE_ID_2')
),

blob_ref_counts AS (
  SELECT
    blob_id,
    bytes,
    system_wide_ref_count,
    COUNT(*) AS in_selection_ref_count,
    CASE WHEN system_wide_ref_count = COUNT(*) THEN 'Y' ELSE 'N' END AS crs_unique_ind  -- Y = reclaimed by purge, N = still held elsewhere
  FROM course_selection_files
  GROUP BY blob_id, bytes, system_wide_ref_count
)

-- >>> GRAIN: whole-selection summary (default)
SELECT
  crs_unique_ind AS unique_to_selection,
  PG_SIZE_PRETTY(SUM(bytes)) AS total_size,
  COUNT(blob_id) AS file_count
FROM blob_ref_counts
GROUP BY crs_unique_ind
ORDER BY crs_unique_ind DESC;

-- >>> GRAIN: per-course breakdown - uncomment instead of the summary above to
-- see which specific courses in the selection actually contribute reclaimable
-- space vs. which are mostly holding shared/rolled-over content.
/*
SELECT
  per_course.course_id_from_path,
  per_course.crs_unique_ind AS unique_to_selection,
  PG_SIZE_PRETTY(SUM(per_course.bytes)) AS total_size,
  COUNT(*) AS file_count
FROM (
  SELECT DISTINCT
    csf.course_id_from_path,
    csf.blob_id,
    brc.bytes,
    brc.crs_unique_ind
  FROM course_selection_files csf
  JOIN blob_ref_counts brc ON brc.blob_id = csf.blob_id
) AS per_course
GROUP BY per_course.course_id_from_path, per_course.crs_unique_ind
ORDER BY per_course.course_id_from_path, per_course.crs_unique_ind DESC;
*/

-- WHO ELSE HOLDS IT: for SHARED blobs, find the other course(s) outside the
-- selection still referencing the content. Re-scans xyf_urls system-wide per
-- shared blob - confirm the 'N' file_count above is a manageable size first.
/*
SELECT DISTINCT
  brc.blob_id,
  SPLIT_PART(REPLACE(furl.full_path, '/internal', ''), '/', 3) AS other_course_id,
  furl.full_path
FROM blob_ref_counts brc
JOIN xyf_file_versions fver ON fver.blob_id = brc.blob_id
JOIN xyf_urls furl          ON furl.file_id = fver.file_id
WHERE brc.crs_unique_ind = 'N'
  AND SPLIT_PART(REPLACE(furl.full_path, '/internal', ''), '/', 3) NOT ILIKE 'REPLACE_ME_TERM%'  -- exclude the selection itself; match >>> SELECTION above
ORDER BY brc.blob_id;
*/
