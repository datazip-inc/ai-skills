#!/usr/bin/env python3
"""UserPromptSubmit hook: point the agent at olake-protocol when a prompt is about OLake.

Prints one line of context on the first matching prompt of a session and nothing otherwise.
"""
import json
import os
import re
import sys
import tempfile

OLAKE = re.compile(r"\bolake\b", re.I)
LAKE = re.compile(r"\b(iceberg|parquet|lakehouse)\b", re.I)
MOVE = re.compile(r"\b(sync\w*|replicat\w*|ingest\w*|cdc|backfill|pipeline)\b", re.I)
SOURCE = re.compile(r"\b(postgres\w*|mysql|mongo\w*|mssql|sql server|oracle|db2|kafka|s3)\b", re.I)

HINT = (
    "This prompt is about OLake. Load the olake-protocol skill first; it routes to the source, "
    "destination and deploy skills. For an error or a pasted log, load olake-troubleshoot."
)


def matches(prompt: str) -> bool:
    if OLAKE.search(prompt):
        return True
    return bool(LAKE.search(prompt) and (MOVE.search(prompt) or SOURCE.search(prompt)))


def first_time(session_id: str) -> bool:
    if not session_id:
        return True
    marker = os.path.join(tempfile.gettempdir(), f"olake-skills-{re.sub(r'[^A-Za-z0-9_-]', '', session_id)}")
    if os.path.exists(marker):
        return False
    try:
        open(marker, "w").close()
    except OSError:
        pass
    return True


def main() -> None:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return
    if matches(event.get("prompt", "")) and first_time(event.get("session_id", "")):
        print(HINT)


if __name__ == "__main__":
    main()
