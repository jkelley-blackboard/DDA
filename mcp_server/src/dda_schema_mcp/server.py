from mcp.server.fastmcp import FastMCP

from . import schema_data

mcp = FastMCP("dda-schema")


@mcp.tool()
def list_schemas() -> dict:
    """List all vendor schema-folder groups in the DDA schema, with per-group table
    counts and a hint about which physical DDA database each group's tables actually
    live in. Call this first to get the lay of the land before searching or looking up
    individual tables."""
    return schema_data.list_schemas()


@mcp.tool()
def list_tables(
    schema: str | None = None,
    common_only: bool = False,
    limit: int = 100,
    offset: int = 0,
) -> dict:
    """List tables with lightweight summaries (not full column detail) - optionally
    filtered to one schema-folder group, or to only tables with at least one of the
    standard "common fields" (pk1, row_status, available_ind, dtcreated, dtmodified,
    batch_uid, data_src_pk1, uuid). Paginated via limit/offset since there are 758
    tables total."""
    return schema_data.list_tables(schema=schema, common_only=common_only, limit=limit, offset=offset)


@mcp.tool()
def get_table(table: str, schema: str | None = None) -> dict:
    """Get full detail for one table by name (case-insensitive): description, columns
    (with types, nullability, defaults, enum value constraints), primary key, foreign
    keys, indexes, which common fields it has, and its FK-graph distance from the core
    anchor tables. Some table names exist in more than one schema-folder group (e.g.
    course_main exists in both "as_core" and "stats") - if the name is ambiguous and
    `schema` isn't given, this returns a list of candidates instead of guessing; call
    again with `schema` set to the one you want."""
    return schema_data.get_table(table, schema=schema)


@mcp.tool()
def search_tables(query: str, limit: int = 30) -> dict:
    """Case-insensitive substring search across table names, column names, and their
    descriptions. Results are ranked table-name match first, then column-name match,
    then description-text match. Useful for discovering relevant tables when you don't
    already know the exact name."""
    return schema_data.search_tables(query, limit=limit)


@mcp.tool()
def get_relationships(table: str, schema: str | None = None, direction: str = "both") -> dict:
    """Get the foreign-key relationships touching a table: which tables/columns it
    references (outgoing) and which tables/columns reference it (incoming). Same
    ambiguous-name handling as get_table. `direction` can be "outgoing", "incoming",
    or "both" (default)."""
    return schema_data.get_relationships(table, schema=schema, direction=direction)


if __name__ == "__main__":
    mcp.run()
