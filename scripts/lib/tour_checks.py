"""Checks for each grand-tour step (scripts/grand-tour.sh, Phase 2.9).

evaluate(run, step) reads a step's raw output (steps/<name>.spike for a
SpikeRunner spike, steps/<name>.out for a wrapper's stdout) and returns
{"checks": [(name, ok, detail)], "numbers": [(key, value)], "notes": [...]}.

Every step gets the generic checks (exit 0, no crash report, nothing left
running, the spike reached its end, no `error:` or `capture_timeout:`
lines). The per-step checks below are the spec's or the phase's own
criterion where it is a rule (a count, an identity, a state), and a
presence check where it is a number: a result line that is missing fails,
so a spike that skips a section (an engine-only path, a guard that
returned early) cannot pass by saying nothing. Timings are
reported as numbers, not judged here, except where the phase set a bound;
`spike-results.md` "Phase 2.9 — grand tour" compares them with the phases.
"""
import os
import re

STEP_CHECKS = {}


def step_check(*names):
    def register(fn):
        for n in names:
            STEP_CHECKS[n] = fn
        return fn
    return register


def lines(path):
    try:
        with open(path, errors="replace") as f:
            return f.read().splitlines()
    except FileNotFoundError:
        return []


def kv(text_lines):
    """Every `key: value` line; repeated keys keep each value in order."""
    out = {}
    for line in text_lines:
        m = re.match(r"^([A-Za-z0-9_@.\-]+): (.*)$", line)
        if m:
            out.setdefault(m.group(1), []).append(m.group(2))
    return out


def field(text, name, cast=float):
    """`name=value` inside a line (units stripped)."""
    if text is None:
        return None
    m = re.search(r"(?:^|[\s;(,])" + re.escape(name) + r"=([-\d.]+)", text)
    return cast(m.group(1)) if m else None


class Ctx:
    def __init__(self, run, step):
        self.run, self.step, self.name = run, step, step["name"]
        steps = os.path.join(run, "steps")
        self.dir = steps
        self.spike = lines(os.path.join(steps, f"{self.name}.spike"))
        self.out = lines(os.path.join(steps, f"{self.name}.out"))
        self.values = kv(self.spike or self.out)
        self.checks, self.numbers, self.notes = [], [], []

    def file(self, suffix):
        return lines(os.path.join(self.dir, f"{self.name}{suffix}"))

    def first(self, key):
        v = self.values.get(key)
        return v[0] if v else None

    def check(self, name, ok, detail=""):
        self.checks.append((name, bool(ok), "" if ok else detail))
        return ok

    def present(self, *keys):
        for k in keys:
            v = self.first(k)
            self.check(f"`{k}` reported", v is not None, "" if v is not None else "missing")

    def number(self, key, value=None):
        v = value if value is not None else self.first(key)
        if v is not None:
            self.numbers.append((key, v))

    def contains(self, key, *needles, label=None):
        v = self.first(key) or ""
        missing = [n for n in needles if n not in v]
        return self.check(label or f"`{key}`: " + ", ".join(needles), v and not missing,
                          ("missing" if not v else "got: " + v[:240]))


def evaluate(run, step):
    c = Ctx(run, step)
    c.check("exit 0", step["status"] == "0", "" if step["status"] == "0" else f"exit {step['status']}")
    c.check("no crash report", step["crash_reports"] == "0", f"{step['crash_reports']} new")
    if step.get("helper_crash_reports", "0") != "0" and c.name != "chrome26b":
        dumps = c.file(".crashpad")
        c.check("no helper crash report", False, f"{step['helper_crash_reports']} new"
                + (": " + "; ".join(l.split("\t", 1)[-1][:140] for l in dumps) if dumps else ""))
    c.check("no Room left running", step["left_running"] == "0", f"{step['left_running']} stopped by the tour")
    if c.spike:
        c.check("spike reached its end", bool(c.values.get("end")), "no `end:` line")
    errors = c.values.get("error", [])
    c.check("no error lines", not errors, "; ".join(errors)[:300])
    timeouts = c.values.get("capture_timeout", [])
    c.check("no capture timeouts", not timeouts, ", ".join(timeouts)[:300])
    if c.spike and c.first("window_main") is not None:
        c.check("window main", c.first("window_main") == "true", f"window_main: {c.first('window_main')}")
    fn = STEP_CHECKS.get(c.name)
    if fn:
        try:
            fn(c)
        except Exception as e:  # a parse error is a failed check, not a crashed summary
            c.check("checks ran", False, f"{type(e).__name__}: {e}")
    return {"checks": c.checks, "numbers": c.numbers, "notes": c.notes}


# --- layout (Chapter 1) -----------------------------------------------------

@step_check("smoke")
def _smoke(c):
    line = " ".join(c.out)
    c.check("exit_status=0, helpers_left=0, new_crash_reports=0",
            "exit_status=0" in line and "helpers_left=0" in line and "new_crash_reports=0" in line, line)
    c.number("quit_seconds", field(line, "quit_seconds"))


def display_height(c):
    """The main display's height in points from the run's display.tsv (`1280 x 800 @ 60.00Hz`), or None."""
    try:
        with open(os.path.join(c.run, "display.tsv")) as f:
            m = re.search(r"\d+ x (\d+)", f.read())
            return int(m.group(1)) if m else None
    except FileNotFoundError:
        return None


def dia_framing(c, ok, label, detail):
    """Dia's 1244 × 818 framing needs a display taller than 818 pt; on a shorter one the card is shorter, by design."""
    h = display_height(c)
    if h is not None and h < 830:
        c.notes.append(f"{label}: not checked, the display is {h} pt tall (the window cannot be 818 pt); got {detail}")
    else:
        c.check(label, ok, detail)


@step_check("window")
def _window(c):
    states = {}
    for l in c.out:
        m = re.match(r"^([a-z0-9-]+): (.*)$", l)
        if m:
            states[m.group(1)] = m.group(2)
    c.check("15 window states captured", len(states) >= 15, f"{len(states)}")
    lights = [s for s in states.values() if "lights={{19, 19}, {60, 14}}" in s]
    c.check("traffic lights at AppKit's place (19,19 60×14) in every state", len(lights) == len(states), f"{len(lights)}/{len(states)}")
    c.check("active states main", all("main=true" in v for k, v in states.items() if "-active-" in k or "compare" in k or "page-" in k), "")
    c.check("inactive states not main", all("main=false" in v for k, v in states.items() if "-inactive-" in k), "")
    # The Room Browser design (2026-10-07): the card 8 pt from the window's edges, a 300 pt default sidebar.
    dia_framing(c, all("card={{280, 8}, {956, 802}}" in v for k, v in states.items() if "compare" in k), "Dia framing: card {{280, 8}, {956, 802}}",
                next((v.split("card=")[1].split(" title")[0] for k, v in states.items() if "compare" in k), ""))
    c.check("sidebar open: card at x 300, closed: at x 8",
            all("card={{300, 8}" in v for k, v in states.items() if k.endswith("-open")) and
            all("card={{8, 8}" in v for k, v in states.items() if k.endswith("-closed")), "")


@step_check("cdp")
def _cdp(c):
    c.present("runtime_evaluate_rtt", "page_capture_screenshot_rtt", "transparent_resize", "opaque_resize")
    rtt = c.first("runtime_evaluate_rtt")
    c.check("CDP round trip median under 1 ms (1.4: 0.21 ms)", (field(rtt, "median") or 99) < 1.0, rtt or "")
    c.number("runtime_evaluate_rtt")
    c.number("page_capture_screenshot_rtt")


def frame_rate(stats):
    med = field(stats, "median")
    return round(1000 / med) if med else None


@step_check("scroll")
def _scroll(c):
    runs = c.values.get("scroll_mask_true", [])
    c.check("two mask-on runs and the mask-off control", len(runs) == 2 and c.first("scroll_mask_false") is not None, f"{len(runs)}")
    for i, r in enumerate(runs):
        hz = frame_rate(r)
        fps = field(r, "fps")
        c.check(f"mask on run {i + 1}: fps at the display's rate ({hz} Hz)", fps and hz and fps >= 0.95 * hz, r)
        # 2.2b's bound for a scroll: at most one late frame (over 1.5 frames); the max is reported.
        c.check(f"mask on run {i + 1}: at most one late frame", (field(r, "max") or 99) <= 2.5 * 1000 / hz, r)
        c.number(f"scroll_mask_true run {i + 1}", r)
    c.number("scroll_mask_false")


@step_check("resize")
def _resize(c):
    for key in ("bound_card_fill", "control_clear_card_fill"):
        c.contains(key, "samples inside card: 0/576", label=f"{key}: no material inside the card (0/576)")
    c.number("control_transparent_page_clear_card")


@step_check("memory")
def _memory(c):
    c.present("baseline", "hidden_1", "hidden_10", "hidden_30")
    for key, n in (("hidden_1", 1), ("hidden_10", 10), ("hidden_30", 30)):
        v = c.first(key) or ""
        m = re.search(r"loaded=(\d+)/(\d+)", v)
        loaded = int(m.group(1)) if m else 0
        c.check(f"{key}: at least 90% loaded (1.4: 8/10, 27/30)", loaded >= 0.9 * n, v)
        c.number(key, v)
    for key in ("hidden_1_page0", "hidden_30_page0"):
        c.contains(key, "hidden", "rafPerSecond\\\":1", label=f"{key}: hidden page at 1 rAF/s")
    c.number("baseline")


@step_check("audio")
def _audio(c):
    for key in ("round1_became_audible", "round1_reported_stopped", "round2_became_audible", "round2_reported_stopped", "webaudio_became_audible"):
        v = c.first(key)
        ms = field("x=" + (v or "").replace("ms", ""), "x")
        c.check(f"{key} within 2 s", ms is not None and ms < 2000, v or "missing")
        c.number(key, v)
    v = c.first("webaudio_still_audible_after_2s_playing")
    c.check("Web Audio stop reported", v is not None, "missing")
    if v == "false":
        c.notes.append("Web Audio reads silent while playing (the Chapter 2 engine's cap, lifted on RoomCore in 3.3a): a regression")


@step_check("popups")
def _popups(c):
    c.contains("target_blank", "current=true", "title=Popup target", "inCard=true")
    c.contains("window_open", "title=Popup target", "inCard=true")
    for kind in ("sel", "date"):
        a, b = c.first(f"popup_{kind}_moved_false") or "", c.first(f"popup_{kind}_moved_true") or ""
        oa, ob = re.search(r"offset (.*)$", a), re.search(r"offset (.*)$", b)
        c.check(f"<{'select' if kind == 'sel' else 'input type=date'}> popup keeps its offset after the window moves",
                oa and ob and oa.group(1) == ob.group(1), f"{a} / {b}")
    # The page marks the DOM after its alert returns (B-75: the spike's script runs in an isolated world and
    # cannot read the page's `window.__alerted`).
    c.check("alert as a sheet, completed", c.first("alert_sheet") == "true" and "true" in (c.first("alert_completed") or ""),
            f"sheet={c.first('alert_sheet')} completed={c.first('alert_completed')}")


@step_check("hidden")
def _hidden(c):
    c.contains("visible_page", '\\"visible\\"', label="visible page: visible")
    c.contains("hidden_never_shown", '\\"hidden\\"', 'rafPerSecond\\":1}', label="never-shown page: hidden, 1 rAF/s")
    c.contains("after_show", '\\"visible\\"', label="shown page: visible")
    c.contains("after_removed_from_card", '\\"hidden\\"', label="page removed from the card: hidden")


@step_check("open10")
def _open10(c):
    pages = int(c.first("pages") or 0)
    c.check("ten pages open", pages >= 10, f"pages {pages}")
    ready = c.first("ready")
    c.check("all loaded within 60 s", ready is not None and int(ready) < 60, f"ready {ready}")
    c.number("seconds to all loaded", ready)


@step_check("diaframe")
def _diaframe(c):
    dia_framing(c, c.first("card") == "{{280, 6}, {958, 806}}", "card at Dia's framing", c.first("card") or "missing")


@step_check("keys")
def _keys(c):
    layouts = [k for k in c.values if k.startswith("keys_")]
    c.check("three layouts (ABC, Colemak, Lithuanian)", len(layouts) >= 3, ", ".join(layouts))
    for k in layouts:
        v = c.first(k)
        # ⌘V lands in the field: RoomCore pastes at the caret the spike placed at the end
        # ("select me and copy PASTED", 3.2b; Chapter 2's engine replaced the selection); the page saw it first.
        c.check(f"{k}: ⌘C/⌘V/⌘Z page-first, then the Edit menu",
                'pasteboard="select me and copy"' in v and re.search(r'⌘V value="[^"]*PASTED"', v) is not None
                and 'Z value="select me and copy"' in v, v[:200])
        if "o typed value=" in v:
            c.check(f"{k}: a plain letter types into the field", re.search(r'o typed value="[^"]*o"', v) is not None, "")
        c.check(f"{k}: ⌘ + number row gives 1…9", "chars: 1 2 3 4 5 6 7 8 9" in v, "")
    reached = [k for k in layouts if "⌘T newPage=true" in c.first(k) and "⌘L addressFocus=true" in c.first(k)]
    c.check("⌘T and ⌘L reach the app in the active layout (synthetic events of other layouts cannot dispatch, 1.4)", len(reached) >= 1, "")
    if all("reserved calls=" in c.first(k) for k in layouts):
        # Since 3.2b each layout counts its own reserved calls (the log also holds consumed keys now).
        c.check("⌘T and ⌘L classified reserved in every layout", all("reserved calls=2" in c.first(k) for k in layouts),
                ", ".join(re.search(r"reserved calls=\d+", c.first(k)).group(0) for k in layouts))
        consumed = [int(m.group(1)) for k in layouts if (m := re.search(r"consumed=(\d+)", c.first(k)))]
        c.number("didConsumeKey calls per layout", ", ".join(map(str, consumed)) or "n/a")
    else:
        log = c.first("delegate_key_log") or ""
        # The log keeps its last 12 entries: the last two layouts' ⌘T and ⌘L.
        c.check("⌘T and ⌘L classified reserved (the log's last two layouts)", log.count("reserved") >= 4, f"{log.count('reserved')} reserved")


@step_check("devtools")
def _devtools(c):
    c.contains("devtools_open", "true", "docked=true")
    v = c.first("inspect_element") or ""
    m = re.search(r'at point "([^"]+)"; frontend selected "([^"]+)"', v)
    c.check("inspect element selects the element under the point", m and m.group(1) == m.group(2), v)
    c.contains("devtools_close", "closed=true", "pane=false", "pageState=alive")
    c.number("devtools_open")


@step_check("quittiming")
def _quittiming(c):
    runs = [l for l in c.out if l.startswith("run=")]
    c.check("three quits", len(runs) == 3, f"{len(runs)}")
    for r in runs:
        q = field(r, "quit_seconds")
        c.check(f"run {field(r, 'run', int)}: under 1.5 s, no helpers left, no crash report",
                q is not None and q < 1.5 and "helpers_left=0" in r and "new_crash_reports=0" in r, r)
        c.number(f"quit run {field(r, 'run', int)}", r)


# --- sidebar (2.1, 2.2) ------------------------------------------------------

@step_check("killtest")
def _killtest(c):
    text = "\n".join(c.out)
    m = re.search(r"summary: (\d+) kills in ([^,]+), (\d+) failures", text)
    c.check("100 kills, 0 failures (every reopen intact at the last committed generation)",
            m and m.group(1) == "100" and m.group(3) == "0", m.group(0) if m else "no summary")
    for pattern, label in ((r"kills with a transaction in flight: (\d+) \(rolled back to the previous generation: (\d+)\)", "in flight / rolled back"),
                           (r"commit time median ([\d.]+) ms, p95 ([\d.]+) ms, max ([\d.]+) ms", "commit time median / p95 / max ms")):
        mm = re.search(pattern, text)
        if mm:
            c.number(label, " / ".join(mm.groups()))
    # B-79: a reopen ahead of the last ack (the commit landed, the kill beat
    # its acknowledgement) is informational; only one behind it is a loss.
    mm = re.search(r"reopened ahead of the last ack[^:]*: (\d+)", text)
    if mm:
        c.number("reopened ahead of the last ack (informational)", mm.group(1))
    mm = re.search(r"reopened behind the last ack[^:]*: (\d+)", text)
    c.check("no reopen behind the last ack (no acknowledged write lost)", mm and mm.group(1) == "0",
            mm.group(0) if mm else "missing")
    if m:
        c.number("wall time", m.group(2))


# --- lifecycle (4.1a) ---------------------------------------------------------

@step_check("archive")
def _archive(c):
    """Spec §A.7 / §H and ROADMAP 4.1a: the launch sweep takes the old Today
    tabs (5 of the fixture) and keeps the selected, the split-with-a-pinned
    and the young ones; the rows are in the database; 13 h later the young
    tabs go; the Library lists the rows by reason and restores into the
    row's space, selected; Clear writes `clear` rows and Undo takes them
    out; the palette shows the Archived chip and Enter restores; Delete
    Space writes `spaceDeleted` rows and Undo takes them out; ⌘Y opens the
    Library at History, Esc returns; Clear Archive empties the table."""
    v = c.first
    c.contains("clock", "injected=true", label="the clock is injected (-RoomClock)")
    sweep = v("launch_sweep") or ""
    c.check("launch sweep archives the five old Today tabs", sweep.startswith("archived=5 ")
            and "Old 1,Old 2,Old 3,Two Old A,Two Old B" in sweep, sweep or "missing")
    c.contains("launch_sweep_kept", "Selected=true", "Split=true", "Young=true", "Two Young=true",
               label="the selected, split-with-pinned and young tabs stay")
    c.check("the archive's rows are reason auto", (v("archive_rows") or "").startswith("5 auto=5 "), v("archive_rows") or "missing")
    c.check("the rows are in the database", v("database_archive_rows") == "5", v("database_archive_rows") or "missing")
    later = v("sweep_after_13h") or ""
    c.check("13 h later the young tabs go", later.startswith("archived=2 ") and "Two Young,Young" in later, later or "missing")
    c.contains("sweep_after_13h_kept", "Selected=true", "Split=true", label="the selected and split tabs still stay")
    c.check("the Library replaces the spaces view", v("library_shown") == "true", v("library_shown") or "missing")
    c.contains("library_rows", "archive=7 (auto=7 clear=0 spaceDeleted=0 windowClosed=0 manual=0)",
               label="the Library lists the seven rows by reason")
    c.contains("library_restore", "space=Two", "top=true", "selected=true", "row_gone=true",
               label="Restore from the Library: back at the top of its space, selected, the row gone")
    clear = v("clear") or ""
    c.check("Clear writes its tabs to the Archive (reason clear) with the Undo toast",
            "done=true" in clear and "rows_clear=0" not in clear and "toast=" in clear and "toast=none" not in clear, clear or "missing")
    m = re.search(r"today_before=(\d+) rows_clear=(\d+)", clear)
    if m:
        c.check("one clear row per Today tab", m.group(1) == m.group(2), clear)
    undo = v("clear_undo") or ""
    c.check("Clear's Undo puts the tabs back and takes the rows out",
            "rows_clear=0" in undo and m is not None and f"today={m.group(1)}" in undo, undo or "missing")
    c.contains("palette_archived_row", "chip=Archived", "group=history", label="the palette's History row has the Archived chip")
    c.contains("palette_restore", "selected=true", "space=Space", "row_gone=true",
               label="Enter on it restores the tab to its space, selected")
    c.contains("delete_space", "space_gone=true", label="Delete Space")
    m = re.search(r"entries=(\d+) rows_spaceDeleted=(\d+)", v("delete_space") or "")
    c.check("Delete Space archives its entries (B-15)", m is not None and m.group(1) == m.group(2) and m.group(1) != "0",
            v("delete_space") or "missing")
    c.contains("delete_space_undo", "space_back=true", "rows_spaceDeleted=0", label="its Undo brings the space and takes the rows out")
    c.contains("cmd_y", "library_shown=true", "history_expanded=true", label="⌘Y opens the Library at History")
    c.contains("esc_returns", "library_shown=false", label="Esc returns to the spaces")
    c.contains("clear_archive", "rows=0", "database_rows=0", label="Clear Archive empties the table")
    for key in ("library_rows", "archive_rows_before_clear_archive", "capture_library"):
        c.number(key)


@step_check("recovery")
def _recovery(c):
    """Spec §H and ROADMAP 4.1b (`scripts/recovery-check.sh`, two launches):
    a backup, a space deleted and written, SIGKILL after the commit; the
    relaunch sees the unclean exit, restores every entry unloaded (the
    selected included) with the card's empty state and the toast; a click
    on the selected row loads it; Restore Sidebar from the backup brings the
    space back with its tabs (in the database too) after backing up the
    current state, and the generation moves on."""
    v = c.first
    c.contains("prepared", "spaces=Recovery Kept,Recovery Gone", "entries=6", "loaded=1",
               label="prepare: two spaces of three tabs, the selection loaded")
    c.contains("backup_taken", "entries=6", "spaces=2", label="a backup taken before the deletion")
    c.contains("deleted", "space_gone=true", "entries=3", label="the space deleted and written")
    killed = [l for l in c.out if l.startswith("killed: ")]
    c.check("killed with SIGKILL right after the commit", bool(killed), "no `killed:` line")
    c.contains("previous_exit", "store_unclean=true", "clean=false", label="the relaunch sees the unclean exit")
    crash = v("crash_recovered") or ""
    c.check("the toast \u201cRoom restarted after a crash\u201d was shown",
            crash.startswith("true") and "logged=true" in crash, crash or "missing")
    c.contains("restored_unloaded", "entries=3", "loaded=0", "card=card-empty-state",
               label="every entry restored unloaded, the selected one included; the card's empty state")
    c.contains("click_loads", "loaded=1", "selected_loaded=true", label="a click on the selected row loads it")
    c.contains("restore", "ok=true", "space_back=true", "entries=3", "database_space=true", "database_entries=3",
               label="Restore Sidebar brings the space back with its tabs, in the database too")
    m = re.search(r"generation=(\d+)->(\d+)", v("restore") or "")
    c.check("the restore is written with a newer generation", m is not None and int(m.group(2)) > int(m.group(1)),
            v("restore") or "missing")
    c.contains("before_restore_backup", "count=1", "entries=3", label="the state before the restore was backed up first")
    c.contains("after_restore", "spaces=Recovery Kept,Recovery Gone", "loaded=1",
               label="after the restore: both spaces, the selection loaded")
    c.check("the check launch reached its end", "recovery" in (c.values.get("end") or []), "no `end: recovery`")
    c.number("launch_backup")


@step_check("sidebardemo", "sidebar500")
def _sidebar(c):
    states = [l for l in c.out if re.match(r"^[a-z0-9-]+: active=", l)]
    c.check("sidebar states captured", len(states) >= 1, f"{len(states)}")
    if c.name == "sidebar500":
        rows = re.search(r"entries: (\d+) rows: (\d+)", "\n".join(c.out))
        c.check("the 500 fixture: 505 entries, 508 rows (the fixture replaced the sidebar it found)",
                rows and rows.group(1) == "505" and rows.group(2) == "508", rows.group(0) if rows else "missing")
        scrolls = [l for l in c.out if l.startswith("scroll native")]
        c.check("three native scroll runs", len(scrolls) == 3, f"{len(scrolls)}")
        for l in scrolls:
            late = re.search(r"late frames \(>1.5× nominal\) (\d+)", l)
            # 2.2b: one late frame in 1,437, in the first second of the first run.
            c.check(f"{l.split(' for ')[0]}: at most one late frame", late and int(late.group(1)) <= 1, l[:220])
        for l in c.out:
            for key in ("full reload", "insert one Today tab", "select", "drop: move a 10-tab group", "remove one Today tab"):
                if l.startswith(key):
                    c.number(key, l.split(": ", 1)[1])
            if l.startswith("scroll "):
                step = re.search(r"main-thread scroll step: (.*)$", l)
                c.number(l.split(" for ")[0], (step.group(1) if step else l)[:160])
    else:
        c.check("demo states light and dark", any("dark=true" in s for s in states) and any("dark=false" in s for s in states), "")


# --- spaces (2.5) --------------------------------------------------------------

@step_check("spaces")
def _spaces(c):
    c.check("the spaces500 fixture: 5 spaces, 500 entries", c.first("spaces") == "5" and c.first("entries") == "500",
            f"spaces {c.first('spaces')} entries {c.first('entries')}")
    c.check("50 pages loaded (10 per space)", c.first("loaded_pages") == "50", c.first("loaded_pages") or "missing")
    c.check("no list loaded during the switches (the slide never waits on a list)", c.first("lists_loaded_during_switches") == "0",
            c.first("lists_loaded_during_switches") or "missing")
    c.check("no switch missed", c.first("switches_missed") == "0", c.first("switches_missed") or "missing")
    c.present("ctrl_digit_key_to_first_slide_frame", "switch_main_thread_code", "rss_50_loaded")
    for key in ("ctrl_digit_key_to_first_slide_frame", "switch_main_thread_code", "first_switch_to_each_space_turn",
                "list_build_load_warm_up_per_space", "rss_50_loaded", "display_frame_interval"):
        c.number(key)


@step_check("spacecaptures")
def _spacecaptures(c):
    caps = c.values.get("capture", [])
    c.check("seven captures (footer, themed light/dark, Reading, form edit/new, mid-slide)", len(caps) == 7, f"{len(caps)}")
    shot = [l for l in c.out if l.startswith("captured ")]
    c.check("every capture written", len(shot) == len(caps), f"{len(shot)}/{len(caps)}")


@step_check("cookies")
def _cookies(c):
    c.check("two profiles, Default and Work (one Work after earlier fixtures)", re.fullmatch(r"Default=\w+ Work=\w+", c.first("profiles") or "") is not None,
            c.first("profiles") or "missing")
    expect = {"default_profile_after_set": "home", "work_profile_after_set": "work", "work_profile_reread": "work",
              "reading_space_same_profile_as_default": "home", "before_move": "home"}
    for key, value in expect.items():
        c.check(f"{key}: room_profile={value}", f"room_profile={value}" in (c.first(key) or ""), c.first(key) or "missing")
    c.check("moved to Work: a new page in Work's context reads Work's cookie",
            'cookie="room_profile=work"' in (c.first("after_move_to_work") or "") and c.first("moved_entry_profile_is_work") == "true",
            c.first("after_move_to_work") or "missing")
    # Since 4.4b (B-22) an engine profile's directory is keyed by the Room profile's id, not its name.
    dirs = (c.first("engine_profile_directories") or "").split(", ")
    c.check("engine profiles are direct children of the root",
            len(dirs) == 2 and all(re.fullmatch(r"Room Profile [0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}", d) for d in dirs),
            c.first("engine_profile_directories") or "missing")
    # History follows the profile: each profile's engine history holds only its own visits (3.5; 3.9 reads the engine's).
    c.check("history follows the profile: Default has only ?set=home, Work only ?set=work",
            c.first("history_by_profile") == "Default: home=true work=false; Work: home=false work=true", c.first("history_by_profile") or "missing")


# --- palette (2.4, 2.6a) -------------------------------------------------------

@step_check("palette")
def _palette(c):
    c.contains("cmd_t_opens", "open=true", "field_first_responder=true", label="⌘T opens the palette in new mode, field focused")
    c.check("⌘T makes no tab until Enter", c.first("cmd_t_no_tab_yet") == "true", c.first("cmd_t_no_tab_yet") or "missing")
    c.contains("enter_new_tab", "closed=true", "selected=true", "page=https://example.com/", "responder=RenderWidgetHostViewCocoa",
               label="Enter: a selected Today tab at example.com, focus back on the page")
    c.contains("cmd_l_prefill", "text=https://example.com/", "selected={0, 20} of 20", label="⌘L prefilled and selected")
    c.contains("cmd_l_enter_navigates_current", "same_entry=true", label="⌘L Enter navigates the same entry")
    c.contains("cmd_l_unchanged_enter_reloads", "loading_seen=true", label="⌘L Enter unchanged reloads")
    c.contains("escape", "first_restores=true", "second_closes=true", label="Esc restores, Esc again closes")
    c.check("⌘T ⌘T and ⌘L ⌘T close", c.first("cmd_t_again_closes") == "true" and c.first("cmd_t_closes_cmd_l") == "true", "")
    c.contains("option_enter_background", "added=1", "selection_kept=true", label="⌥Enter opens in the background")
    c.contains("tab_cycles_groups", "groups=topHit,openTabs", "highlighted_after_tab=1", "cmd_enter_closed=true", label="⇥ cycles groups; ⌘Enter opens")
    c.contains("header_click_docked", "presentation=docked", "panel={{91, 6}, {640, 48}}", label="header click: docked 640 pt panel on the field")
    caps = [k for k in c.values if k.startswith("capture_")]
    c.check("eight captures (four states × light/dark)", len(caps) == 8, f"{len(caps)}")


@step_check("palette2")
def _palette2(c):
    hist = {l.split(": ", 1)[0]: l for l in c.spike if l.startswith("history ")}
    c.check("typed URL recorded as typed", '"typed"' in hist.get("history https://example.com/", ""), hist.get("history https://example.com/", "missing"))
    c.check("script navigation recorded as link", '["link"]' in hist.get("history https://example.org/", ""), "")
    pushed = hist.get("history https://example.org/pushed", "")
    if c.first("history_source") == "engine":
        # 3.5 on RoomCore: Chrome's history also keeps the reload that follows as a visit of its own (Chrome's rule, not the store's).
        c.check("same-document pushState recorded (Chrome's history)", 'visits=["link"' in pushed, pushed)
    else:
        c.check("same-document pushState recorded", '["link"]' in pushed, "")
    c.check("DNS error page not recorded", "visits=[]" in hist.get("history https://nonexistent.invalid/", "visits=[]"), "")
    c.check("a search recorded", "history search page" in hist, "missing")
    if c.first("history_source") == "engine":
        # 3.5: on RoomCore the store's table no longer grows; Chrome's history has the visit and the palette finds it.
        # 3.9: schema v6 dropped the store's history tables; Chrome's history is the only one.
        c.check("the store has no history table (schema v6)", c.first("store_history_tables") == "none", c.first("store_history_tables") or "missing")
        c.check("a visit on RoomCore is in Chrome's history", '"typed"' in (c.first("engine_visit_recorded") or ""), c.first("engine_visit_recorded") or "missing")
        c.check("the palette finds it from Chrome's history", "found=true" in (c.first("palette_room35") or ""), c.first("palette_room35") or "missing")
        c.check("⌘Y lists Chrome's history", re.search(r"rows=[1-9]", c.first("cmd_y") or "") is not None, c.first("cmd_y") or "missing")
        c.check("IDC_FOCUS_LOCATION through RoomAppController's dispatch opens the host's field",
                "requests=1" in (c.first("idc_focus_location_dispatch") or "") and "palette_open=true" in (c.first("idc_focus_location_dispatch") or ""),
                c.first("idc_focus_location_dispatch") or "missing")
        c.check("the chip: secure page secure for the host and Chrome's LocationBarModel",
                "host=secure" in (c.first("chip_secure") or "") and "location_bar_model=SECURE" in (c.first("chip_secure") or ""), c.first("chip_secure") or "missing")
        c.check("the chip: plain HTTP insecure for the host, WARNING for Chrome's LocationBarModel",
                "host=insecure" in (c.first("chip_insecure") or "") and "location_bar_model=WARNING" in (c.first("chip_insecure") or ""),
                c.first("chip_insecure") or "missing")
    exa = next((l for l in c.spike if l.startswith("palette exa: ")), "")
    c.check("inline host completion from history (exa → example.com)", "inline=mple.com" in exa, exa or "missing")
    for appearance in ("light", "dark"):
        # 4.7a and 4.7b added commands that also match ">re" (Reader Mode, Capture Screenshot).
        c.contains(f"state_commands-filtered_{appearance}", "chip=-", '"Reload", "Reload without Cache"', label=f">re filters commands ({appearance})")
        c.contains(f"state_site-search_{appearance}", "chip=YouTube", label=f"yt ⇥ shows the YouTube chip ({appearance})")
        c.contains(f"state_history-inline_{appearance}", "inline=thub.com", label=f"gi completes github.com ({appearance})")
    page = hist.get("history search page", "")
    if "google.com/sorry" in page:
        c.notes.append("the spike's real Google search landed on google.com/sorry (Google's automated-traffic page); history still recorded it")


def proxy_requests(c):
    return [l for l in c.file(".proxy") if l.strip()]


@step_check("suggeston")
def _suggeston(c):
    c.check("suggestions on (the default; nothing left them off)", c.first("suggestions") == "on", f"suggestions: {c.first('suggestions')}")
    reqs = proxy_requests(c)
    connects = [r for r in reqs if " CONNECT " in r]
    engine = [r for r in reqs if " GET /complete/search" in r]
    if engine and not connects:
        # 3.5 on RoomCore: Chrome's SearchProvider asks Room's engine, pointed at the logging server's
        # suggestion endpoint; it polls while typing (Chrome's own debounce), so at least one request per query.
        queries = {q for q in ("swift", "weather", "room") if any(f"q={q}" in r for r in engine)}
        c.check("the engine's suggestion requests reach the logging server for each of the three queries", len(queries) == 3,
                f"{len(engine)} requests: " + "; ".join(r[:90] for r in engine[:4]))
        c.check("suggestion rows shown from the engine", any(not v.endswith("[]") for v in c.values.get("suggest_rows", [])),
                "; ".join(c.values.get("suggest_rows", []))[:200])
    else:
        # 2.4b: three requests, one per pause (the 120 ms debounce), none between keystrokes.
        c.check("one suggestion request per pause (3), through the logging proxy", len(connects) == 3, f"{len(connects)}: " + "; ".join(r[:80] for r in reqs[:5]))
    c.number("proxy requests", len(reqs))


@step_check("suggestoff")
def _suggestoff(c):
    c.check("suggestions off", c.first("suggestions") == "off", c.first("suggestions") or "missing")
    reqs = proxy_requests(c)
    c.check("0 requests while typing with suggestions off", not reqs, "; ".join(r[:80] for r in reqs[:5]))
    c.check("no suggestion rows", all(v.endswith("[]") for v in c.values.get("suggest_rows", ["x"])), "")


@step_check("palettemeasure")
def _palettemeasure(c):
    c.check("500 entries", c.first("entries") == "500", f"entries {c.first('entries')}")
    # Chrome's omnibox answers from its own history (3.5), which the fixture fills to 50k rows (3.9: the only history).
    c.check("Chrome's omnibox answers the palette", c.first("engine_autocomplete") == "true", c.first("engine_autocomplete") or "missing")
    c.check("Chrome's history holds the 50,000 rows the palette reads (plus the tour's own visits)", int(c.first("engine_history_rows") or 0) >= 50000,
            f"engine history {c.first('engine_history_rows')}")
    c.number("engine_async_done")
    q = c.first("keystroke_query_only")
    c.check("local results p95 under 16 ms at 50k rows (ROADMAP 2.4 exit)", (field(q, "p95") or 99) < 16, q or "missing")
    later = c.first("keystroke_to_rows_later_keys")
    c.check("later keystrokes' whole turn p95 under 16 ms", (field(later, "p95") or 99) < 16, later or "missing")
    o = c.first("palette_open_call")
    c.check("palette open, our code, median ≤ 8.3 ms (2.4b target)", (field(o, "median") or 99) <= 8.3, o or "missing")
    f = c.first("palette_open_to_next_frame")
    c.check("palette open to the next frame median ≤ 16.7 ms (2.4b target)", (field(f, "median") or 99) <= 16.7, f or "missing")
    for key in ("palette_open_call", "palette_open_to_next_frame", "keystroke_to_rows_first_key", "keystroke_to_rows_later_keys",
                "keystroke_query_only", "display_frame_interval", "launch_to_spike_s"):
        c.number(key)
    first = c.first("keystroke_to_rows_first_key")
    if first and (field(first, "median") or 0) > 8.33:
        c.notes.append("a query's first keystroke is over one 120 Hz frame: the E-core effect measured in 2.6a (7.5 ms on a P core)")


# --- tabs (2.3) ------------------------------------------------------------------

@step_check("tabs")
def _tabs(c):
    c.contains("cmdW_today", "page=closed", "entryRemoved=true", "selected=A", "inCard=true", label="⌘W on a Today tab: closed, MRU tab A selected")
    c.contains("reopen_today", "selected=C", "url=https://news.ycombinator.com/", label="⇧⌘T reopens C, selected")
    c.contains("ctrl_tab_tap", "selected=A (was C)", label="⌃Tab tapped: back to the previous tab")
    v = c.first("digit_and_next") or ""
    m = re.search(r"⌘1=(\S+) then ⇧⌘\]=(\S+) order=\[\"([^\"]+)\", \"([^\"]+)\"", v)
    c.check("⌘1 then ⇧⌘]: the first entry, then the next in sidebar order", m and m.group(1) == m.group(3) and m.group(2) == m.group(4), v[:200])
    c.contains("pinned_changed", "isChanged=true", label="same-site navigation marks the pinned entry changed")
    c.contains("cmdW_pinned", "page=closed", "entryStays=true", "reset=true", label="⌘W on a pinned entry: unloads and resets, the entry stays")
    c.contains("reopen_pinned", "selected=true", "url=https://example.org/?changed=1", label="⇧⌘T brings the deeper page back")
    c.contains("related_foreground", "newIndex=1", "openerIndex=0", "selectedIsNew=true", label="target=_blank opens below its opener, selected")
    c.contains("related_background", "selectedStaysOpener=true", "backgroundIndexes=[1, 2]", label="⌘-clicks open below the opener in order")
    v = c.first("discard") or ""
    m = re.search(r"pages=(\d+) renderers (\d+)→(\d+) total (\d+)→(\d+) MB", v)
    c.check("Discard Background Pages: every page discarded, renderers released", m and v.count('"discarded"') == int(m.group(1)) and int(m.group(3)) < int(m.group(2)), v[:200])
    c.number("discard", m.group(0) if m else v[:120])
    c.contains("discarded_reselect", "state=alive", label="a discarded tab reloads on selection")
    if "canGoBack=false" in (c.first("discarded_reselect") or ""):
        c.notes.append("the reloaded discarded tab has no back history (B-13, closed on RoomCore in 3.3a): a regression")
    c.check("⇧⌘M mutes the selected page", c.first("mute") == "selectedMuted=true", c.first("mute") or "missing")


@step_check("tabsmeasure")
def _tabsmeasure(c):
    # Two spikes in one output: switch, then relaunch on its state.
    text = c.out
    sw, rl = [], []
    cur = None
    for l in text:
        if l.startswith("spike: "):
            cur = sw if l.endswith("switch") else rl
        if cur is not None:
            cur.append(l)
    s, r = kv(sw), kv(rl)
    g = lambda d, k: (d.get(k) or [None])[0]
    c.check("switch: 50 entries, 10 site tabs loaded", g(s, "entries") == "50" and g(s, "loaded_pages") == "10",
            f"entries {g(s, 'entries')} loaded {g(s, 'loaded_pages')}")
    turn = g(s, "switch_main_thread_turn")
    c.check("switching: click to the new page committed in the card, median under 16 ms (2.3 exit)", (field(turn, "median") or 99) < 16, turn or "missing")
    c.check("switching: p95 under 16 ms (2.3 exit)", (field(turn, "p95") or 99) < 16, turn or "missing")
    vis = g(s, "switch_page_visible")
    c.check("the page's own visible time measured (window visible: B-18)", vis is not None and not vis.startswith("n=0"), vis or "missing")
    c.check("relaunch: only the selected entry loads", g(r, "loaded_pages") == "1", g(r, "loaded_pages") or "missing")
    c.check("relaunch: the entry selected at quit is selected again", g(r, "selected") == g(s, "selected_at_quit"), f"{g(r, 'selected')} vs {g(s, 'selected_at_quit')}")
    c.check("relaunch: 49 rows restored unloaded", (g(r, "unloaded_rows") or "").startswith("49"), g(r, "unloaded_rows") or "missing")
    if g(s, "end") is None or g(r, "end") is None:
        c.check("both spikes reached their end", False, "")
    for d, key in ((s, "switch_select_call"), (s, "switch_main_thread_turn"), (s, "switch_page_visible"), (s, "rss_10_loaded"),
                   (r, "launch_to_load_start_s"), (r, "launch_to_selected_loaded_s"), (r, "rss_relaunch")):
        if g(d, key) is not None:
            c.number(key, g(d, key))


@step_check("tabcapture")
def _tabcapture(c):
    caps = [k for k in c.values if k.startswith("capture_")]
    c.check("five captures (page light/dark, empty light/dark, switcher)", len(caps) == 5, f"{len(caps)}")
    c.contains("switcher_state", "active=true", label="the ⌃Tab switcher shows")


# --- chrome surfaces (2.6) ---------------------------------------------------------

def spike_from_out(c):
    """The wrappers print `== <appearance>` and then the spike's output; use that as the spike."""
    body = [l for l in c.out if not l.startswith("== ") and not l.startswith("captured ")]
    c.spike = body
    c.values = kv(body)
    c.check("spike reached its end", bool(c.values.get("end")), "no `end:` line")
    c.check("window main", c.first("window_main") == "true", f"window_main: {c.first('window_main')}")


@step_check("chrome26a")
def _chrome26a(c):
    spike_from_out(c)
    c.contains("dialog_results", '[\\"confirm\\",true]', '[\\"prompt\\",\\"Grace\\"]', '[\\"alert\\",\\"ok\\"]', label="JS dialogs answered (confirm, prompt, alert)")
    c.check("focus back in the page after the dialogs", c.first("focus_after_dialogs") == "RenderWidgetHostViewCocoa", c.first("focus_after_dialogs") or "")
    c.contains("beforeunload_stay", "page in card=true", label="beforeunload: Stay keeps the page (in a new Today entry, as 2.3)")
    c.contains("beforeunload_leave", "page closed=true", label="beforeunload: Leave closes it")
    c.contains("auth_result", "Signed in as room", label="HTTP auth sheet signs in")
    c.contains("certificate_interstitial", "ERR_CERT_AUTHORITY_INVALID", "row title=127.0.0.1", label="certificate interstitial, row titled by the host")
    c.contains("certificate_go_back", "entry kept=true", "card=card-empty-state", label="Go Back with no history: the empty card (B-25)")
    c.contains("certificate_proceed", "title=Self-signed page", label="Visit anyway reaches the page")
    c.contains("permission_location", "popover=true", "answered=true", label="location prompt in the popover")
    c.contains("permission_notifications", "popover=true", "answered=true", label="notifications prompt in the popover")
    for key in ("file_chooser_image", "file_chooser_docs", "file_chooser_folder"):
        c.contains(key, "sheet=true", label=f"{key}: the panel as a sheet")
    c.contains("context_menu_link", "Open Link in New Tab", "Open Link in Peek", "Copy Link", label="link context menu with Room's items")
    c.contains("context_menu_open_link", "below page=true", label="Open Link in New Tab opens below the page")
    c.contains("popup_window_open", "selected=true", "hello from open", label="window.open: a selected Today tab that can message its opener")
    c.contains("popup_window_close", "entry closed=true", label="window.close() closes the entry")
    c.contains("popup_target_blank", "Popup child (blank, no opener)", label="target=_blank: a Today tab without an opener")
    if "camera" in (c.first("permission_page_results") or "") and "NotFoundError" in (c.first("permission_page_results") or ""):
        c.notes.append("camera/microphone: NotFoundError before any prompt (no devices on the Mac mini; B-26 for the laptop)")
    if '"geolocation\\":\\"prompt' in (c.first("permission_states") or ""):
        c.notes.append("geolocation reads \"prompt\" after Allow: B-26 (3.4a)")


# Every delegate member the 2.6b recorder saw called (docs/engine-api.md, "What CEF could not do": the
# Phase 2.6 checklist); didConsumeKey is measured by the keys spike, not this one.
DELEGATE_MEMBERS = """decidePolicy didChangeAudible didChangeMuted didChangeSecurityState didChangeStatusText didCommitNavigation didCreate
didFailCertificateCheck didReceiveAuthChallenge didUpdateDownload handleUnhandledKeyEvent isReservedKeyEvent processGone runBeforeUnloadDialog
runFileChooser runJavaScriptAlert runJavaScriptConfirm runJavaScriptPrompt webContentsDidClose webContentsDidDismissJavaScriptDialogs
webContentsDidDismissPermissionPrompt webContentsDidRequestEnterFullscreen webContentsDidRequestExitFullscreen willAskForPermission
willBeginDownload willShowContextMenu""".split()


@step_check("chrome26b")
def _chrome26b(c):
    # chrome://crash kills one renderer: its minidump (no FATAL line) is expected here, and only here.
    # RoomCore's Crashpad writes under the engine directory (steps/chrome26b.crashpad); a dev-build
    # DCHECK in another renderer (a FATAL line) is not this step's and fails on its own (B-76).
    dumps = c.file(".crashpad")
    killed = [l for l in dumps if "no FATAL line" in l]
    checks = [l.split("\t", 1)[-1][:140] for l in dumps if "no FATAL line" not in l]
    c.check("one helper crash report, the renderer `chrome://crash` killed", len(killed) == 1,
            f"{len(killed)} killed renderer dumps (helper crash reports {c.step.get('helper_crash_reports')})")
    c.check("no other helper crash report", not checks, "; ".join(checks))
    _chrome26a(c)
    calls = dict(p.split("=") for p in (c.first("delegate_calls") or "").split() if "=" in p)
    missing = [m for m in DELEGATE_MEMBERS if m not in calls]
    c.check(f"every delegate member called ({len(DELEGATE_MEMBERS)}; didConsumeKey: the keys spike)", not missing, "missing: " + ", ".join(missing))
    c.contains("download_begin", "ring=", label="download begins with the ring")
    c.contains("download_names", "on disk=true", label="download lands in Settings' folder")
    c.contains("download_controls", "paused=true", "resumed=true", "cancelled=true", "file left=false", label="pause, resume, cancel")
    c.contains("download_complete", "badge=2", label="two completions: badge 2")
    c.check("opening the popover clears the badge; Clear empties it", c.first("download_seen") == "badge after opening=0" and c.first("download_clear") == "rows=0", "")
    c.contains("find_count", '"1 of 400"', label="find: 1 of 400 highlighted on the first request")
    c.contains("find_step", '⌘G → "2 of 400"', '⇧⌘G → "1 of 400"', label="⌘G / ⇧⌘G step")
    c.contains("find_closed", "bar=false", "focus=RenderWidgetHostViewCocoa", label="Esc closes find, focus back in the page")
    c.contains("zoom_in", 'indicator="110%"', label="⌘= zooms to 110% with the indicator")
    c.contains("zoom_out_reset", "0.9", "after ⌘0 1.0", label="⌘- ⌘- 90%, ⌘0 100%")
    if c.first("print_preview") is not None:
        # RoomCore (3.3b): Chrome's print preview in a child window over Room's, closed by Esc (B-29).
        c.contains("print_preview", "← Room's window", label="⌘P: Chrome's print preview over Room's window (B-29)")
        c.contains("print_preview_dismissed", "closed by Esc", label="Esc closes the print preview")
    else:
        c.contains("print_panel", "modal NSPanel", label="⌘P: a system print panel (no print preview appeared)")
    c.contains("status_pill_dodge", "leading → trailing", label="status pill dodges the pointer")
    c.contains("site_panel_page_sees", 'geolocation\\":\\"denied', label="site panel Block reaches the page")
    c.contains("site_panel_clear", "cleared=true", 'cookie=""', label="site panel Clear empties cookies and storage")
    c.contains("dialog_dismissed_by_navigation", "sheet gone=true", label="a navigation withdraws a dialog")
    c.contains("permission_dismissed_by_navigation", "popover gone=true", label="a navigation withdraws a permission prompt")
    c.contains("process_gone", "view=true", "status=crashed", label="chrome://crash: the crashed-page view")
    c.contains("process_gone_reload", "view gone=true", label="Return reloads the crashed page")
    c.contains("element_fullscreen_enter", "window fullscreen=true", label="element fullscreen: the card edge to edge")
    c.contains("element_fullscreen_exit", "window back=true", "sidebar=true", label="leaving element fullscreen restores the window")
    c.contains("traffic_lights_after_fullscreen", "after close={{19, 19}", "toolbar=true", label="traffic lights back at 19,19 with the toolbar")
    c.contains("devtools_console", "opened=true", label="⌥⌘J opens DevTools on the console")
    if c.first("devtools_element_picker") is not None:
        c.contains("devtools_element_picker", "picker=true", label="⌥⌘C turns on the element picker")
    c.contains("audio", "audible=true", "stopped=true", label="audible on and off (a media element)")
    c.contains("copy_url", "⇧⌘C → http", "⌥⇧⌘C → [Audio]", label="Copy URL and as Markdown")
    for key in ("find_keystroke_to_match", "find_keystroke_to_final", "devtools_open_to_frontend_loaded", "status_text_to_pill", "print_panel", "print_preview", "download_begin"):
        c.number(key)


# --- layout modes (2.7) ----------------------------------------------------------------

@step_check("layoutmodes")
def _layoutmodes(c):
    spike_from_out(c)
    c.contains("menu_sidebar_docked", "enabled=true target=AppDelegate", label="View ▸ Hide Sidebar enabled with a page focused, on AppDelegate")
    c.contains("menu_sidebar_hidden", "enabled=true target=AppDelegate", label="View ▸ Show Sidebar enabled while hidden")
    c.contains("menu_command_s", "hid the sidebar=true", "second ⌘S docked it=true", label="⌘S through the menu hides and docks")
    v = c.first("reveal_band_to_shown")
    c.check("reveal: the 150 ms dwell, then shown (under 250 ms)", v and 150 <= (field(v, "median") or 0) < 250, v or "missing")
    c.check("reveal slide drops no frame", (field(c.first("reveal_slide_frame_intervals"), "max") or 99) <= 1.5 * (field(c.first("reveal_slide_frame_intervals"), "median") or 0), c.first("reveal_slide_frame_intervals") or "missing")
    c.contains("isolation_overlay", "page clicks=0 downs=0 moves=0", label="no event reaches the page under the overlay")
    c.contains("reveal_pin", "stays after leaving=true", "hidden by a page click=true", label="⌥⌘S pins; a page click hides")
    c.contains("cluster_fade", "buttons kept their frames=true", "back when near=true", label="the cluster fades after 2 s and comes back")
    c.contains("drag_regions", "hit=TrafficLightClusterView movable=true", label="the pill is a drag region")
    c.contains("peek_onsite", "in place → http://127.0.0.1:8770/other.html", label="Peek rule: a same-site link navigates in place")
    c.contains("peek_offsite", "peek http://localhost:8770/", label="Peek rule: an off-site link from a pinned entry opens Peek")
    c.check("Peek opens (timings measured)", not (c.first("peek_open_to_overlay_frame") or "n=0").startswith("n=0"), c.first("peek_open_to_overlay_frame") or "missing")
    c.contains("isolation_peek_over_split", "A clicks=0 downs=0 moves=0", "B clicks=0 downs=0 moves=0", "C clicks=0 downs=0 moves=0", label="no event reaches any pane under Peek's dim")
    c.contains("split_panes", "count=2", "pages in their panes=[true, true]", label="split: two panes with their pages")
    c.contains("split_sidebar_row", "SplitGroupCellView", "rows showing B separately: false", label="split: one group row in the sidebar")
    c.check("resizer drag drops no frame", (field(c.first("resizer_drag_frame_intervals"), "max") or 99) <= 1.5 * (field(c.first("resizer_drag_frame_intervals"), "median") or 0), c.first("resizer_drag_frame_intervals") or "missing")
    c.contains("resizer_drag_result", "presses that reached pane A's page=0", label="no press reaches a page under the resizer")
    c.check("double-click equalises", c.first("resizer_double_click") == "ratios=[0.5, 0.5]", c.first("resizer_double_click") or "")
    c.check("the header field follows the focused pane", c.first("focus_field_follows_pane") == "true", "")
    keys = c.first("split_keys") or ""
    c.check("every split key handled", keys and "handled=false" not in keys, keys[:240])
    c.contains("split_command_w", "panes 4 → 3", "removed=true", label="⌘W closes only the focused pane")
    c.contains("peek_split", "panes 2 → 3", "Peek gone=true", label="Peek ▸ Split (⇧⌘O) adds a pane")
    # 4.2: Open as Tab's placement (spec §I.6) and a Peek page's fullscreen request (B-35).
    c.contains("peek_open_as_tab", "selected is the Peek's page=true", "Peek gone=true", label="Open as Tab (⌘O) makes the Peek the selected tab")
    c.contains("peek_open_as_tab_placement", "under the parent=true", label="Open as Tab from a pinned entry: the first Today tab")
    c.contains("peek_open_as_tab_today_parent", "directly under=true", label="Open as Tab from a Today tab: directly under it")
    c.contains("peek_fullscreen", "Peek gone=true", "card page is the Peek's=true", "index in Today=0", "window fullscreen=true",
               "page fullscreen=true", 'document.fullscreenElement="true"', label="B-35: a Peek page's fullscreen expands it into a Today tab, then fullscreen")
    c.contains("peek_fullscreen_exit", "window back=true", "the tab stays=true", label="leaving it restores the window; the tab stays")
    c.contains("split_element_fullscreen", "focused pane fills the card=true", "after exit panes visible=true", label="element fullscreen of a pane")
    for key in ("reveal_band_to_shown", "reveal_leave_to_hidden", "cluster_fade", "peek_open_to_overlay_frame", "peek_open_to_first_contentful_paint",
                "split_create_to_laid_out", "split_create_to_next_frame", "focus_click_to_field_updated", "focus_click_to_next_frame"):
        c.number(key)


# --- space routing (4.2) ------------------------------------------------------------------

@step_check("routing")
def _routing(c):
    spike_from_out(c)
    c.contains("rules", "1. contains route=work → Work", "2. equals localhost → Play", "3. contains site.html → Work (disabled)",
               label="the fixture's three rules in order, one disabled")
    c.contains("invalid_regex", "refused=true", "rules 3 → 3", "Not a valid regular expression", label="an invalid regex is refused at entry")
    c.contains("external_rule_contains", "space=Work", "selected in its space=true", "shown space=Space", 'toast="Opened in Work" button=Switch',
               "page=http://127.0.0.1:8770/other.html?route=work", label="external link, contains rule: in Work with the toast")
    c.contains("external_rule_equals", "space=Play", "selected in its space=true", 'toast="Opened in Play"', label="external link, equals rule (host): in Play")
    c.contains("external_no_rule", "space=Space", "in the card=true", "toast=none", label="no enabled rule: the most recent space, selected, no toast")
    c.contains("toast_switch", "shown space=Work", "card=the routed tab", label="the toast's Switch shows the space with the routed tab")
    c.contains("external_most_recent", "space=Work", "in the card=true", "toast=none", label="the most recent space follows the switch")
    c.contains("external_chosen_default", "space=Play", 'toast="Opened in Play"', label="Settings ▸ Links' chosen space takes unmatched links")
    c.contains("cross_space_off_blank", "space=Space", "under its opener=true", "toast=none", label="routing between spaces off: a target=_blank link stays under its opener")
    c.contains("cross_space_on_blank", "space=Work", "shown space=Space", 'toast="Opened in Work"', label="on: a target=_blank link a rule names goes to Work")
    c.contains("cross_space_on_command_click", "space=Work", 'toast="Opened in Work"', label="on: a ⌘-click a rule names goes to Work")
    c.contains("cross_space_on_no_rule", "space=Space", "under its opener=true", label="on, no rule: the link stays under its opener")
    c.contains("sheet", "shown=true", "editing=true", "match=contains", "pattern=127.0.0.1", "target=Space", label="Add Route for Domain… opens the sheet prefilled")
    c.contains("sheet_try_url", "→ Opens in Play (rule 2)", "example.com → Opens in the default: ", label="Try a URL names the space")
    c.contains("sheet_invalid_regex", "inline=Not a valid regular expression", "save refused=true", "rules=3", label="the sheet refuses an invalid regex inline")
    c.contains("sheet_save", "saved=true", "rules=4", label="the sheet saves a rule")
    c.check("the sheet closes", c.first("sheet_closed") == "true", c.first("sheet_closed") or "missing")
    c.contains("rules_in_database", "3 of 3", label="the rules are in the database")


# --- settings (4.4a) -------------------------------------------------------------------

@step_check("settings")
def _settings(c):
    """ROADMAP 4.4a (`scripts/settings-check.sh`, two launches on one state): Pin
    (⌘D) remapped to ⌥⌘P by a key press in Settings ▸ Shortcuts moves the key in
    the menu, the palette's hint and the sidebar's menu; the old ⌘D reaches the
    keys page (1.4's fixture) and pins nothing, ⌥⌘P pins; a conflict is marked
    on both rows and resolved only when confirmed; macOS's keys refused; a
    reserved action under a new key stays reserved and its old key reaches the
    page; every setting round-trips through a relaunch; the save panel per
    download; Reset All restores the frozen table."""
    spike_from_out(c)
    c.check("both launches reached their end", len(c.values.get("end", [])) == 2, f"{len(c.values.get('end', []))} end lines")
    c.check("both launches had the window main", c.values.get("window_main", []) == ["true", "true"], f"{c.values.get('window_main')}")
    c.contains("defaults", "overrides=0", "pin=⌘D", "reopen=⇧⌘T", "reserved=17", "has ⇧⌘T=true", label="the defaults: the frozen table")
    c.contains("remap_pin", "recording=true", "stored=⌥⌘P", "menu=⌥⌘P", "palette command=⌥⌘P", "sidebar=⌥⌘P",
               label="⌘D → ⌥⌘P recorded in Settings ▸ Shortcuts: the menu, the palette's command and the sidebar's menu")
    c.contains("palette_hint", "row=Pin Tab", "hint=⌥⌘P", label="the palette's row shows the new key")
    t = c.first("remap_timing") or ""
    m = re.search(r"in the menu ([\d.]+) ms.*menu apply ([\d.]+) ms", t)
    c.check("the remap's timing is reported", m, t or "missing")
    if m:
        c.numbers.append(("key press → stored and in the menu (ms)", m.group(1)))
        c.numbers.append(("menu apply (ms)", m.group(2)))
    c.contains("old_key", '"⌘d/KeyD"', "reached the page=true", "kind=today", label="the old ⌘D reaches the page and pins nothing")
    c.contains("new_key", "pinned=true", label="⌥⌘P pins")
    c.contains("new_key_again", "unpinned=true", label="⌥⌘P again unpins")
    c.contains("conflict", 'conflict(["printPage:"])', "pending=true", 'marked=["printPage:", "togglePin:"]', "Use it for Pin Tab instead?",
               label="⌘P (Print's) for Pin: both rows marked, the prompt asks")
    c.contains("conflict_cancel", "pin=⌥⌘P", "print=⌘P", "marked=0", label="Cancel keeps both keys")
    c.contains("conflict_resolved", "pin=⌘P", "print=none", "conflicts=0", label="confirmed: the newer wins, Print loses the key")
    c.contains("refused", "⌘Q: ⌘Q is Quit", "⌘H: ⌘H is Hide Room", "K: K has no ⌘ or ⌃", "Quit to ⌥⌘T: refused", "pin=⌥⌘P", "print=⌘P",
               label="macOS's keys and keys without ⌘ or ⌃ refused with a message; Quit keeps ⌘Q")
    c.contains("reserved_set", "has ⌥⌘T=true", "has ⇧⌘T=false", "count=17", "menu=⌥⌘T", label="Reopen Closed Tab under ⌥⌘T: the reserved set follows")
    c.contains("reserved_remap", '⇧⌘T page saw=["⌘⇧T/KeyT"]', "reopened by ⇧⌘T=false", "⌥⌘T page saw=[]", "reopened by ⌥⌘T=true", "tabs reopened=1",
               label="the old ⇧⌘T reaches the page; ⌥⌘T never does and reopens once")
    c.contains("applied", "toolbar=true", "sidebar=right", "palette engine=Spike Search", "keyword row=Press Tab", "suggestions=false",
               label="the settings applied: toolbar, sidebar side, the profile's engine, the keyword, suggestions off")
    c.contains("save_panel", "shown=true", "sheet=true", "proposed=spike-ask.bin", label="Ask where to save: a save panel over the window")
    c.contains("save_panel_ok", "complete=true", "file=true", label="the panel's file is the download's")
    c.contains("save_panel_cancel", "rows 1 → 1", "listed=false", label="a cancelled panel cancels the download, nothing listed")
    c.contains("stored", "reopenClosedTab:=⌥⌘T", "togglePin:=⌥⌘P", label="the overrides in Settings")
    c.contains("relaunch_equal", "true (13 of 13)", label="every setting read back after the relaunch")
    c.contains("relaunch_applied", "toolbar=true", "sidebar=right", "palette engine=Spike Search", label="applied again at launch")
    c.contains("relaunch_keys", "pin=⌥⌘P", "reopen=⌥⌘T", "print=⌘P", "reserved has ⌥⌘T=true", "has ⇧⌘T=false", label="the remapped keys after the relaunch")
    c.contains("reset_all", "overrides=0", "pin=⌘D", "reopen=⇧⌘T", "has ⇧⌘T=true", "has ⌥⌘T=false", "equals the defaults=true",
               label="Reset All: the frozen table and reserved set again")
    c.contains("restored", "defaults=true", label="the settings put back for the next steps")


# --- settings2 (4.4b) ------------------------------------------------------------------

@step_check("settings2")
def _settings2(c):
    """ROADMAP 4.4b (`scripts/profiles-check.sh`, two launches on one state):
    a second profile's fixture cookie survives a rename (the engine directory
    keyed by the profile's id) and the one-time move of a pre-4.4b directory
    at launch; Clear browsing data for the last hour removes this hour's visit
    and the cookie and keeps a visit 3 h old; a permission stored through
    Settings' path is what permissions.html reads, and its reset too; a
    profile with a space and two pages is deleted with its directory, its tabs
    in the Archive; Default stays; the palette's Settings ▸ Privacy opens the
    section; Chromium's site-data page renders in a tab."""
    spike_from_out(c)
    c.check("both launches reached their end", len(c.values.get("end", [])) == 2, f"{len(c.values.get('end', []))} end lines")
    c.check("both launches had the window main", c.values.get("window_main", []) == ["true", "true"], f"{c.values.get('window_main')}")
    c.contains("reorder", 'up=["Office", "Space"]', 'back=["Space", "Office"]', "positions=[0, 1]", label="spaces reordered as Settings ▸ Spaces moves them")
    c.contains("cookie_set", '"room_profile=work"', "engine profile=the id", label="the fixture cookie in Work's space, its engine profile keyed by id")
    c.contains("renamed", "refusal=none", "empty refused=A profile needs a name.", "name=Office Profile", "space profile kept=true",
               label="renamed through Settings' path; an empty name refused")
    c.contains("directories_set", "Room Profile <work id>", label="the directory is the id's, nothing moved by the rename")
    c.contains("space_routing", "shown=true", "on settings=true", "editing=true", "target=Office", label="a space's Routing… opens the sheet with a rule for it")
    c.contains("moved_at_launch", "Room Profile Office Profile → Room Profile <work id>", "local state updated=true",
               label="the one-time move of a pre-4.4b directory at launch, Local State with it")
    c.contains("directories_verify", "id=true", "legacy=false", label="no directory left or made under the old name")
    c.contains("local_state", "last_used=Room Profile <work id>", label="Chromium's last used profile follows the move")
    c.contains("cookie_after_relaunch", '"room_profile=work"', label="the cookie survives the rename, the move and the relaunch")
    c.contains("clear_hour", "before: fresh=true old=true", "after: fresh=false old=true", 'cookie=""', "toast=Cleared history and cookies from the last hour",
               label="Clear browsing data, last hour: this hour's visit and the cookie go, a 3-hour-old visit stays, the toast says so")
    m = re.search(r"in (\d+) ms", c.first("clear_hour") or "")
    if m:
        c.numbers.append(("clear browsing data, last hour (ms)", m.group(1)))
    c.contains("permission_listed", "http://127.0.0.1:8766=block", label="the stored permission is listed by contentSettings(ofType:)")
    c.contains("permission_page", '\\"notifications\\":\\"denied\\"', label="the page reads the permission set in Settings")
    c.contains("permission_reset", "listed=0", '\\"notifications\\":\\"prompt\\"', label="Reset: the list empties and the page asks again")
    c.contains("delete_profile", "dir before=true", "outcome=deleted", "dir after=false", "archived=2 of 2", "profile gone=true", "space gone=true",
               label="a profile deleted: its directory gone after its pages closed, its tabs in the Archive")
    m = re.search(r"outcome=deleted in (\d+) ms", c.first("delete_profile") or "")
    if m:
        c.numbers.append(("delete a profile with two pages (ms)", m.group(1)))
    c.contains("delete_default_refused", "refused", label="the Default profile cannot be deleted")
    c.contains("palette_section", "commands=8", "visible=true", "title=Privacy", label="the palette's Settings ▸ Privacy opens the section")
    c.contains("all_site_data", "title=Settings - All sites", "state=alive", '\\"ui\\":true', label="Chromium's site-data page renders in a Room tab")


# --- import (4.3a) ---------------------------------------------------------------------

@step_check("import")
def _import(c):
    """ROADMAP 4.3a (`scripts/import-check.sh`, the fixtures of research/spikes/phase-4.3
    listed with -RoomImportSource on the `import` fixture): the sheet opens with the
    fixtures; every reader's counts; nothing written before Import; each import's
    preview equals the store's rows after it; the duplicates, the depth clip at 5,
    the Essentials cap of 12, Arc's spaces with icons, colours and profiles (one
    "Work" profile, made or reused); the history found through the engine in the
    same launch; the rows in the database; the sheet closes."""
    v = c.first
    spike_from_out(c)
    c.contains("sheet_open", "shown=true", "picked=none", "arc (fixture)", "chrome (fixture)", "netscape (fixture)", "safari (fixture)",
               label="the sheet opens over the window, nothing picked, the four fixtures listed")
    c.contains("read_chrome", "bookmarks=31 folders=9", "history=10 visits=16", "extensions=2 skipped=1", "errors=0",
               "profiles=Person 1/Work", label="Chrome's readers: Bookmarks, History, Preferences, Local State's profiles")
    c.contains("read_safari", "bookmarks=10 folders=4 skipped=1", "history=4 visits=6", "errors=0", label="Safari's readers: plist, History.db")
    c.contains("read_netscape", "bookmarks=7 folders=3 skipped=1", "errors=0", label="the Netscape reader")
    c.contains("read_arc", "arc spaces=3 profiles=2 essentials=3 pinned=6 folders=2 today=3 skipped=2", "errors=0", label="Arc's sidebar reader")
    c.contains("nothing_before_import", "unchanged=true", "dirty=false", label="nothing is written before Import (four reads and previews)")
    for label in ("chrome", "safari", "netscape", "arc"):
        c.contains(f"{label}_applied", "equal=true", label=f"{label}: the store's rows after the import equal the preview")
    c.contains("chrome_preview", "spaces=1", "pinned=15", "essentials=12", "folders=7", "duplicates=3", "flattened=2", "overflow=2",
               "history=9", label="Chrome's preview: one space, the bar into Essentials, the clip, the duplicates")
    c.contains("chrome_applied", "history urls=8", "expired=2/1", label="Chrome's history into the engine (visits over 89 days counted out)")
    c.contains("essentials_cap", "essentials=12 cap=12", "overflow pinned=Site 11,Site 12", label="the Essentials cap: 12, the rest pinned")
    c.contains("depth_clip", "max depth=5", "flattened=2", "L5 holds=Level 5,Six,Seven", label="folders clipped at depth 5")
    c.contains("safari_preview", "spaces=5", "history=4", label="Safari: a space per top-level folder plus the target")
    c.contains("safari_spaces", "Safari,Dev,Recipes,Reading List,Travel", label="Safari's folders became spaces (the Reading List one of them)")
    c.contains("netscape_preview", "spaces=0", "folders=3", "pinned=5", "duplicates=1", label="Netscape into Space: the essential Docs is a duplicate")
    c.contains("arc_preview", "spaces=3", "essentials=1", "today=2", "overflow=2", label="Arc's preview")
    c.contains("arc_spaces", "Home icon=🏠 colors=#3366CC profile=Default", "Work icon=💼 colors=#CC4D33 profile=Work", "Side icon=none",
               label="Arc's spaces with their icons, colours and profiles")
    c.contains("arc_profiles", "work profiles=1", "work essentials=Chat", label="one Work profile (made or reused) with its essential")
    c.contains("history_search", "Typed three times=https://example.org/typed visits=3 typed=3", "Swift.org=https://swift.org/",
               label="imported history is in the engine in the same launch (search by title, else the URL's row: B-100)")
    c.check("the toast names the import", (v("toast") or "").startswith('"Imported from '), v("toast") or "missing")
    db = v("database") or ""
    m = re.findall(r"(\d+) of (\d+)", db)
    c.check("the rows are in the database", len(m) == 3 and all(a == b for a, b in m), db or "missing")
    c.check("the sheet closes", v("sheet_closed") == "true", v("sheet_closed") or "missing")
    # 4.3b: Firefox, passwords, the extensions' store pages, cookies, the fake home, file access, the two entry points.
    c.contains("read_firefox", "bookmarks=10 folders=3 skipped=1", "history=4 visits=7", "errors=0", label="Firefox's places.sqlite reader")
    c.contains("firefox_applied", "equal=true", "history urls=4", label="firefox: the store's rows after the import equal the preview")
    c.contains("firefox_space", "Firefox pinned=Firefox,MDN,Dev,Python,Recipes,News,Maps,On the phone", label="Firefox: the toolbar first, then the menu and Other Bookmarks, then mobile")
    c.contains("passwords_chosen", "line=passwords.csv: 4 rows", "phase=choosing", "can_import=true", label="a passwords CSV alone can be imported")
    c.contains("passwords_sheet", "status=success", "imported=3", "skipped=1", label="the CSV's passwords through the engine's importer (the malformed row skipped)")
    c.contains("passwords_toast", "3 passwords", "1 password row skipped", label="the toast names the passwords")
    c.contains("extensions_row", "web_store=uBlock Origin,Bitwarden Password Manager", "chosen=2", "My Unpacked Tool: unpacked", label="the Web Store extensions listed, the unpacked one skipped with its reason")
    c.contains("extensions_import", "pages_to_open=2", "2 extension pages to open, one at a time", label="the summary names the store pages")
    c.contains("store_page_first", "opened=1 pending=1", "tab=today", "space=Space", "webstore/detail.html?id=", "new_tabs=1", label="the first store page opens as a Today tab of the target space")
    c.contains("store_page_waits", "new_tabs=1", "opened=1 pending=1", label="the next page waits while the first is open")
    c.contains("store_page_next", "opened=2 pending=0", "first_tab_gone=true", label="closing the page opens the next")
    c.contains("store_pages_done", "finished", 'toast="Extensions from the Web Store: 0 added, 2 not added"', label="the sequence ends with its toast")
    c.contains("cookies_line", "Cookies and site data are not imported", label="the sheet says cookies are not imported")
    c.contains("home_detected", "home=fake", "Google Chrome=~/Library/Application Support/Google/Chrome", "Arc=~/Library/Application Support/Arc",
               "Safari=~/Library/Safari", "Firefox=~/Library/Application Support/Firefox", label="the browsers detected at their real paths (a fake home)")
    c.contains("home_safari", "bookmarks=10 folders=4", "history=4 visits=6", "errors=0", label="Safari read from ~/Library/Safari")
    c.contains("home_arc", "arc spaces=3", "errors=0", label="Arc read from ~/Library/Application Support/Arc")
    c.contains("home_firefox", "bookmarks=10", "profiles=default-release", "errors=0", label="Firefox's profile found under Profiles/")
    c.contains("permission_denied", "needs_access=true", "error=true", "Choose a File or Folder", label="a file macOS refuses: the sheet offers the open panel")
    c.contains("settings_import", "sheet=true", label="Settings ▸ General ▸ Import… opens the sheet")
    c.contains("first_run_import", "card=true", "sheet=true", label="the first-run card's Import from another browser… opens the sheet")
    for key in ("read_chrome", "read_safari", "read_netscape", "read_arc", "read_firefox", "chrome_applied", "passwords_sheet"):
        c.number(key)


# --- extensions (3.6b, 4.5) ---------------------------------------------------------------

def _no_dumps(c):
    n = c.first("crashpad_dumps")
    c.check("no engine minidump in the run's own engine directory", n == "0",
            f"{n}: " + "; ".join(c.values.get("crashpad_dump", []))[:240] if n else "missing")


@step_check("extpopup")
def _extpopup(c):
    """3.6b's popups from the header (`scripts/extensions-check.sh --spike extpopup`),
    rerun after 4.5's pinned-order change: the fixture's button with the page's
    badge, the popup from a click and its own resize, focus loss and Esc
    closing it with the page destroyed, action.openPopup, ⇧⌘Y and ⇧⌘U from
    the page."""
    spike_from_out(c)
    _no_dumps(c)
    c.contains("header", "buttons=[", "badge=\"T", label="the fixture's button in the header with the page's badge")
    c.contains("popup_click", "page state \"popup", label="a click opens the popup")
    c.check("the popup resized itself to 384×285", "384" in (c.first("popup_click") or ""), c.first("popup_click") or "missing")
    c.contains("popup_focus_loss", "popover_closed=true", "engine_destroyed_page=true", label="focus loss closes it; the engine destroys the page")
    for i in range(3):
        c.contains(f"popup_esc_{i}", "esc closed=true", "page_destroyed=true", label=f"Esc round {i + 1} closes it")
    c.contains("action_open_popup", "popover=true", label="action.openPopup() from the worker opens it")
    c.contains("command_execute_action", "popover=true", label="⇧⌘Y in the page opens it")
    c.contains("command_named", "onCommand=true", label="⇧⌘U in the page reaches commands.onCommand")
    for key in ("popup_open_times", "action_open_popup", "command_execute_action"):
        c.number(key)


@step_check("media")
def _media(c):
    """ROADMAP 4.6 (`scripts/media-check.sh`, the `media` spike): the media
    session's controls through the engine's members (play, pause, next,
    previous, seek, each read back from the fixture's log); the footer's
    media row for the fixture playing in a second space: title and artist,
    pause and play from the row reach the page, next retitles the row, a
    click on the row selects its entry (the row hides), × hides it until the
    page plays again; Chrome's Now Playing info; document picture-in-picture
    in a floating panel of the requested size that closes with its page, with
    the user's close and with its opener; video picture-in-picture's overlay
    window. The synthetic media key and MediaRemote's command are result lines."""
    spike_from_out(c)
    _no_dumps(c)
    c.contains("engine_session", 'title="Room Tone A"', 'artist="Phase 4.6"', "state=playing", "nextTrack", "seekTo", "artwork_png=",
               label="the session: metadata, playing, its actions, the artwork Chrome fetched")
    c.check("the artwork arrived as an image", "artwork_png=0B" not in (c.first("engine_session") or "artwork_png=0B"), c.first("engine_session") or "missing")
    c.contains("engine_pause", "page_logged=true", "state=paused", label="mediaPause reaches the page's pause handler")
    c.contains("engine_play", "page_logged=true", "state=playing", label="mediaPlay reaches the page's play handler")
    c.contains("engine_next", "page_logged=true", 'title="Room Tone B"', label="mediaNextTrack: the page's next track, the session retitled")
    c.contains("engine_previous", "page_logged=true", 'title="Room Tone A"', label="mediaPreviousTrack: back to the first track")
    c.contains("engine_seek", "page_logged=true", "settled=true", "position=12.0/", label="mediaSeek(to: 12) reaches seekto; the position follows")
    c.contains("row_while_selected", "hidden", label="no row while the playing entry is selected")
    c.contains("row_shown", "true in", 'title="Room Tone A"', 'subtitle="Phase 4.6"', "playing=true", "next=true", "image=96x96",
               label="another space: the row shows the session's title, artist and artwork")
    c.check("the row's pause reached the page", "page_logged -1" not in (c.first("row_pause") or "page_logged -1") and "session paused" in (c.first("row_pause") or ""),
            c.first("row_pause") or "missing")
    c.check("the row's play reached the page", "page_logged -1" not in (c.first("row_play") or "page_logged -1") and "session playing" in (c.first("row_play") or ""),
            c.first("row_play") or "missing")
    c.contains("row_next", 'title="Room Tone B"', label="the row's next retitles the row")
    c.contains("row_select", "selected=true", "space=Media", "row_hidden=true", label="a click on the row selects its entry in its space; the row hides")
    c.contains("row_dismiss", "hidden=true", "still_hidden_after_500ms=true", "page_playing=true", label="× hides the row while the page plays")
    c.check("the row returns when the page plays again", "-1 ms" not in (c.first("row_next_session") or "-1 ms"), c.first("row_next_session") or "missing")
    c.contains("nowplaying_playing", 'title="Room Tone A"', 'artist="Phase 4.6"', "rate=1.0", label="Chrome's system media controls fill Now Playing")
    c.contains("docpip_panel", "opened=true", "requested={320, 180}", "content=320x180", "level_floating=true", "nonactivating=true",
               "hides_on_deactivate=false", "Room document picture-in-picture", label="document PiP: a floating panel of the requested size with the page")
    c.contains("docpip_viewport", "320x180", "visible_in_panel=true", "hidden=false",
               label="the engine paints the PiP page at the panel's size (its own capture; the window server's shows Chromium's layers white)")
    c.contains("docpip_opener", "opener_alive=alive", "blockers=pictureInPicture", label="the opener stays loaded and is kept from discarding")
    c.contains("docpip_page_close", "panel_closed=true", "opener_alive=alive", "entry_kept=true", label="the page's window.close() closes the panel")
    c.contains("docpip_user_close", "page_closed=true", "opener_alive=alive", label="closing the panel closes the page")
    c.contains("docpip_opener_close", "panel_closed=true", label="closing the opener closes the panel")
    c.contains("videopip_window", "overlay=true", 'log="video pip"', "NativeWidgetMac", label="video PiP: Chrome's overlay window")
    c.contains("videopip_exit", "overlay_gone=true", 'log="video pip left"', label="exitPictureInPicture() closes it")
    for key in ("row_shown", "row_pause", "row_play", "row_next", "nowplaying_commands", "nowplaying_media_key",
                "nowplaying_mediaremote_pause", "nowplaying_paused", "docpip_panel", "videopip_window"):
        c.number(key)


@step_check("documents")
def _documents(c):
    """ROADMAP 4.7a (`scripts/documents-check.sh`, the `documents` spike and the
    PDFs setting's two launches): Save Page as HTML, complete HTML (the swatch
    and the stylesheet in `_files`) and MHTML through the engine's member, the
    MHTML reopened as a file:// page with its image (the DOM and the engine's
    pixels at the image); a full-page capture through the DevTools protocol
    taller than the viewport, with DevTools closed and open, the viewport
    unchanged after; Chrome's PDF viewer: rendered, the host's find (3
    matches, stepping), zoom, print preview closed by Esc, the toolbar's
    Download opening Chrome's save panel; PDFs ▸ Download at the next launch
    turns a PDF navigation into a download; View Source from the menu and from
    the page's context menu under the page; File ▸ Save Page…'s panel with
    its formats writing the MHTML that reopens, a PDF refused with a toast;
    ⇧⌘2: a dragged rectangle copied as a PNG of its pixel size, Return's
    viewport saved to the downloads folder with a toast and Show, Open as Tab,
    Esc, the full page."""
    spike_from_out(c)
    _no_dumps(c)
    for fmt in ("html", "completeHTML", "mhtml"):
        c.contains(f"engine_save_{fmt}", "ok in", label=f"savePage(as: .{fmt}) wrote its file")
    c.contains("engine_save_completeHTML", "swatch.png 322", "page.css", label="complete HTML keeps the image and the stylesheet in _files")
    c.contains("engine_mhtml_reopened", "url=file:", "image=[true,240,120", label="the MHTML reopens as a file:// page with its image loaded")
    reopened = c.first("engine_mhtml_reopened") or ""
    m = re.search(r"pixel\(orange part\)=\((\d+), (\d+), (\d+)\)", reopened)
    c.check("the engine's pixels at the image are not white", bool(m) and min(int(x) for x in m.groups()) < 200, reopened[-160:] or "missing")

    def taller(key):
        v = c.first(key) or ""
        png = re.search(r"png=(\d+)x(\d+)", v)
        vp = re.search(r"viewport=([\d.]+)x([\d.]+) pt scale=([\d.]+)", v)
        return bool(png and vp) and int(png.group(2)) > float(vp.group(2)) * float(vp.group(3)), v
    ok, v = taller("engine_fullpage")
    c.check("sendDevToolsCommand: a full-page PNG taller than the viewport", ok, v or "missing")
    ok, v = taller("engine_fullpage_devtools_open")
    c.check("the same with DevTools' front-end open", ok, v or "missing")
    after = c.first("engine_fullpage_viewport_after") or ""
    m = re.match(r"before=(\S+) after=(\S+)", after)
    c.check("the page's viewport is unchanged after the capture", bool(m) and m.group(1) == m.group(2), after or "missing")
    c.contains("engine_devtools_unknown", "error", "wasn", label="an unknown protocol method answers an error")
    c.contains("pdf_opened", "application", "pdf", label="a PDF opens in Chrome's viewer on a Room page")
    m = re.search(r"([\d.]+) % not white", c.first("pdf_rendered") or "")
    c.check("the viewer painted (the engine's capture is not blank)", bool(m) and float(m.group(1)) > 5, c.first("pdf_rendered") or "missing")
    c.contains("pdf_find", "matches=3", "final=true", "next → active=2", label="⌘F's find in the PDF: three matches, stepping")
    c.contains("pdf_zoom", "zoomFactor=1.5", "drawing_changed=true", label="zoom redraws the PDF")
    c.contains("pdf_print", "NativeWidgetMac", label="print: Chrome's preview over the window")
    c.contains("pdf_print_closed", "closed by Esc", label="Esc closes the preview")
    c.contains("pdf_toolbar_save", "save panel", 'proposed "sample.pdf"', label="the viewer's Download opens Chrome's save panel for sample.pdf (the landing is by hand)")
    c.contains("pdf_download_launch", "pdfsOpenInRoom=false", '"RoomPdfsDownload"', label="PDFs ▸ Download passes RoomPdfsDownload at the next launch")
    c.contains("pdf_download", "downloaded=true", ".pdf complete", label="then a PDF navigation downloads the file")
    c.contains("viewsource_menu", "below_entry=true", "selected=true", "url=view-source:", '\\"mentions\\":true', label="View Source: view-source: under the entry, shown, the page's source")
    c.contains("viewsource_context_menu", "offered=true", "position_from_page=1", "url=view-source:", label="the context menu's View Page Source opens it under the page")
    c.contains("savepage_panel", "Web Page, Complete", "Web Archive (MHTML)", ".mhtml\"", label="Save Page…: the panel with the formats; MHTML renames the file")
    c.contains("savepage_written", "true in", 'toast="Saved', "action=Show", label="the panel's Save writes the file; a toast with Show")
    c.contains("savepage_reopened", "image=[true,240,120]", label="the saved MHTML reopens with its image")
    c.contains("savepage_pdf", "cannot be saved", label="a page Chromium cannot save says so")
    c.contains("screenshot_overlay", "shown=true", "first_responder=true", label="⇧⌘2: the overlay over the page with the keyboard")
    drag = c.first("screenshot_drag") or ""
    m = re.search(r"image=(\d+)x(\d+) px \(expected ([\d.]+)x([\d.]+)", drag)
    c.check("a dragged rectangle: the capture cut to it at the backing scale (±1 px)",
            bool(m) and abs(int(m.group(1)) - float(m.group(3))) <= 1 and abs(int(m.group(2)) - float(m.group(4))) <= 1 and "bar=true" in drag, drag or "missing")
    copy = c.first("screenshot_copy") or ""
    mp = re.search(r"png=(\d+)x(\d+)", copy)
    c.check("Copy: the pasteboard holds a PNG of the selection's size", bool(m and mp) and (mp.group(1), mp.group(2)) == (m.group(1), m.group(2)) and "overlay_closed=true" in copy,
            copy or "missing")
    px = re.search(r"pixel@\(1/2,1/4\)=\((\d+), (\d+), (\d+)\)", copy)
    c.check("the copied pixels are the swatch's, not white", bool(px) and min(int(x) for x in px.groups()) < 200, copy[-120:] or "missing")
    save = c.first("screenshot_save") or ""
    mi = re.search(r"image=(\d+)x(\d+) px", save)
    mf = re.search(r"png=(\d+)x(\d+)", save)
    c.check("Return then Save: the viewport's PNG in the downloads folder, a toast with Show",
            "return_captured=true" in save and "file=Screenshot " in save and bool(mi and mf) and mi.groups() == mf.groups() and "show=Show" in save, save or "missing")
    c.contains("screenshot_open_as_tab", "url=Screenshot", "selected=true", "image=[", label="Open as Tab: a file:// Today tab under the page, shown")
    c.contains("screenshot_escape", "closed=true", label="Esc cancels the overlay")
    c.contains("screenshot_full_page", "true in", "taller=true", label="Full Page: the whole page, taller than the viewport")
    c.contains("screenshot_full_page_saved", "png=", label="the full page saved")
    for key in ("engine_save_completeHTML", "engine_save_mhtml", "engine_fullpage", "pdf_opened", "pdf_find", "pdf_print",
                "viewsource_menu", "viewsource_context_menu", "savepage_written", "screenshot_drag", "screenshot_full_page"):
        c.number(key)


@step_check("reader")
def _reader(c):
    """ROADMAP 4.7b (`scripts/reader-check.sh`, the `reader` spike): ⌥⇧⌘R on
    article1 shows Room's reader page in the card (the entry's page not
    navigated, the row's glyph) with the article's title, the host, the
    original link and Exit, both images loaded, no sidebar links; the three
    text sizes change the computed font size; light and dark change the
    page's background (the token's colour); Back does nothing while the
    reader shows; Esc returns to the page with its scroll and history, the
    reader file gone and not in history. article2 once: the menu action
    exits, a link exits and loads in the entry's page. notarticle: the
    toast and no reader page. A strict script-src article still distills.
    Translate: no item in the main or context menu, no offer (B-63); the
    context menu's Open in Reading Mode is Room's. Print: ⌘P's preview over
    the window with the keyboard, Return → Print to PDF's save panel, Esc
    closes it; File ▸ Page Setup… shows its sheet."""
    spike_from_out(c)
    _no_dumps(c)
    c.contains("reader_resources", "distiller=111995 B", label="the distiller and the template ship in the app")
    c.contains("reader_menu_item", 'title="Reader Mode"', "key=⌥⌘R", "enabled=true", label="View ▸ Reader Mode ⌥⇧⌘R, enabled on an article")
    c.contains("reader_shown", "by ⌥⇧⌘R", "card_shows_reader=true", "focused=true", "entry_page_url=unchanged", "row_glyph=true", "images=2",
               label="⌥⇧⌘R: the reader page in the card; the entry's page untouched; the row's glyph")
    c.contains("reader_row", "glyph shown=true", label="the sidebar row draws the reader glyph")
    c.contains("reader_dom", "Lighthouse Keepers", '\\"host\\":\\"127.0.0.1\\"', '\\"exit\\":true', "article1.html", '\\"asideLinks\\":0',
               '\\"scripts\\":0', label="the reader page: title, host, the original link, Exit; no sidebar links, no script")
    imgs = c.first("reader_images") or ""
    c.check("both images loaded (DOM: complete, natural size)", imgs.count("[true,") == 2 and "swatch.png" in imgs and "field.png" in imgs, imgs or "missing")
    sizes = c.first("reader_sizes") or ""
    m = re.findall(r'(small|medium|large)="([\d.]+)px"', sizes)
    vals = dict(m)
    c.check("the three text sizes: small < medium < large (computed font size)",
            len(vals) == 3 and float(vals["small"]) < float(vals["medium"]) < float(vals["large"]), sizes or "missing")
    light = c.first("reader_light") or ""
    dark = c.first("reader_dark") or ""
    bl = re.search(r'background\\":\\"(rgb[^\\]*)', light)
    bd = re.search(r'background\\":\\"(rgb[^\\]*)', dark)
    c.check("light: data-appearance light on a white background", '\\"appearance\\":\\"light\\"' in light and bool(bl) and bl.group(1) == "rgb(255, 255, 255)", light or "missing")
    c.check("dark: data-appearance dark on the token's dark background", '\\"appearance\\":\\"dark\\"' in dark and bool(bd) and bd.group(1) != "rgb(255, 255, 255)", dark or "missing")
    c.contains("reader_back_ignored", "entry_page_url=unchanged", "still_reader=true", label="Back while reading: the article's page does not move")
    ex = c.first("reader_exit") or ""
    sm = re.search(r"scroll (\S+)→(\S+)", ex)
    c.check("Esc: back to the page, scroll and history intact, the glyph gone, the file removed",
            "exited" in ex and "card_shows_page=true" in ex and "url=unchanged" in ex and bool(sm) and sm.group(1) == sm.group(2)
            and "canGoBack true→true" in ex and "row_glyph=false" in ex and "file_removed=true" in ex, ex or "missing")
    c.check("the reader file's visit is not in history", "file:" not in (c.first("reader_history") or "file:"), c.first("reader_history") or "missing")
    c.contains("reader_back_after_exit", "url=page.html", label="after Exit, Back moves the article's page")
    c.contains("reader2_shown", "card_shows_reader=true", "images=1", label="article2: the reader page with its figure's image")
    c.contains("reader2_images", "[true,320,180", label="article2's image loaded")
    c.contains("reader2_exit", "exited", "card_shows_page=true", label="View ▸ Exit Reader Mode returns to the page")
    c.contains("reader2_link", "exits reader mode", "entry_page_url=article1.html", "card_shows_page=true", label="a link in the reader page exits and loads in the entry's page")
    c.contains("reader_notarticle", "not an article", 'toast="No article found on this page"', "reader_page=false", label="notarticle: the toast, no reader page")
    c.contains("reader_csp", "shown", label="an article under a strict script-src CSP distills")
    c.contains("translate_absent", "main_menu_items=[]", "context_menu_translate=[]", "offer_toast=none", "context_menu_opened=true",
               label="translate is absent without a key: no menu item, no context-menu item, no offer (B-63)")
    c.contains("translate_context_menu_items", "Open in Reader Mode", label="the context menu's reading-mode item is Room's reader mode")
    c.contains("print_preview", "NativeWidgetMac", "child of Room's window: true", label="⌘P: Chrome's print preview over the window")
    c.contains("print_keyboard", "key_is_preview=true", label="the preview has the keyboard after ⌘P")
    # 5.0b: on a Mac with printers the preview's default is the system's printer and Return prints a page,
    # so the spike presses Esc instead there (the line says so); the save panel is checked where no printer is set up.
    t = c.first("print_to_pdf") or ""
    c.check("Return in the preview: Print to PDF asks where to save (the landing is by hand; not pressed on a Mac with printers)",
            ("save panel" in t and ".pdf" in t) or t.startswith("not pressed: this Mac has"), t or "missing")
    c.contains("print_closed", "closed", label="Esc closes the preview")
    c.contains("page_setup", 'item="Page Setup…"', "sheet=NSPanel", label="File ▸ Page Setup… shows the page layout sheet")
    for key in ("reader_shown", "reader2_shown", "reader_notarticle", "reader_exit", "print_preview", "print_to_pdf"):
        c.number(key)


@step_check("windows")
def _windows(c):
    """ROADMAP 4.8a (`scripts/windows-check.sh`, the `windows` spike, three
    launches): ⌘N opens a second window cascaded from the first on its space
    with an empty Today list, key; a pinned entry renamed in window 1 shows in
    window 2's row in the same turn; a Today tab belongs to its window (listed
    there, not in the other); a pinned page navigated in window 1 and selected
    in window 2 moves (4.8b: the same page through `move(toHostWindow:)`; window
    1's selection on its MRU shown in its card) with its history (the second page, canGoBack, Back works); ⌘1 in
    window 2 selects its first entry and leaves window 1 alone; ⌃Tab's list is
    the window's; Open in New Window from the context menu makes a third
    window with the Today tab moved and selected; a drag ending 20 pt past the
    edge makes nothing, 100 pt past makes a window whose top-left is the drop
    point. Relaunch: every window back with its frame and active space, the
    Today tab in its own window, only the front window loaded; closing a
    window archives its Today tab with `windowClosed` (the Library's row;
    restorable); closing the last window keeps the app, ⌘N reopens the kept
    window, so does the Dock. Memory: ten pages over two windows beside one
    window's (numbers; judged on the release framework)."""
    spike_from_out(c)
    _no_dumps(c)
    c.contains("pinned_window1", "url=next-b.html", "canGoBack=true", label="window 1: the pinned page on its second page with history")
    c.contains("new_window", "by ⌘N windows=2", "key=2", "active_is_new=true", "cascade=22,22", "same_space=true", "today=0", "selected=none",
               "card_empty=true", "rows=2", label="⌘N: a second window, key, cascaded 22 pt, the same space, an empty Today list")
    c.contains("new_window", "window_menu=2", label="the Window menu lists both windows (AppKit's list)")
    c.contains("shared_rename", '→"Renamed in window 1"', 'window1_row="Renamed in window 1"', "same turn",
               label="a pinned entry renamed in window 1 shows in window 2's row at once")
    c.contains("today_per_window", "window2_today=2", "window1_today=0", "tab_window=2", "listed_window2=true", "listed_window1=false",
               "pinned_listed_both=true", label="Today tabs per window; pinned entries in both")
    c.contains("pinned_move", "same_page=true", "page_state=alive", "window1_holds=false", "window1_selected=C (its MRU)", "window1_card_shows_mru=true",
               label="selecting the pinned page in window 2 moves the same page (move(toHostWindow:), 4.8b): window 1 hands it over and shows its MRU")
    c.contains("pinned_move", "window2_url=next-b.html", "window2_canGoBack=true", "history_length=2", "window2_card=true", "owners=2",
               label="window 2 shows the moved page with its history")
    c.contains("pinned_move_back", "url=b.html", label="Back in window 2 goes to the page's first page")
    c.contains("cmd1_window2", "key=2", "selected_first=true", "window1_selection_kept=true", label="⌘1 in window 2 selects window 2's first entry only")
    c.contains("switcher_per_window", "window2_has_its_tab=true", "window1_has_window2_tab=false", label="⌃Tab's recent list is per window")
    c.contains("open_in_new_window", "item=true", "enabled=true", "windows=3", "selected=true", "tab_window=3", "window2_lists=false",
               "window3_lists=true", "page=e.html", "window2_holds=false", label="Open in New Window: a third window with the Today tab moved and selected")
    c.contains("drag_out", "near(20pt)_windows=3", "past(beyond 40pt)_windows=4", "top_left_at_drop=true", "selected=true", "kind=today",
               "tab_window=4", label="the drag out: nothing within 40 pt; past it a window at the drop point with the entry")
    c.contains("saved", "windows=4", "rows=4", label="four windows saved")
    restored = [c.first(f"restored_window_{i}") or "" for i in range(1, 5)]
    c.check("relaunch: every window back with its frame", all("frame_matches=true" in r for r in restored), " | ".join(r[:90] for r in restored))
    saved_spaces = [re.search(r"space=(\S+)", c.first(f"saved_window_{i}") or "") for i in range(1, 5)]
    restored_spaces = [re.search(r"space=(\S+)", r) for r in restored]
    c.check("relaunch: every window on its active space (window 2 on Second)",
            all(a and b and a.group(1) == b.group(1) for a, b in zip(saved_spaces, restored_spaces)) and "space=Second" in restored[1],
            " | ".join((b.group(1) if b else "?") for b in restored_spaces))
    c.contains("restored", "windows=4", "today_d_in_window=2", "today_d_in_front=false", label="relaunch: the Today tab is in its own window, not the front one")
    c.contains("restored", "loaded_windows=1", "key=1", label="relaunch: only the front (key) window's selection loaded (spec §H)")
    c.contains("close_window", "windows 4→3", "entry_gone=true", "archived=windowClosed", "library_row=Windows fixture D", "windowClosed_rows=1",
               label="closing a window archives its Today tab with reason windowClosed (the Library's row)")
    c.contains("close_window_restore", "into the active window", label="the archived tab restores into the window that asks")
    c.contains("close_last", "windows=0", "visible=0", "app_running=true", "rows_kept=1", label="closing the last window keeps the app running")
    c.contains("reopen_cmd_n", "menu_took=true", "windows=1", "same_row=true", "visible=true", label="⌘N reopens a window on the last state")
    c.contains("reopen_dock", "windows=1", "visible=true", label="the Dock's reopen does too")
    one = c.first("memory_windows_1") or ""
    two = c.first("memory_windows_2") or ""
    c.check("memory: ten pages over two windows (5 + 5) beside ten in one window, each on a fresh launch",
            "loaded=10/10" in one and "pages_window1=10" in one and "loaded=10/10" in two and "pages_window1=5" in two and "pages_window2=5" in two,
            (one[:110] + " | " + two[:140]) or "missing")
    for key in ("new_window", "pinned_move", "shared_rename", "memory_baseline_1", "memory_windows_1", "memory_baseline_2", "memory_windows_2"):
        c.number(key)


@step_check("incognito")
def _incognito(c):
    """ROADMAP 4.8b (`scripts/incognito-check.sh`, the `incognito` spike, two
    launches): ⇧⌘N opens the incognito window (titled Incognito, the dark
    appearance whatever the system's, the tint token, the "Incognito" label,
    key; not in the store's windows; in the Window menu); its sidebar is the
    note, the Today list and New Tab (no essentials, no pinned, one space); a
    cookie set at cookies.html there is absent in the regular profile; the
    regular profile's history and Room's store have no row of it; a sign-in
    offers to save in the regular window and not in incognito (3.7a's check
    inverted); "Open Link in Incognito Window" from a regular page lands in
    the incognito window; the fixture extension's action shows in the
    incognito header only while allowed in incognito (the engine's bit
    follows); closing the window ends its pages and the off-the-record
    profile and the renderers go; reopened, a new twin without the cookie;
    the engine's net-log over launch and idle with an incognito window open
    names no host."""
    spike_from_out(c)
    _no_dumps(c)
    c.contains("incognito_window", "by menu key", 'title="Incognito"', "appearance=NSAppearanceNameDarkAqua", "tint=#2A2A33", "badge=Incognito",
               "key=true", "windows=2", "store_rows=1/1", "window_menu_lists=true", "ephemeral=true",
               label="⇧⌘N: the incognito window, dark with its label, not stored, listed in the Window menu")
    c.contains("incognito_sidebar", "rows=note,separator,newtab", "essentials_shown=false", "spaces=1", "pinned=0", "essentials=0",
               label="the incognito sidebar: the note, the Today list, no essentials or pinned")
    c.contains("cookie", 'incognito="room_profile=incognito-main"', 'regular=""', label="a cookie set in incognito is absent from the regular profile")
    c.contains("history", "incognito_rows=0", "store_entries=0", label="the regular profile's history and Room's store have nothing of the incognito page")
    c.contains("login_regular", "save_bubble=true", label="a sign-in in the regular window offers to save (the control)")
    c.contains("login_incognito", "save_bubble=false", "submitted_to=/login", label="a sign-in in incognito shows no save bubble")
    line = c.first("open_link_incognito") or ""
    m = re.search(r"incognito_today=(\d+)→(\d+) regular_today=(\d+)→(\d+)", line)
    c.check("Open Link in Incognito Window from a regular page lands in the incognito window",
            bool(m) and int(m.group(2)) == int(m.group(1)) + 1 and m.group(3) == m.group(4)
            and 'item="Open Link in Incognito Window"' in line and "url=next-a.html" in line and "in_incognito_window=true" in line, line[:200] or "missing")
    c.contains("extensions_incognito", "disallowed: regular=true incognito=false", "allowed: incognito=true engine=true",
               "disallowed again: gone=true engine=true regular=true", label="the extension's action in incognito only while allowed")
    close = c.first("close_incognito") or ""
    r = re.search(r"renderers=(\d+)\(launch\)→(\d+)\(open\)→(\d+)\(closed\)", close)
    c.check("closing the incognito window ends its pages and the off-the-record profile; renderers go",
            "windows=1" in close and "→0 twin_gone=true" in close and bool(r) and int(r.group(3)) < int(r.group(2))
            and "store_rows=1" in close and "reader_folder_left=false" in close, close[:220] or "missing")
    c.contains("reopen_incognito", "new_twin=true", 'cookie=""', label="reopened: a new twin without the cookie")
    c.contains("idle_incognito", "opened=true", label="the net-log launch: an incognito window open over launch and idle")
    c.contains("netlog", "(0 not page traffic: none)", label="the engine's net-log names no host with an incognito window open")
    for key in ("incognito_window", "open_link_incognito", "close_incognito"):
        c.number(key)


@step_check("extensions")
def _extensions(c):
    """ROADMAP 4.5 (`scripts/extensions-check.sh`, the `extux` spike with the
    net-log): site access On click keeps the fixture's content script waiting
    until Run (the engine's member and the site panel's button), On this site
    holds across reloads; ⇧⌘U and ⇧⌘Y with the sidebar's list focused reach
    the extension (B-70); unpinning moves the action to the overflow menu with
    its badge, its popup points at the overflow button, Pin puts it back at
    the header's end; the options page opens in a space of the extension's
    profile with two profiles (B-67), a profile without a space gets one;
    Chrome's shortcuts page as a tab; Settings ▸ Shortcuts' read-only rows;
    the extension's own request carries its origin and the engine's own
    requests stay 0."""
    spike_from_out(c)
    _no_dumps(c)
    c.contains("content_script_default", "ran=true", label="the content script runs by default (on all sites)")
    c.contains("access_default", "level=onAllSites", 'selectable=["onClick", "onSite", "onAllSites"]', "canAffect=true",
               label="site access: on all sites, all three levels selectable")
    c.contains("access_on_click", "set=true", "ran_after_reload=false", "level=onClick", "wantsToRun=true",
               label="On click: after a reload the script waits (wantsToRun)")
    c.contains("access_run", "run=true", "ran=true", "wantsToRun=false", label="runAction runs the waiting script")
    c.contains("access_on_site", "set=true", "ran_after_reloads=[true, true]", "level=onSite", label="On this site: runs after two reloads")
    c.contains("commands", "_execute_action=⇧⌘Y action", "room-named=⇧⌘U", label="the commands with their keys in Room's notation")
    c.contains("command_sidebar_named", "first_responder=SidebarOutlineView", "page_has_keyboard=false", "routed=⇧⌘U true", "onCommand=true",
               label="⇧⌘U with the sidebar's list focused reaches commands.onCommand (B-70)")
    c.contains("command_sidebar_action", "popover=true", "routed=⇧⌘Y true", label="⇧⌘Y with the sidebar focused opens the popup")
    c.contains("command_sidebar_other_key", "routed=⇧⌘C false", label="a key no extension has goes on to the menu")
    c.contains("header_initial", 'buttons=["fixture", "second"]', "overflow_button=false", label="two pinned actions in install order, no overflow button")
    c.contains("header_unpinned", 'buttons=["second"]', 'overflow=["fixture"]', "overflow_button=true", "Room 3.6 fixture  T", "badge=T",
               label="unpinned: the header keeps the other, the overflow menu lists it with its badge")
    c.contains("overflow_run", "popover=true", "anchored_on_overflow=true", "shown_id=fixture", label="the overflow item runs the action; its popup on the overflow button")
    c.contains("header_repinned", 'buttons=["second", "fixture"]', "overflow_button=false", label="Pin puts it back at the header's end (the pinned order)")
    c.contains("site_panel_section", 'rows=["fixture"]', "host=127.0.0.1", "level=0", "run_shown=true", "ran_before_run=false",
               label="the site panel lists the extension on click with Run; the script has not run")
    c.contains("site_panel_run", "ran=true", "ran_here=true", "keep_offered=true", label="the site panel's Run runs it and offers to keep it on the site")
    c.contains("site_panel_on_site", "ran_after_reloads=[true, true]", "level=1", "wants_to_run=false",
               label="\"Always on this site\": remembered across two reloads")
    c.contains("site_access_all", "set=true", "level=2", label="back to On all sites")
    c.contains("options_page", "profiles=2", "shown_before=Office", "space_profile=extension's", "options.html", "page_profile=extension's",
               "storage written", label="the options page opens in a space of the extension's profile with two profiles (B-67) and works there")
    c.contains("extension_page_new_space", "made=Extensions", "shown=true", label="a profile without a space gets an Extensions space for its page")
    c.contains("shortcuts_page", "url=chrome://extensions/shortcuts", "space_profile=extension's", label="Keyboard Shortcuts…: Chrome's page as a tab")
    c.contains("settings_shortcut_rows", "⇧⌘Y", "⇧⌘U", label="Settings ▸ Shortcuts lists the fixture's two commands read-only")
    c.contains("incognito_setting", "stored=true", "other_profile=false", label="Allow in incognito stored per profile")
    c.contains("extension_fetch_server", "1 request(s)", label="the extension's own request reached the local server once")
    c.contains("extension_fetch_netlog", "1 with initiator chrome-extension://", label="the net-log attributes it to the extension's origin")
    c.contains("engine_netlog", "0 not page traffic", label="the engine's own requests: 0")
    for key in ("access_run", "command_sidebar_named", "command_sidebar_action", "overflow_run", "site_panel_run"):
        c.number(key)


# --- app integration (2.8) ---------------------------------------------------------------

@step_check("app28a")
def _app28a(c):
    spike_from_out(c)
    items = [l for l in c.spike if l.startswith("menu_item")]
    c.check("the menu walk covered the bar (≥ 118 items)", len(items) >= 118, f"{len(items)}")
    for key in ("menu_duplicate_keys", "menu_app_items_not_on_app_delegate", "menu_app_items_without_validation"):
        c.check(f"{key}: none", c.first(key) == "none", c.first(key) or "missing")
    c.contains("menu_command_left", "enabled with the page focused=true", "with the palette's field editing=false", label="⌘← is Back on a page, the field's key while editing")
    for section in ("general", "appearance", "search", "downloads", "privacy"):
        c.check(f"Settings ▸ {section.title()} shows", (c.first(f"settings_{section}") or "").startswith(f"title={section.title()}"), c.first(f"settings_{section}") or "missing")
    c.contains("settings_sidebar_side", "right applied=true", label="Settings ▸ Sidebar Right applies at once")
    c.contains("right_docked_chrome", "over the card=true", "cluster shown=true", label="sidebar right: buttons over the card, the cluster shown")
    c.contains("right_overlay", "shown=true", label="sidebar right: the overlay from the right edge")
    for i in range(3):
        c.contains(f"fullscreen_enter_{i}", "entered=true", "laid out=true", label=f"⌃⌘F round {i + 1}: in, header laid out")
        c.contains(f"fullscreen_exit_{i}", "exited=true", "toolbar visible=true", label=f"⌃⌘F round {i + 1}: out, toolbar back")
    c.contains("fullscreen_state", "header x=8.0", "toolbar visible=false", label="fullscreen: the 8 pt top-bar fallback, toolbar hidden")
    c.contains("fullscreen_reveal", "shown=true", label="hover reveal in fullscreen")
    c.check("header back after the buttons when windowed", c.first("fullscreen_header_windowed") == "x=94.0 (before: 94.0)", c.first("fullscreen_header_windowed") or "")
    for key in ("menu_update_all", "settings_sidebar_side", "fullscreen_enter_0", "fullscreen_exit_0", "fullscreen_reveal"):
        c.number(key)


@step_check("app28b")
def _app28b(c):
    spike_from_out(c)
    c.contains("cold_url", "arrived queued (inbox closed: true)", label="a cold launch by a link: queued until the engine is up")
    c.contains("cold_url_entry", "kind=today", "selected=http://127.0.0.1:8770/site.html?cold-", label="the cold link opens as the selected Today tab")
    c.contains("opt_ins_launch", "updater created=false", "crash reporter created=false", label="at launch with both opt-ins off, neither Sparkle nor Sentry exists")
    c.contains("first_run_launch", "card=shown", "above footer=true", label="the first-run card shows (docked left)")
    c.contains("first_run_right", "shown", label="the card docked right")
    c.contains("first_run_overlay", "in overlay=true", label="the card in the hidden sidebar's overlay")
    c.contains("first_run_engine", "after choice=duckduckgo", label="the card's engine choice reaches the palette")
    c.contains("first_run_done", "card gone=true", "stored done=true", label="Done stores the first run")
    c.contains("first_run_show_again", "card back=true", label="Show Welcome Card brings it back")
    for method in ("open", "applescript", "workspace"):
        c.contains(f"running_url_{method}", f"selected=http://127.0.0.1:8770/site.html?running-{method}", label=f"a running link by {method}: selected Today tab")
    c.contains("closed_window_link", "window visible=true", "main=true", label="a link after ⇧⌘W brings the window back with it")
    c.contains("opt_in_updates_on", "updater created=true", label="automatic checks on: the updater is made")
    c.contains("opt_in_crash_on", "reporting=true", label="crash reports on: the reporter starts")
    c.contains("opt_in_crash_off", "reporting=false", label="crash reports off: stopped")
    log = [l for l in c.out if re.match(r"^\d+\.\d+ (GET|POST|HEAD|CONNECT) ", l)]
    marker = c.values.get("opt_ins_marker", [])
    start = float(marker[0].split()[0]) if marker else 0
    early = [l for l in log if float(l.split()[0]) < start]
    c.check("no endpoint request before the opt-ins were switched on", not early, "; ".join(early)[:200])
    c.check("the feed was fetched only after automatic checks went on", any("/appcast.xml" in l for l in log), "no feed request")
    for key in ("cold_url", "cold_url_event_to_requested", "cold_url_requested_to_loaded", "running_url_open", "running_url_applescript",
                "running_url_workspace", "closed_window_link", "first_run_done"):
        c.number(key)


@step_check("netlog")
def _netlog(c):
    text = "\n".join(c.out)
    body = text.split("== Room's own code", 1)
    own = body[1].split("==", 1)[0] if len(body) > 1 else ""
    c.check("Room's own code: 0 requests to the feed, crash endpoint and suggestion proxy", own.strip().splitlines()[1:2] == ["none"], own.strip()[:200])
    main = re.search(r"^Room\.\d+ in=(\d+) out=(\d+)", text, re.M)
    c.check("Room's main process moved 0 bytes", main and main.group(1) == "0" and main.group(2) == "0", main.group(0) if main else "missing")
    spike = [l for l in c.out[:20]]
    v = kv(spike)
    opt = (v.get("opt_ins") or [""])[0]
    c.check("launch with every opt-in declined: no updater, no crash reporter", "updater created=false crash reporter created=false" in opt, opt)
    c.check("suggestions at their default (on) for the check", "searchSuggestions=true" in opt, opt)
    c.check("the spike reached its end", "end: netcheck" in text, "")
    hosts = re.search(r"hosts: (\d+) \((\d+) not page traffic: ([^)]*)\)", text)
    if hosts:
        c.number("engine hosts (not page traffic)", f"{hosts.group(2)}: {hosts.group(3)}")
        c.notes.append(f"the engine's own requests (0 expected since 3.1b-2): {hosts.group(3)}")
