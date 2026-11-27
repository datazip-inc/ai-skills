---
description: Find why an OLake check, discover, sync or UI job failed, and fix it
argument-hint: "[log file or failing step]"
---

Debug this OLake failure: $ARGUMENTS

Load the `olake-troubleshoot` skill and follow it. Run `olake-troubleshoot/scripts/triage_logs.py`
on the log instead of reading the log. Report the matched error row, apply its fix after any
confirmation the skill requires, and rerun only the failed stage.
