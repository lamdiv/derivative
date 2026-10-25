import { spawn, execFileSync } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';

await mkdir('native/build', { recursive: true });
execFileSync('xcrun', ['swiftc', '-swift-version', '5', '-O', '-module-cache-path', 'native/.cache/swift-modules', 'native/Sources/FaviconLoader.swift', 'native/Tests/FaviconTests.swift', '-o', 'native/build/favicon-tests'], { stdio: 'inherit' });
const image = await readFile('assets/icon.png');
const hits = new Map();
const server = createServer((req, res) => {
  hits.set(req.url, (hits.get(req.url) ?? 0) + 1);
  if (req.url === '/') { res.writeHead(302, { location: '/nested/page' }); res.end(); return; }
  if (req.url === '/nested/page') {
    res.setHeader('content-type', 'text/html');
    res.end("<html><head><base href='/assets/'><link rel='icon' type='image/svg+xml' href='mark.svg'><link rel='icon' type='image/png' href='mark.png'></head><body>Fixture</body></html>"); return;
  }
  if (req.url === '/assets/mark.png') { res.setHeader('content-type', 'image/png'); res.end(image); return; }
  res.writeHead(404); res.end('Missing');
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const missingHits = [];
const missingServer = createServer((req, res) => { missingHits.push(req.url); res.writeHead(404); res.end(); });
await new Promise(resolve => missingServer.listen(0, '127.0.0.1', resolve));
try {
  const child = spawn('native/build/favicon-tests', [`http://127.0.0.1:${server.address().port}/`, `http://127.0.0.1:${missingServer.address().port}/`, ...(process.argv.includes('--live') ? ['--live'] : [])], { stdio: 'inherit' });
  const code = await new Promise((resolve, reject) => { child.once('error', reject); child.once('exit', resolve); });
  assert.equal(code, 0);
  assert.equal(hits.get('/assets/mark.png'), 1, 'Deduplicate icon downloads');
  assert.equal(hits.get('/'), 1);
  assert.equal(hits.get('/nested/page'), 1);
  assert.deepEqual(missingHits, ['/favicon.ico', '/'], 'Cache failures without visiting the saved path');
  assert.equal(hits.get('/favicon.ico'), 1, 'Deduplicate conventional probes');
  assert.equal([...hits.keys()].some(path => path.includes('unopened') || path.includes('token=')), false, 'Never fetch an unopened path or its query tokens');
  assert.equal(hits.has('/assets/mark.svg'), false, 'Prefer a supported PNG when available');
  console.log('PASS: real local HTTP favicon discovery after /favicon.ico returns 404.');
} finally {
  server.closeAllConnections(); missingServer.closeAllConnections();
  await Promise.all([new Promise(resolve => server.close(resolve)), new Promise(resolve => missingServer.close(resolve))]);
}
