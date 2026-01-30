-- List of Node admins and roles
-- jeff.kelley@anthology.com 2026-01-30
-- No warranty or support


WITH RECURSIVE Ancestors AS (
    SELECT 
        pk1,
        parent_pk1, 
        CAST(name AS VARCHAR) AS ancestor_path
    FROM mi_node
    WHERE parent_pk1 IS NULL  -- Assuming the root node has a NULL parent_pk1

    UNION ALL

    SELECT 
        child.pk1, 
        child.parent_pk1, 
        CONCAT(parent.ancestor_path, ' -> ', child.name) AS ancestor_path
    FROM mi_node AS child
    INNER JOIN Ancestors AS parent
    ON child.parent_pk1 = parent.pk1
)

SELECT 
    uu.user_id,
    min.name AS node_name,
    sr.name AS system_role,
    DATE(da.dtmodified) AS last_modified,
    an.ancestor_path AS node_path
FROM domain_admin da
JOIN users uu ON uu.pk1 = da.user_pk1
JOIN domain dom ON dom.pk1 = da.domain_pk1
JOIN system_roles sr ON sr.system_role = da.system_role
JOIN mi_node min ON min.domain_pk1 = dom.pk1
JOIN Ancestors an ON an.pk1 = min.pk1
WHERE dom.pk1 > 1   --not the root (Top) node