#!/usr/bin/env python3
"""A fake DeepInfra endpoint, used only by tools/check_deepseek.sh (bead
inc-3dgz). It never talks to the real service; it exists so the check can
run with no network request at all.

Binds 127.0.0.1 on an OS-assigned port and prints that port, alone, on its
first line of stdout, then serves forever. Reads INCURSION_STUB_MODE on
every request ("ok", "no-cost", "error") and writes the running request
count to the path in INCURSION_STUB_COUNT, if set.
"""

import http.server
import json
import os
import sys


def bump_count():
    path = os.environ.get("INCURSION_STUB_COUNT")
    if not path:
        return
    try:
        with open(path) as fh:
            n = int(fh.read().strip() or "0")
    except (FileNotFoundError, ValueError):
        n = 0
    with open(path, "w") as fh:
        fh.write(str(n + 1))


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # keep the check's own output clean

    def do_POST(self):
        bump_count()
        length = int(self.headers.get("Content-Length", 0))
        self.rfile.read(length)  # drain the body; the stub never inspects it

        mode = os.environ.get("INCURSION_STUB_MODE", "ok")
        if mode == "error":
            body = json.dumps({"detail": "stub failure"}).encode("utf-8")
            self.send_response(500)
        else:
            usage = {
                "prompt_tokens": 11,
                "completion_tokens": 3,
                "total_tokens": 14,
                "prompt_tokens_details": {"cached_tokens": 7},
            }
            if mode != "no-cost":
                usage["estimated_cost"] = 0.000123
            payload = {
                "id": "stub-1",
                "choices": [{"message": {"role": "assistant", "content": "STUB REPLY OK"}}],
                "usage": usage,
            }
            body = json.dumps(payload).encode("utf-8")
            self.send_response(200)

        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    print(server.server_address[1], flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
