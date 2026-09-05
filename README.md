# DSGames v1.4 — Device Sync Fixed

Fixes:
- GitHub Pages now publishes `dsgames-config.json`.
- App fetches Device API config from Pages, Raw GitHub, then jsDelivr.
- Added `/heartbeat` to Cloudflare Worker so existing activated keys continuously update device information without storing plaintext keys in the app.
- Device data: device name, Device ID (IDFV), iOS version, DSGames version, activation time and last online.
- IMEI remains unavailable to normal iOS apps.


## Admin login
Admin now uses a separate login page. ADMIN_SECRET and GITHUB_TOKEN stay as Cloudflare Worker secrets; they are never exposed to the browser.


## Admin login
- Password is stored in `Admin/admin-config.js` as `ADMIN_PASSWORD`. This file is public on GitHub Pages, so this is not suitable for high-security secrets.
- `GITHUB_TOKEN` must remain a Cloudflare Worker Secret and must never be placed in JavaScript.
- The Cloudflare Worker `ADMIN_SECRET` must match `ADMIN_PASSWORD` so the login can obtain a short-lived admin session.
