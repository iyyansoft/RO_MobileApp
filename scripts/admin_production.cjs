// Local Admin for PRODUCTION: the local Admin Panel (web_preview/admin.html)
// working on the live data through the Production Render API.
//
//   node scripts/admin_production.cjs              -> http://127.0.0.1:8110/admin
//   node scripts/admin_production.cjs --port=8110
//   node scripts/admin_production.cjs --target=http://127.0.0.1:9000   (tests: a fake Production)
//
// How it works:
//  - /admin serves the local admin.html with a PRODUCTION label.
//  - /api/* is forwarded unchanged (method, body, Authorization) to the
//    Production API on Render. Render checks the admin login and does every
//    write; nothing is saved here.
//  - Other GET requests (product pictures, /images, /purifier.jpg) are read from
//    Render. Any other write is refused.
//
// Safety:
//  - Listens on 127.0.0.1 only (not reachable from other devices).
//  - Holds no secrets: it never reads .env and has no database or Supabase key.
//    The admin password goes only to Render's own login endpoint.
//  - Writes are never retried. If Render does not answer, the Admin Panel is
//    told the outcome is unknown and reads the data back to find out.
'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const PRODUCTION_ORIGIN = 'https://ro-mobileapp.onrender.com';
const ADMIN_HTML = path.join(__dirname, '..', 'web_preview', 'admin.html');
const MAX_BODY = 25 * 1024 * 1024;
const UPSTREAM_TIMEOUT_MS = 100 * 1000; // Render can take ~1 minute to wake up
const FORWARD_REQUEST_HEADERS = ['content-type', 'authorization', 'x-admin-token', 'accept', 'if-match'];
const FORWARD_RESPONSE_HEADERS = ['content-type', 'cache-control', 'retry-after', 'content-disposition', 'etag', 'last-modified'];
const SAFE_METHODS = new Set(['GET', 'HEAD']);

function normaliseTarget(target) {
  const url = new URL(target || PRODUCTION_ORIGIN);
  if (!/^https?:$/.test(url.protocol)) throw new Error(`Unsupported target: ${target}`);
  return url.origin;
}

/** The label the Admin Panel shows; PRODUCTION only for the real Render API. */
function adminEnvironment(target) {
  const realProduction = target === PRODUCTION_ORIGIN;
  return { mode: 'production', realProduction, target };
}

function adminPage(target) {
  const env = JSON.stringify(adminEnvironment(target)).replace(/</g, '\\u003c');
  return fs.readFileSync(ADMIN_HTML, 'utf8').replace('<head>', `<head>\n<script>window.__ADMIN_ENV = ${env};</script>`);
}

function sendJson(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(JSON.stringify(body));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', chunk => {
      size += chunk.length;
      if (size > MAX_BODY) { reject(Object.assign(new Error('Request is too large.'), { status: 413 })); req.destroy(); return; }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

async function forward(req, res, target, { timeoutMs = UPSTREAM_TIMEOUT_MS } = {}) {
  const isWrite = !SAFE_METHODS.has(req.method);
  const headers = { 'user-agent': 'neeroplus-local-admin' };
  for (const name of FORWARD_REQUEST_HEADERS) if (req.headers[name]) headers[name] = req.headers[name];
  let body;
  try {
    body = isWrite ? await readBody(req) : undefined;
  } catch (error) {
    return sendJson(res, error.status || 400, { success: false, error: error.message });
  }
  let upstream;
  try {
    upstream = await fetch(target + req.url, {
      method: req.method,
      headers,
      body: body && body.length ? body : undefined,
      redirect: 'manual',
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (error) {
    const timedOut = error.name === 'TimeoutError' || error.name === 'AbortError';
    // A write that got no answer may or may not have been saved: the Admin
    // Panel reads the data back instead of guessing.
    return sendJson(res, timedOut ? 504 : 502, {
      success: false,
      outcomeUnknown: isWrite,
      error: isWrite
        ? `${timedOut ? 'Production did not answer in time' : 'Could not reach Production'}. The change may or may not have been saved.`
        : `${timedOut ? 'Production did not answer in time' : 'Could not reach Production'}. Please try again.`,
    });
  }
  const responseHeaders = {};
  for (const name of FORWARD_RESPONSE_HEADERS) {
    const value = upstream.headers.get(name);
    if (value) responseHeaders[name] = value;
  }
  const bytes = Buffer.from(await upstream.arrayBuffer());
  res.writeHead(upstream.status, responseHeaders);
  res.end(req.method === 'HEAD' ? undefined : bytes);
}

function createHandler(target, options = {}) {
  return async (req, res) => {
    try {
      const pathname = new URL(req.url, 'http://local').pathname;
      if (pathname === '/' && SAFE_METHODS.has(req.method)) {
        res.writeHead(302, { location: '/admin' });
        return res.end();
      }
      if ((pathname === '/admin' || pathname.startsWith('/admin/')) && SAFE_METHODS.has(req.method)) {
        res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
        return res.end(req.method === 'HEAD' ? undefined : adminPage(target));
      }
      if (pathname.startsWith('/api/')) return await forward(req, res, target, options);
      if (SAFE_METHODS.has(req.method)) return await forward(req, res, target, options);
      return sendJson(res, 405, { success: false, error: 'Only Admin API requests are forwarded.' });
    } catch (error) {
      if (!res.headersSent) sendJson(res, 500, { success: false, error: 'Local Admin proxy error.' });
      else res.end();
    }
  };
}

async function startAdminProduction({ port = 8110, target = PRODUCTION_ORIGIN, quiet = false, timeoutMs } = {}) {
  const origin = normaliseTarget(target);
  const server = http.createServer(createHandler(origin, timeoutMs ? { timeoutMs } : {}));
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', resolve);
  });
  const actualPort = server.address().port;
  if (!quiet) {
    const env = adminEnvironment(origin);
    console.log(`Local Admin: http://127.0.0.1:${actualPort}/admin`);
    console.log(env.realProduction
      ? `Target: PRODUCTION (${origin}). Every save goes to the live database through the Render API.`
      : `Target: TEST TARGET ${origin} (not Production).`);
  }
  return { server, port: actualPort, target: origin, close: () => new Promise(resolve => server.close(resolve)) };
}

module.exports = { startAdminProduction, adminEnvironment, PRODUCTION_ORIGIN };

if (require.main === module) {
  const arg = name => {
    const found = process.argv.find(a => a.startsWith(`--${name}=`));
    return found ? found.slice(name.length + 3) : undefined;
  };
  startAdminProduction({ port: Number(arg('port') || 8110), target: arg('target') || PRODUCTION_ORIGIN })
    .catch(error => { console.error('Could not start Local Admin:', error.message); process.exit(1); });
}
