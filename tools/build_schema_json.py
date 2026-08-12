#!/usr/bin/env python3
"""
Parses the generated schema HTML under docs/schema-<version>/schema/tables/**
into a single structured JSON file (tables, columns, primary keys, foreign
keys, indexes). Stdlib only - no pip install required.

Usage:
    python tools/build_schema_json.py [schema-version-dir]

If no directory is given, the single schema-* directory under docs/ is used.
Output is written to <schema-dir>/schema/schema.json.
"""

import json
import re
import sys
from collections import deque
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Recurring columns documented in docs/key-tables.md's "Common Fields"
# section - flagging which ones a table has is a cheap, purely structural
# signal for "does this behave like a standard entity table."
COMMON_FIELDS = [
    "pk1",
    "row_status",
    "available_ind",
    "dtcreated",
    "dtmodified",
    "batch_uid",
    "data_src_pk1",
    "uuid",
]

# Well-known core entity tables used as BFS sources for anchor_distance -
# how many FK hops a table is from the tables most reporting work starts
# from. Lower = more central to typical use cases.
ANCHOR_TABLES = ["course_main", "users", "course_contents", "course_users"]

# A DDA deployment spans five physical databases, not one (see
# docs/index.md's "DDA Database Overview"). The vendor schema HTML groups
# tables by an informal internal schema-folder label, and for two labels
# specifically that label has been empirically confirmed to predict a
# separate physical database: diffing a live core-DB connection's
# information_schema against these docs showed every table present here but
# absent live was labeled "stats" or "admin".
#
# This does NOT generalize to every schema-folder label, though - e.g. the
# "cms" label (cms_bookmarks, cms_comments, etc.) looks like it should mean
# the separate _cms_doc content-system database by name alone, but is
# empirically wrong: all 28 of those tables showed up in a live *primary*
# DB connection. The actual _cms_doc tables (xyf_files, xyf_urls per
# content_system_queries.md) aren't documented in this schema package at
# all. Only add an entry here once it's been checked against a live
# connection the way stats/admin were - don't extend this by name-pattern
# guessing.
DATABASE_HINTS = {
    "stats": "Long-term/historical data. Lives in a separate database, pattern BB<deployment_id>_stats.",
    "admin": "Internal system/instance coordination. Lives in a separate database (exact naming pattern not documented).",
}
DEFAULT_DATABASE_HINT = "Primary database (BB<deployment_id>) - what a standard DDA connection exposes directly."


def strip_tags(fragment: str) -> str:
    text = re.sub(r"<[^>]+>", " ", fragment)
    text = text.replace("&quot;", '"').replace("&amp;", "&")
    text = text.replace("&#39;", "'").replace("&apos;", "'")
    return re.sub(r"\s+", " ", text).strip()


def extract_section(html: str, label: str) -> str | None:
    pattern = rf"<h3><span>{re.escape(label)}</span></h3>\s*<div>(.*?)</div>\s*(?=<h3>|<table)"
    m = re.search(pattern, html, re.S)
    return m.group(1) if m else None


def parse_primary_key(section: str | None) -> dict | None:
    if not section:
        return None
    name_m = re.search(r'<p class="primaryName">(.*?)</p>', section, re.S)
    columns = re.findall(r'<a href="#column-([\w]+)">', section)
    return {"name": strip_tags(name_m.group(1)) if name_m else None, "columns": columns}


def resolve_referenced_table(desc: str) -> str | None:
    # The vendor-generated FK description sentence isn't perfectly uniform
    # across the schema - try progressively looser patterns before giving up.
    patterns = [
        r"(?:of|on)\s+(?:the\s+)?(?:\[[\w-]+\]\.)?(\S+?)\s+table\b",
        r"referencing the\s+(\S+?)\s+table\b",
        r"key to\s+(?:\[[\w-]+\]\.)?(\S+?)[.\s]",
    ]
    for p in patterns:
        m = re.search(p, desc)
        if m:
            return m.group(1)
    return None


def parse_foreign_keys(section: str | None) -> list:
    if not section:
        return []
    results = []
    # Most FKs reference the target's primary key and have one <ul> of this
    # table's own columns. Some reference a named unique constraint instead
    # and carry a second <ul> spelling out the schema-qualified target
    # table/column via a link - both forms are handled here.
    pattern = re.compile(
        r"<li>\s*(?P<name>[\w]+)\s*(?:<span>(?P<span>.*?)</span>\s*)?"
        r"<p>(?P<desc>.*?)</p>\s*<ul>\s*(?P<cols>.*?)\s*</ul>"
        r"(?:\s*<ul>\s*(?P<target_cols>.*?)\s*</ul>)?\s*</li>",
        re.S,
    )
    for m in pattern.finditer(section):
        desc = strip_tags(m.group("desc"))
        referenced_table = resolve_referenced_table(desc)
        referenced_column = None
        if m.group("target_cols"):
            link_m = re.search(r"tables/[\w]+/([\w]+)\.html", m.group("target_cols"))
            if link_m:
                referenced_table = link_m.group(1)
            cols_m = re.findall(r'<a href="#column-([\w]+)">', m.group("target_cols"))
            if cols_m:
                referenced_column = cols_m[-1]
        results.append(
            {
                "name": m.group("name").strip(),
                "on_delete": strip_tags(m.group("span")).strip("()") if m.group("span") else None,
                "referenced_table": referenced_table,
                "referenced_column": referenced_column,
                "columns": re.findall(r'<a href="#column-([\w]+)">', m.group("cols")),
            }
        )
    return results


def parse_indexes(section: str | None) -> list:
    if not section:
        return []
    results = []
    pattern = re.compile(
        r"<li>\s*(?P<name>[\w]+)\s*<ul>\s*(?P<cols>.*?)\s*</ul>\s*</li>", re.S
    )
    for m in pattern.finditer(section):
        results.append(
            {
                "name": m.group("name").strip(),
                "columns": re.findall(r'<a href="#column-([\w]+)">', m.group("cols")),
            }
        )
    return results


def parse_columns(html: str) -> list:
    table_m = re.search(r'<table title="Columns">.*?<tbody>(.*?)</table>', html, re.S)
    if not table_m:
        return []
    columns = []
    for row_m in re.finditer(r"<tr>(.*?)</tr>", table_m.group(1), re.S):
        cells = re.findall(r"<td[^>]*>(.*?)</td>", row_m.group(1), re.S)
        if len(cells) != 8:
            continue
        name_m = re.search(r'<a name="column-([\w]+)">', cells[0])
        if not name_m:
            continue
        value_constraint = None
        vc_raw = cells[3]
        if strip_tags(vc_raw):
            name_part = re.sub(r"<ul>.*", "", vc_raw, flags=re.S)
            values = re.findall(r"<span>(.*?)</span>", vc_raw, re.S)
            value_constraint = {
                "name": strip_tags(name_part) or None,
                "values": [strip_tags(v) for v in values] if values else [],
            }
        columns.append(
            {
                "name": name_m.group(1),
                "type": strip_tags(cells[1]),
                "default": strip_tags(cells[2]) or None,
                "value_constraint": value_constraint,
                "default_constraint": strip_tags(cells[4]) or None,
                "identity": strip_tags(cells[5]).lower() == "true",
                "nullable": strip_tags(cells[6]).lower() == "true",
                "description": strip_tags(cells[7]) or None,
            }
        )
    return columns


def parse_table_file(path: Path) -> dict:
    html = path.read_text(encoding="utf-8", errors="replace")

    h1_m = re.search(r"<h1>\s*(\w+)\s*(?:<p>(.*?)</p>)?\s*</h1>", html, re.S)
    table_name = h1_m.group(1) if h1_m else path.stem
    description = strip_tags(h1_m.group(2)) if h1_m and h1_m.group(2) else None

    return {
        "schema": path.parent.name,
        "table": table_name,
        "description": description,
        "primary_key": parse_primary_key(extract_section(html, "Primary key constraint")),
        "foreign_keys": parse_foreign_keys(extract_section(html, "Foreign key constraints")),
        "indexes": parse_indexes(extract_section(html, "Indexes")),
        "columns": parse_columns(html),
    }


def annotate_common_fields(tables: list) -> None:
    for t in tables:
        col_names = {c["name"] for c in t["columns"]}
        t["common_fields"] = [f for f in COMMON_FIELDS if f in col_names]


def annotate_anchor_distance(tables: list, relationships: list) -> None:
    # Undirected: a table referencing an anchor is just as "close" to it as
    # one the anchor references - direction doesn't matter for relevance.
    adjacency: dict = {}
    for rel in relationships:
        a, b = rel["from_table"], rel["to_table"]
        if not a or not b:
            continue
        adjacency.setdefault(a, set()).add(b)
        adjacency.setdefault(b, set()).add(a)

    distance = {}
    nearest_anchor = {}
    queue = deque()
    for anchor in ANCHOR_TABLES:
        distance[anchor] = 0
        nearest_anchor[anchor] = anchor
        queue.append(anchor)

    while queue:
        current = queue.popleft()
        for neighbor in adjacency.get(current, ()):
            if neighbor not in distance:
                distance[neighbor] = distance[current] + 1
                nearest_anchor[neighbor] = nearest_anchor[current]
                queue.append(neighbor)

    for t in tables:
        t["anchor_distance"] = distance.get(t["table"])
        t["nearest_anchor"] = nearest_anchor.get(t["table"])


def build_schema_index(tables: list) -> dict:
    index: dict = {}
    for t in tables:
        index.setdefault(t["schema"], []).append(t["table"])
    for names in index.values():
        names.sort()
    return dict(sorted(index.items()))


def build_database_hints(schemas_index: dict) -> dict:
    return {
        schema: DATABASE_HINTS.get(schema, DEFAULT_DATABASE_HINT)
        for schema in schemas_index
    }


def find_schema_dir(arg: str | None) -> Path:
    if arg:
        return REPO_ROOT / arg
    candidates = sorted((REPO_ROOT / "docs").glob("schema-*"))
    if not candidates:
        sys.exit("No docs/schema-* directory found.")
    return candidates[-1]


def main() -> None:
    schema_dir = find_schema_dir(sys.argv[1] if len(sys.argv) > 1 else None)
    tables_dir = schema_dir / "schema" / "tables"
    if not tables_dir.is_dir():
        sys.exit(f"Not found: {tables_dir}")

    table_files = sorted(tables_dir.glob("*/*.html"))
    tables = [parse_table_file(f) for f in table_files]

    relationships = [
        {
            "from_table": t["table"],
            "from_column": col,
            "to_table": fk["referenced_table"],
        }
        for t in tables
        for fk in t["foreign_keys"]
        for col in fk["columns"]
    ]

    annotate_common_fields(tables)
    annotate_anchor_distance(tables, relationships)
    schemas_index = build_schema_index(tables)

    output = {
        "schema_version": schema_dir.name.replace("schema-", ""),
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "table_count": len(tables),
        "anchor_tables": ANCHOR_TABLES,
        "schemas": schemas_index,
        "database_hints": build_database_hints(schemas_index),
        "tables": tables,
        "relationships": relationships,
    }

    out_path = schema_dir / "schema" / "schema.json"
    out_path.write_text(json.dumps(output, indent=2), encoding="utf-8")
    print(f"Wrote {len(tables)} tables ({len(relationships)} FK relationships) to {out_path}")


if __name__ == "__main__":
    main()
