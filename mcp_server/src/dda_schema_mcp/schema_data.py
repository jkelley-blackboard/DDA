import json
import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_SCHEMA_PATH = REPO_ROOT / "docs" / "schema-4000.19.0" / "schema" / "schema.json"
SCHEMA_PATH = Path(os.environ.get("DDA_SCHEMA_JSON_PATH", DEFAULT_SCHEMA_PATH))

_data = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
_tables = _data["tables"]
_relationships = _data["relationships"]

# 24 table names (including 3 of the 4 anchor tables) exist in more than one
# schema-folder group - e.g. course_main lives under both "as_core" and
# "stats". A bare-name lookup is genuinely ambiguous for exactly the tables
# people look up most, so every name-based lookup goes through this index
# and _resolve() below rather than assuming the first match is the right one.
_by_name: dict[str, list[dict]] = {}
for _t in _tables:
    _by_name.setdefault(_t["table"].lower(), []).append(_t)


def list_schemas() -> dict:
    counts = {schema: len(names) for schema, names in _data["schemas"].items()}
    return {
        "schema_version": _data["schema_version"],
        "generated_at": _data["generated_at"],
        "table_count": _data["table_count"],
        "anchor_tables": _data["anchor_tables"],
        "schemas": [
            {
                "name": schema,
                "table_count": count,
                "database_hint": _data["database_hints"].get(schema),
            }
            for schema, count in sorted(counts.items())
        ],
    }


def _resolve(table: str, schema: str | None):
    """Returns (table_dict, None) on an unambiguous match, (None, ambiguous_payload) if
    more than one schema-folder has this name and `schema` wasn't given to disambiguate,
    or (None, None) if nothing matches at all."""
    candidates = _by_name.get(table.lower())
    if not candidates:
        return None, None
    if schema is not None:
        schema = schema.lower()
        matches = [t for t in candidates if t["schema"].lower() == schema]
        return (matches[0], None) if matches else (None, None)
    if len(candidates) == 1:
        return candidates[0], None
    return None, {
        "ambiguous": True,
        "table": table,
        "candidates": [
            {"schema": t["schema"], "table": t["table"], "description": t["description"]}
            for t in candidates
        ],
    }


def _not_found(table: str, schema: str | None) -> dict:
    suffix = f" in schema '{schema}'" if schema else ""
    return {"error": f"No table named '{table}' found{suffix}"}


def list_tables(
    schema: str | None = None,
    common_only: bool = False,
    limit: int = 100,
    offset: int = 0,
) -> dict:
    filtered = _tables
    if schema is not None:
        schema_lower = schema.lower()
        filtered = [t for t in filtered if t["schema"].lower() == schema_lower]
    if common_only:
        filtered = [t for t in filtered if t["common_fields"]]

    total = len(filtered)
    page = filtered[offset : offset + limit]
    return {
        "total_count": total,
        "returned_count": len(page),
        "tables": [
            {
                "schema": t["schema"],
                "table": t["table"],
                "description": t["description"],
                "common_fields": t["common_fields"],
                "anchor_distance": t["anchor_distance"],
            }
            for t in page
        ],
    }


def get_table(table: str, schema: str | None = None) -> dict:
    match, ambiguous = _resolve(table, schema)
    if ambiguous:
        return ambiguous
    if match is None:
        return _not_found(table, schema)
    return match


_MATCH_RANK = {"table_name": 0, "column_name": 1, "description": 2, "column_description": 3}


def search_tables(query: str, limit: int = 30) -> dict:
    q = query.lower().strip()
    if not q:
        return {"query": query, "match_count": 0, "results": []}

    results = []
    for t in _tables:
        table_name = t["table"].lower()
        description = (t.get("description") or "").lower()
        col_names = {c["name"].lower() for c in t["columns"]}
        col_descriptions = " ".join((c.get("description") or "").lower() for c in t["columns"])

        if q in table_name:
            matched_in = "table_name"
        elif any(q in c for c in col_names):
            matched_in = "column_name"
        elif q in description:
            matched_in = "description"
        elif q in col_descriptions:
            matched_in = "column_description"
        else:
            continue

        results.append(
            {
                "schema": t["schema"],
                "table": t["table"],
                "matched_in": matched_in,
                "description": t["description"],
            }
        )

    results.sort(key=lambda r: _MATCH_RANK[r["matched_in"]])
    return {"query": query, "match_count": len(results), "results": results[:limit]}


def get_relationships(table: str, schema: str | None = None, direction: str = "both") -> dict:
    match, ambiguous = _resolve(table, schema)
    if ambiguous:
        return ambiguous
    if match is None:
        return _not_found(table, schema)

    name = match["table"]
    result = {"schema": match["schema"], "table": name}
    if direction in ("outgoing", "both"):
        result["outgoing"] = [r for r in _relationships if r["from_table"] == name]
    if direction in ("incoming", "both"):
        result["incoming"] = [r for r in _relationships if r["to_table"] == name]
    return result
