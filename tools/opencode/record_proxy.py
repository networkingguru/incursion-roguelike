#!/usr/bin/env python3
"""record_proxy.py -- a local recording proxy in front of DeepInfra.

    tools/opencode/record_proxy.py --dir <record dir> --port-file <file>

Binds 127.0.0.1 on an ephemeral port, writes the chosen port to --port-file
(written to a temp name then renamed, so a reader never sees a partial file),
and serves until SIGTERM. Point opencode at it by exporting
INCURSION_DS_BASEURL=http://127.0.0.1:<port>/v1/openai (tools/opencode_ds.sh
does this). The upstream origin is env INCURSION_DS_UPSTREAM, default
https://api.deepinfra.com.

Every request/response is recorded under --dir so a run that produced a
repetition loop can later be replayed:

    NNNN.request.json   the request body bytes exactly as received
    NNNN.response.txt   the response body bytes exactly as read from upstream
    NNNN.meta.json      {method, path, status, started, finished,
                         request_bytes, response_bytes}

NNNN is the zero-padded request counter, assigned under a lock so concurrent
requests keep distinct numbers.

The method, path, query and body are forwarded to the upstream unchanged, and
the response is streamed back chunk by chunk with a flush after each, so a
streamed reply (opencode uses stream:true, server-sent events) reaches the
client before upstream has finished. Request headers are forwarded except
Host, Connection, Accept-Encoding and hop-by-hop headers; the client's
Authorization header is passed through untouched.

This proxy NEVER reads a key from the environment or a file, and NEVER writes
the Authorization header, any header value, or any key into a record file. It
holds no credential of its own: the only credential in play is the client's
Authorization header, which is relayed and never recorded.

An upstream network error returns 502 to the client with a short JSON body and
still writes meta with status 502.

Exit: 0 after SIGTERM; 2 on a usage error.
"""

import argparse
import http.client
import json
import os
import signal
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFAULT_UPSTREAM = "https://api.deepinfra.com"

# Headers the proxy must not forward, or must handle itself:
#   Host             -- must name the upstream, not this proxy.
#   Connection and the hop-by-hop headers -- end-to-end, not hop-to-hop.
#   Accept-Encoding  -- dropped so the upstream replies uncompressed and the
#                       recorded response.txt holds readable bytes; the proxy
#                       does not re-add an encoding it cannot decode.
#   Content-Length   -- recomputed (or dropped when re-chunking) by http.client.
HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
    "host",
    "accept-encoding",
    "content-length",
}

CHUNK_SIZE = 8192


class Counter:
    """Hands out request numbers under a lock so they never collide."""

    def __init__(self):
        self._lock = threading.Lock()
        self._n = 0

    def next(self):
        with self._lock:
            self._n += 1
            return self._n


def parse_upstream(origin):
    if "://" not in origin:
        raise ValueError("upstream must be a URL like https://api.deepinfra.com")
    scheme, rest = origin.split("://", 1)
    if scheme not in ("http", "https"):
        raise ValueError("upstream scheme must be http or https")
    host_port = rest.split("/", 1)[0]
    if ":" in host_port:
        host, port_s = host_port.rsplit(":", 1)
        port = int(port_s)
    else:
        host, port = host_port, (443 if scheme == "https" else 80)
    if not host:
        raise ValueError("upstream has no host")
    return scheme, host, port


def connection_class(scheme):
    return (
        http.client.HTTPSConnection
        if scheme == "https"
        else http.client.HTTPConnection
    )


def write_meta(path, method, req_path, status, started, finished, req_bytes, resp_bytes):
    # Only scalar request facts and byte counts: no header values, no key.
    meta = {
        "method": method,
        "path": req_path,
        "status": status,
        "started": started,
        "finished": finished,
        "request_bytes": req_bytes,
        "response_bytes": resp_bytes,
    }
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(meta, fh)
        fh.write("\n")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    upstream = ("https", "api.deepinfra.com", 443)
    record_dir = "."
    counter = None

    def log_message(self, *args):
        # Never let BaseHTTPRequestHandler echo request lines or headers.
        pass

    def _read_chunked(self):
        # Minimal chunked decoder for the request body; the bytes are kept
        # de-chunked (so request.json is the payload, not the framing).
        chunks = []
        while True:
            size_line = self.rfile.readline(65536).strip()
            if not size_line:
                break
            size = int(size_line.split(b";", 1)[0], 16)
            if size == 0:
                self.rfile.readline(65536)
                break
            chunks.append(self.rfile.read(size))
            self.rfile.readline(65536)
        return b"".join(chunks)

    def _relay(self):
        started = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        n = self.counter.next()
        base = os.path.join(self.record_dir, "%04d" % n)

        # Read the request body: by Content-Length, else by chunked framing,
        # else there is none. Never a bare read() to EOF, which would hang a
        # keep-alive client that sent no body.
        transfer = (self.headers.get("Transfer-Encoding") or "").lower()
        length = self.headers.get("Content-Length")
        if "chunked" in transfer:
            body = self._read_chunked()
        elif length is not None:
            body = self.rfile.read(int(length))
        else:
            body = b""

        # The request body is the one file that holds caller bytes; it is
        # written before the upstream call so a failed forward is still
        # recorded.
        with open(base + ".request.json", "wb") as fh:
            fh.write(body)

        method = self.command
        req_path = self.path
        scheme, host, port = self.upstream

        # Forward every header except the ones this hop owns. Authorization
        # rides along untouched.
        out_headers = {}
        for key, value in self.headers.items():
            if key.lower() in HOP_BY_HOP:
                continue
            out_headers[key] = value
        out_headers["Host"] = host

        conn = connection_class(scheme)(host, port)
        status = 502
        resp_bytes = 0
        try:
            conn.request(method, req_path, body=body, headers=out_headers)
            upstream_resp = conn.getresponse()
            status = upstream_resp.status

            # Copy status and headers, dropping hop-by-hop headers and
            # Content-Length. The client reply is length-less and framed by
            # connection close: the proxy re-emits de-chunked bytes and the
            # client learns where the stream ends when the socket closes.
            self.send_response(status)
            for key, value in upstream_resp.getheaders():
                if key.lower() in HOP_BY_HOP:
                    continue
                self.send_header(key, value)
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True

            with open(base + ".response.txt", "wb") as out:
                while True:
                    # read1 returns as soon as any data is available; read(n)
                    # would block until n bytes or end of stream, holding a
                    # streamed chunk back from the client.
                    chunk = upstream_resp.read1(CHUNK_SIZE)
                    if not chunk:
                        break
                    out.write(chunk)
                    self.wfile.write(chunk)
                    self.wfile.flush()
                    resp_bytes += len(chunk)
        except (OSError, http.client.HTTPException):
            status = 502
            try:
                payload = json.dumps(
                    {"error": "upstream request failed"}
                ).encode()
                self.send_response(502)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                self.wfile.flush()
            except (OSError, ValueError):
                pass
        finally:
            conn.close()
            finished = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            write_meta(
                base + ".meta.json",
                method,
                req_path,
                status,
                started,
                finished,
                len(body),
                resp_bytes,
            )

    do_GET = _relay
    do_POST = _relay
    do_PUT = _relay
    do_PATCH = _relay
    do_DELETE = _relay
    do_HEAD = _relay
    do_OPTIONS = _relay


def usage_error(message):
    sys.stderr.write("record_proxy: %s\n" % message)
    sys.stderr.write("usage: tools/opencode/record_proxy.py --dir <dir> --port-file <file>\n")
    sys.exit(2)


def main(argv):
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--dir", required=True)
    parser.add_argument("--port-file", required=True)
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        if exc.code != 0:
            usage_error("bad arguments")
        raise

    try:
        upstream = parse_upstream(os.environ.get("INCURSION_DS_UPSTREAM", DEFAULT_UPSTREAM))
    except ValueError as exc:
        usage_error(str(exc))

    try:
        os.makedirs(args.dir, exist_ok=True)
    except OSError as exc:
        usage_error("cannot make record dir %s: %s" % (args.dir, exc))

    Handler.upstream = upstream
    Handler.record_dir = args.dir
    Handler.counter = Counter()

    try:
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    except OSError as exc:
        usage_error("cannot bind 127.0.0.1: %s" % exc)

    port = server.server_address[1]
    tmp = args.port_file + ".tmp.%d" % os.getpid()
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write("%d\n" % port)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, args.port_file)
    except OSError as exc:
        usage_error("cannot write port file %s: %s" % (args.port_file, exc))

    def term(_signum, _frame):
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, term)
    signal.signal(signal.SIGINT, term)
    try:
        server.serve_forever()
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
