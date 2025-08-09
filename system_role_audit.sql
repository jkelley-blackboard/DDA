-- List of users with ANY system role other than 'None'
-- includes primary, secondary and node admin roles
-- jeff.kelley@anthology.com  2025-08-09
-- no support or warranty 


WITH second_sys_roles AS (
  SELECT
    user_pk1,
    STRING_AGG(system_role, ';') AS secondary_system_roles
  FROM domain_admin
  WHERE domain_pk1 = 1  -- "Top" system node
  GROUP BY user_pk1
),
node_specific_roles AS (
  SELECT 
    node_roles.user_pk1,
    '{' || STRING_AGG(
      '"' || node_roles.node || '": [' || node_roles.roles || ']',
      ', '
    ) || '}' AS node_specific_roles
  FROM (
    SELECT 
      da.user_pk1,
      min.name AS node,
      STRING_AGG('"' || sr.system_role || '"', ', ') AS roles
    FROM domain_admin da
      JOIN domain dom ON dom.pk1 = da.domain_pk1
      JOIN system_roles sr ON sr.system_role = da.system_role
      JOIN mi_node min ON min.domain_pk1 = dom.pk1
    WHERE dom.pk1 > 1
    GROUP BY da.user_pk1, min.name
  ) AS node_roles
  GROUP BY node_roles.user_pk1
)

SELECT
  uu.user_id,
  -- uu.student_id,
  -- uu.email,
  -- uu.firstname,
  -- uu.lastname,
  uu.system_role AS primary_system_role,
  ssr.secondary_system_roles,
  nsr.node_specific_roles AS node_roles
FROM users uu
  LEFT JOIN second_sys_roles ssr ON ssr.user_pk1 = uu.pk1
  LEFT JOIN node_specific_roles nsr ON nsr.user_pk1 = uu.pk1
WHERE uu.system_role != 'N' 
   OR ssr.secondary_system_roles IS NOT NULL
   OR nsr.node_specific_roles IS NOT NULL
ORDER BY uu.user_id
