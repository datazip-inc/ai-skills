#!/usr/bin/env python3
"""Estimate how many tokens the skills cost an agent.

  - always: name + description of every listed skill, loaded into every session
  - body: each SKILL.md, loaded when the skill runs
  - refs: the references/ files a skill links to, loaded only when a step needs them

Tokens are estimated as characters / 4. Use the numbers to compare versions, not as exact counts.

Usage:
  python tools/measure_tokens.py                      # every skill
  python tools/measure_tokens.py --path olake-protocol,olake-driver-postgres,olake-destination-iceberg
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
FIELD_RE = re.compile(r"^(name|description):\s*(.*)$", re.MULTILINE)


def tokens(text):
    return (len(text) + 3) // 4


def listed_skills(root):
    skills = {}
    for manifest in root.glob("*/.claude-plugin/plugin.json"):
        plugin_dir = manifest.parent.parent
        for entry in json.loads(manifest.read_text(encoding="utf-8")).get("skills", []):
            path = (plugin_dir / entry / "SKILL.md").resolve()
            if path.is_file():
                skills[path.parent.name] = path
    return skills


def measure(path):
    text = path.read_text(encoding="utf-8")
    match = FRONTMATTER_RE.match(text)
    front = dict(FIELD_RE.findall(match.group(1))) if match else {}
    always = tokens(front.get("name", "") + front.get("description", ""))
    refs = sum(tokens(p.read_text(encoding="utf-8")) for p in (path.parent / "references").rglob("*.md"))
    return always, tokens(text), refs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", help="comma-separated skill names loaded in one run")
    parser.add_argument("--root", type=Path, default=ROOT, help="repo to measure (default: this one)")
    args = parser.parse_args()

    skills = listed_skills(args.root)
    rows = {name: measure(path) for name, path in sorted(skills.items())}

    print(f"{'skill':<34} {'always':>7} {'body':>7} {'refs':>7}")
    for name, (always, body, refs) in rows.items():
        print(f"{name:<34} {always:>7} {body:>7} {refs:>7}")
    print(f"{'total (always loaded)':<34} {sum(r[0] for r in rows.values()):>7}")

    if args.path:
        names = [n.strip() for n in args.path.split(",") if n.strip()]
        missing = [n for n in names if n not in rows]
        if missing:
            print(f"unknown skill(s): {', '.join(missing)}", file=sys.stderr)
            return 1
        body = sum(rows[n][1] for n in names)
        always = sum(r[0] for r in rows.values())
        print(f"\npath {','.join(names)}: always {always} + bodies {body} = {always + body} tokens "
              f"(references extra, up to {sum(rows[n][2] for n in names)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
