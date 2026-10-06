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
palette, Settings, and moving between tabs and spaces — the same kind of set
Chrome reserves. ⌘S (toggle sidebar) is page-first because web editors (Figma,
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
| Settings | ⌘, | **yes** | 2.8 | reserved again after the Phase 1.6 review: Settings must be reachable from any page, as in every macOS app |
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
| Split layout grid / vertical / horizontal / unsplit | ⌥⌘G / ⌥⌘V / — / ⌥⌘U | no | 2.7 | ⌥⌘H stays Hide Others, the macOS standard (decided 2026-10-04, B-36); the horizontal layout is in the menu, the palette and the pane header |
| Focus split pane N / next / previous | ⌃⇧1…4 / ⌃⇧] / ⌃⇧[ | no | 2.7 | |
| Open link in Peek | ⇧-click | — | 2.7 | pointer gesture |
| Expand Peek to tab / Peek to split | ⌘O / ⇧⌘O | no | 2.7 | Open File is menu-only |
| Close Peek | Esc, ⌘W | — | 2.7 | ⌘W is reserved |
| Mute tab | ⇧⌘M | no | 2.3 | |
| Library / archive | ⇧⌘L | no | 4.1 | the Library in place of the spaces view (Archive, Downloads, History); ⇧⌘L or Esc returns |
| Downloads popover | ⇧⌘J | no | 2.6 | |
| History | ⌘Y | no | 4.1 | the Library at History (4.1); the palette's history group stays (2.4) |
| Fullscreen | ⌃⌘F | no | 2.8 | |
| Reader mode | ⌥⇧⌘R | no | 4.7 | View ▸ Reader Mode (4.7b): the article (Chrome's DOM Distiller) in Room's reader page in the card, the entry's page kept behind it; again, Esc or Exit Reader returns; Settings ▸ Appearance ▸ Reader text size; a page without an article gets a toast. The context menu's Open in Reader Mode does the same |
| Save page | ⇧⌘S | no | 4.7 | File ▸ Save Page…: a save panel with Web Page, Complete / HTML Only / Web Archive (MHTML); added 2026-10-07 (4.7a), the key the ⌘S row reserved |
| Capture screenshot | ⇧⌘2 | no | 4.7 | a crop overlay over the page: drag a rectangle, Return for the whole viewport, Esc cancels; then Copy, Save, Open as Tab, Full Page |
| Palette actions mode | ⌘T then Tab, or `>` | — | 2.4 | |
| Developer tools / inspect / console | ⌥⌘I / ⌥⌘C / ⌥⌘J | no | 1.4 / 2.6 | |
| Rename entry | Enter on a focused row, double-click | — | 2.2 | ⇧⌘R stays hard reload |
| Duplicate tab, unload tab, reset pinned entry | — | — | 2.2 | menu and palette only |

**Since 4.4a this table is the default set, and Settings ▸ Shortcuts remaps it.** `UIKitCore.ShortcutTable` takes every action of `MainMenuTable` with its default key from here (`MenuTableTests` checks the table's defaults against this page) and the user's overrides from `Settings.shortcutOverrides` (`kv`: action id → key, `""` for no key). The menu bar, the palette's command hints, the sidebar's context menus and the key router's reserved set all read that one table. Reserved belongs to the action, not the key: an action marked **yes** above stays reserved under any key it is given, and its old key then reaches the page like any other. A key two actions would share is marked on both rows and moves only when the user confirms. Keys macOS or the page's editing needs are refused for every action: ⌘Q, ⌘H, ⌥⌘H, ⌘M, ⌘, (so Quit, Hide, Hide Others, Minimize and Settings keep theirs), ⌘\`, ⇧⌘\`, ⌘Space, ⌃⌘Space, ⇧⌘3/4/5, ⌃⌘Q, ⇧⌘/, ⌘C, ⌘V, ⌘X, ⌘Z, ⇧⌘Z, ⌘A, and any key without ⌘ or ⌃. The ⌃Tab rows are fixed too: holding ⌃ with Tab is the switcher's gesture. Reset per row and Reset All bring back this table.
