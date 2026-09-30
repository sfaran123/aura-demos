# AURA ERP – demo pages

Static demo pages (sample data only). Netlify publishes the `public` folder on every push to `main`.

- `public/index.html` – list of demos (Hebrew / Arabic / English)
- `public/cash-register/` – cash register list and consolidated Z report (PDF / CSV), in Hebrew, Arabic and English
  - Language: buttons in the header, or add `#he`, `#ar`, `#en` to the link
  - `fonts/` – font used inside the PDF (Hebrew, Arabic, Latin)

To add a demo: create `public/<name>/index.html` and add a link in `public/index.html`.
