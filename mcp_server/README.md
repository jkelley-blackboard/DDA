# dda-schema-mcp

An MCP (Model Context Protocol) server exposing read-only lookup tools over the Blackboard DDA Postgres schema — search tables, look up columns/types/constraints, and trace foreign-key relationships, without needing a live database connection or credentials.

It serves `docs/schema-4000.19.0/schema/schema.json`, generated from the vendor's schema HTML by [`tools/build_schema_json.py`](../tools/build_schema_json.py). Regenerate that file (and re-point this server at a new version via `DDA_SCHEMA_JSON_PATH`, see below) if you're working against a different DDA schema release.

**Scope:** schema lookup only. This server does not connect to a live DDA database and needs no credentials — it's safe to run against just the data already committed to this repo. Live-database scripts (`tools/dda_query.ps1`, `tools/dda_schema_introspect.ps1/.sql`) are separate, stay local/`.gitignore`d, and are not part of this server.

## Setup

```
cd mcp_server
pip install -e .
```

(`uv` works too if you have it — `uv sync` — but isn't required.)

## Tools

| Tool | Purpose |
|---|---|
| `list_schemas()` | Vendor schema-folder groups, per-group table counts, and which physical DDA database each group's tables actually live in. Call this first. |
| `list_tables(schema=None, common_only=False, limit=100, offset=0)` | Lightweight table summaries, optionally filtered/paginated. |
| `get_table(table, schema=None)` | Full detail for one table: columns, types, constraints, enum values, PK/FK, indexes. |
| `search_tables(query, limit=30)` | Substring search across table/column names and descriptions. |
| `get_relationships(table, schema=None, direction="both")` | FK edges touching a table, incoming and/or outgoing. |

**Ambiguous table names:** 24 table names (including `course_main`, `users`, and `course_users`) exist in more than one schema-folder group — e.g. `course_main` lives under both `as_core` and `stats`. `get_table`/`get_relationships` return `{"ambiguous": true, "candidates": [...]}` instead of guessing when `schema` isn't given for one of these; call again with `schema` set.

## Running it

Manual check (opens the MCP Inspector in a browser, no client config needed):

```
mcp dev src/dda_schema_mcp/server.py
```

Point a real MCP client at it — Claude Code:

```
claude mcp add dda-schema -- python -m dda_schema_mcp.server
```

(run from inside `mcp_server/` with its environment active, or use an absolute interpreter path). Claude Desktop: add an equivalent entry to `claude_desktop_config.json`'s `mcpServers` block, with an **absolute** path — relative paths are the most common reason a server silently doesn't show up.

## Testing

```
pytest
```

Two layers: `tests/test_schema_data.py` unit-tests the plain query functions directly, `tests/test_server.py` exercises the actual tool wiring via an in-memory MCP client session (no subprocess, no live DDA connection).

## Possible follow-ups (not built yet)

- Layering in `docs/key-tables.md`'s hand-written gotchas and join-pattern notes for the handful of tables it covers in depth — it's prose, not structured data, so this needs its own small parser rather than a JSON lookup.
- A live-query tool (see `tools/dda_query.ps1` for the equivalent standalone script) — deliberately out of scope for this server since it would require handling real DDA credentials.
