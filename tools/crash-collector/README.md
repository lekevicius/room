# Room's crash collector

Where Room's crash reports go when a user opts in (Settings ▸ Privacy ▸ Send crash reports, or the first-run card). ROADMAP 6.3, B-105; the reasoning is in `research/notes/crash-reporting.md`.

Room's engine (Chromium's Crashpad) catches a crash in any of Room's processes, the app's own included, and writes a minidump under the data root's `Crashpad/` directory. With the user's consent it posts the minidump here. Without it, nothing leaves the Mac.

- `collector.py` receives the uploads at Sentry's minidump URL, `POST /api/<project>/minidump/?sentry_key=<key>`. It stores `<id>.dmp` and `<id>.json` (Chromium's annotations: product, version, process type, channel, Room's commit) under `DATA/<project>/<date>/`. It keeps no client addresses and deletes reports after 90 days. Python's standard library only.
- `triage.py` stack-walks new dumps with `minidump-stackwalk` (rust-minidump) against Breakpad symbols and prints one line per crash signature, most reports first.
- `scripts/crash-symbols.sh` (in the repository) writes the symbols for a release.

## Deploy (once)

On a small Linux server with a domain name (any VPS; 512 MB is plenty):

1. Copy `collector.py` and `triage.py` to `/opt/room-crash/`.
2. Pick a project id and a key, e.g. project `1` and a random key from `openssl rand -hex 16`. The key only lets a client upload: it ships inside the app and is not a secret.
3. Add a systemd unit, `/etc/systemd/system/room-crash.service`:

   ```ini
   [Unit]
   Description=Room crash collector
   After=network.target

   [Service]
   Environment=ROOM_CRASH_KEYS=1:<key>
   Environment=ROOM_CRASH_DATA=/var/lib/room-crash
   ExecStart=/usr/bin/python3 /opt/room-crash/collector.py --port 8787
   DynamicUser=yes
   StateDirectory=room-crash
   Restart=on-failure

   [Install]
   WantedBy=multi-user.target
   ```

   Then run `systemctl enable --now room-crash`.
4. Put TLS in front of it. With Caddy, add this to `/etc/caddy/Caddyfile`, which turns access logs off:

   ```
   crash.example.com {
       reverse_proxy 127.0.0.1:8787
       log {
           output discard
       }
   }
   ```

5. Check it with `curl https://crash.example.com/health`, which should answer `ok`.
6. In the repository, set `ROOM_CRASH_DSN: "https://<key>@crash.example.com/1"` in `xcodegen/base.yml`, then rebuild and release. Builds without a DSN keep their reports on disk and show the setting as unavailable.

## Each release

```bash
scripts/crash-symbols.sh build/symbols-<build>
rsync -a build/symbols-<build>/ <server>:/var/lib/room-crash/symbols/
```

The first run needs Breakpad's `dump_syms`, built from the Chromium checkout:

```bash
autoninja -C ~/chromium/src/out/release dump_syms
```

## Triage

On the server, or on a Mac with the data pulled over `rsync`:

```bash
cargo install minidump-stackwalk
python3 triage.py --data /var/lib/room-crash --symbols /var/lib/room-crash/symbols --days 14
```

Each signature prints as one line: the number of reports, the top three named frames of the crashing thread, the crash reason, the versions and process types seen, and the newest report's path.

## What a report holds

A minidump holds each thread's stack memory, the registers, the loaded modules and the OS version. Stack memory can contain fragments of what was on the page (a URL, some text), so Room's setting says so. No heap, no browsing history, no identifiers beyond Chromium's annotations.
