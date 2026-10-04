#!/usr/bin/env python3
"""Bounded ten-origin loopback shutdown comparison; not a real-site baseline.

Run --mode room or stock in a NEW output directory. Stock requires ROOM_COMPARE_APP
and, for the component bundle, DYLD_LIBRARY_PATH pointing at its own Libraries.
The server binds only 127.0.0.1; Chromium resolves *.localhost to loopback.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
PAGE = b'''<!doctype html><meta charset="utf-8"><title>Room shutdown loading</title>
<canvas width="640" height="360"></canvas><main></main><script>
(async () => {
  const name = location.hostname;
  document.querySelector('main').textContent = 'Room local fixture '.repeat(1000);
  document.cookie = 'room_shutdown=fixture; Max-Age=3600; SameSite=Lax';
  localStorage.setItem('shutdown', 'x'.repeat(65536));
  const db = await new Promise((resolve, reject) => {
    const r = indexedDB.open('room-shutdown', 1);
    r.onupgradeneeded = () => r.result.createObjectStore('data');
    r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);
  });
  await new Promise((resolve, reject) => {
    const tx = db.transaction('data', 'readwrite');
    tx.objectStore('data').put('y'.repeat(65536), 'payload');
    tx.oncomplete = resolve; tx.onerror = () => reject(tx.error);
  });
  db.close();
  const bytes = await (await fetch('/asset')).arrayBuffer();
  if(bytes.byteLength !== 131072) throw Error('wrong asset length');
  const canvas = document.querySelector('canvas'), ctx = canvas.getContext('2d');
  let frame = 0;
  function paint() {
    ctx.fillStyle = `hsl(${frame++ % 360} 60% 40%)`;
    ctx.fillRect(0, 0, 640, 360);
    if(frame < 240) requestAnimationFrame(paint);
  }
  paint(); document.title = 'Room shutdown ready ' + name;
})().catch(error => document.title = 'Room shutdown error ' + error);
</script>'''


class Fixture(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'x' * 131072 if self.path == '/asset' else PAGE
        self.send_response(200)
        self.send_header('Content-Type', 'application/octet-stream' if self.path == '/asset' else 'text/html')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'max-age=3600' if self.path == '/asset' else 'no-store')
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['room', 'stock'], required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--count', type=int, choices=[1, 2, 3], default=3)
    parser.add_argument('--app', type=Path, default=ROOT / 'build/roomcore/DerivedData/Build/Products/Debug/Room.app')
    args = parser.parse_args()
    directory = args.output.resolve()
    directory.mkdir()  # never replace previous evidence
    server = ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    urls = [f'http://room{i}.localhost:{port}/page' for i in range(10)]
    manifest = directory / 'urls.json'
    manifest.write_text(json.dumps(urls, indent=2) + '\n')
    (directory / 'machine-before.txt').write_text(subprocess.check_output(['top', '-l', '1', '-n', '0'], text=True))
    started = time.time()

    def run(group):
        out = directory / f'group-{group}'
        command = ['python3', str(ROOT / 'scripts/roomcore-quit-timing.py'),
                   '--app', str(args.app), '--runs', '1', '--output', str(out),
                   '--urls-json', str(manifest)]
        with (directory / f'group-{group}.log').open('w') as log:
            return subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=160).returncode

    try:
        if args.mode == 'room':
            with ThreadPoolExecutor(max_workers=args.count) as pool:
                status = list(pool.map(run, range(1, args.count + 1)))
        else:
            environment = dict(os.environ, ROOM_COMPARE_URLS_JSON=str(manifest))
            with (directory / 'stock.log').open('w') as log:
                status = [subprocess.run(['node', str(ROOT / 'research/notes/roomcore-shutdown-comparison.mjs'),
                                         str(directory / 'stock'), str(args.count)], env=environment,
                                        stdout=log, stderr=subprocess.STDOUT, timeout=220).returncode]
        receipt = {'mode': args.mode, 'corpus': 'loopback-storage-canvas-v1', 'browsers': args.count,
                   'elapsed_seconds': round(time.time() - started, 3), 'runner_exits': status,
                   'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()}
        (directory / 'exercise.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps(receipt), flush=True)
        if any(status):
            raise SystemExit(1)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()
