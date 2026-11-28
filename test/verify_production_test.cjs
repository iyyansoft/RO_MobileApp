// scripts/verify_production.cjs against FAKE Render, Vercel and GitHub servers
// (no network, no production access).
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { runChecks } = require('../scripts/verify_production.cjs');

const SHA = 'a'.repeat(40);
function serve(handler) {
  return new Promise(resolve => {
    const server = http.createServer(handler);
    server.listen(0, '127.0.0.1', () => resolve({ server, url: `http://127.0.0.1:${server.address().port}` }));
  });
}
const send = (res, status, body, headers = {}) => {
  res.writeHead(status, { 'content-type': typeof body === 'string' ? 'text/html' : 'application/json', ...headers });
  res.end(typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body));
};

/** Fake production; `state` lets each test break one thing. */
async function fakeProduction(state) {
  const api = await serve((req, res) => {
    if (req.url === '/health') return send(res, 200, { status: 'ok', commit: state.renderCommit }, { 'cache-control': 'no-store' });
    if (req.url === '/api/products') return send(res, 200, { success: true, products: [{ id: 'P1', sku: 'S1', name: 'Pump', img: state.productImg }] });
    if (req.url === '/api/categories') return send(res, 200, { success: true, categories: [{ id: 'CAT_SYS', title: 'RO Systems', image_url: state.categoryImage }] });
    if (req.url.startsWith('/images/') || req.url.startsWith('/api/product-images/')) {
      return state.brokenImages ? send(res, 404, 'missing') : send(res, 200, Buffer.from([0x89, 0x50]), { 'content-type': 'image/png' });
    }
    if (req.url === '/admin') return send(res, 200, state.adminHtml);
    return send(res, 404, 'not found');
  });
  const site = await serve((req, res) => {
    if (req.url === '/') return send(res, 200, '<html></html>', { 'cache-control': 'public, max-age=0, must-revalidate' });
    if (req.url === '/flutter_service_worker.js') return send(res, 200, '', { 'cache-control': 'no-cache, no-store, must-revalidate' });
    if (req.url === '/main.dart.js') return send(res, 200, state.bundle(api.url), { 'cache-control': 'public, max-age=0, must-revalidate', 'content-type': 'text/javascript' });
    return send(res, 404, 'not found');
  });
  const github = await serve((req, res) => {
    if (req.url.startsWith('/repos/o/r/deployments?')) return send(res, 200, [{ environment: 'Production – ro-mobileapp', sha: state.vercelSha, created_at: '2026-11-26T00:00:00Z', statuses_url: `${github.url}/statuses/1` }]);
    if (req.url === '/statuses/1') return send(res, 200, [{ state: state.vercelState }]);
    return send(res, 404, []);
  });
  return {
    run: () => runChecks({ expect: SHA, api: api.url, site: site.url, githubApi: github.url, repo: 'o/r', timeoutMs: 5000 }),
    close: () => Promise.all([api, site, github].map(s => new Promise(r => s.server.close(r)))),
  };
}
const healthy = () => ({
  renderCommit: SHA, vercelSha: SHA, vercelState: 'success', productImg: 'https://x.supabase.co/storage/v1/object/public/ro-product-images/a.jpg',
  categoryImage: '/images/RO_System.png', brokenImages: false,
  adminHtml: '<div class="admin-env-banner"></div><script>function adminWrite(){}</script>',
  bundle: apiUrl => `var base="${apiUrl}/api/";`,
});
async function scenario(change) {
  const state = { ...healthy(), ...change };
  const fake = await fakeProduction(state);
  try { return await fake.run(); } finally { await fake.close(); }
}
const failed = results => results.filter(r => !r.ok).map(r => r.name);

test('everything deployed and healthy: all 7 checks pass', async () => {
  const results = await scenario({});
  assert.equal(results.length, 7);
  assert.deepEqual(failed(results), [], JSON.stringify(results, null, 1));
});

test('Render still on the previous commit: only the Render check fails', async () => {
  const results = await scenario({ renderCommit: 'b'.repeat(40) });
  assert.deepEqual(failed(results), ['Render /health reports the expected commit']);
  assert.match(results[0].detail, /expected a{40}/);
});

test('Vercel on another commit, or its deployment failed', async () => {
  assert.deepEqual(failed(await scenario({ vercelSha: 'c'.repeat(40) })), ['Vercel production deployment is the expected commit']);
  assert.deepEqual(failed(await scenario({ vercelState: 'failure' })), ['Vercel production deployment is the expected commit']);
});

test('website built with a localhost API, another API, or a secret: fails', async () => {
  assert.deepEqual(failed(await scenario({ bundle: apiUrl => `var a="${apiUrl}/api/";var b="http://localhost:8080/api/";` })), ['Website uses the production API (no localhost, no secrets)']);
  assert.deepEqual(failed(await scenario({ bundle: () => 'var a="https://other.onrender.com/api/";' })), ['Website uses the production API (no localhost, no secrets)']);
  assert.deepEqual(failed(await scenario({ bundle: apiUrl => `var a="${apiUrl}/api/";var k="service_role";` })), ['Website uses the production API (no localhost, no secrets)']);
});

test('localhost image URLs in data, or a broken saved category image: fails', async () => {
  assert.deepEqual(failed(await scenario({ productImg: 'http://localhost:8091/uploads/a.png' })), ['Products API (what the website shows)']);
  assert.deepEqual(failed(await scenario({ categoryImage: 'http://127.0.0.1:8101/images/x.png' })), ['Categories API and category images']);
  assert.deepEqual(failed(await scenario({ brokenImages: true })), ['Categories API and category images']);
});

test('old Admin Panel deployed: fails', async () => {
  assert.deepEqual(failed(await scenario({ adminHtml: '<html>old admin</html>' })), ['Admin Panel is served (verified-save version)']);
});
