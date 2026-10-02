# Shortcuts, v0 (frozen in Phase 1.6)

The v1 shortcut table (feature spec §G) with the **reserved** set marked.
Reserved shortcuts never reach the page: `WebContentsUIDelegate.isReservedKeyEvent`
returns `true` and the engine hands them to the main menu. Everything else
goes to the page first; if the page does not consume it, it reaches the main
menu once (`handleUnhandledKeyEvent`, PLAN §2.4).

Source of truth for the reserved set: `Packages/UIKitCore/Sources/UIKitCore/ReservedShortcuts.swift`
(`ReservedShortcuts.all`, tested in `ReservedShortcutsTests`). Changing it
after the freeze needs a log entry in `docs/progress.md` saying why.

Why so few are reserved: a reserved key is one a web app can never use. The
set is the browser frame's escape hatches — open, close, quit, reopen, the
palette, and moving between tabs and spaces — the same kind of set Chrome
reserves. ⌘S (toggle sidebar) is page-first because web editors (Figma,
StackBlitz, vscode.dev) save with it; when the page does not handle it, the
sidebar toggles. Matching uses the active layout's character for letters (⌘T
is the key labelled T on Colemak), the US key for non-Latin characters, and
key codes for arrows and Tab (`ReservedShortcuts.key(for:)`).

| Action | Keys | Reserved | Chapter | Notes |
|---|---|---|---|---|
| New tab (palette) | ⌘T | **yes** | 2.4 | pressing again closes the palette |
| Edit current URL (palette) | ⌘L | **yes** | 2.4 | Enter unchanged = reload |
| New window | ⌘N | **yes** | 2.8 | multi-window proper is Chapter 4.8 |
| New incognito window | ⇧⌘N | **yes** | 4.8 | menu item disabled until then |
| Close tab / pane (permanent entry: unload + reset + switch) | ⌘W | **yes** | 2.3 | spec §A.3 |
| Close window | ⇧⌘W | **yes** | 1.4 | "Remove" a permanent entry is menu-only |
| Reopen closed tab (incl. Peek) | ⇧⌘T | **yes** | 2.3 / 2.7 | |
| Quit | ⌘Q | **yes** | 1.1 | |
| MRU switcher / backwards | ⌃Tab / ⌃⇧Tab | **yes** | 2.3 | hold ⌃, tap W closes |
| Next / previous tab | ⇧⌘] / ⇧⌘[ | **yes** | 2.3 | |
| Next / previous tab in sidebar order | ⌥⌘↓ / ⌥⌘↑ | **yes** | 2.3 | |
| Next / previous space | ⌥⌘→ / ⌥⌘← | **yes** | 2.5 | wraps around |
| Toggle sidebar | ⌘S | no | 1.3 | page-first; "Save page" is ⇧⌘S |
| Pin overlay sidebar open | ⌥⌘S | no | 2.7 | |
| Settings | ⌘, | no | 2.8 | page-first (was reserved in Chapter 1) |
| Pin / unpin | ⌘D | no | 2.2 | |
| Add to / remove from Essentials | ⇧⌘D | no | 2.2 | |
| Copy URL / as Markdown | ⇧⌘C / ⌥⇧⌘C | no | 2.6 | toast |
| Clear Today tabs | ⇧⌘K | no | 2.2 | toast with Undo |
| Sidebar item 1–8, last | ⌘1…⌘8, ⌘9 | no | 2.3 | essentials, then pinned (expanded order), then Today |
| Space 1–9, 10 | ⌃1…⌃9, ⌃0 | no | 2.5 | |
| Back / forward | ⌘[ ⌘] and ⌘← ⌘→ (outside text fields) | no | 1.4 | |
| Reload / hard reload / stop | ⌘R / ⇧⌘R / ⌘. | no | 1.4 / 2.6 | |
| Find / next / previous | ⌘F / ⌘G / ⇧⌘G | no | 2.6 | |
| Zoom in / out / reset | ⌘= / ⌘- / ⌘0 | no | 2.6 | |
| New split (empty pane) | ⇧⌘= (alias ⌃⇧=) | no | 2.7 | |
| Remove split pane | ⌃⇧- | no | 2.7 | |
| Split layout grid / vertical / horizontal / unsplit | ⌥⌘G / ⌥⌘V / ⌥⌘H / ⌥⌘U | no | 2.7 | |
| Focus split pane N / next / previous | ⌃⇧1…4 / ⌃⇧] / ⌃⇧[ | no | 2.7 | |
| Open link in Peek | ⇧-click | — | 2.7 | pointer gesture |
| Expand Peek to tab / Peek to split | ⌘O / ⇧⌘O | no | 2.7 | Open File is menu-only |
| Close Peek | Esc, ⌘W | — | 2.7 | ⌘W is reserved |
| Mute tab | ⇧⌘M | no | 2.3 | |
| Library / archive | ⇧⌘L | no | 4.1 | |
| Downloads popover | ⇧⌘J | no | 2.6 | |
| History | ⌘Y | no | 2.4 | palette history group until Chapter 3 |
| Fullscreen | ⌃⌘F | no | 2.8 | |
| Reader mode | ⌥⇧⌘R | no | 4.7 | |
| Capture screenshot | ⇧⌘2 | no | 4.7 | |
| Palette actions mode | ⌘T then Tab, or `>` | — | 2.4 | |
| Developer tools / inspect / console | ⌥⌘I / ⌥⌘C / ⌥⌘J | no | 1.4 / 2.6 | |
| Rename entry | Enter on a focused row, double-click | — | 2.2 | ⇧⌘R stays hard reload |
| Duplicate tab, unload tab, reset pinned entry | — | — | 2.2 | menu and palette only |

All non-reserved shortcuts become remappable in Settings ▸ Shortcuts (Chapter 4.4); reserved ones are remappable too, and the reserved set follows the remapped keys.
