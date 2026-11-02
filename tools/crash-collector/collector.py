#!/usr/bin/env python3
"""Room's crash collector (6.3, B-105; research/notes/crash-reporting.md).

Receives Crashpad's uploads at Sentry's minidump URL shape,
    POST /api/<project>/minidump/?sentry_key=<key>
(multipart/form-data, gzip-encoded by default, the dump in the field
`upload_file_minidump`, Chromium's process annotations as the other fields),
and writes each report as two files under DATA_DIR/<project>/<YYYY-MM-DD>/:
<id>.dmp and <id>.json (the annotations and the time received; no client
address is stored). Answers the report id as Crashpad expects. Reports older
than RETENTION_DAYS are deleted once a day. Python's standard library only.

Run behind a TLS proxy (Caddy: `reverse_proxy 127.0.0.1:8787`):
    ROOM_CRASH_KEYS="project:key[,project:key]" ROOM_CRASH_DATA=/var/lib/room-crash \\
        python3 collector.py --port 8787
`tools/crash-collector/README.md` has the systemd unit and the triage step.
"""
import argparse
import datetime
import email.parser
import email.policy
import gzip
import json
import os
import re
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

MAX_BODY = 64 * 1024 * 1024  # a Chromium minidump is ~1–2 MB; leave room for a large one
RETENTION_DAYS = int(os.environ.get("ROOM_CRASH_RETENTION_DAYS", "90"))
PATH = re.compile(r"^/api/([A-Za-z0-9_-]+)/minidump/?$")


def keys_from_env():
    keys = {}
    for pair in os.environ.get("ROOM_CRASH_KEYS", "").split(","):
        if ":" in pair:
            project, key = pair.split(":", 1)
            keys[project.strip()] = key.strip()
    return keys


def parse_multipart(content_type, body):
    """The form's fields as {name: bytes} (the dump stays bytes, the rest are text)."""
    message = email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(
        b"Content-Type: " + content_type.encode() + b"\r\n\r\n" + body)
    fields = {}
    for part in message.iter_parts():
        name = part.get_param("name", header="content-disposition")
        if name:
            fields[name] = part.get_payload(decode=True) or b""
    return fields


class Handler(BaseHTTPRequestHandler):
    server_version = "RoomCrashCollector/1"

    def log_message(self, fmt, *args):  # no client addresses in the log
        pass

    def reply(self, status, text):
        if self.command == "POST":
            print(f"{datetime.datetime.now(datetime.timezone.utc):%Y-%m-%dT%H:%M:%SZ} POST {status} {text.strip()}",
                  file=sys.stderr, flush=True)
        data = text.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def read_body(self):
        """The request body, or None when it is missing or over MAX_BODY. Crashpad's Mac uploader
        streams the form (Transfer-Encoding: chunked, no Content-Length); curl sends a length."""
        if (self.headers.get("Transfer-Encoding") or "").lower() == "chunked":
            chunks, total = [], 0
            while True:
                size = int(self.rfile.readline().split(b";")[0].strip() or b"0", 16)
                if size == 0:
                    while self.rfile.readline() not in (b"\r\n", b"\n", b""):  # trailers
                        pass
                    break
                total += size
                if total > MAX_BODY:
                    return None
                chunks.append(self.rfile.read(size))
                self.rfile.readline()  # the chunk's CRLF
            return b"".join(chunks) or None
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BODY:
            return None
        return self.rfile.read(length)

    def do_GET(self):
        self.reply(200 if self.path == "/health" else 404, "ok\n" if self.path == "/health" else "not found\n")

    def do_POST(self):
        url = urlparse(self.path)
        match = PATH.match(url.path)
        if not match:
            return self.reply(404, "not found\n")
        project = match.group(1)
        key = (parse_qs(url.query).get("sentry_key") or [""])[0]
        if self.server.keys.get(project) != key or not key:
            return self.reply(403, "unknown project or key\n")
        body = self.read_body()
        if body is None:
            return self.reply(413, "bad length\n")
        if (self.headers.get("Content-Encoding") or "").lower() == "gzip":
            try:
                body = gzip.decompress(body)
            except OSError:
                return self.reply(400, "bad gzip\n")
        try:
            fields = parse_multipart(self.headers.get("Content-Type", ""), body)
        except Exception:
            return self.reply(400, "bad form\n")
        dump = fields.pop("upload_file_minidump", None)
        if not dump or not dump.startswith(b"MDMP"):
            return self.reply(400, "no minidump\n")
        report = uuid.uuid4().hex
        now = datetime.datetime.now(datetime.timezone.utc)
        directory = os.path.join(self.server.data, project, now.strftime("%Y-%m-%d"))
        os.makedirs(directory, exist_ok=True)
        with open(os.path.join(directory, report + ".dmp"), "wb") as f:
            f.write(dump)
        annotations = {k: v.decode("utf-8", "replace")[:4096] for k, v in fields.items()}
        with open(os.path.join(directory, report + ".json"), "w") as f:
            json.dump({"id": report, "received": now.isoformat(), "bytes": len(dump), "annotations": annotations}, f, indent=1)
        self.reply(200, report)


def prune(data):
    """Deletes day directories older than the retention, once a day."""
    while True:
        cutoff = (datetime.date.today() - datetime.timedelta(days=RETENTION_DAYS)).isoformat()
        for project in os.listdir(data) if os.path.isdir(data) else []:
            if not os.path.isdir(os.path.join(data, project)):
                continue
            for day in os.listdir(os.path.join(data, project)):
                if re.match(r"^\d{4}-\d{2}-\d{2}$", day) and day < cutoff:
                    path = os.path.join(data, project, day)
                    for name in os.listdir(path):
                        os.remove(os.path.join(path, name))
                    os.rmdir(path)
        time.sleep(24 * 3600)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.keys = keys_from_env()
    server.data = os.environ.get("ROOM_CRASH_DATA", os.path.abspath("crash-data"))
    if not server.keys:
        raise SystemExit("ROOM_CRASH_KEYS is empty (project:key)")
    os.makedirs(server.data, exist_ok=True)
    threading.Thread(target=prune, args=(server.data,), daemon=True).start()
    print(f"room crash collector on {args.host}:{args.port}, data {server.data}, projects {sorted(server.keys)}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
