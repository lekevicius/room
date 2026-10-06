# Phase 4.7 fixtures

Served by `scripts/documents-check.sh` on `http://127.0.0.1:8777/phase-4.7/` (the `research/spikes` directory).

- `sample.pdf`: three US-letter pages of Helvetica text, "zebracorn" twice on page 2 and once on page 3 (three matches), title "Room PDF fixture". Written by `make-fixtures.py`.
- `swatch.png`: 240 × 120, orange with a blue band at rows 50–69 (no white pixel). Written by `make-fixtures.py`.
- `page.html` (+ `page.css`): a heading, a paragraph and the swatch: Save Page as HTML, complete HTML (the swatch and the stylesheet in `page_files`) and MHTML, and the MHTML reopened.
- `tall.html`: eight 500 px coloured bands (4,000 px): the full-page capture is taller than the viewport.
- `pdf.html`: a link to the PDF.
