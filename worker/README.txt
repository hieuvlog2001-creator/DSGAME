DSGames Cloudflare Worker

Worker URL:
https://dsgame.hieuvlog2001.workers.dev

Required KV binding:
- Binding name: DEVICES
- Namespace: DSGAMES_DEVICES
- Namespace ID: 893701c625c24f568487018e5dddf4e1

Required Worker secrets:
1) ADMIN_SECRET
   - This is the password used by DSGames Admin.
   - Do not put it in GitHub.
2) GITHUB_TOKEN
   - Fine-grained GitHub token with access to the DSGAME repository contents/releases.
   - This token is stored ONLY as a Cloudflare Worker secret.
   - Do not put it in the Admin web page or repository.

Required variable:
GITHUB_RAW_KEYS is configured in wrangler.toml.

Admin API:
- POST /admin/sync
- GET/PUT /admin/github/content
- POST /admin/github/release
- POST /admin/github/release-asset
All require header: x-admin-secret

Deploy from the worker directory:
cd worker && npx wrangler deploy
