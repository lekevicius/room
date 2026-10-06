# Reader mode resources (Phase 4.7b)

- `domdistiller.js`: Chrome's DOM Distiller, copied unmodified from the Chromium
  checkout's `third_party/dom_distiller_js/dist/js/domdistiller.js` at
  **155.0.8059.36** (dom-distiller revision `36c717851221b0f3a0a337a5930162b5933e872c`,
  per `third_party/dom_distiller_js/README.chromium`). BSD-3-Clause and Apache-2.0:
  `LICENSE-dom-distiller` is that directory's `LICENSE`, copied with it. Refresh it on a
  rebase only if the file changed upstream.
- `reader.html`: Room's own reader page template (`ReaderRules.page` in `Packages/Chrome`
  fills its slots; the CSS variables come from the design tokens through `ReaderStyle`).

The distiller runs in the page's isolated world through `WebContents.executeJavaScript`
(`ReaderRules.distillerScript` wraps it as Chrome's `domdistiller_wrapped.js` does); nothing
here makes a network request.
