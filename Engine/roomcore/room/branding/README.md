# Room branding

`BRANDING` is Chromium's branding file for the fork (`branding_file_path` in
`Engine/roomcore/args/dev.gn`). It sets the product name (Room → `Room.app`,
`Room Helper*.app`), the bundle id (`app.room.desktop`, helpers
`.helper`, `.helper.gpu`, `.helper.renderer`, `.helper.plugin`, `.helper.alerts`;
PLAN §4 Identity) and the copyright line.

`branding_path_component = "room"` makes Chromium look for icons and logos in
`chrome/app/theme/room`, `chrome/app/theme/default_{100,200}_percent/room` and
`components/vector_icons/room`. Until Room has its own icon set,
`scripts/roomcore-apply.sh` creates those as symlinks to the `chromium`
directories (icon placeholder).
