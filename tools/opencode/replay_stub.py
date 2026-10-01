#!/usr/bin/env python3
"""A fake streaming DeepInfra endpoint, used only by tools/opencode/check_replay.sh.

Binds 127.0.0.1 on an OS-assigned port and prints that port alone on its first
line of stdout, then serves forever. It never talks to the real service.

Reads on every request:
  INCURSION_REPLAY_MODE   one of "ok" (default), "markup", "markup-inline",
                          "repeat", "no-usage", "no-cost", "error".
  INCURSION_REPLAY_COUNT  if set, the running POST count is written here.
  INCURSION_REPLAY_SAVE   if set, the raw request body of POST N is written
                          to "<SAVE>/request-N.json" (1-based), so a check can
                          prove what the client actually sent.

It answers every POST with a fixed SSE stream (Content-Type text/event-stream)
so the client's stream parser is exercised offline.
"""

import http.server
import json
import os
import sys

USAGE = {
    "prompt_tokens": 11,
    "completion_tokens": 3,
    "total_tokens": 14,
    "estimated_cost": 0.000123,
    "prompt_tokens_details": {"cached_tokens": 7},
}


def bump_count():
    path = os.environ.get("INCURSION_REPLAY_COUNT")
    if not path:
        return 0
    try:
        with open(path) as fh:
            n = int(fh.read().strip() or "0")
    except (FileNotFoundError, ValueError):
        n = 0
    n += 1
    with open(path, "w") as fh:
        fh.write(str(n))
    return n


def chunk(delta, finish=None, usage=None, ident="stub-1"):
    payload = {
        "id": ident,
        "object": "chat.completion.chunk",
        "model": "deepseek-ai/DeepSeek-V4.1-Flash",
        "choices": [
            {"index": 0, "delta": delta, "finish_reason": finish}
        ],
        "usage": usage,
    }
    return "data: " + json.dumps(payload) + "\n\n"


def tool_chunk(names, finish=None, usage=None):
    calls = []
    for i, name in enumerate(names):
        calls.append(
            {
                "index": i,
                "id": "call-%d" % i,
                "type": "function",
                "function": {"name": name, "arguments": ""},
            }
        )
    return chunk({"tool_calls": calls}, finish=finish, usage=usage)


def sse_ok():
    out = []
    out.append(chunk({"role": "assistant", "content": ""}))
    out.append(chunk({"content": "STUB REPLY OK"}))
    out.append(tool_chunk(["read"], finish="tool_calls", usage=USAGE))
    out.append("data: [DONE]\n\n")
    return "".join(out)


def sse_markup():
    out = []
    out.append(chunk({"role": "assistant", "content": ""}))
    out.append(chunk({"content": "before\n<\uFF5CDSML\uFF5Cinvoke tail after\n"}))
    out.append(chunk({"reasoning_content": "hmm"}))
    out.append(chunk({}, finish="stop", usage=USAGE))
    out.append("data: [DONE]\n\n")
    return "".join(out)


def sse_markup_inline():
    out = []
    out.append(chunk({"role": "assistant", "content": ""}))
    out.append(chunk({"content": "See line 2 of markup-dsml.jsonl: `<\uFF5CDSML\uFF5C parameter` and `</\uFF5C parameter>` -- just a quote.\n"}))
    out.append(chunk({"reasoning_content": "hmm"}))
    out.append(chunk({}, finish="stop", usage=USAGE))
    out.append("data: [DONE]\n\n")
    return "".join(out)


def sse_repeat():
    out = []
    out.append(chunk({"role": "assistant", "content": ""}))
    for _ in range(40):
        out.append(chunk({"content": "repeated line\n"}))
    out.append(chunk({}, finish="length", usage=USAGE))
    out.append("data: [DONE]\n\n")
    return "".join(out)


def sse_no_usage():
    out = []
    out.append(chunk({"role": "assistant", "content": ""}))
    out.append(chunk({"content": "no usage here"}, finish="stop"))
    out.append("data: [DONE]\n\n")
    return "".join(out)


# Fireworks' streamed usage chunk (measured): token counts but no
# estimated_cost, shape prompt_tokens=33, completion_tokens=20,
# reasoning_tokens=20. cached_tokens is nonzero here so the cached-price
# term is exercised: (33-5)*in + 5*cached + 20*out.
NO_COST_USAGE = {
    "prompt_tokens": 33,
    "completion_tokens": 20,
    "total_tokens": 53,
    "prompt_tokens_details": {"cached_tokens": 5},
    "completion_tokens_details": {"reasoning_tokens": 20},
}


def sse_no_cost():
    out = []
    out.append(chunk({"role": "assistant", "content": ""}))
    out.append(chunk({"content": "STUB REPLY OK"}))
    out.append(tool_chunk(["read"], finish="tool_calls", usage=NO_COST_USAGE))
    out.append("data: [DONE]\n\n")
    return "".join(out)


STREAMS = {
    "ok": sse_ok,
    "markup": sse_markup,
    "markup-inline": sse_markup_inline,
    "repeat": sse_repeat,
    "no-usage": sse_no_usage,
    "no-cost": sse_no_cost,
}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_POST(self):
        n = bump_count()
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)

        save_dir = os.environ.get("INCURSION_REPLAY_SAVE")
        if save_dir:
            try:
                with open(os.path.join(save_dir, "request-%d.json" % n), "wb") as fh:
                    fh.write(body)
            except OSError:
                pass

        mode = os.environ.get("INCURSION_REPLAY_MODE", "ok")
        if mode == "error":
            payload = json.dumps({"detail": "stub failure"}).encode("utf-8")
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        stream = STREAMS.get(mode, sse_ok)()
        data = stream.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main():
    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    print(server.server_address[1], flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
