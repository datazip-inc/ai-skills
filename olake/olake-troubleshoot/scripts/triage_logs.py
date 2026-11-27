#!/usr/bin/env python3
"""Match an OLake log against the Common errors tables of every installed OLake skill.

Prints only the matching rows (skill, error, cause, fix) and the log line that matched, so the
agent never reads the whole log. Every skill's error table is read at run time: a row added to
any skill is found with no extra index.

Usage:
  triage_logs.py <log file> [<log file> ...]
  docker logs olake-ui 2>&1 | triage_logs.py -

A pattern is each `code span` in the first column of an error table that looks like log text: it
has a space or is not a lower-case name (`NoSuchBucket`, `ORA-01017`; not `discover` or a file
name). Parts around `...` and `<placeholder>` must all appear in one log line, in any order.
"""

import re
import sys
from pathlib import Path

SKILLS_ROOT = Path(__file__).resolve().parent.parent.parent
HEADING_RE = re.compile(r"^#{2,3} .*error", re.IGNORECASE)
CODE_RE = re.compile(r"`([^`]+)`")
SPLIT_RE = re.compile(r"\.\.\.|…|<[^>]+>")
MIN_PART = 4
MIN_PATTERN = 8
MAX_LINE = 300
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


def table_rows(text):
    """Yield the cells of each row in tables under a heading that mentions errors."""
    in_errors = False
    for line in text.splitlines():
        if line.startswith("#"):
            in_errors = bool(HEADING_RE.match(line))
            continue
        if not in_errors or not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 3 or set(cells[0]) <= set("-: ") or cells[0].lower().startswith("error"):
            continue
        yield cells


def looks_like_log(parts):
    if sum(len(p) for p in parts) < MIN_PATTERN:
        return False
    return any(" " in p or not p.islower() for p in parts)


def load_patterns():
    patterns = []
    for doc in sorted(SKILLS_ROOT.rglob("*.md")):
        skill = next((p.name for p in [doc.parent, *doc.parents] if (p / "SKILL.md").is_file()), None)
        if skill is None:
            continue
        for cells in table_rows(doc.read_text(encoding="utf-8")):
            for code in CODE_RE.findall(cells[0]):
                parts = [p.strip() for p in SPLIT_RE.split(code) if len(p.strip()) >= MIN_PART]
                if looks_like_log(parts):
                    patterns.append((parts, skill, doc, cells))
    return patterns


def read_lines(args):
    for arg in args:
        stream = sys.stdin if arg == "-" else open(arg, encoding="utf-8", errors="replace")
        with stream:
            yield from stream


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip())
        return 2
    patterns = load_patterns()
    matched = {}
    tail = []
    for line in read_lines(sys.argv[1:]):
        line = ANSI_RE.sub("", line.rstrip("\n"))
        if re.search(r"fatal|error", line, re.IGNORECASE):
            tail = (tail + [line])[-3:]
        for parts, skill, doc, cells in patterns:
            key = (skill, cells[0])
            if key not in matched and all(p in line for p in parts):
                matched[key] = (doc, cells, line)

    if not matched:
        print("No known error matched. Last error lines:")
        for line in tail or ["(none)"]:
            print("  " + line[:MAX_LINE])
        print("Next: name the stage (olake-troubleshoot), then search that skill's references.")
        return 1

    for (skill, error), (doc, cells, line) in matched.items():
        print(f"[{skill}] {doc.relative_to(SKILLS_ROOT)}")
        print(f"  error: {error}")
        print(f"  cause: {cells[1]}")
        print(f"  fix:   {cells[2]}")
        print(f"  log:   {line[:MAX_LINE]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
