# Room's built-in blocker: bundled assets (B-30)

Refreshed by `scripts/content-blocking-assets.sh` before a release; copied into
the app as `Resources/ContentBlocking`. The app reads them with no network.

| File | What | Licence |
|---|---|---|
| `easylist.txt` | EasyList (ads), easylist.to | CC BY-SA 3.0 (dual-licensed with GPLv3; used under CC BY-SA), © The EasyList authors |
| `easyprivacy.txt` | EasyPrivacy (trackers), easylist.to | CC BY-SA 3.0, © The EasyList authors |
| `easylist-cookie.txt` | EasyList Cookie List (cookie banners) | CC BY 3.0, © The EasyList authors |
| `redirect-resources.json` | empty script, frame, text and image bodies for `$redirect` rules, Room's own | MPL-2.0 (Room) |
| `autoconsent-room.js` | DuckDuckGo's autoconsent `autoconsent-version.txt`, bundled with Room's entry (`scripts/content-blocking/autoconsent-room.ts`) | MPL-2.0 (`LICENSE-autoconsent`) |

Lists under GPL (uBlock Origin's) are never bundled: Settings offers them as downloads the user turns on.
