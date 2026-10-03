# B-14 Crashpad path — draft, not applied

Source inspection on Chromium `4930cc45a85ce`:

- `chrome/app/chrome_crash_reporter_client.cc`,
  `ChromeCrashReporterClient::GetCrashDumpLocation` asks PathService for
  `chrome::DIR_CRASH_DUMPS`.
- `chrome/common/chrome_paths.cc`, `DIR_CRASH_DUMPS` explicitly uses
  `GetDefaultUserDataDirectory`, ignoring `--user-data-dir`, then appends
  `Crashpad` on macOS. This explains the Chromium directory in B-14.
- `chrome/app/chrome_main_delegate.cc` registers the Chrome path provider
  before `InitializeCrashpad` during startup.

Smallest proposed hook: in `room/core/room_application.mm`, after the host
user-data URL is validated and before `ChromeMain`, override
`chrome::DIR_CRASH_DUMPS` using
`base::PathService::Override(chrome::DIR_CRASH_DUMPS,
userDataPath.Append(FILE_PATH_LITERAL("Crashpad")))`.
Add `base/path_service.h` and `chrome/common/chrome_paths.h`. Fail host
initialization visibly if creating/overriding the selected directory fails.
The host already selects `~/Library/Application Support/Room/RoomCore`
through AppPaths; use that exact selected root, including isolated spike
profiles, rather than introducing a second hard-coded root.

PathService overrides can precede provider registration; verify startup does
not erase this override. The helper must inherit the browser's Crashpad
connection, not create a second default database. Runtime acceptance is the
handler command line `--database=<selected-root>/Crashpad`, plus a clean
nav/open10/quit run and no new Chromium/Crashpad writes. Capture both primary
handler and self-monitor handler. Do not delete/move old crash databases.

No patch or public ObjC API change expected. This remains a draft until the
component build and handler inspection pass.

## Implemented and verified — 2026-10-03 07:23 EEST

The override now runs immediately before ChromeMain using the effective
--user-data-dir (or Chromium's existing default when none was supplied).
PathService creates the directory; initialization stops visibly on failure.
No old database is moved/deleted. Build: 18 s, 2 steps; ad-hoc package valid.

Runtime evidence feature-crashpad-path/handlers.txt contains two handlers:
PID 17544 --monitor-self and PID 17548 --no-periodic-tasks. Both report
--database=/Users/j/.codex/worktrees/35bc/room/research/notes/feature-crashpad-path/profile/Crashpad
and --annotation=prod=Room_Mac. Probe exits 0 after 30 s idle.

Baseline nav 19.676 s; ten loaded pages; quit 2.591 s at load1 43.40;
26 helpers observed, 0 left after 5 s grace, 0 new crash reports, exit 0.
This verifies selected-directory placement. Normal host AppPaths supplies
Room/RoomCore; public nil-directory semantics are intentionally unchanged.
