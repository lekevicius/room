# Room, the website

A static page with no build step and no dependencies. The type is self-hosted, it makes no third-party requests, and it has no analytics.

```bash
python3 -m http.server 4747 --directory Website     # or the "website" entry in .claude/launch.json
```

## Layout

| Path | What |
|---|---|
| `index.html` | The page: the hero, pillars, the feature tour, details, privacy, prints (icon picker), shortcuts, source, closing. |
| `assets/css/site.css` | Paper and ink tokens (light and dark), the hero's punched-hole layers, sections. |
| `assets/js/site.js` | The hero choreography, reveals, the tour, clips with a drawn cursor, the icon picker, the brand menu (right-click the header mark). |
| `assets/art/` | The risograph prints as AVIF (1536 and 800 px). |
| `assets/icons/` | Room's eight icons rendered by Icon Composer (light, dark, and the bare glyph art), the favicon. |
| `assets/shots/` | App stills, `<scene>-<light|dark>.webp`, from `capture/capture.sh`. |
| `assets/clips/` | App clips, MP4 with a poster and a pointer track, from `capture/record.sh`. `clips.json` lists them. A tour step with a clip plays it in place of its still. |
| `assets/mark.svg` | Room's glyph as a vector, traced from the icon's art and checked against it to within 0.7% of pixels. |
| `scripts/build-art.sh` | Regenerates `assets/art` and `assets/icons` from the originals in `research/art/`, which are gitignored. |
| `capture/` | The capture system for stills and clips. See `capture/README.md`. |

## The hero

The page is a sheet of paper (`.hero-paper`) with a hole cut in the shape of Room's mark. A print (`.hero-print`) lies beneath it. As you scroll, the hole widens in log space around a fixed point of the glyph, so it reads as a camera move, until the print fills the screen. The window then rises onto the print, and the print draws in from the edges to become a panel on the paper. With reduced motion, or without JavaScript, the hero is a static composition.

Choosing a print in the icon picker re-prints the page: the hero's print, the header mark, the favicon and the brand menu's download all follow it. The choice is remembered in `localStorage`.

## Copy rules

- No em or en dashes in visible text.
- Every number comes from the repo: the idle network audit (`research/notes/roomcore-network-audit.md`: 0 requests in 600 s, against 62 for stock Chromium).
- Every shortcut comes from `docs/shortcuts.md`.
