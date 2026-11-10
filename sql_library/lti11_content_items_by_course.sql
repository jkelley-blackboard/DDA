-- LTI 1.1 content items per course: which LTI 1.1 tools are present in each course, and how many items
-- Counts placement content items (matched by placement handle) and generic LTI links (matched by URL host
-- to the most specific registered domain). Tools used only from Books & Tools are not content and are not counted.
-- Also lists items that match no registration: generic links to an unregistered host (almost certainly LTI 1.1,
-- since an LTI 1.3 link needs a registration) and items whose placement was deleted (version unknown).

-- jeff.kelley@blackboard.com 2026-11-10
-- This software is provided "as is" without warranty or support

WITH selected_courses AS (
  -- the courses to report on: set the term (or other course filters) here; no filter = all courses
  SELECT
    cm.pk1,
    cm.course_id,
    cm.course_name,
    cm.ultra_status,
    t.name AS term_name
  FROM course_main cm
  LEFT JOIN course_term ct
    ON ct.crsmain_pk1 = cm.pk1
  LEFT JOIN term t
    ON t.pk1 = ct.term_pk1
  -- WHERE t.name = 'Fall 2026'                                -- example: one term by name
  -- WHERE t.sourcedid_id IN ('2026FA', '2026SU')              -- example: terms by term ID
  -- WHERE NOW() BETWEEN t.start_date AND t.end_date           -- example: terms running today
  -- WHERE t.pk1 IS NULL                                       -- example: courses with no term
  -- WHERE cm.course_id LIKE '%2026FA%'                        -- example: by course ID pattern
),
lti_items AS (
  -- every LTI content item in the selected courses, generic or placement-based
  SELECT
    cc.pk1,
    cc.crsmain_pk1,
    cc.cnthndlr_handle,
    lower(cc.web_url_host) AS host,
    cc.available_ind,
    cc.dtcreated
  FROM course_contents cc
  JOIN selected_courses sc
    ON sc.pk1 = cc.crsmain_pk1
  WHERE cc.cnthndlr_handle LIKE 'resource/x-bb-blti%'
),
placement_match AS (
  -- placement items: the handler names the placement handle
  SELECT
    li.pk1,
    bp.blti_domain_config_pk1,
    bp.name AS placement_name,
    'placement' AS match_type
  FROM lti_items li
  JOIN blti_placement bp
    ON li.cnthndlr_handle = 'resource/x-bb-bltiplacement-' || bp.handle
),
domain_match AS (
  -- generic links: match the URL host to the most specific registered domain
  SELECT DISTINCT ON (li.pk1)
    li.pk1,
    dh.blti_domain_config_pk1,
    CAST(NULL AS varchar) AS placement_name,
    'domain' AS match_type
  FROM lti_items li
  JOIN blti_domain_host dh
    ON li.host = lower(dh.domain_name)
    OR li.host LIKE '%.' || lower(dh.domain_name)
  WHERE li.cnthndlr_handle = 'resource/x-bb-blti-link'
  ORDER BY li.pk1, length(dh.domain_name) DESC
),
unmatched AS (
  -- items with no registration: unregistered host (generic links) or deleted placement
  SELECT
    li.pk1,
    CAST(NULL AS bigint) AS blti_domain_config_pk1,
    CASE WHEN li.cnthndlr_handle = 'resource/x-bb-blti-link'
         THEN li.host
         ELSE replace(li.cnthndlr_handle, 'resource/x-bb-bltiplacement-', '') END AS placement_name,
    CASE WHEN li.cnthndlr_handle = 'resource/x-bb-blti-link'
         THEN 'unregistered host'
         ELSE 'deleted placement' END AS match_type
  FROM lti_items li
  WHERE li.pk1 NOT IN (SELECT pk1 FROM placement_match)
    AND li.pk1 NOT IN (SELECT pk1 FROM domain_match)
    AND (li.cnthndlr_handle <> 'resource/x-bb-blti-link' OR li.host <> '')
),
matched AS (
  SELECT * FROM placement_match
  UNION ALL
  SELECT * FROM domain_match
  UNION ALL
  SELECT * FROM unmatched
),
domains AS (
  -- 1.1 registrations have no name, so label them by their domains
  SELECT
    dh.blti_domain_config_pk1,
    string_agg(dh.domain_name, ', ' ORDER BY dh.primary_ind DESC, dh.domain_name) AS domain_names
  FROM blti_domain_host dh
  GROUP BY dh.blti_domain_config_pk1
)
SELECT
  sc.term_name,
  sc.course_id,
  sc.course_name,
  sc.ultra_status,                                -- U = Ultra, C = Classic (Original), P = preview, N = not set
  COALESCE(d.domain_names, '(none)') AS lti11_registration,
  m.match_type,                                   -- placement, domain, unregistered host, deleted placement
  string_agg(DISTINCT m.placement_name, ', ') AS placement_or_host,
  COUNT(*) AS content_items,
  COUNT(*) FILTER (WHERE li.available_ind = 'Y') AS available_items,
  MAX(li.dtcreated)::date AS newest_item
FROM matched m
JOIN lti_items li
  ON li.pk1 = m.pk1
LEFT JOIN blti_domain_config dc
  ON dc.pk1 = m.blti_domain_config_pk1
LEFT JOIN domains d
  ON d.blti_domain_config_pk1 = dc.pk1
JOIN selected_courses sc
  ON sc.pk1 = li.crsmain_pk1
WHERE (dc.lti_type = '1'                          -- LTI 1.1 registrations only ('3' = LTI 1.3)
       OR m.blti_domain_config_pk1 IS NULL)       -- plus unregistered hosts and deleted placements
  -- AND m.match_type IN ('placement', 'domain')    -- example: registered tools only
  -- AND d.domain_names ILIKE '%example-tool.com%'  -- example: one tool
  -- AND sc.ultra_status = 'U'                      -- example: Ultra courses only
GROUP BY sc.term_name, sc.course_id, sc.course_name, sc.ultra_status, d.domain_names, m.match_type,
  CASE WHEN m.blti_domain_config_pk1 IS NULL THEN m.placement_name END  -- one row per unregistered host / deleted placement
ORDER BY m.match_type, lti11_registration, placement_or_host, content_items DESC, sc.course_id;
