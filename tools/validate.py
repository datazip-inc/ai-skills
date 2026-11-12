#!/usr/bin/env python3
"""Validate every skill in the repo.

Checks, per SKILL.md:
  - frontmatter parses as YAML and has name, description, metadata.olake_version, metadata.status
  - name matches the folder, is kebab-case, at most 64 chars, and is unique
  - description is at most 1024 chars
  - metadata.parent, when set, names an existing skill
  - the skill is listed in its product's .claude-plugin/plugin.json
  - SKILL.md is at most MAX_LINES lines
  - stable skills have every required section

Also checks that every plugin.json skill path and marketplace.json plugin source exists.
Exits 1 on any error.
"""

import json
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
MAX_LINES = 200
NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
STATUSES = {"stable", "experimental"}
REQUIRED_SECTIONS = [
    "When to use",
    "Inputs to collect",
    "Prerequisites",
    "Steps",
    "Verify",
    "Common errors",
    "Next",
    "Rules",
]

errors = []


def error(path, msg):
    errors.append(f"{path.relative_to(ROOT)}: {msg}")


def read_frontmatter(path):
    text = path.read_text(encoding="utf-8")
    match = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not match:
        error(path, "missing frontmatter (--- ... ---) at the top of the file")
        return None, text
    try:
        data = yaml.safe_load(match.group(1))
    except yaml.YAMLError as exc:
        error(path, f"frontmatter is not valid YAML (quote values that contain ': '): {exc}")
        return None, text
    if not isinstance(data, dict):
        error(path, "frontmatter must be a YAML mapping")
        return None, text
    return data, text


def check_skill(path, data, text):
    name = data.get("name")
    folder = path.parent.name
    if not isinstance(name, str) or not name:
        error(path, "missing name")
    else:
        if name != folder:
            error(path, f"name '{name}' does not match folder '{folder}'")
        if not NAME_RE.match(name) or len(name) > 64:
            error(path, f"name '{name}' must be kebab-case and at most 64 chars")

    desc = data.get("description")
    if not isinstance(desc, str) or not desc.strip():
        error(path, "missing description")
    elif len(desc) > 1024:
        error(path, f"description is {len(desc)} chars, max 1024")

    meta = data.get("metadata") or {}
    if not isinstance(meta, dict):
        error(path, "metadata must be a mapping")
        meta = {}
    status = meta.get("status")
    if status not in STATUSES:
        error(path, f"metadata.status must be one of {sorted(STATUSES)}, got {status!r}")
    if not meta.get("olake_version"):
        error(path, "missing metadata.olake_version")

    lines = text.count("\n") + 1
    if lines > MAX_LINES:
        error(path, f"{lines} lines, max {MAX_LINES}; move depth into references/")

    if status == "stable":
        headings = set(re.findall(r"^## (.+?)\s*$", text, re.MULTILINE))
        for section in REQUIRED_SECTIONS:
            if section not in headings:
                error(path, f"missing required section '## {section}'")

    return name, meta.get("parent")


def check_plugin(plugin_dir, skill_dirs):
    manifest = plugin_dir / ".claude-plugin" / "plugin.json"
    try:
        listed = json.loads(manifest.read_text(encoding="utf-8")).get("skills", [])
    except (OSError, json.JSONDecodeError) as exc:
        error(manifest, f"cannot read: {exc}")
        return
    listed_dirs = set()
    for entry in listed:
        target = (plugin_dir / entry).resolve()
        if not (target / "SKILL.md").is_file():
            error(manifest, f"skills entry '{entry}' has no SKILL.md")
        listed_dirs.add(target)
    for skill_dir in skill_dirs:
        if skill_dir.resolve() not in listed_dirs:
            rel = "./" + str(skill_dir.relative_to(plugin_dir))
            error(manifest, f"skill '{rel}' is not listed in skills")


def check_marketplace():
    manifest = ROOT / ".claude-plugin" / "marketplace.json"
    if not manifest.is_file():
        return
    try:
        plugins = json.loads(manifest.read_text(encoding="utf-8")).get("plugins", [])
    except json.JSONDecodeError as exc:
        error(manifest, f"invalid JSON: {exc}")
        return
    for plugin in plugins:
        source = plugin.get("source")
        if isinstance(source, str) and not (ROOT / source / ".claude-plugin" / "plugin.json").is_file():
            error(manifest, f"plugin '{plugin.get('name')}' source '{source}' has no .claude-plugin/plugin.json")


def main():
    plugin_dirs = [p.parent.parent for p in ROOT.glob("*/.claude-plugin/plugin.json")]
    names = {}
    parents = []

    for plugin_dir in plugin_dirs:
        skill_files = sorted(plugin_dir.rglob("SKILL.md"))
        for path in skill_files:
            data, text = read_frontmatter(path)
            if data is None:
                continue
            name, parent = check_skill(path, data, text)
            if name:
                if name in names:
                    error(path, f"duplicate name '{name}', also in {names[name].relative_to(ROOT)}")
                names[name] = path
            if parent:
                parents.append((path, parent))
        check_plugin(plugin_dir, [p.parent for p in skill_files])

    for path, parent in parents:
        if parent not in names:
            error(path, f"metadata.parent '{parent}' is not an existing skill")

    check_marketplace()

    if errors:
        print("\n".join(errors))
        print(f"\n{len(errors)} error(s)")
        return 1
    print(f"OK: {len(names)} skill(s) in {len(plugin_dirs)} plugin(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
