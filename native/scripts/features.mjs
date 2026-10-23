import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtemp, rm, readFile, writeFile, realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import assert from 'node:assert/strict';
import { NativeTarget } from './target.mjs';
import { command, waitFor } from './driver.mjs';

const payload = Buffer.from('A download from Derivative.\n'.repeat(4096));
let cacheHits = 0;
const server = createServer((req, res) => {
  if (req.url === '/cache') { res.writeHead(200, { 'cache-control': 'public, max-age=3600' }); res.end(String(++cacheHits)); return; }
  if (req.url === '/slow-download') {
    res.writeHead(200, { 'content-type': 'application/octet-stream', 'content-disposition': 'attachment; filename="slow-test.txt"', 'content-length': 13107200 });
    const timer = setInterval(() => res.write(Buffer.alloc(131072)), 100);
    res.on('close', () => clearInterval(timer)); return;
  }
  if (req.url === '/download') { res.writeHead(200, { 'content-type': 'application/octet-stream', 'content-disposition': 'attachment; filename="derivative-test.txt"', 'content-length': payload.length }); res.end(payload); return; }
  if (req.url === '/favicon.ico') { res.writeHead(404); res.end(); return; }
  res.setHeader('content-type', 'text/html');
  res.end(`<!doctype html><title>${req.url}</title><h1>${req.url}</h1><textarea aria-label="Draft"></textarea><a href="/download" download>Download</a>`);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const address = `http://127.0.0.1:${server.address().port}`;
const ports = createServer(); await new Promise(resolve => ports.listen(0, '127.0.0.1', resolve)); const port = ports.address().port; await new Promise(resolve => ports.close(resolve));
const profile = await mkdtemp(join(tmpdir(), 'derivative-features-'));
const driver = join(profile, 'driver');
const tab = (id, spaceId, path) => ({ id, spaceId, url: address+path, title: path, pinned: false, lastActive: 1 });
await writeFile(join(profile, 'native-state.json'), JSON.stringify({ version: 1, spaces: [{ id: 'personal', name: 'Personal', icon: 'camera.macro', color: 'lavender' }, { id: 'work', name: 'Work', icon: 'diamond', color: 'mint' }], tabs: [tab('one', 'personal', '/one'), tab('two', 'personal', '/two'), tab('work-tab', 'work', '/work')], folders: [], favorites: [], history: [], activeSpaceId: 'personal', activeTabId: 'one', preferences: { theme: 'dark', sidebarMode: 'fixed', sidebarSize: 'comfortable', restoreSession: true, searchEngine: 'google' } }));
const app = spawn(await realpath(resolve('native/build/Derivative.app/Contents/MacOS/Derivative')), ['--use-mock-keychain', `--remote-debugging-port=${port}`], { env: { ...process.env, DERIVATIVE_NATIVE_USER_DATA: profile, DERIVATIVE_NATIVE_TEST_DIRECTORY: driver, DERIVATIVE_NATIVE_AUTOMATED: '1' }, stdio: ['ignore', 'ignore', 'pipe'] });
let logs = ''; app.stderr.on('data', data => logs += data);
const connections = [];
let stage = 'startup';
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
  await first.evaluate(() => { document.querySelector('textarea').value = 'Keep me'; document.cookie = 'profile=personal; Path=/'; });
  await send('favorite.save', { name: 'One', url: address+'/one' });
  let s = await snapshot(); const favorite = s.state.favorites[0].id;
  await send('favorite.save', { name: 'Two', url: address+'/two' });
  s = await snapshot(); const secondFavorite = s.state.favorites[1].id;
  await send('favorite.reorder', { id: secondFavorite, beforeId: favorite });
  assert.equal((await snapshot()).state.favorites[0].id, secondFavorite);
  await send('favorite.save', { id: favorite, name: 'Renamed', url: address+'/one' });
  assert.equal((await snapshot()).state.favorites.find(f => f.id === favorite).name, 'Renamed');
  assert.deepEqual((await snapshot()).favoriteRows, [2]);
  const gridDrop = await send('drop', { token: 'favorite:'+favorite, kind: 'favoriteGrid' }); assert.equal(gridDrop.dropOperation, 'move');
  const favoriteTab = await send('drop', { token: 'favorite:'+favorite, kind: 'today' }); assert.equal(favoriteTab.dropOperation, 'copy');
  const copiedID = favoriteTab.state.activeTabId; assert.equal(favoriteTab.state.tabs.find(t => t.id === copiedID).favoriteId, undefined);
  await send('closeTab', { id: copiedID }); await waitFor(async () => !(await snapshot()).state.tabs.some(t => t.id === copiedID), 'Close copied favorite tab');
  await send('selectTab', { id: 'one' });
  const added = await send('drop', { token: 'tab:two', kind: 'favoriteGrid' }); assert.equal(added.dropOperation, 'copy'); assert.equal(added.state.favorites.length, 3);
  const beforeDownloads = await snapshot();
  await send('downloads.toggle');
  const expandedDownloads = await snapshot();
  assert.equal(expandedDownloads.downloadsExpanded, true);
  assert.deepEqual(expandedDownloads.sidebarBounds, beforeDownloads.sidebarBounds, 'Downloads must float without resizing the sidebar');
  assert.deepEqual(expandedDownloads.pageBounds, beforeDownloads.pageBounds, 'Downloads must not shift the webpage');
  await send('downloads.toggle');
  await send('folder.create', { name: 'Reading' });
  const folder = (await snapshot()).state.folders[0].id;
  await send('tab.place', { id: 'one', folderId: folder, pinned: 'true' });
  s = await snapshot(); assert.equal(s.state.tabs.find(t => t.id === 'one').folderId, folder); assert.equal(s.loadedPages, 1);
  stage = 'address bar and site controls';
  const controlsBefore = await snapshot(); const initialViewport = await first.evaluate(() => innerWidth);
  assert.equal(controlsBefore.displayAddress, new URL(address).host);
  await send('site.controls');
  assert.equal((await snapshot()).siteControlsOpen, true);
  assert.deepEqual((await snapshot()).pageBounds, controlsBefore.pageBounds, 'Site controls must not resize the webpage');
  await send('page.zoom', { percent: '150' });
  await waitFor(async () => (await snapshot()).pageZoom === 150 && await first.evaluate(() => innerWidth) < initialViewport, 'Page zoom must change actual Chromium viewport scaling');
  for (const [input, expected] of [['999', 300], ['-20', 25], ['100', 100]]) {
    await send('page.zoom', { percent: input });
    await waitFor(async () => (await snapshot()).pageZoom === expected, 'Zoom clamping/reset failed');
  }
  await send('page.mute', { muted: 'true' }); await waitFor(async () => (await snapshot()).pageMuted, 'Mute did not reach Chromium');
  await send('selectTab', { id: 'two' }); assert.equal((await snapshot()).pageMuted, false, 'Mute must belong to the selected tab');
  assert.equal((await snapshot()).siteControlsOpen, false, 'Switching tabs dismisses site controls');
  await send('selectTab', { id: 'one' }); assert.equal((await snapshot()).pageMuted, true, 'Muted tab keeps its state');
  await send('page.mute', { muted: 'false' }); await waitFor(async () => !(await snapshot()).pageMuted, 'Unmute did not reach Chromium');
  assert.deepEqual((await snapshot()).pageBounds, controlsBefore.pageBounds);
  stage = 'organization';
  await send('folder.toggle', { id: folder }); assert.equal((await snapshot()).state.folders[0].collapsed, true);
  await send('folder.rename', { id: folder, name: 'Read later' }); assert.equal((await snapshot()).state.folders[0].name, 'Read later');
  await send('split.open', { id: 'two', withId: 'one' }); const second = await page('/two');
  await waitFor(async () => (await snapshot()).pageFrames.length === 2, 'Both native split panes must attach');
  s = await snapshot(); assert.deepEqual(s.splitIDs, ['one', 'two']);
  assert.equal(await first.evaluate(() => document.visibilityState), 'visible'); assert.equal(await second.evaluate(() => document.visibilityState), 'visible');
  assert.equal(await first.evaluate(() => document.querySelector('textarea').value), 'Keep me');
  const widths = s.pageFrames.map(frame => frame.width).sort((a,b) => a-b); assert.ok(Math.abs(widths[0]-widths[1]) < 2);
  await send('split.ratio', { ratio: '0.65' });
  s = await snapshot(); assert.ok(Math.abs(s.pageFrames[0].width-s.pageFrames[1].width) > 100);
  const original = s.pageBounds;
  await send('settings'); s = await snapshot(); assert.equal(s.overlay, 'settings'); assert.deepEqual(s.pageBounds, original); assert.equal(s.pageFrames.length, 2);
  await send('preferences', { theme: 'light', sidebarSize: 'wide', searchEngine: 'duckduckgo' }); s = await snapshot(); assert.equal(s.dark, false); assert.equal(s.sidebarBounds.width, 320);
  await send('preferences', { theme: 'dark' }); assert.equal((await snapshot()).dark, true);
  await send('expandedLayout', { expanded: true });
  await send('preferences', { sidebarMode: 'hidden' }); s = await snapshot(); assert.equal(s.sidebarMode, 'hidden'); assert.equal(s.state.preferences.sidebarMode, 'fixed'); assert.equal(s.sidebarVisible, false);
  await send('preferences', { sidebarMode: 'fixed' }); s = await snapshot(); assert.equal(s.sidebarVisible, true); assert.deepEqual(s.pageBounds, s.rootBounds);
  await send('expandedLayout', { expanded: false });
  await send('overlay.close'); await send('split.close');
  const initialSearch = await send('search');
  await send('searchQuery', { query: 'nothing matches this phrase' });
  await waitFor(async () => (await snapshot()).searchBounds.height < initialSearch.searchBounds.height, 'Search panel did not shrink to its visible content');
  assert.equal((await snapshot()).searchBounds.y, initialSearch.searchBounds.y, 'Search input must stay anchored as results change');
  await send('dismissSearch');
  await send('recent'); assert.equal((await snapshot()).overlay, 'recent'); await send('commitRecent'); assert.equal((await snapshot()).state.activeTabId, 'two');
  await send('closeTab', { id: 'two' }); await waitFor(async () => !(await snapshot()).state.tabs.some(t => t.id === 'two'), 'Close failed');
  await send('shortcut', { key: 1102 }); s = await snapshot(); assert.ok(s.state.tabs.some(t => t.url === address+'/two')); assert.equal(s.state.tabs.length, 3);
  await send('selectTab', { id: 'one' });
  await first.evaluate(() => { document.querySelector('a').click(); });
  await waitFor(async () => (await snapshot()).downloads.some(d => d.status === 'completed'), 'Download did not complete');
  const download = (await snapshot()).downloads.find(d => d.status === 'completed'); assert.deepEqual(await readFile(download.path), payload); assert.equal(download.name, 'derivative-test.txt');
  await send('selectSpace', { id: 'work' }); const work = await page('/work'); await work.evaluate(() => { document.cookie = 'profile=work; Path=/'; });
  // Use a fresh profile's first download; scripted clicks do not reset Chromium's multiple-download permission.
  stage = 'download cancellation';
  await work.evaluate(() => { const link = document.createElement('a'); link.href = '/slow-download'; link.download = 'slow-test.txt'; document.body.append(link); link.click(); }, undefined, true);
  await waitFor(async () => (await snapshot()).downloads.some(d => d.id !== download.id && d.status === 'progressing'), 'Slow download did not start');
  const slow = (await snapshot()).downloads.find(d => d.id !== download.id && d.status === 'progressing'); await send('download.cancel', { id: slow.id });
  await waitFor(async () => (await snapshot()).downloads.find(d => d.id === slow.id)?.status === 'cancelled', 'Download cancellation failed');
  stage = 'cross-Space move';
  await send('tab.place', { id: 'one', spaceId: 'work', pinned: 'true' });
  await waitFor(async () => (await snapshot()).state.tabs.find(t => t.id === 'one')?.spaceId === 'work', 'Cross-Space move did not finish');
  const moved = await page('/one'); assert.match(await moved.evaluate(() => document.cookie), /profile=work/); assert.doesNotMatch(await moved.evaluate(() => document.cookie), /profile=personal/);
  s = await send('snapshot', { query: '/two' }); assert.equal(s.suggestions.filter(x => x.kind === 'tab' && x.url === address+'/two').length, 0, 'Search must not list tabs from another Space');
  await send('swipe', { dx: -60, dy: 0, time: 1, began: true }); assert.equal((await snapshot()).state.activeSpaceId, 'personal');
  s = await send('swipe', { dx: -70, dy: 0, time: 2, began: true }); assert.equal(s.swipeEdge, 'First Space');
  await send('space.create', { name: 'Art', color: 'blush', icon: '✿' }); s = await snapshot(); const art = s.state.spaces.at(-1).id;
  await send('space.rename', { id: art, name: 'Studio' }); await send('space.reorder', { id: art, beforeId: 'personal' }); assert.equal((await snapshot()).state.spaces[0].name, 'Studio');
  await send('space.delete', { id: art }); await send('folder.delete', { id: folder }); assert.equal((await snapshot()).state.folders.length, 0);
  stage = 'cookie clearing';
  await send('selectSpace', { id: 'work' }); await send('clear', { id: 'cookies' }); await waitFor(async () => await moved.evaluate(() => document.cookie) === '', 'Cookie clearing failed');
  stage = 'cache clearing';
  const cached = await moved.evaluate(async () => await fetch('/cache').then(r => r.text()));
  assert.equal(await moved.evaluate(async () => await fetch('/cache').then(r => r.text())), cached);
  await send('clear', { id: 'cache' });
  await waitFor(async () => await moved.evaluate(async () => await fetch('/cache').then(r => r.text())) !== cached, 'HTTP cache clearing failed');
  await send('clear', { id: 'history' }); assert.equal((await snapshot()).state.history.length, 0);
  stage = 'quit';
  const exited = new Promise((resolve, reject) => { const timer = setTimeout(() => reject(new Error('Quit failed: '+logs)), 10000); app.once('exit', () => { clearTimeout(timer); resolve(); }); });
  await send('quit'); await exited; assert.equal(app.exitCode, 0, logs);
  console.log('PASS: native favorite/folder organization, split view and sizing, settings/themes, recent/reopened tabs, download bytes, profile-safe moves, scoped search, swipe edges, Space management, browsing-data clearing, and clean quit.');
} catch (error) { console.error('Failed stage:', stage, 'exit:', app.exitCode, app.signalCode); console.error(logs); console.error(await snapshot().catch(() => null)); throw error; }
finally {
  for (const connection of connections) connection.close();
  if (app.exitCode === null && app.signalCode === null) { const done = new Promise(resolve => app.once('exit', resolve)); app.kill(); await done; }
  server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); await rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
}
