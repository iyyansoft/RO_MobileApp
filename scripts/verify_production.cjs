// Read-only production check after a push to main (GitHub -> Render + Vercel).
//
//   node scripts/verify_production.cjs                    # expects the commit of origin/main
//   node scripts/verify_production.cjs --expect=<sha>     # a specific commit
//   node scripts/verify_production.cjs --wait=15          # keep checking up to 15 minutes until deployed
//   node scripts/verify_production.cjs --json             # machine-readable result
//
// Only public GET requests: no login, no database access, no credentials, no
// writes. Exit code 0 = every check passed, 1 = something failed.
'use strict';
const { execSync } = require('node:child_process');

const DEFAULTS = {
  api: 'https://ro-mobileapp.onrender.com',
  site: 'https://ro-mobileapp.vercel.app',
  githubApi: 'https://api.github.com',
  repo: 'iyyansoft/RO_MobileApp',
  vercelEnvironment: 'Production – ro-mobileapp',
  timeoutMs: 90 * 1000,
};
const LOCAL_URL = /https?:\/\/(localhost|127\.0\.0\.1|10\.0\.2\.2|0\.0\.0\.0)(?=[:/"'\s]|$)/i;
const SECRET = /eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}|sb_secret_[A-Za-z0-9_-]+|service_role|postgres(ql)?:\/\/[^\s"']+:[^\s"']+@/i;

async function get(url, opts, extra = {}) {
  const res = await fetch(url, { cache: 'no-store', redirect: 'follow', signal: AbortSignal.timeout(opts.timeoutMs), headers: { 'user-agent': 'neeroplus-verify-production', ...(extra.headers || {}) } });
  return res;
}
const json = async (url, opts, extra) => { const r = await get(url, opts, extra); return { status: r.status, body: await r.json().catch(() => null), headers: r.headers }; };

/** Runs every check; returns [{ name, ok, detail }]. */
async function runChecks(options = {}) {
  const opts = { ...DEFAULTS, ...options };
  const results = [];
  const check = async (name, fn) => {
    try { const detail = await fn(); results.push({ name, ok: true, detail }); }
    catch (error) { results.push({ name, ok: false, detail: error.message }); }
  };
  const must = (cond, message) => { if (!cond) throw new Error(message); };
  const sha = String(opts.expect || '').trim().toLowerCase();
  must(sha || true, '');

  await check('Render /health reports the expected commit', async () => {
    const { status, body, headers } = await json(`${opts.api}/health`, opts);
    must(status === 200 && body && body.status === 'ok', `health ${status} ${JSON.stringify(body)}`);
    must(/no-store/.test(headers.get('cache-control') || ''), 'health is cacheable');
    must(body.commit, 'health has no commit (deployed before /health reported commits?)');
    if (sha) must(body.commit === sha, `Render runs ${body.commit}, expected ${sha}`);
    return `ok, commit ${body.commit}`;
  });

  await check('Vercel production deployment is the expected commit', async () => {
    const { status, body } = await json(`${opts.githubApi}/repos/${opts.repo}/deployments?per_page=10`, opts, { headers: { accept: 'application/vnd.github+json' } });
    must(status === 200 && Array.isArray(body), `GitHub deployments ${status}`);
    const latest = body.find(d => d.environment === opts.vercelEnvironment);
    must(latest, `no "${opts.vercelEnvironment}" deployment found`);
    if (sha) must(latest.sha === sha, `latest Vercel production deployment is ${latest.sha.slice(0, 7)}, expected ${sha.slice(0, 7)}`);
    const st = await json(latest.statuses_url, opts, { headers: { accept: 'application/vnd.github+json' } });
    const state = Array.isArray(st.body) && st.body[0] ? st.body[0].state : 'unknown';
    must(state === 'success', `Vercel deployment state: ${state}`);
    return `${latest.sha.slice(0, 7)} success (${latest.created_at})`;
  });

  await check('Website responds and the app shell is never served stale', async () => {
    const page = await get(`${opts.site}/`, opts);
    must(page.status === 200, `site HTTP ${page.status}`);
    const sw = await get(`${opts.site}/flutter_service_worker.js`, opts);
    must(/no-store|no-cache/.test(sw.headers.get('cache-control') || ''), 'service worker may be cached');
    const main = await get(`${opts.site}/main.dart.js`, opts, {});
    must(main.status === 200, `main.dart.js HTTP ${main.status}`);
    must(/must-revalidate|no-cache|no-store/.test(main.headers.get('cache-control') || ''), 'main.dart.js may be cached');
    opts._bundle = await main.text();
    return `HTTP 200, ${opts._bundle.length} byte app`;
  });

  await check('Website uses the production API (no localhost, no secrets)', async () => {
    must(opts._bundle, 'app not downloaded');
    must(opts._bundle.includes(`${opts.api}/api/`), `app does not call ${opts.api}/api/`);
    const bases = [...new Set(opts._bundle.match(/https:\/\/[a-z0-9.-]+\.onrender\.com\/api\/?/g) || [])];
    must(bases.every(b => b.startsWith(opts.api)), `other API bases: ${bases.join(', ')}`);
    must(!LOCAL_URL.test(opts._bundle.split(opts.api).join('')), 'app contains a localhost/emulator URL');
    must(!SECRET.test(opts._bundle), 'app contains something that looks like a secret');
    return bases.join(', ');
  });

  let categories = [];
  await check('Products API (what the website shows)', async () => {
    const { status, body } = await json(`${opts.api}/api/products`, opts);
    must(status === 200 && body && body.success && Array.isArray(body.products), `products ${status}`);
    must(body.products.length > 0, 'no products');
    must(body.products.every(p => p.id && p.sku && p.name), 'a product is missing id/sku/name');
    must(!body.products.some(p => LOCAL_URL.test(String(p.img || ''))), 'a product image points to localhost');
    must(!body.products.some(p => Object.hasOwn(p, 'purchase_price')), 'purchase price is public');
    return `${body.products.length} products`;
  });

  await check('Categories API and category images', async () => {
    const { status, body } = await json(`${opts.api}/api/categories`, opts);
    must(status === 200 && body && body.success && Array.isArray(body.categories) && body.categories.length, `categories ${status}`);
    categories = body.categories;
    must(!categories.some(c => LOCAL_URL.test(String(c.image_url || ''))), 'a category image points to localhost');
    // Pictures the app shows: Admin-saved real images (URL or server path).
    const shown = categories.map(c => String(c.image_url || '').trim()).filter(v => /^https?:\/\//i.test(v) || /^\/(images|api\/product-images|uploads)\//.test(v));
    for (const v of shown) {
      const url = v.startsWith('/') ? opts.api + v : v;
      const r = await get(url, opts);
      must(r.status === 200 && /^image\//.test(r.headers.get('content-type') || ''), `category image ${v} -> HTTP ${r.status}`);
    }
    const builtIn = await get(`${opts.api}/images/RO_System.png`, opts);
    must(builtIn.status === 200, `/images/RO_System.png HTTP ${builtIn.status}`);
    return `${categories.length} categories, ${shown.length} saved image(s) load`;
  });

  await check('Admin Panel is served (verified-save version)', async () => {
    const r = await get(`${opts.api}/admin`, opts);
    const html = await r.text();
    must(r.status === 200, `admin HTTP ${r.status}`);
    must(html.includes('function adminWrite') && html.includes('admin-env-banner'), 'admin page is not the verified-save version');
    return 'ok';
  });
  return results;
}

function defaultExpectedCommit() {
  try {
    execSync('git fetch -q origin', { stdio: 'ignore', timeout: 60000 });
    return execSync('git rev-parse origin/main', { encoding: 'utf8' }).trim();
  } catch (_) {
    try { return execSync('git rev-parse HEAD', { encoding: 'utf8' }).trim(); } catch (__) { return ''; }
  }
}

module.exports = { runChecks, DEFAULTS };

if (require.main === module) {
  (async () => {
    const arg = name => { const a = process.argv.find(x => x.startsWith(`--${name}=`)); return a ? a.slice(name.length + 3) : undefined; };
    const expect = arg('expect') || defaultExpectedCommit();
    const waitMinutes = Number(arg('wait') || 0);
    const deadline = Date.now() + waitMinutes * 60 * 1000;
    let results;
    for (;;) {
      results = await runChecks({ expect, api: arg('api') || DEFAULTS.api, site: arg('site') || DEFAULTS.site });
      if (results.every(r => r.ok) || Date.now() >= deadline) break;
      if (!process.argv.includes('--json')) console.log(`Not deployed yet (${results.filter(r => !r.ok).length} failing); checking again in 20 s...`);
      await new Promise(r => setTimeout(r, 20000));
    }
    if (process.argv.includes('--json')) console.log(JSON.stringify({ expect, ok: results.every(r => r.ok), results }, null, 1));
    else {
      console.log(`Expected commit: ${expect || '(any)'}`);
      for (const r of results) console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.name}: ${r.detail}`);
      console.log(results.every(r => r.ok) ? 'ALL CHECKS PASSED' : 'SOME CHECKS FAILED');
    }
    process.exitCode = results.every(r => r.ok) ? 0 : 1;
  })().catch(e => { console.error('FAILED', e.message); process.exit(1); });
}
