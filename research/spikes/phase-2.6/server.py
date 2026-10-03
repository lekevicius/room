#!/usr/bin/env python3
"""Phase 2.6 test server (scripts/chrome-surfaces.sh starts it).

HTTP on 127.0.0.1:8766 serves this directory, plus /auth (Basic auth,
user "room", password "secret", realm "Room test") and, for 2.6b,
/download?name=&size=&rate=[&nolength=1] (an attachment of `size` zero
bytes sent at `rate` bytes per second, 0 = at once; `nolength` leaves out
Content-Length). HTTPS on 127.0.0.1:8767 serves the same files with a
self-signed certificate made at start (CN and SAN 127.0.0.1), so Chromium
reports ERR_CERT_AUTHORITY_INVALID.
"""
import base64, http.server, os, ssl, subprocess, sys, tempfile, threading, time, urllib.parse

ROOT = os.path.dirname(os.path.abspath(__file__))
HTTP_PORT, HTTPS_PORT = 8766, 8767
EXPECTED = "Basic " + base64.b64encode(b"room:secret").decode()


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
        if self.path == "/download" or self.path.startswith("/download?"):
            return self.download()
        if self.path.startswith("/auth"):
            if self.headers.get("Authorization") != EXPECTED:
                body = b"<title>Not signed in</title><p>401</p>"
                self.send_response(401)
                self.send_header("WWW-Authenticate", 'Basic realm="Room test"')
                self.send_header("Content-Type", "text/html")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            body = b"<title>Signed in as room</title><h1>Signed in as room</h1>"
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()


    def download(self):
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        name = query.get("name", ["room-test.bin"])[0]
        size = int(query.get("size", ["1000000"])[0])
        rate = int(query.get("rate", ["0"])[0])
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Disposition", 'attachment; filename="%s"' % name)
        if "nolength" not in query:
            self.send_header("Content-Length", str(size))
        self.end_headers()
        chunk = 64 * 1024
        sent = 0
        try:
            while sent < size:
                part = min(chunk, size - sent)
                self.wfile.write(b"\0" * part)
                self.wfile.flush()
                sent += part
                if rate > 0:
                    time.sleep(part / rate)
        except (BrokenPipeError, ConnectionResetError):
            pass  # the download was cancelled


def self_signed_context():
    directory = tempfile.mkdtemp(prefix="room-2.6a-cert-")
    key, cert = os.path.join(directory, "key.pem"), os.path.join(directory, "cert.pem")
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert, "-days", "2",
                    "-subj", "/CN=127.0.0.1", "-addext", "subjectAltName=IP:127.0.0.1"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    return context


def main():
    http_server = http.server.ThreadingHTTPServer(("127.0.0.1", HTTP_PORT), Handler)
    https_server = http.server.ThreadingHTTPServer(("127.0.0.1", HTTPS_PORT), Handler)
    https_server.socket = self_signed_context().wrap_socket(https_server.socket, server_side=True)
    threading.Thread(target=https_server.serve_forever, daemon=True).start()
    print("serving http://127.0.0.1:%d and https://127.0.0.1:%d" % (HTTP_PORT, HTTPS_PORT), flush=True)
    http_server.serve_forever()


if __name__ == "__main__":
    main()
