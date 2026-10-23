import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtemp, rm, realpath, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import assert from 'node:assert/strict';
import { command } from './driver.mjs';

const server = createServer((req, res) => {
  res.setHeader('content-type', 'text/html');
  res.end('<!doctype html><title>Sidebar fixture</title><h1>Native sidebar layout</h1>');
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const url = `http://127.0.0.1:${server.address().port}/`;
const profile = await mkdtemp(join(tmpdir(), 'derivative-sidebar-'));
const driver = join(profile, 'driver');
// Include the maximum grid and a real active tab so shrinking cannot hide a
// header overflow behind an empty Space's shorter layout.
await writeFile(join(profile, 'native-state.json'), JSON.stringify({
  version: 1, spaces: [{ id: 'personal', name: 'Personal', icon: 'camera.macro', color: 'lavender' }],
  tabs: [{ id: 'one', spaceId: 'personal', url, title: 'Sidebar fixture', pinned: false, lastActive: 1 }],
  folders: [], favorites: Array.from({ length: 12 }, (_, i) => ({ id: `favorite-${i}`, name: `Favorite ${i}`, url: url + i })),
  history: [], activeSpaceId: 'personal', activeTabId: 'one',
  preferences: { theme: 'dark', sidebarMode: 'fixed', sidebarSize: 'comfortable', restoreSession: true, searchEngine: 'google' }
}));
const executable = await realpath(resolve('native/build/Derivative.app/Contents/MacOS/Derivative'));
const app = spawn(executable, ['--use-mock-keychain'], {
  env: { ...process.env, DERIVATIVE_NATIVE_USER_DATA: profile, DERIVATIVE_NATIVE_TEST_DIRECTORY: driver, DERIVATIVE_NATIVE_AUTOMATED: '1' },
  stdio: ['ignore', 'ignore', 'pipe']
});
let logs = '';
app.stderr.on('data', chunk => { logs += chunk; });
const near = (actual, expected, message) => assert.ok(Math.abs(actual - expected) < 1, `${message}: ${actual} vs ${expected}`);
function header(snapshot, expanded = false) {
  const sidebar = snapshot.sidebarBounds;
  const row = snapshot.sidebarControls.find(control => control.label === 'header')?.bounds;
  assert.ok(row, 'SwiftUI header must exist');
  near(row.y, sidebar.y + 14, 'Header must stay inside the sidebar, including the title-bar area');
  near(row.height, 28, 'Header must retain its full height');
  near(row.x, sidebar.x + 14, 'Header horizontal inset');
  near(row.width, sidebar.width - 28, 'Header width');
  if (!expanded) {
    assert.equal(snapshot.windowButtons.length, 3, 'All native window controls must remain available');
    assert.ok(snapshot.systemControlsHidden.every(Boolean), 'Normal window uses sidebar controls without duplicates');
    for (const [index, button] of snapshot.windowButtons.entries()) {
      assert.equal(button.hidden, false);
      assert.equal(button.hitTarget, true, 'Traffic-light clicks must reach the actual native button');
      near(button.bounds.y + button.bounds.height / 2, row.y + row.height / 2, 'Traffic lights and navigation must share a center line');
      near(button.bounds.x, sidebar.x + 14 + index * 20, 'Traffic-light spacing');
    }
  }
}
try {
  header(await command(driver, 'snapshot'));
  header(await command(driver, 'relayoutTitlebar'));
  await command(driver, 'window.minimize');
  assert.equal((await command(driver, 'snapshot')).windowMiniaturized, true, 'Yellow native button must minimize the window');
  await command(driver, 'window.restore');
  assert.equal((await command(driver, 'snapshot')).windowMiniaturized, false);
  for (const [size, width] of [['compact', 252], ['comfortable', 288], ['wide', 320]]) {
    await command(driver, 'sidebarSize', { id: size });
    for (const [windowWidth, height] of [[700, 480], [1280, 840], [900, 600]]) {
      const snapshot = await command(driver, 'resize', { width: windowWidth, height });
      header(snapshot);
      near(snapshot.sidebarBounds.width, width, 'Sidebar width preset');
      near(snapshot.pageBounds.x, width + 16, 'Fixed sidebar reserves page space');
    }
  }
  const hidden = await command(driver, 'toggleSidebar');
  assert.equal(hidden.sidebarVisible, false);
  assert.ok(hidden.windowButtons.every(button => button.hidden));
  const floating = await command(driver, 'revealSidebar');
  header(floating);
  header(await command(driver, 'relayoutTitlebar'));
  assert.equal(floating.sidebarVisible, true);
  assert.deepEqual(floating.pageBounds, hidden.pageBounds, 'Revealing the sidebar must not shift the page');
  const full = await command(driver, 'expandedLayout', { expanded: true });
  assert.equal(full.sidebarVisible, false);
  assert.ok(full.windowButtons.every(button => button.hidden), 'Fullscreen sidebar traffic lights stay hidden');
  assert.equal(full.systemControlsHidden.length, 3);
  assert.ok(full.systemControlsHidden.every(hidden => !hidden), 'Native controls belong to the fullscreen top bar');
  assert.deepEqual(full.pageBounds, full.rootBounds, 'Fullscreen page has no padding');
  const fullReveal = await command(driver, 'revealSidebar');
  header(fullReveal, true);
  assert.ok(fullReveal.windowButtons.every(button => button.hidden), 'Revealing the fullscreen sidebar must not show traffic lights');
  await command(driver, 'systemControlsReveal');
  const afterTopHover = await command(driver, 'snapshot');
  assert.ok(afterTopHover.systemControlsHidden.every(hidden => !hidden), 'Top-edge title-bar reveal must retain native traffic lights');
  assert.ok(afterTopHover.windowButtons.every(button => button.hidden));
  near(fullReveal.sidebarBounds.y, 8, 'Fullscreen sidebar matches the bottom inset');
  assert.deepEqual(fullReveal.pageBounds, full.pageBounds, 'Fullscreen reveal must not resize the page');
  header(await command(driver, 'expandedLayout', { expanded: false }));
  await command(driver, 'preferences', { sidebarMode: 'fixed' });
  function nativeControlsOnly(snapshot) {
    assert.ok(snapshot.windowButtons.every(button => button.hidden), 'Sidebar lights must stay hidden throughout the native fullscreen animation');
    assert.ok(snapshot.systemControlsHidden.every(hidden => !hidden), 'Only native controls own the transition');
  }
  for (let cycle = 0; cycle < 2; cycle++) {
    nativeControlsOnly(await command(driver, 'fullscreenPhase', { phase: 'entering' }));
    nativeControlsOnly(await command(driver, 'resize', { width: 1100, height: 750 }));
    nativeControlsOnly(await command(driver, 'fullscreenPhase', { phase: 'entered' }));
    nativeControlsOnly(await command(driver, 'revealSidebar'));
    const leaving = await command(driver, 'fullscreenPhase', { phase: 'exiting' });
    assert.equal(leaving.fullscreenTransitioning, true); nativeControlsOnly(leaving);
    nativeControlsOnly(await command(driver, 'resize', { width: 900, height: 600 }));
    const normal = await command(driver, 'fullscreenPhase', { phase: 'exited' });
    assert.equal(normal.fullscreenTransitioning, false); header(normal);
  }
  await command(driver, 'fullscreenPhase', { phase: 'entering' });
  const failed = await command(driver, 'fullscreenPhase', { phase: 'failedEntering' });
  assert.equal(failed.fullscreenTransitioning, false); header(failed);
  const exited = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Native quit timed out: ' + logs)), 10000);
    app.once('exit', () => { clearTimeout(timer); resolve(); });
  });
  await command(driver, 'quit');
  await exited;
  assert.equal(app.exitCode, 0, logs);
  console.log('PASS: native sidebar header, aligned traffic lights, three widths, minimum-size 12-favorite grid, floating reveal, fullscreen composition, and clean quit.');
} finally {
  if (app.exitCode === null && app.signalCode === null) {
    const exited = new Promise(resolve => app.once('exit', resolve));
    app.kill('SIGTERM');
    await exited;
  }
  await new Promise(resolve => server.close(resolve));
  await rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
}
