import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtemp, rm, readFile, writeFile, realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import assert from 'node:assert/strict';
import { NativeTarget } from './target.mjs';
import { command, waitFor } from './driver.mjs';

const server = createServer((req, res) => {
  if (req.url === '/image.svg') { res.setHeader('content-type', 'image/svg+xml'); res.end('<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80"><rect width="120" height="80" fill="plum"/></svg>'); return; }
  if (req.url === '/favicon.ico') { res.writeHead(404); res.end(); return; }
  res.setHeader('content-type', 'text/html'); res.end(`<!doctype html><title>${req.url}</title><h1>${req.url}</h1>`);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const address = `http://127.0.0.1:${server.address().port}`;
const ports = createServer(); await new Promise(resolve => ports.listen(0, '127.0.0.1', resolve)); const port = ports.address().port; await new Promise(resolve => ports.close(resolve));
const profile = await mkdtemp(join(tmpdir(), 'derivative-context-menu-'));
const driver = join(profile, 'driver');
const tab = (id, spaceId, path) => ({ id, spaceId, url: address+path, title: path, pinned: false, lastActive: 1 });
await writeFile(join(profile, 'native-state.json'), JSON.stringify({ version: 1, spaces: [{ id: 'personal', name: 'Personal', icon: 'camera.macro', color: 'lavender' }, { id: 'work', name: 'Work', icon: 'diamond', color: 'mint' }], tabs: [tab('one', 'personal', '/one'), tab('two', 'personal', '/two'), tab('work-tab', 'work', '/work')], folders: [], favorites: [], history: [], activeSpaceId: 'personal', activeTabId: 'one', preferences: { theme: 'dark', sidebarMode: 'fixed', sidebarSize: 'comfortable', restoreSession: true, searchEngine: 'google' } }));
const app = spawn(await realpath(resolve('native/build/Derivative.app/Contents/MacOS/Derivative')), ['--use-mock-keychain', `--remote-debugging-port=${port}`], { env: { ...process.env, DERIVATIVE_NATIVE_USER_DATA: profile, DERIVATIVE_NATIVE_TEST_DIRECTORY: driver, DERIVATIVE_NATIVE_AUTOMATED: '1' }, stdio: ['ignore', 'ignore', 'pipe'] });
let logs = ''; app.stderr.on('data', data => logs += data);
const connections = [];
const send = (action, values = {}) => command(driver, action, values);
const snapshot = () => send('snapshot');
async function page(path) {
  let info;
  await waitFor(async () => { try { const targets = await fetch(`http://127.0.0.1:${port}/json/list`).then(r => r.json()); info = targets.find(t => t.url === address+path); return !!info; } catch { return false; } }, 'Missing page '+path);
  const target = new NativeTarget(info.webSocketDebuggerUrl); connections.push(target); await target.ready;
  await waitFor(async () => await target.evaluate(() => document.querySelector('h1')?.textContent) === path, 'Page did not load '+path);
  return target;
}
try {
  const first = await page('/one');
  await first.evaluate(() => { document.body.innerHTML = '<a id="linked" href="/linked"><img src="/image.svg" width="120" height="80"></a><p id="selection">A selected phrase</p><textarea id="edit">Editable text</textarea><a id="unsafe" href="javascript:void(0)">Script link</a>'; });
  await waitFor(async () => await first.evaluate(() => document.querySelector('img').complete), 'Image did not load');
  async function context(selector) {
    const previous = (await snapshot()).contextMenu;
    const position = await first.evaluate(selector => { const r = document.querySelector(selector).getBoundingClientRect(); return { x: r.x+r.width/2, y: r.y+r.height/2 }; }, selector);
    await first.send('Input.dispatchMouseEvent', { type: 'mousePressed', ...position, button: 'right', clickCount: 1 });
    await first.send('Input.dispatchMouseEvent', { type: 'mouseReleased', ...position, button: 'right', clickCount: 1 });
    let menu;
    await waitFor(async () => { menu = (await snapshot()).contextMenu; return menu.items?.length > 0 && menu.generation !== previous.generation; }, 'No context menu for '+selector);
    return menu;
  }
  const imageMenu = await context('img'); const labels = imageMenu.items.map(i => i.label);
  for (const label of ['Open Link in New Tab', 'Open Link in Split View', 'Save Link As…', 'Copy Link Address', 'Open Image in New Tab', 'Save Image As…', 'Copy Image', 'Copy Image Address', 'Search Google for Image', 'Inspect']) assert.ok(labels.includes(label), 'Missing '+label);
  const commandFor = label => imageMenu.items.find(i => i.label === label).id;
  await send('context.command', { command: commandFor('Copy Image') });
  await waitFor(async () => (await snapshot()).contextMenu.imageCopied, 'Copy Image did not produce PNG data');
  const before = (await snapshot()).state.tabs.length;
  await send('context.command', { command: commandFor('Open Link in New Tab') });
  let s = await snapshot(); const opened = s.state.tabs.find(t => t.url === address+'/linked');
  assert.ok(opened); assert.equal(opened.spaceId, 'personal'); assert.equal(s.state.tabs.length, before+1);
  await send('selectTab', { id: 'one' }); await context('img');
  await send('context.command', { command: commandFor('Open Link in Split View') });
  s = await snapshot(); assert.equal(s.splitIDs[0], 'one'); assert.equal(s.splitIDs.length, 2);
  assert.equal(s.state.tabs.find(t => t.id === s.splitIDs[1]).url, address+'/linked');
  await send('split.close'); await send('selectTab', { id: 'one' }); await context('img');
  await send('context.command', { command: commandFor('Save Image As…') });
  await waitFor(async () => (await snapshot()).downloads.some(d => d.status === 'completed'), 'Context image download did not complete');
  const download = (await snapshot()).downloads.find(d => d.status === 'completed'); assert.match(await readFile(download.path, 'utf8'), /<svg/);
  const edit = await context('#edit'); const editingLabels = edit.items.map(i => i.label);
  for (const label of ['Undo', 'Cut', 'Copy', 'Paste', 'Select All']) assert.ok(editingLabels.some(i => i.replaceAll('&', '') === label), 'Editing menu lost '+label);
  await first.evaluate(() => { const r = document.createRange(); r.selectNodeContents(document.querySelector('#selection')); window.getSelection().removeAllRanges(); window.getSelection().addRange(r); });
  const selection = await context('#selection'); assert.ok(selection.items.some(i => i.label === 'Search the Web for Selection'));
  await first.evaluate(() => window.getSelection().removeAllRanges());
  const unsafe = await context('#unsafe'); assert.ok(unsafe.items.some(i => i.label === 'Copy Link Address')); assert.ok(!unsafe.items.some(i => i.label === 'Open Link in New Tab'));
  await context('img'); await send('context.command', { command: commandFor('Inspect') });
  await waitFor(async () => (await snapshot()).devToolsOpen, 'Inspect did not open developer tools');
  await send('context.closeTools'); await waitFor(async () => !(await snapshot()).devToolsOpen, 'Developer tools did not close');
  const exited = new Promise((resolve, reject) => { const timer = setTimeout(() => reject(new Error(logs)), 10000); app.once('exit', () => { clearTimeout(timer); resolve(); }); });
  await send('quit'); await exited; assert.equal(app.exitCode, 0, logs);
  console.log('PASS: real Chromium linked-image, editable text, selected text and unsafe-link menus; new-tab/split profile ownership, copied PNG data, downloaded image bytes, and working developer tools.');
} catch (error) { console.error('Context menu failure:', app.exitCode, app.signalCode); console.error(logs); console.error(await snapshot().catch(() => null)); throw error; }
finally {
  for (const connection of connections) connection.close();
  if (app.exitCode === null && app.signalCode === null) { const done = new Promise(resolve => app.once('exit', resolve)); app.kill(); await done; }
  server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); await rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
}
