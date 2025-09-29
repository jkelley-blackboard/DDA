erDiagram
    mi_node {
        bigint pk1
        bigint parent_pk1
    }
    mi_affiliate_context {
        bigint pk1
        bigint mi_node_pk1
        bigint context_override_pk1
    }
    application_setting {
        bigint pk1
        bigint mi_affiliate_context_pk1
        bigint application
    }
    application {
        bigint application
    }
    content_handler_settings {
        bigint pk1
        bigint mi_affiliate_context_pk1
        bigint content_handler_pk1
    }
    content_handlers {
        bigint pk1
    }

    %% Self-join
    mi_node ||--o{ mi_node : "parent_pk1"

    %% Context
    mi_node ||--|| mi_affiliate_context : "mi_node_pk1"

    %% Applications
    mi_affiliate_context ||--o{ application_setting : "mi_affiliate_context_pk1"
    application_setting ||--|| application : "application"

    %% Content Handlers
    mi_affiliate_context ||--o{ content_handler_settings : "mi_affiliate_context_pk1"
    content_handler_settings ||--|| content_handlers : "content_handler_pk1"

    %% Overrides
    mi_affiliate_context ||--|| mi_affiliate_context : "context_override_pk1 (ctx_override)"
    mi_affiliate_context ||--|| mi_affiliate_context : "context_override_pk1 (lock_override)"
