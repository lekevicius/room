"""Checks for each grand-tour step (scripts/grand-tour.sh, Phase 2.9).

evaluate(run, step) reads a step's raw output (steps/<name>.spike for a
SpikeRunner spike, steps/<name>.out for a wrapper's stdout) and returns
{"checks": [(name, ok, detail)], "numbers": [(key, value)], "notes": [...]}.

Every step gets the generic checks (exit 0, no crash report, nothing left
running, the spike reached its end, no `error:` or `capture_timeout:`
lines). The per-step checks below are the spec's or the phase's own
criterion where it is a rule (a count, an identity, a state), and a
presence check where it is a number: a result line that is missing fails,
so a spike that skips a section (a CEF-only path on another engine, a
guard that returned early) cannot pass by saying nothing. Timings are
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
        c.check("no helper crash report", False, f"{step['helper_crash_reports']} new")
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
    dia_framing(c, all("card={{280, 6}, {958, 806}}" in v for k, v in states.items() if "compare" in k), "Dia framing: card {{280, 6}, {958, 806}}",
                next((v.split("card=")[1].split(" title")[0] for k, v in states.items() if "compare" in k), ""))
    c.check("sidebar open: card at x 240, closed: at x 6",
            all("card={{240, 6}" in v for k, v in states.items() if k.endswith("-open")) and
            all("card={{6, 6}" in v for k, v in states.items() if k.endswith("-closed")), "")


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
        c.notes.append("Web Audio reads silent while playing: the known CEF cap (ROADMAP Chapter 2 caps; RoomCore 3.3a)")


@step_check("popups")
def _popups(c):
    c.contains("target_blank", "current=true", "title=Popup target", "inCard=true")
    c.contains("window_open", "title=Popup target", "inCard=true")
    for kind in ("sel", "date"):
        a, b = c.first(f"popup_{kind}_moved_false") or "", c.first(f"popup_{kind}_moved_true") or ""
        oa, ob = re.search(r"offset (.*)$", a), re.search(r"offset (.*)$", b)
        c.check(f"<{'select' if kind == 'sel' else 'input type=date'}> popup keeps its offset after the window moves",
                oa and ob and oa.group(1) == ob.group(1), f"{a} / {b}")
    c.check("alert as a sheet, completed", c.first("alert_sheet") == "true" and "true" in (c.first("alert_completed") or ""), "")


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
        # ⌘V lands in the field: CEF replaces the selection (" PASTED"), RoomCore pastes at the caret the
        # spike placed at the end ("select me and copy PASTED", 3.2b); either way the page saw it first.
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
        c.number("didConsumeKey calls per layout (CEF: never)", ", ".join(map(str, consumed)) or "n/a")
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
    mm = re.search(r"reopened at a generation committed after the last ack: (\d+)", text)
    c.check("no generation lost after its acknowledgement", mm and mm.group(1) == "0", mm.group(0) if mm else "missing")
    if m:
        c.number("wall time", m.group(2))


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
    c.check("engine profiles are direct children of the root", c.first("engine_profile_directories") == "Room Profile Default, Room Profile Work",
            c.first("engine_profile_directories") or "missing")
    c.check("Work has no history from Default (history follows the profile)", "Work=0" in (c.first("history_rows") or ""), c.first("history_rows") or "")


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
    c.check("same-document pushState recorded", '["link"]' in hist.get("history https://example.org/pushed", ""), "")
    c.check("DNS error page not recorded", "visits=[]" in hist.get("history https://nonexistent.invalid/", "visits=[]"), "")
    c.check("a search recorded", "history search page" in hist, "missing")
    exa = next((l for l in c.spike if l.startswith("palette exa: ")), "")
    c.check("inline host completion from history (exa → example.com)", "inline=mple.com" in exa, exa or "missing")
    for appearance in ("light", "dark"):
        c.contains(f"state_commands-filtered_{appearance}", 'rows=["Reload", "Reload without Cache"]', label=f">re filters commands ({appearance})")
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
    c.check("500 entries and 50,000 history rows", c.first("entries") == "500" and c.first("history_rows") == "50000",
            f"entries {c.first('entries')} history {c.first('history_rows')}")
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
        c.notes.append("the reloaded discarded tab has no back history: CEF cap B-13 (3.3a)")
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


# Every delegate member the recorder saw called on CEF in 2.6b (docs/engine-api.md, "Phase 2.6 exit checklist");
# didConsumeKey is the one CEF never calls.
DELEGATE_MEMBERS = """decidePolicy didChangeAudible didChangeMuted didChangeSecurityState didChangeStatusText didCommitNavigation didCreate
didFailCertificateCheck didReceiveAuthChallenge didUpdateDownload handleUnhandledKeyEvent isReservedKeyEvent processGone runBeforeUnloadDialog
runFileChooser runJavaScriptAlert runJavaScriptConfirm runJavaScriptPrompt webContentsDidClose webContentsDidDismissJavaScriptDialogs
webContentsDidDismissPermissionPrompt webContentsDidRequestEnterFullscreen webContentsDidRequestExitFullscreen willAskForPermission
willBeginDownload willShowContextMenu""".split()


@step_check("chrome26b")
def _chrome26b(c):
    # chrome://crash makes one renderer crash report: expected here, and only here.
    helpers = c.step.get("helper_crash_reports", c.step["crash_reports"])
    if "helper_crash_reports" not in c.step:  # the first light run counted both together
        c.checks = [ch for ch in c.checks if ch[0] != "no crash report"]
    c.check("one helper crash report, the renderer `chrome://crash` killed", helpers == "1", f"{helpers}")
    _chrome26a(c)
    calls = dict(p.split("=") for p in (c.first("delegate_calls") or "").split() if "=" in p)
    missing = [m for m in DELEGATE_MEMBERS if m not in calls]
    c.check(f"every delegate member called on CEF ({len(DELEGATE_MEMBERS)}; didConsumeKey never, as known)", not missing, "missing: " + ", ".join(missing))
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
        c.contains("print_panel", "modal NSPanel", label="⌘P: CEF's print panel (B-29)")
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
    c.contains("split_element_fullscreen", "focused pane fills the card=true", "after exit panes visible=true", label="element fullscreen of a pane")
    for key in ("reveal_band_to_shown", "reveal_leave_to_hidden", "cluster_fade", "peek_open_to_overlay_frame", "peek_open_to_first_contentful_paint",
                "split_create_to_laid_out", "split_create_to_next_frame", "focus_click_to_field_updated", "focus_click_to_next_frame"):
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
    c.contains("fullscreen_state", "header x=16.0", "toolbar visible=false", label="fullscreen: the 16 pt header fallback, toolbar hidden")
    c.contains("fullscreen_reveal", "shown=true", label="hover reveal in fullscreen")
    c.check("header back after the buttons when windowed", c.first("fullscreen_header_windowed") == "x=91.0 (before: 91.0)", c.first("fullscreen_header_windowed") or "")
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
        c.notes.append(f"the engine's own requests (B-19, Chapter 3.1b): {hosts.group(3)}")
