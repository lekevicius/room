# Crash reporting without a third-party service (B-105, ROADMAP 6.3)

Researched 2026-10-18 (Claude Code, laptop; the user asked for "a simple self
hosted thing I can deploy"). Research only: no code, no deployment. Every
number below carries its source; "not verified" marks what a page or issue
did not say.

## Recommendation

**A small collector of our own, plus `minidump-stackwalk` (rust-minidump) with
Breakpad symbols.** Not GlitchTip, Bugsink or Sentry, for now.

Why, in one paragraph: what Room has to catch is Chromium crashes, and a
Chromium minidump is only useful with a full stack walk and symbols for a very
large binary. Of the three servers, only self-hosted Sentry does both today,
and it needs 16 GB of RAM and a Kafka/ClickHouse stack. GlitchTip (the best
fit for "simple") reports **one frame per thread** from a minidump until its
rust-minidump work lands (open issue, 2026-09-26). Bugsink's minidump path is
labelled experimental, **did not work in its latest release (2.6.1)** and was
fixed on `main` on 2026-10-05; it has no dSYM support (open issue). The bare
route uses the same stack walker GlitchTip is about to adopt, runs on one
small VPS with no database, and I ran it on a real Room dump (below).

The collector speaks the **Sentry minidump URL shape**
(`/api/<project>/minidump/?sentry_key=<key>`), so the DSN stays the one
setting and GlitchTip or Bugsink can replace the collector later by changing
a host name, not the app.

What this costs: someone writes the collector (about a page of code: receive
a multipart POST, write two files) and a triage script (stack-walk new dumps,
group by crashing frame). There is no web UI, no alerting, no issue grouping
beyond that script. That is the trade for the footprint and the stack quality;
the revisit triggers at the end say when to move to GlitchTip.

## What Room has to ingest

- **Crashpad minidumps.** The app process calls `ChromeMain` itself
  (`Engine/roomcore/room/core/room_application.mm`, the `DIR_CRASH_DUMPS`
  override), so Crashpad's handler covers the app process and every helper.
  Dumps land in `<engine>/Crashpad/pending` (the tour already counts them).
  On macOS the handler is started with `--url=` from
  `CrashReporterClient::GetUploadUrl()`
  (`components/crash/core/app/crashpad_mac.mm`, `StartHandler(..., url, ...)`),
  which returns an **empty string unless `GOOGLE_CHROME_BRANDING && OFFICIAL_BUILD`**
  (`crash_reporter_client.cc`). `GetCollectStatsConsent()` returns false for a
  non-Chrome-branded build (`chrome_crash_reporter_client.cc`). So today Room
  writes dumps and never uploads one, and enabling upload needs a small
  `//room` hook (a crash reporter client, or a `chromium_src` shadow) that
  supplies the URL and the consent: a 6.3 engine step, the kind PLAN §4
  "Engine work in app chapters" allows if the ROADMAP names it.
- **What Crashpad POSTs.** `multipart/form-data`, gzip by default, the dump in
  the field `upload_file_minidump` (`third_party/crashpad/.../crash_report_upload_thread.cc:309`),
  the process annotations (`prod=Room_Mac`, `ver`, `plat`, `channel`, `ptype`,
  ...) as further fields. Chrome's default is to rate-limit uploads to one an
  hour (`kUploadAttemptIntervalSeconds = 60 * 60`; `ShouldRateLimitUploads`).
  `upload_file_minidump` is also the field name Sentry's minidump endpoint
  expects.
- **The Swift app's own reports.** Today `Packages/Integration/Sources/CrashReports/SentryCrashReporter.swift`
  starts Sentry Cocoa from `RoomSentryDSN` (Info.plist, from `ROOM_SENTRY_DSN`
  in `xcodegen/base.yml`) when the user has opted in; the DSN is empty, so
  nothing is sent. Because Crashpad already sees a crash in the app process,
  a second crash handler (Sentry Cocoa installs its own) is redundant and a
  risk (two handlers in one process; not tested here). **Recommend dropping
  Sentry Cocoa in 6.3** and reading the same DSN for the Crashpad URL. The
  user decides; nothing changes now.

## Comparison

| | GlitchTip | Bugsink | Self-hosted Sentry | Bare collector + rust-minidump |
|---|---|---|---|---|
| Minidump (Crashpad) ingestion | `/minidump/` since 6.1 (2026-03-23). Today **one frame per thread** (issue 511, opened 2026-09-26; it proposes rust-minidump). Pure-Python parser; a bounds guard merged 2026-09-26 (MR 2582); MR 2585 (keep the SDK scope, raise the size cap) is a draft. Crashpad specifically: not verified | `FEATURE_MINIDUMPS` flag, "Experimental", "development-only" with DoS-like risks as of 2.0.7 (2026-01-06). **Broken in 2.6.1** (issue 530: file saved without `.dmp`, digest fails); fix merged to `main` 2026-10-05 (PR 532), not in a tag as of the tags list (latest 2.6.1). Upstream issue 82 ("Support for minidumps") still open | Full: the minidump endpoint, Breakpad/Crashpad, size limits 40 MB compressed / 200 MB decompressed | Ours: accepts what Crashpad sends. Stack walk with CFI via `minidump-stackwalk` |
| Symbols / dSYM | `glitchtip-cli debug-files upload ./build` (dSYM, PDB, ELF). macOS ObjC symbolication issues closed Feb and Apr 2026 (453, 455). Open: the resolver reads **every** debug file in the project for any event without a native debug_id (512: a user's 13 GB project took the box down), large PDB blobs held in memory (513) | Sourcemaps yes; debug-file metadata exists for minidumps (changelog 2.2.0) but **dSYM support is an open issue (20)**; pins `symbolic==8.7.2`, "the last version to support ProcessState" | Full: dSYM, Breakpad, ELF; Sentry processes the dump and drops it unless attachments are on | Breakpad `.sym` files (`dump_syms` from the dSYM or binary); `minidump-stackwalk --symbols-path` (or a symbol URL). `.sym` carries `STACK CFI`, which gives exact unwinding |
| Sentry SDK compatibility | Yes (DSN, envelope, minidump URL) | Yes ("Sentry-SDK compatible"); envelope fixes in 2.x (395, 383) | It is Sentry | Only the minidump URL and DSN shape; an envelope endpoint is more work and is not needed if Sentry Cocoa goes |
| Deployment | One service (web + worker with `GLITCHTIP_EMBED_WORKER`), **PostgreSQL 14+** required, Valkey/Redis optional (`VALKEY_URL=""` falls back to Postgres), S3 or a volume for uploaded files. Docs: 256 MB minimum all-in-one, 512 MB recommended; about 30 GB disk per million events a month | One Docker container (`docker run` with `SECRET_KEY`), **SQLite by default**, MySQL/Postgres optional. About 50 MiB RSS after `django.setup()` (PR 325 profile) | Docker Compose, Kafka, ClickHouse and others on one host. **4 cores, 16 GB RAM + 16 GB swap (32 GB recommended), 20 GB disk**. "No guarantees or dedicated support" for self-hosted | One static binary or script behind Caddy, files on disk, no database. A dump is about 1 MB here (five local dumps: 1.0–1.7 MB) |
| Licence | MIT | PolyForm Shield 1.0.0 (source-available; may not be offered as a competing service; running it for yourself is fine; the `sentry/` directory is BSD-3) | FSL (Fair Source), Apache 2.0 after two years | MIT (rust-minidump, `minidump-stackwalk`); `dump_syms` licence not checked |
| Maintenance | Backend repo active (last activity 2026-10-16; tags v6.2.6 on 2026-08-07; a "7.0 release notes" MR merged 2026-09-26; 7,354 commits) | Very active (pushed 2026-10-18; 2.6.1 on 2026-09-25; releases every few weeks), one maintainer company (Bugsink B.V.) | Active, but self-hosted is a secondary product | rust-minidump v0.27.0 2026-08-11, pushed 2026-10-12; Mozilla uses it in production |

## Evidence run (local, 2026-10-18)

`cargo install minidump-stackwalk` (v0.27.0) built in about three minutes on
the laptop. Run on a real Room dump from
`~/Library/Application Support/Room/RoomCore/Crashpad/pending`
(`c32c5649-….dmp`, 1.05 MB, 2026-10-15), **without any symbols**:

- 0.34 s wall time, 1,185 modules in the module list;
- crashing thread 11 (`VizCompositorThread`), reason "Simulated Exception"
  (a dump-without-crashing), **44 frames** walked from the frame pointer,
  each as `RoomCore + 0x…`, so with a `.sym` file for that RoomCore build
  they become function names and lines;
- the other threads, spot-checked: 10–14 frames each (a Python-side count over the `--json` output).

Not done: a symbolicated run. The release build on this machine
(`out/release`) was mid-build for build 14 and its `RoomCore.dSYM` was an
empty bundle, so `dump_syms` (v2.3.9 installed fine) had nothing to read, and
the dump's `RoomCore` debug id (`4C4C4446…`) would not have matched a newer
build in any case. This is 6.3's first measurement: the size of the `.sym`
for `RoomCore` and the helpers at `symbol_level = 1` (`args/release.gn`),
and a symbolicated stack for a build whose dump and dSYM both exist.

## How it is wired

1. **One setting.** `ROOM_SENTRY_DSN` in `xcodegen/base.yml` keeps its place
   and its DSN shape: `https://<key>@crash.room.app/<project>` (host name an
   example; the user picks it). The key is a write-only upload token, not a
   secret worth rotating per user; it ships in the app.
2. **Crashpad's URL** is derived from it:
   `https://crash.room.app/api/<project>/minidump/?sentry_key=<key>`. The app
   passes the DSN (or the derived URL) to the engine in `EngineConfiguration`
   before it starts; a `//room` crash reporter client returns it from
   `GetUploadUrl()`. That is the `--url=` Crashpad's handler is started with.
   With the DSN empty (every build until the user deploys the collector) the
   URL is empty and the handler cannot upload.
3. **Consent.** The same client's `GetCollectStatsConsent()` reads Room's
   setting. Upload is toggled at runtime with `crash_reporter::SetUploadConsent`
   (`components/crash/core/app/crashpad.cc`; whether it is reachable from
   `RoomCore` needs a look). Room's `Settings.crashReports` already exists
   and is **off by default** (the first-run card asks; `IntegrationTests`
   checks the default); the build with no DSN shows the switch as unavailable
   (`SettingsServices.crashReportsUnavailable`).
4. **Symbols.** The release pipeline runs `dump_syms` over `RoomCore.dSYM` and
   the helpers' dSYMs and copies the resulting Breakpad tree
   (`<module>/<debug id>/<module>.sym`) to the collector next to each DMG
   (`scripts/sparkle-package.sh` is the neighbour). `minidump-stackwalk
   --symbols-path` reads that tree.
5. **Triage.** A script on the collector (or the laptop, pulling over ssh)
   stack-walks every new dump with `--json`, takes the crashing thread's top
   frames, and groups by `(module, function)`; the output is a text report.
   That is ROADMAP 6.3's "triage routine".

## What stays opt-in, and what to say

- **Uploading** is off until the user turns on Settings ▸ Privacy ▸ crash
  reports (or accepts the first-run card). Off: Crashpad still writes dumps
  to the local `Crashpad/pending` directory (it always did; the tour counts
  them) and never connects to anything. Say that in the setting's text, and
  that the dump stays on the disk until the user deletes it.
- **Per-report consent is possible and cheaper than it looks.** Keep upload
  off and offer "Send this report" from the crash view: Crashpad has
  `RequestSingleCrashUpload(local_id)` (`crashpad.cc`) for exactly that. Not
  recommended as the default (users answer once or never), but it is the
  stronger answer to the privacy question below if the user wants it.
- **What a minidump holds:** the stack memory of each thread, the registers,
  the module list, the OS version. Stack memory can contain fragments of page
  data (a URL, text). Sentry's docs say the same of its own endpoint and say
  heap memory is not included by default. The setting's text must say "may
  contain fragments of what was on the page", not "no personal data". Our
  collector: HTTPS only, no access log with addresses, retention 90 days,
  nothing but the two files and the annotations stored.
- **No sessions, no analytics, no breadcrumbs, no Sentry Cocoa telemetry.**
  The Crashpad annotations are the ones Chromium already sets (product,
  version, platform, process type, channel) plus `room-commit` and
  `room-app-version` crash keys (`Engine/roomcore/README.md`).

## Revisit

- **GlitchTip** when its issue 511 (rust-minidump stack walking) ships in a
  tagged release: then it gives a UI, grouping, alerts and dSYM upload on
  Postgres at 512 MB, MIT, with the same minidump URL, so the move is a
  host-name change. Check 512 (every debug file read per event) first:
  RoomCore's symbols are large.
- **Bugsink** when a tagged release has the 2026-10-05 fix and dSYM support
  (issue 20) and the minidump feature is no longer "experimental".
- **Self-hosted Sentry** never, for this footprint: 16 GB of RAM for a crash
  list that one person reads.

## Sources

- GlitchTip: [install guide](https://glitchtip.com/documentation/install) ·
  [CLI debug-files upload](https://glitchtip.com/documentation/cli/) ·
  [6.1 release post, 2026-03-23](https://glitchtip.com/blog/2026-03-23-glitchtip-6-1-released/) ·
  [backend repo, MIT](https://gitlab.com/glitchtip/glitchtip-backend) ·
  issues [511](https://gitlab.com/glitchtip/glitchtip-backend/-/issues/511),
  [512](https://gitlab.com/glitchtip/glitchtip-backend/-/issues/512),
  [513](https://gitlab.com/glitchtip/glitchtip-backend/-/issues/513),
  [453](https://gitlab.com/glitchtip/glitchtip-backend/-/issues/453),
  [455](https://gitlab.com/glitchtip/glitchtip-backend/-/issues/455) ·
  tags and merge requests read through the GitLab API on 2026-10-18.
- Bugsink: [repository](https://github.com/bugsink/bugsink) ·
  [LICENSE (PolyForm Shield 1.0.0)](https://github.com/bugsink/bugsink/blob/main/LICENSE) ·
  [CHANGELOG](https://github.com/bugsink/bugsink/blob/main/CHANGELOG.md)
  (2.0.7 minidump note, 2.2.0 debug-file scoping, 2.6.1) ·
  issues [82](https://github.com/bugsink/bugsink/issues/82),
  [20](https://github.com/bugsink/bugsink/issues/20),
  [530](https://github.com/bugsink/bugsink/issues/530), PRs
  [270](https://github.com/bugsink/bugsink/pull/270),
  [325](https://github.com/bugsink/bugsink/pull/325),
  [532](https://github.com/bugsink/bugsink/pull/532) ·
  [Bugsink vs. GlitchTip](https://www.bugsink.com/blog/bugsink-vs-glitchtip/)
  (written by Bugsink's author) · [docs](https://www.bugsink.com/docs/).
- Self-hosted Sentry: [requirements, licence and support statement](https://develop.sentry.dev/self-hosted/) ·
  [repository](https://github.com/getsentry/self-hosted) ·
  [minidump endpoint, size limits, what a dump holds](https://docs.sentry.io/platforms/native/guides/minidumps/).
- rust-minidump: [repository, MIT](https://github.com/rust-minidump/rust-minidump) ·
  [minidump-stackwalk README](https://github.com/rust-minidump/rust-minidump/blob/main/minidump-stackwalk/README.md)
  (Breakpad `.sym` files; v0.27.0 on 2026-08-11 from the GitHub API).
- Chromium at Room's checkout (`~/chromium/src`): `components/crash/core/app/{crashpad_mac.mm,crashpad.cc,crash_reporter_client.cc}`,
  `chrome/app/chrome_crash_reporter_client.cc`,
  `third_party/crashpad/crashpad/handler/{crash_report_upload_thread.cc,handler_main.cc}`.
- Room: `Engine/roomcore/room/core/room_application.mm`,
  `Packages/Integration/Sources/CrashReports/SentryCrashReporter.swift`,
  `App/Sources/AppDelegate.swift` (`makeOptIns`), `xcodegen/base.yml`,
  `Engine/roomcore/args/release.gn`, `research/notes/roomcore-crashpad-draft.md`.
