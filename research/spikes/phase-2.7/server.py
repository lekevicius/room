#!/usr/bin/env python3
"""Phase 2.7a test server (scripts/layout-modes.sh starts it).

HTTP on 127.0.0.1:8770 serves this directory. The same server answers as
http://127.0.0.1:8770 (the pinned "site") and http://localhost:8770 (an
"other site": a different host, so a different eTLD+1 for Peek's off-site
rule), plus:
  /redirect?to=URL           302 to URL (a redirect chain started by the site)
  /oauth/authorize?...       an "identity provider" page that sends the
                             browser back to redirect_uri with a code (302)
  /login (POST)              a form post answered with 303 to ?next=URL
"""
import http.server, os, sys, urllib.parse

ROOT = os.path.dirname(os.path.abspath(__file__))
PORT = 8770


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def redirect(self, location, code=302):
        self.send_response(code)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)
        if url.path == "/redirect":
            return self.redirect(query.get("to", ["/"])[0])
        if url.path == "/oauth/authorize":
            back = query.get("redirect_uri", ["http://127.0.0.1:%d/site.html" % PORT])[0]
            return self.redirect(back + ("&" if "?" in back else "?") + "code=room-test")
        super().do_GET()

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        fields = urllib.parse.parse_qs(self.rfile.read(length).decode())
        if url.path == "/login":
            return self.redirect(fields.get("next", ["/site.html"])[0], 303)
        self.send_error(404)


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print("serving %s on 127.0.0.1:%d" % (ROOT, PORT), file=sys.stderr)
    server.serve_forever()
