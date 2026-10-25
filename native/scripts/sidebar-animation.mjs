import { spawn } from 'node:child_process';
import { mkdtemp, rm, realpath, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import assert from 'node:assert/strict';
import { command, waitFor } from './driver.mjs';
const profile = await mkdtemp(join(tmpdir(), 'derivative-slide-'));
const driver = join(profile, 'driver');
await writeFile(join(profile, 'native-state.json'), JSON.stringify({ version: 1, spaces: [{ id: 'personal', name: 'Personal', icon: 'camera.macro', color: 'lavender' }], tabs: [], folders: [], favorites: [], history: [{ url: 'https://example.org/', title: 'Old history', visitedAt: 1 }], activeSpaceId: 'personal', activeTabId: null, preferences: { theme: 'dark', sidebarMode: 'fixed', sidebarSize: 'comfortable', restoreSession: true, searchEngine: 'google' } }));
const app = spawn(await realpath(resolve('native/build/Derivative.app/Contents/MacOS/Derivative')), ['--use-mock-keychain'], { env: { ...process.env, DERIVATIVE_NATIVE_USER_DATA: profile, DERIVATIVE_NATIVE_TEST_DIRECTORY: driver, DERIVATIVE_NATIVE_AUTOMATED: '1', DERIVATIVE_NATIVE_TEST_ANIMATIONS: '1' }, stdio: ['ignore', 'ignore', 'pipe'] });
let logs = ''; app.stderr.on('data', value => logs += value);
const send = (action, values = {}) => command(driver, action, values);
const snapshot = () => send('snapshot');
try {
  const initial = await snapshot(); assert.equal(initial.suggestions.some(s => s.kind === 'history'), false);
  const typed = await send('snapshot', { query: 'Old history' }); assert.equal(typed.suggestions.some(s => s.kind === 'history'), true);
  await send('homeQuery', { query: 'Old history' });
  await waitFor(async () => (await snapshot()).searchOpen, 'Typing on the new-tab page must open regular search');
  const searching = await snapshot(); assert.equal(searching.homeVisible, false); assert.equal(searching.state.tabs.length, 0);
  await send('searchQuery', { query: 'example.org' });
  assert.equal((await snapshot()).searchBounds.y, searching.searchBounds.y, 'Search position must stay anchored as results change');
  await send('dismissSearch');
  assert.equal((await snapshot()).homeVisible, true);
  for (const sidebarSide of ['left', 'right']) {
    await send('preferences', { sidebarSide, sidebarMode: 'fixed' });
    await send('toggleSidebar');
    await send('toggleSidebar');
    await waitFor(async () => { const s = await snapshot(); return !s.sidebarTransitioning && s.sidebarVisible; }, 'Interrupted pin animation must end visible');
    await send('toggleSidebar');
    await waitFor(async () => !(await snapshot()).sidebarVisible, 'Sidebar should slide closed');
    const closed = await snapshot();
    await send('revealSidebar');
    await new Promise(resolve => setTimeout(resolve, 60));
    const during = await snapshot(); assert.deepEqual(during.pageBounds, closed.pageBounds, 'Floating animation cannot resize the page');
    const visibleX = during.sidebarBounds.x;
    const intermediate = sidebarSide === 'right'
      ? during.sidebarPresentationX > visibleX && during.sidebarPresentationX < during.rootBounds.width
      : during.sidebarPresentationX < 8 && during.sidebarPresentationX > -during.sidebarBounds.width;
    assert.ok(intermediate, 'Sidebar must visibly pass through intermediate positions on '+sidebarSide+': '+JSON.stringify({x:during.sidebarPresentationX,frame:during.sidebarBounds,transitioning:during.sidebarTransitioning}));
    await send('revealSidebar', { visible: false });
    await send('revealSidebar', { visible: true });
    await waitFor(async () => { const s = await snapshot(); return s.sidebarVisible && !s.sidebarTransitioning; }, 'Stale hide completion must not hide a reopened sidebar');
    assert.deepEqual((await snapshot()).pageBounds, closed.pageBounds);
  }
  const exited = new Promise((resolve, reject) => { const timer = setTimeout(() => reject(new Error(logs)), 10000); app.once('exit', () => { clearTimeout(timer); resolve(); }); });
  await send('quit'); await exited; assert.equal(app.exitCode, 0, logs);
  console.log('PASS: sliding intermediate positions, rapid reveal/hide reversal, stable webpage bounds, and new-tab search promotion with history only after typing.');
} finally {
  if (app.exitCode === null && app.signalCode === null) { const exited = new Promise(resolve => app.once('exit', resolve)); app.kill(); await exited; }
  await rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
}
