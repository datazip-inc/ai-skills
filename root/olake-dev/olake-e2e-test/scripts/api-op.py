#!/usr/bin/env python3
"""Run one asynchronous OLake API operation and save its result.

Usage: api-op.py <run-dir> <api-path> <body.json> <result.json> [timeout-seconds]

POSTs the body to $OLAKE_URL/api/v1/project/123/<api-path> (OLAKE_URL defaults to http://localhost:8000) with the session cookie
from <run-dir>/cookies.txt (written by `curl -c` at login), long-polls the operation (POLL_WAIT seconds per call),
writes the result to <result.json> and prints one status line.
Exits 0 on "succeeded", 1 otherwise.

An operation that succeeded can still carry a failed result: for a test connection, check
data.connection_result.status in <result.json>.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

# Both stacks serve the UI and API on localhost:8000 (compose publishes the port, kind port-forwards it),
# under project id "123", the id the UI uses (olake-ui ui/src/config/apiConfig.ts).
# OLAKE_URL overrides the host and port, for a stack on another port or machine.
BASE = os.environ.get("OLAKE_URL", "http://localhost:8000").rstrip("/") + "/api/v1/project/123"
# Spec, test connection and discover finish in under 2 minutes on a warm stack: the silence limit in the skill's
# Waits table. A failed operation returns at once, whatever the limit.
DEFAULT_TIMEOUT = 120
# Each request returns at once, or after the 10-second long poll below; 30 seconds covers a slow container.
HTTP_TIMEOUT = 30
# The server holds an operations poll for up to this many seconds before it answers "running".
POLL_WAIT = 10


class ConnectFailed(Exception):
    pass


def main():
    if len(sys.argv) < 5:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    run_dir, path, body_file, result_file = sys.argv[1:5]
    timeout = int(sys.argv[5]) if len(sys.argv) > 5 else DEFAULT_TIMEOUT
    # curl writes the session cookie as an "#HttpOnly_" line, which http.cookiejar skips.
    cookies = []
    with open(f"{run_dir}/cookies.txt") as f:
        for line in f:
            line = line.strip().removeprefix("#HttpOnly_")
            fields = line.split("\t")
            if len(fields) == 7 and not line.startswith("#"):
                cookies.append(f"{fields[5]}={fields[6]}")
    headers = {"Content-Type": "application/json", "Cookie": "; ".join(cookies)}
    opener = urllib.request.build_opener()

    def call(url, data=None):
        """Return (HTTP status, JSON body). Errors from the server carry their reason in "message"."""
        req = urllib.request.Request(url, data=data, headers=headers)
        try:
            with opener.open(req, timeout=HTTP_TIMEOUT) as resp:
                status, raw = resp.status, resp.read()
        except urllib.error.HTTPError as exc:
            status, raw = exc.code, exc.read()
        except (urllib.error.URLError, OSError) as exc:
            raise ConnectFailed(f"{url}: {getattr(exc, 'reason', exc)}") from exc
        try:
            return status, json.loads(raw or b"{}")
        except ValueError:
            return status, {"message": raw[:300].decode(errors="replace")}

    def message(body):
        return str(body.get("message", ""))[:300]

    try:
        with open(body_file, "rb") as f:
            status, started = call(f"{BASE}/{path}", f.read())
        op_id = (started.get("data") or {}).get("operation_id")
        if not op_id:
            print(f"START FAILED http={status} {json.dumps(started)[:300]}")
            return 1

        deadline = time.time() + timeout
        state = "running"
        while state == "running" and time.time() < deadline:
            status, polled = call(f"{BASE}/operations/{op_id}?wait={POLL_WAIT}")
            if status != 200:
                print(f"POLL FAILED {op_id} http={status} {message(polled)}")
                return 1
            state = (polled.get("data") or {}).get("status", "unknown")
            if state == "running":
                print(f"running {op_id} {int(deadline - time.time())}s left", flush=True)
        if state == "running":
            print(f"STUCK {op_id}: still running after {timeout}s")
            return 1

        # A failed operation answers 500 here; its body is still saved as the result.
        status, result = call(f"{BASE}/operations/{op_id}/result")
    except ConnectFailed as exc:
        print(f"CONNECT FAILED {exc}")
        return 1

    with open(result_file, "w") as f:
        json.dump(result, f, indent=1)
    print(f"{state.upper()} {op_id} -> {result_file}")
    if state != "succeeded":
        print((polled.get("data") or {}).get("error", "")[:400])
        return 1
    if status != 200:
        print(f"RESULT FAILED {op_id} http={status} {message(result)}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
