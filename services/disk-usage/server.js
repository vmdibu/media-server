'use strict';

const http = require('node:http');
const { execFile } = require('node:child_process');

const port = Number(process.env.PORT || 3000);
const diskPath = process.env.DISK_PATH || '/mnt/plexdrive';
const cacheMs = Number(process.env.CACHE_MS || 5000);

let cache = { ts: 0, payload: null };

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Content-Length': Buffer.byteLength(body)
  });
  res.end(body);
}

function runDf(args) {
  return new Promise((resolve, reject) => {
    execFile('df', args, { timeout: 5000 }, (err, stdout) => {
      if (err) {
        reject(err);
        return;
      }
      resolve(stdout);
    });
  });
}

async function readDiskStats() {
  let stdout;
  try {
    stdout = await runDf(['-kP', diskPath]);
  } catch (error) {
    stdout = await runDf(['-k', diskPath]);
  }

  const lines = String(stdout || '').trim().split(/\r?\n/);
  if (lines.length < 2) {
    throw new Error('Unexpected df output');
  }

  const parts = lines[lines.length - 1].trim().split(/\s+/);
  if (parts.length < 6) {
    throw new Error('Unexpected df output');
  }

  const totalBlocks = Number(parts[1]);
  const usedBlocks = Number(parts[2]);
  const freeBlocks = Number(parts[3]);
  const usedPercentText = parts[4] || '';
  const mountPoint = parts.slice(5).join(' ');

  const totalBytes = totalBlocks * 1024;
  const usedBytes = usedBlocks * 1024;
  const freeBytes = freeBlocks * 1024;
  const usedPercent = Number(usedPercentText.replace('%', '')) ||
    (totalBytes ? Math.round((usedBytes / totalBytes) * 100) : 0);

  return {
    path: diskPath,
    mountPoint,
    totalBytes,
    usedBytes,
    freeBytes,
    usedPercent,
    updatedAt: new Date().toISOString()
  };
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');

  if (url.pathname === '/health') {
    sendJson(res, 200, { status: 'ok' });
    return;
  }

  if (url.pathname !== '/disk') {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Not found');
    return;
  }

  if (cache.payload && Date.now() - cache.ts < cacheMs) {
    sendJson(res, 200, cache.payload);
    return;
  }

  try {
    const payload = await readDiskStats();
    cache = { ts: Date.now(), payload };
    sendJson(res, 200, payload);
  } catch (error) {
    sendJson(res, 500, { error: 'disk stats failed', message: error.message });
  }
});

server.listen(port, '0.0.0.0', () => {
  console.log(`disk-usage listening on ${port} for ${diskPath}`);
});
