import { _electron as electron } from 'playwright';
import { createServer } from 'node:http';
import { mkdtemp, rm } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import assert from 'node:assert/strict';
import { runtime } from '../scripts/runtime.mjs';
const executablePath = await runtime();

// Real native views, using a local server so the check does not rely on public websites.
const server = createServer((req, res) => {
  res.setHeader('Content-Type', 'text/html');
  if (req.url === '/favicon.ico') { res.writeHead(404).end(); return; }
  res.end(`<!doctype html><title>${req.url === '/two' ? 'Second page' : 'A real Chromium page'}</title><style>body{font:18px system-ui;padding:60px;background:#faf7f2;color:#453f4d}textarea{display:block;margin:25px 0;width:300px;height:80px}</style><h1>${req.url === '/two' ? 'A second place' : 'Hello from Chromium'}</h1><textarea placeholder="State stays here"></textarea><a href="/two">Next page</a>`);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const address = `http://127.0.0.1:${server.address().port}`;
const userData = await mkdtemp(join(tmpdir(), 'derivative-electron-'));
let application;
let chrome;
const env = { ...process.env, DERIVATIVE_USER_DATA: userData };
delete env.ELECTRON_RUN_AS_NODE;
delete env.ELECTRON_RENDERER_URL;
async function launch() {
  const app = await electron.launch({ executablePath, args: [resolve('.')], env, timeout: 30000 });
  application = app;
  app.on('console', msg => console.log(`[electron] ${msg.text()}`));
  await app.firstWindow();
  // Tests inject input into web contents; exclude unrelated physical pointer events.
  await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setIgnoreMouseEvents(true));
  await waitFor(() => app.context().pages().some(page => page.url().includes('chrome=1')) && app.context().pages().some(page => page.url().includes('index.html') && !page.url().includes('chrome=1')), 'Chrome UI did not load');
  chrome = app.context().pages().find(page => page.url().includes('chrome=1'));
  await app.context().route('**/favicon.ico', route => route.abort());
  const ui = app.context().pages().find(page => page.url().includes('index.html') && !page.url().includes('chrome=1'));
  await ui.waitForFunction(() => !!window.browser);
  ui.on('pageerror', error => console.error(`[renderer] ${error.message}`));
  await ui.getByRole('heading', { name: 'New tab', exact: true }).waitFor();
  return { app, ui };
}
async function waitFor(predicate, message) {
  const end = Date.now() + 12000;
  while (Date.now() < end) { if (await predicate()) return; await new Promise(resolve => setTimeout(resolve, 80)); }
  throw new Error(message);
}
const getState = ui => ui.evaluate(() => window.browser.getState());
const send = (ui, action) => ui.evaluate(action => window.browser.dispatch(action), action);
const native = app => app.evaluate(({ BrowserWindow }) => {
  const win = BrowserWindow.getAllWindows()[0];
  const children = win.contentView.children.filter(v => 'webContents' in v && v.webContents.id !== win.webContents.id && !v.webContents.getURL().includes('chrome=1'));
  return children.map(v => ({ id: v.webContents.id, url: v.webContents.getURL(), bounds: v.getBounds() }));
});
try {
  const first = await launch(); application = first.app; const ui = first.ui;
  if (process.platform === 'darwin') assert.deepEqual(await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].getWindowButtonPosition()), { x:20, y:20 });
  if (process.platform === 'darwin') {
    await application.evaluate(({ BrowserWindow }) => {
      const win = BrowserWindow.getAllWindows()[0];
      globalThis.originalVisibility = win.setWindowButtonVisibility;
      win.setWindowButtonVisibility = visible => {
        globalThis.originalVisibility.call(win, visible);
        // Reproduce AppKit snapping the controls back when visibility changes.
        if (visible) win.setWindowButtonPosition({ x:12, y:11 });
      };
    });
    try {
      for (let i=0; i<3; i++) {
        await send(ui, { type:'preferences', preferences:{ sidebarMode:'hidden' } });
        await send(ui, { type:'preferences', preferences:{ sidebarMode:'fixed' } });
        assert.deepEqual(await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].getWindowButtonPosition()), { x:20, y:20 }, 'Showing the controls must restore sidebar alignment after a native position reset');
      }
    } finally {
      await application.evaluate(({ BrowserWindow }) => { BrowserWindow.getAllWindows()[0].setWindowButtonVisibility = globalThis.originalVisibility; });
    }
  }
  // The native traffic lights stay at x=20,y=20; reserve their row before the toggle.
  for (const sidebarSize of ['compact', 'comfortable', 'wide']) {
    await send(ui, { type:'preferences', preferences:{ sidebarSize } });
    const row = await ui.locator('.sidebar-navigation').evaluate(el => {
      const toggle = el.querySelector('.sidebar-toggle').getBoundingClientRect();
      const nav = el.querySelector('.nav-pair').getBoundingClientRect();
      return { toggleX:toggle.x, centerY:toggle.y+toggle.height/2, toggleRight:toggle.right, navX:nav.x };
    });
    assert.equal(row.toggleX, 92, 'Toggle must sit to the right of native traffic lights');
    assert.equal(row.centerY, 27, 'Toggle must align with the traffic-light row');
    assert.ok(row.toggleRight < row.navX, 'Navigation controls must not overlap at any sidebar width');
  }
  await send(ui, { type:'preferences', preferences:{ sidebarSize:'comfortable' } });
  await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].emit('enter-full-screen'));
  await waitFor(async () => (await getState(ui)).windowExpanded, 'Expanded state not received');
  assert.deepEqual(await ui.locator('.webpage-frame').evaluate(el => {
    const r = el.getBoundingClientRect(); return { x:r.x, y:r.y, width:r.width, height:r.height, viewport:[innerWidth, innerHeight], radius:getComputedStyle(el).borderRadius, padding:getComputedStyle(el.parentElement).padding };
  }), await ui.evaluate(() => ({ x:0, y:0, width:innerWidth, height:innerHeight, viewport:[innerWidth, innerHeight], radius:'0px', padding:'0px' })));
  await send(ui, { type: 'navigate', input: address, newTab: false });
  await waitFor(async () => (await native(application)).length === 1, 'Website view not attached');
  const size = await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].getContentSize());
  const bounds = { x:0, y:0, width:size[0], height:size[1] };
  assert.deepEqual((await native(application))[0].bounds, bounds);
  const pageId = (await native(application))[0].id;
  const moveOnPage = x => application.evaluate(({ webContents }, { id, x }) => webContents.fromId(id).sendInputEvent({ type:'mouseMove', x, y:220 }), { id:pageId, x });
  await moveOnPage(100);
  assert.equal((await getState(ui)).sidebarRevealed, false, 'Page content should not reveal the sidebar');
  await moveOnPage(2);
  await waitFor(async () => (await getState(ui)).sidebarRevealed, 'Sidebar did not reveal');
  assert.deepEqual((await native(application))[0].bounds, bounds);
  await chrome.getByRole('button', { name:'Keep sidebar open', exact:true }).waitFor();
  await chrome.evaluate(async()=>{await new Promise(requestAnimationFrame);await Promise.all(document.getAnimations().filter(a=>a.effect?.getTiming().iterations!==Infinity).map(a=>a.finished.catch(()=>{})));});
  assert.deepEqual(await chrome.locator('.floating-sidebar').evaluate(el=>{const box=el.getBoundingClientRect();return {x:box.x,y:box.y,height:box.height,viewport:innerHeight,width:box.width,radius:getComputedStyle(el).borderRadius};}), {x:8,y:0,height:bounds.height-8,viewport:bounds.height,width:288,radius:'14px'}, 'Expanded sidebar must reach the top while retaining side/bottom spacing, corner radius, and width');
  await moveOnPage(100);
  await new Promise(resolve => setTimeout(resolve, 280));
  assert.equal((await getState(ui)).sidebarRevealed, true, 'Crossing events inside the sidebar must not dismiss it');
  await moveOnPage(500);
  await waitFor(async () => !(await getState(ui)).sidebarRevealed, 'Leaving the sidebar must dismiss it');
  await new Promise(resolve => setTimeout(resolve, 220));
  await moveOnPage(2);
  await waitFor(async () => (await getState(ui)).sidebarRevealed, 'Native webpage edge must reopen sidebar');
  assert.deepEqual((await native(application))[0].bounds, bounds);
  await send(ui, { type:'sidebar.toggle' });
  await send(ui, { type:'preferences', preferences:{ sidebarSize:'wide' } });
  assert.deepEqual((await native(application))[0].bounds, bounds);
  await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].emit('leave-full-screen'));
  await waitFor(async () => !(await getState(ui)).windowExpanded, 'Normal state not restored');
  assert.equal((await native(application))[0].bounds.x, 336);
  assert.equal((await native(application))[0].bounds.y, 8);
  console.log('PASS: native webpage edge reveal, dismissal/reopen, edge-to-edge page and New Tab, pinned/resized sidebar, normal-window restoration.');
} finally {
  if (application) await application.close();
  await new Promise(resolve => server.close(resolve));
  await rm(userData, { recursive: true, force: true });
}
