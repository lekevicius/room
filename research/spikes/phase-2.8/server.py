#!/usr/bin/env python3
"""Phase 2.8b local endpoints (scripts/app-integration.sh --session 2.8b and
scripts/netlog-check.sh start it).

HTTP on 127.0.0.1:8771:
  GET  /appcast.xml       the dev update feed (one entry, version 9.9, no archive)
  POST /api/<id>/envelope/ a stand-in Sentry endpoint, answers 200
  CONNECT host:port       a logging proxy that refuses the tunnel (502)
Every request line is appended, with a timestamp, to the log file given as
the first argument (stderr without one), so a check can count who asked.
"""
import http.server, os, sys, time

ROOT = os.path.dirname(os.path.abspath(__file__))
PORT = 8771
LOG = open(sys.argv[1], "a", buffering=1) if len(sys.argv) > 1 else sys.stderr


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def log_message(self, fmt, *args):
        pass

    def record(self):
        LOG.write("%.3f %s %s %s\n" % (time.time(), self.command, self.path, self.headers.get("User-Agent", "-")))

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
        self.record()
        super().do_GET()

    def do_HEAD(self):
        self.record()
        super().do_HEAD()

    def do_POST(self):
        self.record()
        length = int(self.headers.get("Content-Length", "0") or 0)
        if length:
            self.rfile.read(length)
        body = b"{}"
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_CONNECT(self):
        self.record()
        self.send_response(502)
        self.end_headers()


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
