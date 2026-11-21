# AgentGauge 官网 · Website

A zero-build static site (HTML + CSS + vanilla JS). It's bilingual (中文 / English) and includes a live WebGL port of the app's Metal liquid shader.

## Run locally

```bash
cd Website
python3 -m http.server 8765
# open http://127.0.0.1:8765
```

Language: auto-detected from the browser. To force one, use `?lang=zh` / `?lang=en`. The toggle in the nav remembers the choice.

## Before publishing

- **Download link**: set `window.AG_CONFIG.downloadUrl` in `index.html` (near the bottom). While it's empty, the download buttons show a "coming soon" toast.
- **Hosting**: any static host works (Cloudflare Pages, Netlify, Vercel, GitHub Pages). Upload the whole `Website/` folder.

## Structure

| Path | Purpose |
|---|---|
| `index.html` | Page structure (all copy comes from `js/i18n.js`) |
| `css/site.css` | Single-canvas design system (`#ffffff` + `#f6f5f1` cards, `Cabinet Grotesk` + system CJK sans) |
| `js/i18n.js` | All zh / en copy |
| `js/liquid.js` | WebGL port of `NativeIconRenderer` (waves, refraction, bubbles, split-text / R-corner badge, inertial tilt) |
| `js/app.js` | Live macOS stage (menu bar, popover, Dock, hover cards), Liquid Lab, sections |
| `assets/` | Real captures from the app and promo pipeline (demo data only; no real accounts) |

## Notes

- Render loops run only while their section is on screen and stop when idle, mirroring the app's zero-idle behaviour. `prefers-reduced-motion` is respected.
- `?qa=<section-id>` is a QA helper. It hides earlier sections so headless screenshots can start mid-page.
