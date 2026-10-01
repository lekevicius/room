# Visual reference: Dia, Arc, Zen windows (as installed, Oct 2026)

Screenshots in `research/screenshots/` (`dia-window.jpg`, `arc-window.jpg`, `zen-window.jpg`), captured from the running apps on macOS 27.0.1.

## Dia (the visual target)

- **Window material**: full-height, single-material window. The sidebar area is a light neutral vibrancy material (looks like `NSVisualEffectView` with `.sidebar`/`.underWindowBackground` style, blending behind-window). No visible titlebar; traffic lights are inset inside the sidebar at the top-left with the space name ("Personal") in bold next to them.
- **Page card**: the web content is a separate white rounded rectangle, inset from the window edge on the top, right and bottom (~8pt gap), with a very subtle shadow/border. The card itself contains a slim toolbar row (sidebar toggle, back, forward, reload, URL text) *above* the page, inside the card: in Dia the address bar lives in the content card, not in the sidebar. (Arc/Zen put it in the sidebar; that's what we want.)
- **Sidebar list**: selected tab is a rounded, slightly-elevated white pill (full-width, ~36pt tall, 12-14pt corner radius) with favicon + title; unselected rows are text-only with no background. "New Tab" row with a `+` in secondary gray. Typography is SF Pro at ~13pt, titles in regular weight, selected tab same weight; the space title is semibold.
- **Bottom of sidebar**: small page-indicator dots (space dots) centered, and a chevron on the right. Very quiet.
- **Icons**: SF Symbols-style, monochrome, thin.
- Overall: lots of whitespace, no dividers, no hairlines, one accent (selection pill). The "beauty" comes from the card inset + material + restraint.

## Arc

- Window tinted with the space's color (pastel lavender gradient here) across the sidebar; content card is a white/near-white rounded rectangle inset on top/right/bottom with a soft shadow.
- Top of sidebar: traffic lights, then on the right a back/forward/"..." row. Below: a full-width rounded search field ("Search...") with a magnifier icon — this is the address bar in the sidebar (click or Cmd+L/Cmd+T opens the command bar overlay).
- Space section: colored dot/emoji + bold space name ("General"); "New Tab" row under it with `+`.
- Bottom bar: an archive/library icon at far left, then a row of space icons (emoji per space, selected one filled), and a `+` at the right end for new tab (actually new-space in Arc's bar is via the `+` at far right? here `+` is new tab/space). Everything is monochrome at ~50% opacity, selected space icon in full color.
- Icons are soft, slightly playful (emoji as space icons).

## Zen

- Firefox-based but visually Arc-like: sidebar on a light gray translucent background, "essentials" favicons grid at the very top (one large rounded tile with the Facebook icon), then a "Reading" workspace label with its icon, then "New Tab".
- Toolbar (back, forward, reload, URL bar) is *above the content card*, outside the sidebar, in a top row (Zen's default; Zen also offers a compact mode where the URL bar floats).
- Content card: white rounded rectangle inset on all sides from the window background with a visible shadow.
- Bottom-left of the sidebar: downloads icon; bottom-right: `+` (new tab). No space dots visible in this single-workspace state.

## What we take from each

| Element | Choice | From |
|---|---|---|
| Window material | Translucent vibrancy on the whole window, optionally tinted by space color at low opacity | Dia (neutral) + Arc (tint) |
| Content card | Inset on top/right/bottom (left edge butts against the sidebar area with a gap), rounded 10-12pt, hairline border at 6-8% + soft shadow | Dia |
| Address bar | In the sidebar as a rounded field below the traffic lights/nav row; opens the palette on focus | Arc |
| Pinned icons | Grid of large rounded favicon tiles at top of the space | Arc Favorites / Zen Essentials |
| Pinned list / folders / today tabs | List rows, selected = elevated pill | Dia/Arc |
| Bottom bar | downloads (left), space dots (center), new tab `+` (right) | Zen/Arc |
| Toast | Small pill rising from bottom of sidebar ("Copied URL") | Arc |
