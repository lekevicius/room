# Built-in ad and tracker blocking: by-hand steps (B-30)

2026-10-17. These are for the user, on a Room built from branch `claude/adblock-ad74ae`: the Debug app over `out/dev`, or a later DMG. Each step says what to see. Anything that disagrees is a row for B-30.

Before you start: if uBlock Origin Lite is installed, turn it off (⌘, ▸ Extensions), so what you see is Room's own blocker.

1. **Out of the box.** Open a news site you know is full of ads, such as a local newspaper.
   - Ads and their empty boxes are gone.
   - Click the site button at the left of the sidebar's header. The panel has **Block ads and trackers** switched on, with "N requests blocked on this page" under it, and N grows as the page loads more.

2. **Turn it off for one site.** In that panel, switch the toggle off, then click Reload.
   - The ads come back.
   - The line under the toggle reads "Off for <site>".
   - ⌘, ▸ Privacy ▸ Allowed sites lists the site. Click **Block Again** there and reload the page: the ads are gone again.

3. **Cookie banners.** Open a site with a consent banner, for example a European newspaper or a WordPress blog.
   - With **Cookie banners: Reject** (the default), the banner disappears on its own.
   - The site's cookie settings, if you reopen them, show only the necessary purposes on.
   - Set **Hide** and open another such site in a new tab: the banner never shows and nothing is answered.
   - Set **Leave alone**: banners show.

4. **Trackers only.** In ⌘, ▸ Privacy, turn **Block ads** off and keep **Block trackers** on, then reload the news site.
   - Ads show.
   - The site panel still counts blocked requests (analytics and pixels).

5. **A custom rule.** In Privacy ▸ Custom rules, type `##img` and click Apply. Reload any page: every image is hidden. Delete the rule, Apply, reload: the images are back.

6. **An optional list.** In Privacy ▸ Lists, turn on **uBlock filters**.
   - A spinner shows briefly. This is the one moment Room contacts `ublockorigin.github.io`, because you asked.
   - The row then shows its rule count and "updated just now".
   - Turn it off: nothing is fetched.

7. **A list by URL.** Paste `https://secure.fanboy.co.nz/fanboy-annoyance.txt` into the list URL field and click **Add List**.
   - The row takes the list's title ("Fanboy's Annoyance List") and a rule count.
   - **Remove** deletes it.

8. **No network unless asked.** With **Update lists automatically** off (the default), quit and relaunch Room with Little Snitch or LuLu watching. No request goes to `easylist.to`, `fanboy.co.nz` or `github.io` at launch or while idle.
   - Turn the switch on: the lists in use are fetched within a minute.
   - Turn it off again.

9. **YouTube.** Play a video. The bundled lists (EasyList, EasyPrivacy) are not enough for YouTube's own ads; uBlock filters (step 6) and its scriptlets are needed. Note what you see; it decides the follow-up (§ Limits below).

10. **Speed and memory.** Use Room for a day with blocking on. Report any page that breaks (a broken layout, a missing video, a login that loops), with its URL.
    - The site panel's switch is the quick way to tell whether the blocker caused it: turn it off and reload.

## Limits of this version (follow-ups)

- **Redirect hops** are not re-matched: an allowed request that redirects to an ad host loads.
- **`$removeparam` and `$csp`** rules are parsed but not applied.
- **Procedural cosmetic filters** (`:has-text`, `:upward`…) are not run.
- **uBlock's scriptlets are not loaded:** its lists' `+js()` rules do nothing.
- **Allowed sites and cookie-banner changes** reach open pages when they reload.
