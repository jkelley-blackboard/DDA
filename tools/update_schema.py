#!/usr/bin/env python3
"""
Moves the schema explorer to a new vendor schema package. Stdlib only.

Not every build Blackboard publishes to bbprepo reaches customers: only some
are released to Test/Stage and Production. By default this script targets the
highest version that has reached Test/Stage, read from the Feature Test/Stage
Release notices on status.blackboard.com, so the site is never ahead of what
institutions can see on their own Test/Stage servers.

Steps, when a newer target exists:
  1. Download schema-<v>.zip from bbprepo and verify its SHA-256.
  2. Unpack it to docs/schema-<v>/.
  3. Generate schema.json and all_tables_combined.html.
  4. Diff against the current version and add an entry to docs/schema-changes.md.
  5. Repoint version references in the repo's Markdown files.
  6. Delete the old docs/schema-<old>/ folder.

Changes are left uncommitted for review.

Usage:
    python tools/update_schema.py                 # auto: latest Test/Stage release
    python tools/update_schema.py --version 4001.4.0
    python tools/update_schema.py --check         # report only, change nothing
    python tools/update_schema.py --pr-body body.md
"""

import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

import build_combined_html
import build_schema_json
import diff_schema
from build_schema_json import REPO_ROOT, find_schema_dir, version_key

REPO_URL = "https://bbprepo.blackboard.com"
METADATA_URL = f"{REPO_URL}/repository/releases/bbdn/schema/maven-metadata.xml"
SEARCH_URL = f"{REPO_URL}/service/rest/v1/search?repository=releases&group=bbdn&name=schema&version={{v}}"
STATUS_URL = "https://status.blackboard.com/api/v2/scheduled-maintenances.json"

# e.g. "Blackboard SaaS 4001.2.0: Feature Test/Stage Release (scheduled for Sep 29, 2026)"
TEST_STAGE_NOTICE = re.compile(r"SaaS (\d+\.\d+\.\d+): Feature Test/Stage Release")
# A notice counts once the release has started, not when it is announced:
# releases are sometimes postponed after the notice goes up.
RELEASED_STATUSES = {"in_progress", "verifying", "completed"}

CHANGELOG = REPO_ROOT / "docs" / "schema-changes.md"
CHANGELOG_MARKER = "<!-- New entries are added below this line by tools/update_schema.py -->"


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "dda-schema-updater"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


def published_builds() -> list:
    root = ET.fromstring(fetch(METADATA_URL))
    return sorted((v.text for v in root.iter("version")), key=version_key)


def test_stage_versions() -> list:
    notices = json.loads(fetch(STATUS_URL))["scheduled_maintenances"]
    versions = {
        m.group(1)
        for n in notices
        if n["status"] in RELEASED_STATUSES
        and (m := TEST_STAGE_NOTICE.search(n["name"]))
    }
    return sorted(versions, key=version_key)


def package_asset(version: str) -> dict:
    items = json.loads(fetch(SEARCH_URL.format(v=version)))["items"]
    for item in items:
        for asset in item["assets"]:
            if asset["path"].endswith(f"schema-{version}.zip"):
                return asset
    sys.exit(f"schema-{version}.zip not found on bbprepo.")


def download_and_unpack(version: str, dest: Path) -> None:
    asset = package_asset(version)
    print(f"Downloading {asset['downloadUrl']}")
    data = fetch(asset["downloadUrl"])
    digest = hashlib.sha256(data).hexdigest()
    if digest != asset["checksum"]["sha256"]:
        sys.exit(f"SHA-256 mismatch for schema-{version}.zip: got {digest}")

    with tempfile.TemporaryDirectory() as tmp:
        zip_path = Path(tmp) / "schema.zip"
        zip_path.write_bytes(data)
        with zipfile.ZipFile(zip_path) as zf:
            for name in zf.namelist():
                if not name.startswith("schema/") or ".." in Path(name).parts:
                    sys.exit(f"Unexpected path in package: {name}")
            zf.extractall(dest)


def update_references(old: str, new: str) -> list:
    """Repoint links and labels in tracked Markdown files at the new version."""
    old_short, new_short = old.rsplit(".", 1)[0], new.rsplit(".", 1)[0]
    patterns = [
        (re.compile(rf"schema-{re.escape(old)}\b"), f"schema-{new}"),
        (re.compile(rf"\bv{re.escape(old_short)}(?!\.?\d)"), f"v{new_short}"),
    ]
    tracked = subprocess.run(
        ["git", "ls-files", "*.md"], cwd=REPO_ROOT, capture_output=True, text=True, check=True
    ).stdout.split()
    changed = []
    for rel in tracked:
        if rel.startswith("docs/schema-"):  # generated folders, and the changelog's history
            continue
        path = REPO_ROOT / rel
        text = path.read_text(encoding="utf-8")
        updated = text
        for pattern, repl in patterns:
            updated = pattern.sub(repl, updated)
        if updated != text:
            path.write_text(updated, encoding="utf-8", newline="")
            changed.append(rel)
    return changed


def changelog_intro(old: str, new: str, builds: list, date: str) -> str:
    between = [b for b in builds if version_key(old) < version_key(b) < version_key(new)]
    text = f"Updated {date}. Compares the {old} and {new} Test/Stage releases."
    if between:
        listed = ", ".join(between)
        text += (
            f" Intermediate builds ({listed}) were not released to Test/Stage on their own,"
            " so their changes are included here."
        )
    return text


def add_changelog_entry(entry: str) -> None:
    text = CHANGELOG.read_text(encoding="utf-8")
    if CHANGELOG_MARKER not in text:
        sys.exit(f"Marker not found in {CHANGELOG}")
    text = text.replace(CHANGELOG_MARKER, f"{CHANGELOG_MARKER}\n\n{entry.rstrip()}\n", 1)
    CHANGELOG.write_text(text, encoding="utf-8", newline="")


def set_output(**values) -> None:
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as f:
            for k, v in values.items():
                f.write(f"{k}={v}\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version", help="Target this version instead of the latest Test/Stage release.")
    parser.add_argument("--check", action="store_true", help="Report what would happen; change nothing.")
    parser.add_argument("--pr-body", type=Path, help="Also write the change summary to this file.")
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")

    old_dir = find_schema_dir()
    current = old_dir.name.replace("schema-", "")
    builds = published_builds()

    if args.version:
        target = args.version
    else:
        released = [v for v in test_stage_versions() if v in builds]
        if not released:
            print("No Test/Stage release notice matches a package on bbprepo; nothing to do.")
            set_output(updated="false")
            return
        target = released[-1]

    print(f"Current: {current}  Target: {target}  Latest build on bbprepo: {builds[-1]}")
    if version_key(target) <= version_key(current):
        print("Already up to date.")
        set_output(updated="false")
        return
    if target not in builds:
        sys.exit(f"{target} is not published on bbprepo.")
    if args.check:
        set_output(updated="false", version=target)
        return

    new_dir = REPO_ROOT / "docs" / f"schema-{target}"
    if new_dir.exists():
        sys.exit(f"{new_dir} already exists.")
    download_and_unpack(target, new_dir)

    build_schema_json.write(new_dir)
    build_combined_html.write(new_dir)

    old_data = diff_schema.load(old_dir / "schema" / "schema.json")
    new_data = diff_schema.load(new_dir / "schema" / "schema.json")
    result = diff_schema.diff(old_data, new_data)
    refs = diff_schema.find_references(result)
    today = datetime.date.today().isoformat()
    entry = diff_schema.render_markdown(
        result, refs, heading=f"{target} (from {current})",
        intro=changelog_intro(current, target, builds, today),
    )
    add_changelog_entry(entry)

    changed = update_references(current, target)
    shutil.rmtree(old_dir)

    print(f"Updated {current} → {target}. Repointed: {', '.join(changed) or 'none'}")
    if args.pr_body:
        args.pr_body.write_text(entry, encoding="utf-8")
    set_output(updated="true", version=target, old_version=current)


if __name__ == "__main__":
    main()
