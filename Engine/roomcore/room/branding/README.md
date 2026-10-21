# Room branding

`BRANDING` is Chromium's branding file for the fork (`branding_file_path` in
`Engine/roomcore/args/dev.gn` and `release.gn`). It sets the product name (Room → `Room.app`,
`Room Helper*.app`), the bundle id (`app.room.desktop`; the helpers take Chromium's suffixes,
PLAN §4 Identity) and the copyright line.

What Chrome's own surfaces show (B-103, 5.2b), without a patch:

- **Strings** (`room_branded_strings.cc`, the `//room/branding` target, linked through
  `//room/core`): at startup (the first call of patch 0013's AppController hook,
  `ChromeBrowserMainPartsMac::PreCreateThreads`) every locale string of Chrome's string headers
  whose text names Chromium is overridden with `ui::ResourceBundle::OverrideLocaleStringResource`:
  "Chromium" becomes the product name, except in the open-source attribution ("the Chromium open
  source project", linked or not) and Chromium OS's name; the about pages' company and copyright
  are BRANDING's. The ids come from the generated grit headers (`tools/gen_string_ids.py`, the
  `string_ids` action), so no grd, xtb or resource id changes. 608 of 13,418 strings on
  155.0.8059.36, in about 3 ms. Strings a renderer process formats itself are not covered (none
  name Chromium in English on 155).
- **Theme images**: `branding_path_component = "room"` makes Chromium read
  `chrome/app/theme/room`, `chrome/app/theme/default_{100,200}_percent/room` and
  `components/vector_icons/room`. `tools/install_theme.sh` (run by `scripts/roomcore-apply.sh`)
  makes the three theme directories copies of Chromium's `chromium` ones with Room's files over
  them: `theme/` (the product logos WebUI pages show in their corner, 16–256 px, and the
  wordmark; `tools/render_theme.swift` renders them from the Room icon's glyph) and `theme/gen/mac`
  (`app.icns` and `Assets.car`, compiled by actool from `App/Resources/AppIcon.icon`: the alerts
  helpers' icon, which macOS shows on web notifications). `components/vector_icons/room` is still a
  link to Chromium's (no Room vector icon). Copies, not symlinks: `bundle_data` copies a link as a
  link, which left the helpers' icons pointing out of the bundle.

Not reachable without a patch (backlog): `chrome://version`'s wordmark (`IDR_PRODUCT_LOGO`, a
fixed `chromium/product_logo.png` path in `components/resources`, not the branding component).
