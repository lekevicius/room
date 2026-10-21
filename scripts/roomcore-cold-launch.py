#!/usr/bin/env python3
"""Cold launch of Room.app (any configuration, Release included): process
start to the first page's load event, then a quit by pid.

The Release app has no DEBUG spikes and no -RoomEngineDirectory, so the
measurement needs nothing from the app but its two undebugged defaults,
-RoomStateDirectory and -RoomStartURL, plus Chromium's own --user-data-dir
(RoomCore puts the host's data root first, so a later --user-data-dir wins:
profiles, Local State and Crashpad land in the scratch directory) and a log
file beside it. The start page is served on 127.0.0.1 by this script; its
load handler fetches /loaded, and the time that request arrives is the end
of the launch. Start is the moment before the executable is spawned.

Each run gets a fresh state and engine directory (the first launch on a new
profile). The app quits through the quit AppleEvent to its pid
(scripts/lib/room-ae.swift, B-47); exit status, quit time and helpers left
after 5 s are reported.

Usage: scripts/roomcore-cold-launch.py <Room.app> <new-output-dir> [runs]
5.4a: on a Debug app each run also writes the launch's steps
(`launch-marks.tsv`, `-RoomLaunchMarksFile`: name and ms since the process
started) beside its log.
"""
import http.server
import json
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAGE = b"""<!doctype html><title>cold launch</title>
<body style="font:24px -apple-system;padding:40px">cold launch fixture
<script>
addEventListener('load', () => {
  fetch('/loaded?nav=' + performance.now().toFixed(1)).catch(() => {});
});
</script>
"""


class Beacon:
    def __init__(self):
        self.event = threading.Event()
        self.arrived = None
        self.nav_ms = None


def serve(beacon_holder):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path.startswith('/loaded'):
                beacon = beacon_holder[0]
                if beacon and not beacon.event.is_set():
                    beacon.arrived = time.time()
                    beacon.nav_ms = float(self.path.split('nav=')[1])
                    beacon.event.set()
                body = b'ok'
            elif self.path.startswith('/favicon'):
                self.send_response(404)
                self.end_headers()
                return
            else:
                body = PAGE
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def room_helpers():
    out = subprocess.run(['pgrep', '-f', 'Room Helper'], capture_output=True, text=True).stdout
    return [p for p in out.split() if p]


def main():
    app = Path(sys.argv[1]).resolve()
    out = Path(sys.argv[2])
    runs = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    out.mkdir(parents=True)
    out = out.resolve()
    ae = ROOT / 'build/tools/room-ae'
    if not ae.exists():
        subprocess.run(['swiftc', '-O', '-o', str(ae), str(ROOT / 'scripts/lib/room-ae.swift')], check=True)
    holder = [None]
    server = serve(holder)
    url = f'http://127.0.0.1:{server.server_port}/start.html'
    results = []
    for run in range(1, runs + 1):
        state = out / f'run-{run}'
        engine = state / 'engine'
        engine.mkdir(parents=True)
        beacon = Beacon()
        holder[0] = beacon
        load = os.getloadavg()[0]
        args = [str(app / 'Contents/MacOS/Room'), '-RoomStateDirectory', str(state),
                '-RoomStartURL', url, '-ApplePersistenceIgnoreState', 'YES',
                f'--user-data-dir={engine}', '--enable-logging', f'--log-file={state}/RoomCore.log',
                '-RoomLaunchMarksFile', str(state / 'launch-marks.tsv')]
        with (state / 'stdout.log').open('w') as log:
            started = time.time()
            proc = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT)
            loaded = beacon.event.wait(90)
            result = {'run': run, 'load1': round(load, 2)}
            if loaded:
                result['launch_to_loaded_s'] = round(beacon.arrived - started, 3)
                result['navigation_to_load_ms'] = beacon.nav_ms
            else:
                result['error'] = 'no load event within 90 s'
            time.sleep(3)  # let the launch settle before the quit
            helpers_running = len(room_helpers())
            quit_started = time.time()
            subprocess.run([str(ae), 'quit', str(proc.pid)], capture_output=True)
            try:
                status = proc.wait(20)
            except subprocess.TimeoutExpired:
                proc.kill()
                status = 'killed after 20 s'
            result.update({'helpers_running': helpers_running,
                           'quit_seconds': round(time.time() - quit_started, 3),
                           'exit_status': status})
            deadline = time.time() + 5
            while room_helpers() and time.time() < deadline:
                time.sleep(0.1)
            result['helpers_left'] = len(room_helpers())
        crashpad = engine / 'Crashpad'
        result['engine_data_in_scratch'] = (engine / 'Local State').exists()
        result['crash_dumps'] = len(list(crashpad.rglob('*.dmp'))) if crashpad.exists() else 0
        print(json.dumps(result), flush=True)
        results.append(result)
        time.sleep(2)
    times = sorted(r['launch_to_loaded_s'] for r in results if 'launch_to_loaded_s' in r)
    summary = {'runs': runs, 'loaded': len(times), 'launch_to_loaded_s': times,
               'median_s': times[len(times) // 2] if times else None}
    print(json.dumps(summary))
    (out / 'summary.json').write_text(json.dumps({'runs': results, 'summary': summary}, indent=1))
    server.shutdown()


if __name__ == '__main__':
    main()
