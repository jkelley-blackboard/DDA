
WITH RECURSIVE node_path AS (
    -- Anchor: start from root nodes
    SELECT 
        n.pk1,
        n.parent_pk1,
        n.domain_pk1,
        n.batch_uid,
        0 AS level,
        format('%s (%s / %s)', n.name, n.pk1, n.batch_uid) AS path
    FROM mi_node n
    WHERE n.parent_pk1 IS NULL

    UNION ALL

    -- Recursive: append child node info
    SELECT 
        c.pk1,
        c.parent_pk1,
        c.domain_pk1,
        c.batch_uid,
        np.level + 1 AS level,
        np.path || ' -> ' || format('%s (%s / %s)', c.name, c.pk1, c.batch_uid) AS path
    FROM mi_node c
    INNER JOIN node_path np ON c.parent_pk1 = np.pk1
)

SELECT 
    n.pk1,
    n.name,
    np.level,
    np.path
FROM mi_node n
JOIN node_path np ON np.pk1 = n.pk1
ORDER BY np.level;






