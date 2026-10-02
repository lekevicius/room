# Private feature-drive command hook — draft, not compiled

Do not apply while the initial build runs. Add only to
`Engine/roomcore/room/core/room_browser.mm`, never public headers. The host
invokes the selector dynamically on its own RoomBrowser, which directly owns
`BrowserWindowInterface`; no browser search or accidentally targeting another
window. `AppController -commandDispatch:` handles app-wide commands, but its
`executeCommand:withProfile:` switch does not dispatch find, zoom or print.
Pretending those menu tags worked would leave these paths untested.

Include `chrome/app/chrome_command_ids.h`. Add a method returning NSNumber
so Objective-C's dynamic `perform` has an object ABI. Gate on the explicit
host spike argument and allowlist commands. Existing `browser_commands.h`
provides `IsCommandEnabled` / `ExecuteCommand`. No production menu wiring.

```objc
- (NSNumber*)roomSpikeCommand:(NSNumber*)command {
  if (!_browser ||
      ![[NSProcessInfo processInfo].arguments containsObject:@"-RoomSpike"]) {
    return @NO;
  }
  const int command_id = command.intValue;
  switch (command_id) {
    case IDC_FIND:
    case IDC_FIND_NEXT:
    case IDC_ZOOM_PLUS:
    case IDC_ZOOM_MINUS:
    case IDC_ZOOM_NORMAL:
    case IDC_PRINT:
      if (!chrome::IsCommandEnabled(_browser, command_id)) {
        return @NO;
      }
      return @(chrome::ExecuteCommand(_browser, command_id));
    default:
      return @NO;
  }
}
```

Check the M154 signatures before applying; run component rebuild and the
nav/open10/quit baseline before interpreting feature results. Missing hook is
currently an explicit host-spike error, not an assumed successful command.
