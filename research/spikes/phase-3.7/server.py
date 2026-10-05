#!/usr/bin/env python3
"""Phase 3.7a test server (scripts/passwords-autofill.sh starts it).

HTTP on port 8772, answering as 127.0.0.1 and as localhost (IPv4 and IPv6
loopback), so the password manager sees two sites: login.html posts to
/login and gets a "Signed in" page, signup.html posts to /signup,
address.html to /address. HTTPS on 127.0.0.1:8773 serves the same files with
a self-signed certificate made at start (CN localhost, SAN 127.0.0.1 and
localhost) for card.html (Chrome offers and fills cards only in a secure
context): the certificate's SPKI hash is printed and written to the file
given as the first argument, for --ignore-certificate-errors-spki-list.
Every POST is logged to stderr with its field names only (never values).
"""
import base64, hashlib, html, http.server, os, socket, ssl, subprocess, sys, tempfile, threading, urllib.parse

ROOT = os.path.dirname(os.path.abspath(__file__))
HTTP_PORT, HTTPS_PORT = 8772, 8773

PAGES = {
    "/login": ("Signed in", lambda f: "Signed in as %s" % f.get("username", "")),
    "/signup": ("Account created", lambda f: "Account created for %s" % f.get("username", "")),
    "/address": ("Address received", lambda f: "Shipping to %s" % f.get("name", "")),
    "/card": ("Payment received", lambda f: "Paid with a card ending %s" % f.get("cc-number", "")[-4:]),
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        length = int(self.headers.get("Content-Length") or 0)
        fields = {k: v[0] for k, v in urllib.parse.parse_qs(self.rfile.read(length).decode("utf-8", "replace")).items()}
        sys.stderr.write("POST %s host=%s fields=%s\n" % (path, self.headers.get("Host"), ",".join(sorted(fields))))
        if path not in PAGES:
            self.send_error(404)
            return
        title, text = PAGES[path]
        body = ("<!doctype html><meta charset=utf-8><title>%s</title><h1 id=done>%s</h1>"
                % (title, html.escape(text(fields)))).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class Server6(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET6


def self_signed_context(spki_file):
    directory = tempfile.mkdtemp(prefix="room-3.7a-cert-")
    key, cert = os.path.join(directory, "key.pem"), os.path.join(directory, "cert.pem")
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert, "-days", "2",
                    "-subj", "/CN=localhost", "-addext", "subjectAltName=IP:127.0.0.1,DNS:localhost"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    der = subprocess.run(["openssl", "x509", "-in", cert, "-pubkey", "-noout"], check=True, capture_output=True).stdout
    spki = subprocess.run(["openssl", "pkey", "-pubin", "-outform", "der"], input=der, check=True, capture_output=True).stdout
    digest = base64.b64encode(hashlib.sha256(spki).digest()).decode()
    if spki_file:
        with open(spki_file, "w") as f:
            f.write(digest + "\n")
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    return context, digest


def main():
    spki_file = sys.argv[1] if len(sys.argv) > 1 else None
    servers = [http.server.ThreadingHTTPServer(("127.0.0.1", HTTP_PORT), Handler)]
    try:
        servers.append(Server6(("::1", HTTP_PORT), Handler))
    except OSError as error:
        sys.stderr.write("no IPv6 loopback listener: %s\n" % error)
    https_server = http.server.ThreadingHTTPServer(("127.0.0.1", HTTPS_PORT), Handler)
    context, digest = self_signed_context(spki_file)
    https_server.socket = context.wrap_socket(https_server.socket, server_side=True)
    servers.append(https_server)
    for server in servers[1:]:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    print("serving http://127.0.0.1:%d, http://localhost:%d and https://127.0.0.1:%d (spki %s)"
          % (HTTP_PORT, HTTP_PORT, HTTPS_PORT, digest), flush=True)
    servers[0].serve_forever()


if __name__ == "__main__":
    main()
