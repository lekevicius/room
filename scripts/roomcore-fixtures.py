#!/usr/bin/env python3
"""Loopback-only HTTP/HTTPS fixtures for RoomCoreHost feature drives."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import signal
import ssl
import threading
import time

PAGE = b'''<!doctype html><meta charset="utf-8"><title>RoomCore features</title>
<style>body{font:16px -apple-system;margin:30px}button,a{display:block;margin:16px}</style>
<h1>RoomCore features</h1><a id="download" href="/download">Download fixture</a>
<button onclick="Notification.requestPermission()">Notifications</button>
<button onclick="navigator.geolocation.getCurrentPosition(console.log,console.error)">Location</button>
<button onclick="print()">Print</button>
<button onclick="document.documentElement.requestFullscreen()">Fullscreen</button>
<p>Find this RoomCore needle. No third-party resources.</p>'''


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/auth':
            if self.headers.get('Authorization') != 'Basic cm9vbTpzcGlrZQ==':
                self.send_response(401)
                self.send_header('WWW-Authenticate', 'Basic realm="RoomCore fixture"')
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
        elif self.path == '/download':
            body = b'RoomCore download fixture\n'
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', 'attachment; filename="roomcore-spike.txt"')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        elif self.path == '/download-slow':
            total = 32 * 1024 * 1024
            chunk = b'RoomCore cancellation fixture\n'.ljust(65536, b'.')
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', 'attachment; filename="roomcore-slow.bin"')
            self.send_header('Content-Length', str(total))
            self.end_headers()
            sent = 0
            try:
                while sent < total:
                    self.wfile.write(chunk)
                    self.wfile.flush()
                    sent += len(chunk)
                    time.sleep(0.1)
            except (BrokenPipeError, ConnectionResetError):
                print(f'download-slow disconnected after {sent} of {total} bytes', flush=True)
            return
        elif self.path.startswith('/phase-1.4/'):
            return super().do_GET()
        elif self.path not in ('/features', '/auth'):
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(PAGE)))
        self.end_headers()
        self.wfile.write(PAGE)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--cert', required=True)
    parser.add_argument('--key', required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    args = parser.parse_args()
    handler = partial(Handler, directory=str(args.root))
    http = ThreadingHTTPServer(('127.0.0.1', 0), handler)
    https = ThreadingHTTPServer(('127.0.0.1', 0), handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(args.cert, args.key)
    https.socket = context.wrap_socket(https.socket, server_side=True)
    for server in (http, https):
        threading.Thread(target=server.serve_forever, daemon=True).start()
    args.receipt.write_text(json.dumps({'http': f'http://127.0.0.1:{http.server_port}',
                                        'https': f'https://127.0.0.1:{https.server_port}'}) + '\n')
    signal.pause()


if __name__ == '__main__':
    main()
