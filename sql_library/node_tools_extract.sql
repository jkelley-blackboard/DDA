WITH RECURSIVE node_path AS (
    -- Anchor: start from root nodes
    SELECT 
        n.pk1,
        n.name,
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
        c.name,
        c.parent_pk1,
        c.domain_pk1,
        c.batch_uid,
        np.level + 1 AS level,
        np.path || ' -> ' || format('%s (%s / %s)', c.name, c.pk1, c.batch_uid) AS path
    FROM mi_node c
    INNER JOIN node_path np ON c.parent_pk1 = np.pk1
)

SELECT 
    --np.path,
    np.name AS node_name,
    app.pk1 AS tool_id,
    ctx.affiliate_id,
    ctx.assoc_object_type,
    ctx.affiliate_group_id,
    ctx.node_locked_ind,
    ctx.context_override_pk1,
    ctx.node_lock_override_pk1,
    app.application,
    app.name AS application_name,
    app.description AS application_description,
    setting.enabled_ind,
    setting.setting_type,
    setting.is_course_setting_ind,
    setting.application AS setting_application
FROM mi_affiliate_context ctx
JOIN application_setting setting ON setting.mi_affiliate_context_pk1 = ctx.pk1
JOIN application app ON app.application = setting.application
JOIN node_path np ON np.pk1 = ctx.mi_node_pk1
WHERE ctx.mi_node_pk1 = 716
 --AND ctx.affiliate_id ILIKE '%tutor%'
ORDER BY np.level;
