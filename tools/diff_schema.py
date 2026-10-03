#!/usr/bin/env python3
"""
Compares two schema.json files (as written by build_schema_json.py) and
reports what changed: tables added, removed or moved between schema groups,
and per-table column, foreign key and index changes. Also flags files in
sql_library/ and docs/ that mention a removed table or column. Stdlib only.

Usage:
    python tools/diff_schema.py OLD.json NEW.json

Prints a Markdown summary to stdout.
"""

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Where hand-written SQL and prose live. Generated schema folders and the
# changelog itself are excluded so they never count as "references".
REFERENCE_GLOBS = ["sql_library/**/*.sql", "docs/*.md"]
REFERENCE_EXCLUDE = {"docs/schema-changes.md"}


def load(path: Path) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _by_key(data: dict) -> dict:
    return {(t["schema"], t["table"]): t for t in data["tables"]}


def _column_changes(old: dict, new: dict) -> dict:
    old_cols = {c["name"]: c for c in old["columns"]}
    new_cols = {c["name"]: c for c in new["columns"]}
    changed = []
    for name in sorted(old_cols.keys() & new_cols.keys()):
        o, n = old_cols[name], new_cols[name]
        notes = []
        if o["type"] != n["type"]:
            notes.append(f"type `{o['type']}` → `{n['type']}`")
        if o["nullable"] != n["nullable"]:
            notes.append("now nullable" if n["nullable"] else "now NOT NULL")
        o_vals = (o["value_constraint"] or {}).get("values") or []
        n_vals = (n["value_constraint"] or {}).get("values") or []
        if o_vals != n_vals:
            added = [v for v in n_vals if v not in o_vals]
            removed = [v for v in o_vals if v not in n_vals]
            parts = []
            if added:
                parts.append("added " + ", ".join(f"`{v}`" for v in added))
            if removed:
                parts.append("removed " + ", ".join(f"`{v}`" for v in removed))
            notes.append("allowed values " + "; ".join(parts or ["reordered"]))
        if notes:
            changed.append({"column": name, "changes": notes})
    return {
        "columns_added": [
            {"column": c, "type": new_cols[c]["type"]}
            for c in sorted(new_cols.keys() - old_cols.keys())
        ],
        "columns_removed": sorted(old_cols.keys() - new_cols.keys()),
        "columns_changed": changed,
    }


def _named_changes(old: list, new: list, kind: str) -> dict:
    old_names = {x["name"] for x in old}
    new_names = {x["name"] for x in new}
    return {
        f"{kind}_added": sorted(new_names - old_names),
        f"{kind}_removed": sorted(old_names - new_names),
    }


def diff(old: dict, new: dict) -> dict:
    old_t, new_t = _by_key(old), _by_key(new)
    added_keys = new_t.keys() - old_t.keys()
    removed_keys = old_t.keys() - new_t.keys()

    # A table whose name disappears from one schema group and appears in
    # another is reported as moved, not as a remove plus an add.
    added_names = {}
    for k in added_keys:
        added_names.setdefault(k[1], []).append(k)
    moved = []
    for k in sorted(removed_keys):
        if len(added_names.get(k[1], [])) == 1:
            to = added_names.pop(k[1])[0]
            moved.append({"table": k[1], "from": k[0], "to": to[0]})
            added_keys.discard(to)
            removed_keys.discard(k)

    changed = []
    for k in sorted(old_t.keys() & new_t.keys()):
        entry = {"schema": k[0], "table": k[1]}
        entry.update(_column_changes(old_t[k], new_t[k]))
        entry.update(_named_changes(old_t[k]["foreign_keys"], new_t[k]["foreign_keys"], "fks"))
        entry.update(_named_changes(old_t[k]["indexes"], new_t[k]["indexes"], "indexes"))
        if any(v for key, v in entry.items() if key not in ("schema", "table")):
            changed.append(entry)

    return {
        "old_version": old["schema_version"],
        "new_version": new["schema_version"],
        "old_table_count": old["table_count"],
        "new_table_count": new["table_count"],
        "tables_added": [
            {"schema": k[0], "table": k[1], "description": new_t[k]["description"]}
            for k in sorted(added_keys)
        ],
        "tables_removed": [{"schema": k[0], "table": k[1]} for k in sorted(removed_keys)],
        "tables_moved": moved,
        "tables_changed": changed,
    }


def find_references(result: dict) -> list:
    """Files in this repo that mention a removed table or a removed column."""
    tables = {t["table"] for t in result["tables_removed"]}
    columns = {
        (c["table"], col)
        for c in result["tables_changed"]
        for col in c["columns_removed"]
    }
    if not tables and not columns:
        return []

    hits = []
    files = sorted({p for g in REFERENCE_GLOBS for p in REPO_ROOT.glob(g)})
    for path in files:
        rel = path.relative_to(REPO_ROOT).as_posix()
        if rel in REFERENCE_EXCLUDE:
            continue
        text = path.read_text(encoding="utf-8", errors="replace").lower()
        found = [t for t in sorted(tables) if re.search(rf"\b{re.escape(t.lower())}\b", text)]
        # A column name alone is too generic to flag; only count it when the
        # file also mentions the table it was removed from.
        found += [
            f"{t}.{c}"
            for t, c in sorted(columns)
            if re.search(rf"\b{re.escape(t.lower())}\b", text)
            and re.search(rf"\b{re.escape(c.lower())}\b", text)
        ]
        if found:
            hits.append({"file": rel, "mentions": found})
    return hits


def _summary_line(result: dict) -> str:
    return (
        f"{result['old_table_count']} → {result['new_table_count']} tables: "
        f"{len(result['tables_added'])} added, {len(result['tables_removed'])} removed, "
        f"{len(result['tables_moved'])} moved, {len(result['tables_changed'])} changed."
    )


def render_markdown(result: dict, references: list, heading_level: int = 2,
                    heading: str | None = None, intro: str | None = None) -> str:
    h = "#" * heading_level
    sub = "#" * (heading_level + 1)
    lines = [f"{h} {heading or result['new_version']}", ""]
    if intro:
        lines += [intro, ""]
    lines += [_summary_line(result), ""]

    if result["tables_added"]:
        lines += [f"{sub} Tables added", "", "| Table | Schema group | Description |", "|---|---|---|"]
        for t in result["tables_added"]:
            lines.append(f"| `{t['table']}` | {t['schema']} | {t['description'] or ''} |")
        lines.append("")

    if result["tables_removed"]:
        lines += [f"{sub} Tables removed", "", "| Table | Schema group |", "|---|---|"]
        for t in result["tables_removed"]:
            lines.append(f"| `{t['table']}` | {t['schema']} |")
        lines.append("")

    if result["tables_moved"]:
        lines += [f"{sub} Tables moved between schema groups", "", "| Table | From | To |", "|---|---|---|"]
        for t in result["tables_moved"]:
            lines.append(f"| `{t['table']}` | {t['from']} | {t['to']} |")
        lines.append("")

    if result["tables_changed"]:
        lines += [f"{sub} Tables changed", "", "| Table | Change |", "|---|---|"]
        for t in result["tables_changed"]:
            notes = []
            notes += [f"Added column `{c['column']}` ({c['type']})" for c in t["columns_added"]]
            notes += [f"Removed column `{c}`" for c in t["columns_removed"]]
            notes += [f"`{c['column']}`: {'; '.join(c['changes'])}" for c in t["columns_changed"]]
            notes += [f"Added foreign key `{n}`" for n in t["fks_added"]]
            notes += [f"Removed foreign key `{n}`" for n in t["fks_removed"]]
            notes += [f"Added index `{n}`" for n in t["indexes_added"]]
            notes += [f"Removed index `{n}`" for n in t["indexes_removed"]]
            lines.append(f"| `{t['table']}` ({t['schema']}) | {'<br>'.join(notes)} |")
        lines.append("")

    if references:
        lines += [
            f"{sub} Content in this repo that may need review",
            "",
            "These files mention a table or column that was removed.",
            "",
        ]
        for r in references:
            lines.append(f"- `{r['file']}`: {', '.join(f'`{m}`' for m in r['mentions'])}")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    result = diff(load(sys.argv[1]), load(sys.argv[2]))
    sys.stdout.reconfigure(encoding="utf-8")
    print(render_markdown(result, find_references(result)))


if __name__ == "__main__":
    main()
