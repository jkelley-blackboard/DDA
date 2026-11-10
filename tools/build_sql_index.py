#!/usr/bin/env python3
"""Rebuild the index of SQL files in sql_library/README.md.

For every .sql file under sql_library/ (including subfolders), the index lists:
  - the file, linked
  - its description: the first non-blank line of the file, which must be a "--" comment
  - the date it last changed: today if it has uncommitted changes, otherwise its last commit date

The table is written between these two markers in sql_library/README.md, and nothing
outside them is touched:
  <!-- sql-index:start -->
  <!-- sql-index:end -->

Usage (from the repo root):
  python tools/build_sql_index.py           rewrite the index
  python tools/build_sql_index.py --check   exit 1 if the index is out of date (no write)

Standard library only. Needs git on PATH.
"""

from __future__ import annotations

import argparse
import datetime
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LIBRARY = REPO / "sql_library"
README = LIBRARY / "README.md"
START = "<!-- sql-index:start -->"
END = "<!-- sql-index:end -->"


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(REPO), *args],
        capture_output=True, text=True, encoding="utf-8", errors="replace", check=False,
    )
    return result.stdout.strip()


def description(path: Path) -> str | None:
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("--"):
            return stripped.lstrip("-").strip() or None
        return None
    return None


def last_changed(path: Path) -> str:
    rel = path.relative_to(REPO).as_posix()
    if git("status", "--porcelain", "--", rel):
        return datetime.date.today().isoformat()
    return git("log", "-1", "--format=%cs", "--", rel) or datetime.date.today().isoformat()


def build_table() -> tuple[str, list[str]]:
    warnings: list[str] = []
    files = sorted(LIBRARY.rglob("*.sql"), key=lambda p: (p.parent != LIBRARY, p.relative_to(LIBRARY).as_posix().lower()))
    rows = ["| File | Description | Last changed |", "|---|---|---|"]
    for path in files:
        rel = path.relative_to(LIBRARY).as_posix()
        desc = description(path)
        if desc is None:
            warnings.append(f"{rel}: first non-blank line is not a '--' description")
            desc = "(no description)"
        desc = desc.replace("|", "\\|")
        rows.append(f"| [`{rel}`]({rel}) | {desc} | {last_changed(path)} |")
    return "\n".join(rows), warnings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="exit 1 if the index is out of date; do not write")
    args = parser.parse_args()

    text = README.read_text(encoding="utf-8")
    if START not in text or END not in text:
        print(f"{README.relative_to(REPO)}: add the {START} and {END} markers first", file=sys.stderr)
        return 2

    table, warnings = build_table()
    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)

    head, rest = text.split(START, 1)
    _, tail = rest.split(END, 1)
    updated = f"{head}{START}\n{table}\n{END}{tail}"

    if args.check:
        if updated != text:
            print("sql_library/README.md index is out of date: run python tools/build_sql_index.py", file=sys.stderr)
            return 1
        print("index is up to date")
        return 0

    if updated != text:
        README.write_text(updated, encoding="utf-8", newline="\n")
        print(f"updated {README.relative_to(REPO)}")
    else:
        print("index already up to date")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
