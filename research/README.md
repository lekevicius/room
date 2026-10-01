# Research index (2026-10-01)

Conclusions are consolidated in [`../PLAN.md`](../PLAN.md). These are the underlying reports.

| File | What it answers | Key finding |
|---|---|---|
| `notes/arccore-adk-bundle-analysis.md` | How Arc/Dia actually embed Chromium (from the installed bundles) | Swift app + `ArcCore.framework` (Chromium 154) exporting 204 ObjC headers; every Chrome UI surface is a delegate; AppKit + SwiftUI hybrid; GRDB/Sparkle/Sentry; helpers need only `allow-jit` |
| `notes/arc-dia-architecture.md` | What The Browser Company has said publicly | "ADK" = Chromium as an SDK + Swift chrome; Dia moved to AppKit-only for performance; nothing open-sourced; Arc in maintenance since May 2025 |
| `notes/cef.md` | Is CEF enough? | On macOS a CEF browser inside your own NSView is always Alloy-style: no extension popups/Web Store, no password-save bubbles, no Translate, no tab discarding, no omnibox autocomplete |
| `notes/chromium-fork.md` | What a fork with a native window costs | 1.5–2 h builds on this Mac; Brave-style overlay dir is the right patch strategy; `BrowserWindow` has ~98 virtuals, a third cleanly replaceable; Chrome ships every 2 weeks now; Sync unavailable, Web Store works, Widevine gated |
| `notes/macos-ui-stack.md` | How to build the chrome | AppKit shell + SwiftUI leaves; `NSVisualEffectView` window + layer-clipped card (spike the clipping); GRDB; no App Sandbox; exact entitlements; palette and persistence designs |
| `notes/feature-spec.md` | What exactly to build | v1 spec A–J with Zen source and Arc doc citations; full macOS shortcut table |
| `notes/visual-reference.md` | What it should look like | Dia card + material, Arc tint and footer, Zen essentials; see `screenshots/` |

`repos/` is gitignored: `cef/` (CEF source + docs), `cef-wiki/` (stub), `zen-desktop/` (Zen source), `arccore-headers/` (ArcCore public headers copied from Dia 1.51; proprietary, study only, never copy code).
