-- look up users by institution role (primary and secondary)

-- © 2025 Anthology Inc. All rights reserved.
-- This software is provided "as is" without warranty or support
-- jeff.kelley@anthology.com 

WITH my_constants AS (
  SELECT 'STAFF'::text AS role_id  --enter the role ID here
)
SELECT DISTINCT 
  DATE(uu.dt_created) AS created_on,
  DATE(uu.last_login_date) AS last_login,
  uu.user_id,
  uu.first_name,
  uu.last_name,
  uu.email,
  pri_ir.role_name AS primary_role,
  STRING_AGG(sec_ir.role_name, ', ') AS secondary_roles

FROM users uu
LEFT JOIN user_roles ur ON ur.users_pk1 = uu.pk1 
LEFT JOIN institution_roles sec_ir ON sec_ir.pk1 = ur.institution_roles_pk1
INNER JOIN institution_roles pri_ir ON pri_ir.pk1 = uu.institution_roles_pk1

WHERE pri_ir.role_id = (SELECT role_id FROM my_constants)
  OR sec_ir.role_id = (SELECT role_id FROM my_constants)

GROUP BY uu.dt_created, uu.last_login_date, uu.user_id, uu.first_name, uu.last_name, uu.email, pri_ir.role_name

ORDER BY uu.last_name;
