// DSGames Device + Admin API - Cloudflare Worker
// Public endpoints:
// POST /register {key, deviceId, deviceName, iosVersion, appVersion}
// POST /heartbeat {keyHash, deviceId, deviceName, iosVersion, appVersion}
// GET  /status?key=...
// Admin endpoints require x-admin-secret and use the GitHub token stored ONLY as a Worker secret:
// POST /admin/sync
// GET/PUT /admin/github/content?path=...&ref=...
// POST /admin/github/release
// POST /admin/github/release-asset?owner=...&repo=...&releaseId=...&name=...

const GH_API = 'https://api.github.com';

async function sha256(text) {
  const data = new TextEncoder().encode(text.trim().toUpperCase());
  const hash = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(hash)].map(b => b.toString(16).padStart(2, '0')).join('');
}

async function getKeys(env) {
  const r = await fetch(env.GITHUB_RAW_KEYS, { headers: { 'Cache-Control': 'no-cache' } });
  if (!r.ok) throw new Error('keys.json unavailable');
  return await r.json();
}

function json(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'content-type': 'application/json;charset=UTF-8',
      'access-control-allow-origin': '*',
      'access-control-allow-methods': 'GET,POST,PUT,OPTIONS',
      'access-control-allow-headers': 'content-type,x-admin-secret,authorization',
      ...extraHeaders
    }
  });
}

async function makeAdminToken(env, ttlSeconds = 3600) {
  const exp = Math.floor(Date.now() / 1000) + ttlSeconds;
  const payload = `dsgames:${exp}`;
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(env.ADMIN_SECRET), {name:'HMAC', hash:'SHA-256'}, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(payload)));
  const b64 = btoa(String.fromCharCode(...sig)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
  return `${exp}.${b64}`;
}

async function validAdminToken(token, env) {
  if (!token || !env.ADMIN_SECRET) return false;
  const parts = token.split('.');
  if (parts.length !== 2) return false;
  const exp = Number(parts[0]);
  if (!Number.isFinite(exp) || exp < Math.floor(Date.now()/1000)) return false;
  const payload = `dsgames:${exp}`;
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(env.ADMIN_SECRET), {name:'HMAC', hash:'SHA-256'}, false, ['verify']);
  let raw;
  try { const b64 = parts[1].replace(/-/g,'+').replace(/_/g,'/'); raw = Uint8Array.from(atob(b64 + '='.repeat((4 - b64.length % 4) % 4)), c => c.charCodeAt(0)); } catch { return false; }
  return await crypto.subtle.verify('HMAC', key, raw, new TextEncoder().encode(payload));
}

async function requireAdmin(req, env) {
  const supplied = req.headers.get('x-admin-secret') || '';
  if (env.ADMIN_SECRET && supplied === env.ADMIN_SECRET) return true;
  const auth = req.headers.get('Authorization') || '';
  if (!auth.startsWith('Bearer ')) return false;
  return await validAdminToken(auth.slice(7).trim(), env);
}

function githubHeaders(env, contentType = 'application/vnd.github+json') {
  if (!env.GITHUB_TOKEN) throw new Error('GITHUB_TOKEN is not configured on Worker');
  return {
    'Authorization': `Bearer ${env.GITHUB_TOKEN}`,
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'Content-Type': contentType
  };
}

function safeRepoPart(value) {
  const v = String(value || '').trim();
  return /^[A-Za-z0-9_.-]+$/.test(v) ? v : null;
}

function safePath(value) {
  const p = String(value || '').trim().replace(/^\/+/, '');
  if (!p || p.includes('..') || p.includes('\\')) return null;
  return p;
}

async function githubJSON(url, env, options = {}) {
  const r = await fetch(url, { ...options, headers: { ...githubHeaders(env), ...(options.headers || {}) } });
  const text = await r.text();
  let body;
  try { body = text ? JSON.parse(text) : {}; } catch { body = { message: text }; }
  return { r, body };
}

export default {
  async fetch(req, env) {
    if (req.method === 'OPTIONS') return json({ ok: true });
    const url = new URL(req.url);

    try {
      // Device registration: the app sends the plaintext key only to this Worker.
      if (url.pathname === '/register' && req.method === 'POST') {
        const body = await req.json();
        if (!body.key || !body.deviceId) return json({ ok: false, error: 'missing key/deviceId' }, 400);
        const hash = await sha256(body.key);
        const manifest = await getKeys(env);
        const license = (manifest.licenses || []).find(x => String(x.keyHash || '').toLowerCase() === hash.toLowerCase());
        if (!license || !license.enabled) return json({ ok: false, error: 'invalid_or_disabled_key' }, 403);
        if (license.expiresAt && new Date(license.expiresAt) <= new Date()) return json({ ok: false, error: 'expired_key' }, 403);
        const now = new Date().toISOString();
        const record = {
          deviceName: body.deviceName || '',
          deviceId: body.deviceId,
          imei: 'Không khả dụng trên iOS',
          iosVersion: body.iosVersion || '',
          appVersion: body.appVersion || '',
          activatedAt: now,
          lastSeenAt: now
        };
        await env.DEVICES.put('license:' + hash, JSON.stringify(record));
        return json({ ok: true, license: { id: license.id, expiresAt: license.expiresAt || null }, device: record });
      }

      if (url.pathname === '/heartbeat' && req.method === 'POST') {
        const body = await req.json();
        const keyHash = String(body.keyHash || '').trim().toLowerCase();
        if (!keyHash || !body.deviceId) return json({ ok: false, error: 'missing keyHash/deviceId' }, 400);
        const manifest = await getKeys(env);
        const license = (manifest.licenses || []).find(x => String(x.keyHash || '').trim().toLowerCase() === keyHash);
        if (!license || !license.enabled) return json({ ok: false, error: 'invalid_or_disabled_key' }, 403);
        if (license.expiresAt && new Date(license.expiresAt) <= new Date()) return json({ ok: false, error: 'expired_key' }, 403);
        const now = new Date().toISOString();
        const old = await env.DEVICES.get('license:' + keyHash, 'json') || {};
        const record = {
          deviceName: body.deviceName || old.deviceName || '',
          deviceId: body.deviceId,
          imei: 'Không khả dụng trên iOS',
          iosVersion: body.iosVersion || old.iosVersion || '',
          appVersion: body.appVersion || old.appVersion || '',
          activatedAt: old.activatedAt || now,
          lastSeenAt: now
        };
        await env.DEVICES.put('license:' + keyHash, JSON.stringify(record));
        return json({ ok: true, device: record });
      }

      if (url.pathname === '/status' && req.method === 'GET') {
        const key = url.searchParams.get('key');
        if (!key) return json({ ok: false, error: 'missing key' }, 400);
        const hash = await sha256(key);
        const manifest = await getKeys(env);
        const license = (manifest.licenses || []).find(x => String(x.keyHash || '').toLowerCase() === hash.toLowerCase());
        if (!license || !license.enabled) return json({ ok: false, error: 'invalid_or_disabled_key' }, 403);
        if (license.expiresAt && new Date(license.expiresAt) <= new Date()) return json({ ok: false, error: 'expired_key' }, 403);
        const old = await env.DEVICES.get('license:' + hash, 'json');
        if (old) {
          old.lastSeenAt = new Date().toISOString();
          await env.DEVICES.put('license:' + hash, JSON.stringify(old));
        }
        return json({ ok: true, license: { id: license.id, expiresAt: license.expiresAt || null }, device: old || null });
      }

      // Admin login: password is checked here; GitHub credentials never reach the browser.
      if (url.pathname === '/admin/login' && req.method === 'POST') {
        const body = await req.json().catch(() => ({}));
        if (!env.ADMIN_SECRET || !body.password || body.password !== env.ADMIN_SECRET) {
          return json({ ok: false, error: 'invalid_password' }, 401);
        }
        return json({ ok: true, token: await makeAdminToken(env, 8 * 3600), expiresIn: 8 * 3600 });
      }

      // All admin endpoints below are protected by the admin password/session token.
      if (url.pathname.startsWith('/admin/')) {
        if (!(await requireAdmin(req, env))) return json({ ok: false, error: 'unauthorized' }, 401);
      }

      if (url.pathname === '/admin/sync' && req.method === 'POST') {
        const manifest = await getKeys(env);
        const result = [];
        for (const k of (manifest.licenses || [])) {
          const d = await env.DEVICES.get('license:' + k.keyHash, 'json');
          result.push({ ...k, ...(d || {}) });
        }
        return json({ ok: true, licenses: result });
      }

      // Browser Admin reads/writes repository files through the Worker.
      if (url.pathname === '/admin/github/content') {
        const path = safePath(url.searchParams.get('path'));
        const ref = String(url.searchParams.get('ref') || 'main').trim();
        if (!path) return json({ ok: false, error: 'invalid path' }, 400);
        const owner = safeRepoPart(url.searchParams.get('owner') || 'hieuvlog2001-creator');
        const repo = safeRepoPart(url.searchParams.get('repo') || 'DSGAME');
        if (!owner || !repo) return json({ ok: false, error: 'invalid owner/repo' }, 400);
        const ghURL = `${GH_API}/repos/${owner}/${repo}/contents/${path}?ref=${encodeURIComponent(ref)}`;

        if (req.method === 'GET') {
          const { r, body } = await githubJSON(ghURL, env, { method: 'GET' });
          return json(body, r.status);
        }
        if (req.method === 'PUT') {
          const payload = await req.json();
          if (!payload || !payload.message || !payload.content) return json({ ok: false, error: 'invalid GitHub content payload' }, 400);
          const { r, body } = await githubJSON(`${GH_API}/repos/${owner}/${repo}/contents/${path}`, env, {
            method: 'PUT',
            body: JSON.stringify(payload)
          });
          return json(body, r.status);
        }
        return json({ ok: false, error: 'method_not_allowed' }, 405);
      }

      if (url.pathname === '/admin/github/release' && req.method === 'POST') {
        const body = await req.json();
        const owner = safeRepoPart(body.owner || 'hieuvlog2001-creator');
        const repo = safeRepoPart(body.repo || 'DSGAME');
        if (!owner || !repo || !body.tag_name) return json({ ok: false, error: 'invalid release payload' }, 400);
        const payload = {
          tag_name: body.tag_name,
          name: body.name || body.tag_name,
          body: body.body || '',
          draft: !!body.draft,
          prerelease: !!body.prerelease
        };
        const { r, body: out } = await githubJSON(`${GH_API}/repos/${owner}/${repo}/releases`, env, {
          method: 'POST',
          body: JSON.stringify(payload)
        });
        return json(out, r.status);
      }

      if (url.pathname === '/admin/github/release-asset' && req.method === 'POST') {
        const owner = safeRepoPart(url.searchParams.get('owner'));
        const repo = safeRepoPart(url.searchParams.get('repo'));
        const releaseId = String(url.searchParams.get('releaseId') || '').trim();
        const name = String(url.searchParams.get('name') || '').trim();
        if (!owner || !repo || !/^\d+$/.test(releaseId) || !name || name.includes('/') || name.includes('\\')) {
          return json({ ok: false, error: 'invalid release asset parameters' }, 400);
        }
        const uploadURL = `https://uploads.github.com/repos/${owner}/${repo}/releases/${releaseId}/assets?name=${encodeURIComponent(name)}`;
        if (req.headers.get('content-type') !== 'application/octet-stream') return json({ ok: false, error: 'content-type must be application/octet-stream' }, 400);
        const r = await fetch(uploadURL, {
          method: 'POST',
          headers: githubHeaders(env, 'application/octet-stream'),
          body: req.body
        });
        const text = await r.text();
        let body;
        try { body = text ? JSON.parse(text) : {}; } catch { body = { message: text }; }
        return json(body, r.status);
      }

      return json({ ok: false, error: 'not_found' }, 404);
    } catch (e) {
      return json({ ok: false, error: e.message || String(e) }, 500);
    }
  }
};
