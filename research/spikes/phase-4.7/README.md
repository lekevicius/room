# Phase 4.7 fixtures

Served by `scripts/documents-check.sh` on `http://127.0.0.1:8777/phase-4.7/` (the `research/spikes` directory).

- `sample.pdf`: three US-letter pages of Helvetica text, "zebracorn" twice on page 2 and once on page 3 (three matches), title "Room PDF fixture". Written by `make-fixtures.py`.
- `swatch.png`: 240 × 120, orange with a blue band at rows 50–69 (no white pixel). Written by `make-fixtures.py`.
- `page.html` (+ `page.css`): a heading, a paragraph and the swatch: Save Page as HTML, complete HTML (the swatch and the stylesheet in `page_files`) and MHTML, and the MHTML reopened.
- `tall.html`: eight 500 px coloured bands (4,000 px): the full-page capture is taller than the viewport.
- `pdf.html`: a link to the PDF.

Phase 4.7b (`scripts/reader-check.sh`, the `reader` spike):

- `article1.html`: a long article (four headings, ten paragraphs) with `swatch.png` and `field.png` in figures, a site header, a sidebar of links and a footer: reader mode keeps the article and both images, drops the rest.
- `article2.html`: a short article with one `<figure>` (`field.png`) and one link to `article1.html` (a link in the reader page leaves reader mode).
- `notarticle.html`: a dashboard of eight short widgets: the distiller finds no article (the toast).
- `articlecsp.html`: `article1.html` with `<meta>` CSP `script-src 'self'` (written by `make-fixtures.py`).
- `field.png`: 320 × 180, green with a yellow band at rows 80–99. Written by `make-fixtures.py`.
