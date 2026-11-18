#!/usr/bin/env python3
"""Check links in every Markdown file.

Relative links must point to an existing file or folder. With --external, http(s) links must
also return a status below 400. Links inside fenced code blocks are ignored.
Exits 1 on any broken link.
"""

import argparse
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
FENCE_RE = re.compile(r"^```.*?^```", re.MULTILINE | re.DOTALL)
SKIP_DIRS = {".git", "node_modules"}
TIMEOUT = 15


def markdown_files():
    for path in ROOT.rglob("*.md"):
        if not SKIP_DIRS.intersection(path.relative_to(ROOT).parts):
            yield path


def url_ok(url):
    headers = {"User-Agent": "ai-skills-link-check"}
    for method in ("HEAD", "GET"):
        try:
            req = urllib.request.Request(url, method=method, headers=headers)
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                return resp.status < 400, resp.status
        except urllib.error.HTTPError as exc:
            # Some servers reject HEAD; retry with GET before failing.
            if method == "HEAD" and exc.code in (403, 405):
                continue
            return False, exc.code
        except (urllib.error.URLError, TimeoutError) as exc:
            return False, str(exc)
    return False, "unreachable"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--external", action="store_true", help="also check http(s) links")
    args = parser.parse_args()

    broken = []
    checked_urls = {}
    for path in markdown_files():
        text = FENCE_RE.sub("", path.read_text(encoding="utf-8"))
        for target in LINK_RE.findall(text):
            if target.startswith(("http://", "https://")):
                if not args.external:
                    continue
                if target not in checked_urls:
                    checked_urls[target] = url_ok(target)
                ok, status = checked_urls[target]
                if not ok:
                    broken.append(f"{path.relative_to(ROOT)}: {target} ({status})")
            elif target.startswith(("#", "mailto:")):
                continue
            else:
                file_part = target.split("#", 1)[0]
                if file_part and not (path.parent / file_part).exists():
                    broken.append(f"{path.relative_to(ROOT)}: {target} (not found)")

    if broken:
        print("\n".join(broken))
        print(f"\n{len(broken)} broken link(s)")
        return 1
    print("OK: no broken links")
    return 0


if __name__ == "__main__":
    sys.exit(main())
