// Opt-in integration test: creates one isolated profile and its own Keychain
// item, checks encrypted cookies across restart, then removes only that item.
import { spawn, execFileSync } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtemp, readFile, realpath, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { command } from './driver.mjs';

const profile = await mkdtemp(join(tmpdir(), 'derivative-real-keychain-'));
const server = createServer((req, res) => {
  if (req.url === '/seed') res.setHeader('Set-Cookie', 'keychain_fixture=retained; Max-Age=600; HttpOnly; SameSite=Lax');
  res.setHeader('Content-Type', 'text/html');
  res.end(`<title>Keychain fixture</title><h1>${req.headers.cookie || 'No cookie'}</h1>`);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const executable = await realpath(resolve(process.env.DERIVATIVE_NATIVE_APP || 'native/build/Derivative.app', 'Contents/MacOS/Derivative'));
let app, browser, identity, firstIdentity;
try {
  for (let pass = 0; pass < 2; pass++) {
    const ports = createServer();
    await new Promise(resolve => ports.listen(0, '127.0.0.1', resolve));
    const port = ports.address().port;
    await new Promise(resolve => ports.close(resolve));
    const driver = join(profile, `driver-${pass}`);
    app = spawn(executable, [`--url=${origin}/${pass ? 'check' : 'seed'}`, `--remote-debugging-port=${port}`], {
      env: { ...process.env, DERIVATIVE_NATIVE_USER_DATA: profile, DERIVATIVE_NATIVE_TEST_DIRECTORY: driver, DERIVATIVE_NATIVE_AUTOMATED: '1' },
      stdio: ['ignore', 'ignore', 'pipe'],
    });
    let logs = '';
    app.stderr.on('data', chunk => { logs += chunk; });
    browser = null;
    const deadline = Date.now() + 30000;
    while (Date.now() < deadline && app.exitCode === null) {
      try { browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`, { timeout: 500 }); break; }
      catch { await new Promise(resolve => setTimeout(resolve, 200)); }
    }
    assert.ok(browser, `Browser startup blocked or failed on pass ${pass + 1}: ${logs}`);
    let page;
    while (!page && Date.now() < deadline) {
      page = browser.contexts().flatMap(context => context.pages()).find(page => page.url().startsWith(origin));
      if (!page) await new Promise(resolve => setTimeout(resolve, 100));
    }
    assert.ok(page, 'Fixture page did not open');
    await page.goto(`${origin}/check`);
    await page.getByRole('heading', { name: 'keychain_fixture=retained' }).waitFor();
    identity = JSON.parse(await readFile(join(profile, 'keychain-identity.json'), 'utf8'));
    assert.match(identity.service, /^Derivative(?: Development)? Safe Storage$/);
    assert.match(identity.account, /^app\.derivative\.browser\.native\./);
    if (firstIdentity) assert.deepEqual(identity, firstIdentity, 'Restart changed the encryption identity');
    firstIdentity = identity;
    // No -w/-g: inspect only this fixture item's metadata, never its secret.
    execFileSync('security', ['find-generic-password', '-s', identity.service, '-a', identity.account], { stdio: 'ignore' });
    const exited = new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Browser failed to quit')), 10000);
      app.once('exit', code => { clearTimeout(timer); code === 0 ? resolve() : reject(new Error(logs)); });
    });
    await command(driver, 'quit');
    await exited;
    await browser.close().catch(() => {}); browser = null;
  }
  execFileSync('python3', ['-c', `
import pathlib,sqlite3,sys
rows=[]
for path in pathlib.Path(sys.argv[1]).rglob('Cookies'):
 with sqlite3.connect('file:'+str(path)+'?mode=ro',uri=True) as db:
  rows += db.execute("select value,length(encrypted_value) from cookies where name='keychain_fixture'").fetchall()
assert rows and all(value=='' and size>0 for value,size in rows), rows
`, profile]);
  console.log('PASS: real scoped Keychain item, two startups, stable identity, encrypted cookie persistence across restart.');
} finally {
  if (app?.exitCode === null) { app.kill('SIGTERM'); await new Promise(resolve => app.once('exit', resolve)); }
  if (browser) await browser.close().catch(() => {});
  if (!identity) { try { identity = JSON.parse(await readFile(join(profile, 'keychain-identity.json'), 'utf8')); } catch {} }
  if (identity && /^Derivative(?: Development)? Safe Storage$/.test(identity.service) && /^app\.derivative\.browser\.native\./.test(identity.account)) {
    try { execFileSync('security', ['delete-generic-password', '-s', identity.service, '-a', identity.account], { stdio: 'ignore' }); } catch {}
  }
  await new Promise(resolve => server.close(resolve));
  await rm(profile, { recursive: true, force: true });
}
