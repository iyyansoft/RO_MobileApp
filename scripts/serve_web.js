const express = require('express');
const path = require('path');
const https = require('https');

const app = express();
const PRIMARY_PORT = parseInt(process.env.WEB_PORT, 10) || 8080;
const SECONDARY_PORT = 8085;
const buildDir = path.join(__dirname, '..', 'build', 'web');

// Enable CORS for all incoming browser requests
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS, HEAD, PATCH');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(204);
  }
  next();
});

// Transparent proxy for /api requests forwarding to the deployed Render backend
app.use('/api', (req, res) => {
  const targetPath = '/api' + (req.url.startsWith('/') ? req.url : '/' + req.url);
  const headers = { ...req.headers };
  delete headers.host;
  delete headers.origin;
  delete headers.referer;
  headers.host = 'ro-mobileapp.onrender.com';

  const options = {
    hostname: 'ro-mobileapp.onrender.com',
    port: 443,
    path: targetPath,
    method: req.method,
    headers: headers,
  };

  const proxyReq = https.request(options, (proxyRes) => {
    res.writeHead(proxyRes.statusCode, proxyRes.headers);
    proxyRes.pipe(res);
  });

  proxyReq.on('error', (err) => {
    console.error(`[Proxy Error] ${req.method} ${targetPath}:`, err.message);
    if (!res.headersSent) {
      res.status(502).json({
        success: false,
        error: 'Backend gateway connection error: ' + err.message,
      });
    }
  });

  req.on('aborted', () => {
    proxyReq.destroy();
  });

  req.pipe(proxyReq);
});

// Local category/product images: http://localhost:8080/images/<file> -> assets/images/<file>
app.use('/images', express.static(path.join(__dirname, '..', 'assets', 'images')));

// Serve compiled Flutter Web static files with no-cache headers
app.use(express.static(buildDir, {
  setHeaders: (res, filePath) => {
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');
  }
}));

// Single Page Application (SPA) fallback to index.html for GoRouter routes
app.get('*', (req, res) => {
  res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Expires', '0');
  res.sendFile(path.join(buildDir, 'index.html'));
});

function startListener(port) {
  const server = app.listen(port, '0.0.0.0', () => {
    console.log(`Flutter Web Server listening at: http://localhost:${port}`);
  });
  server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
      console.warn(`[Notice] Port ${port} is in use; skipping port ${port}.`);
    } else {
      console.error(`[Error] Failed to listen on port ${port}:`, err);
    }
  });
  return server;
}

startListener(PRIMARY_PORT);
if (SECONDARY_PORT !== PRIMARY_PORT) {
  startListener(SECONDARY_PORT);
}

