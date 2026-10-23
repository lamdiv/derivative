import { _electron as electron } from 'playwright';
import { createServer } from 'node:http';
import { mkdtemp, mkdir, readFile, rm } from 'node:fs/promises';
import { join, resolve, dirname } from 'node:path';
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
await mkdir('test-results', { recursive: true });
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
const shortcut = (app, key, id, modifiers = ['meta']) => app.evaluate(({ BrowserWindow, webContents }, { key, id, modifiers }) => {
  const win = BrowserWindow.getAllWindows()[0];
  win.focus();
  const wc = id ? webContents.fromId(id) : win.webContents;
  wc.focus();
  wc.sendInputEvent({ type: 'keyDown', keyCode: key, modifiers });
  wc.sendInputEvent({ type: 'keyUp', keyCode: key, modifiers });
}, { key, id, modifiers });
const settleVisuals = ui => ui.evaluate(async () => { await new Promise(requestAnimationFrame); await Promise.all(document.getAnimations().filter(a => a.effect?.getTiming().iterations !== Infinity).map(a => a.finished.catch(() => {}))); });
const native = app => app.evaluate(({ BrowserWindow }) => {
  const win = BrowserWindow.getAllWindows()[0];
  const children = win.contentView.children.filter(v => 'webContents' in v && v.webContents.id !== win.webContents.id && !v.webContents.getURL().includes('chrome=1'));
  return children.map(v => ({ id: v.webContents.id, url: v.webContents.getURL(), bounds: v.getBounds() }));
});
try {
  const first = await launch(); application = first.app; let ui = first.ui;
  await send(ui, { type: 'preferences', preferences: { theme: 'light' } });
  await settleVisuals(ui);
  await ui.screenshot({ path: 'test-results/home-light.png' });
  if (process.platform === 'darwin') {
    const plist = await readFile(join(dirname(dirname(executablePath)), 'Info.plist'), 'utf8');
    assert.match(plist, /<key>CFBundleDisplayName<\/key>\s*<string>Derivative<\/string>/);
    assert.equal(await application.evaluate(({ app }) => app.getName()), 'Derivative');
  }
  const favoriteGeometry = await ui.locator('.favorite').evaluateAll(tiles => tiles.map(tile => {
    const rect = tile.getBoundingClientRect(), icon = tile.querySelector('.favicon').getBoundingClientRect();
    return { x: rect.x, y: rect.y, width: rect.width, height: rect.height, iconWidth: icon.width, iconHeight: icon.height };
  }));
  assert.equal(favoriteGeometry.length, 9);
  assert.equal(new Set(favoriteGeometry.map(tile => tile.x)).size, 3);
  assert.equal(new Set(favoriteGeometry.map(tile => tile.y)).size, 3);
  assert.ok(favoriteGeometry.every(tile => tile.width === favoriteGeometry[0].width && tile.height === 48 && tile.iconWidth === 20 && tile.iconHeight === 20));
  for (let i = 10; i <= 12; i++) {
    await ui.getByRole('button', { name: 'Add favorite', exact: true }).click();
    await ui.getByRole('textbox', { name: 'Favorite name', exact: true }).fill(`Local ${i}`);
    await ui.getByRole('textbox', { name: 'Favorite URL', exact: true }).fill(`${address}/favorite-${i}`);
    await ui.getByRole('button', { name: 'Save favorite', exact: true }).click();
    await waitFor(async () => (await getState(ui)).favorites.length === i, 'Adding favorite failed');
  }
  await waitFor(async () => ui.getByRole('button', { name: 'Add favorite', exact: true }).isDisabled(), 'Full favorites grid must disable adding another tile');
  await send(ui, { type: 'favorite.save', name: 'Over capacity', url: `${address}/overflow` });
  assert.equal((await getState(ui)).favorites.length, 12);
  await ui.getByRole('button', { name: 'Done editing favorites', exact: true }).click();
  await waitFor(async () => await ui.locator('.favorite').count() === 12, 'Twelve favorites did not render');
  assert.equal(await ui.locator('.favorite').evaluateAll(tiles => new Set(tiles.map(tile => tile.getBoundingClientRect().y)).size), 4);
  await ui.screenshot({ path: 'test-results/favorites-twelve.png' });
  await ui.getByRole('button', { name: 'Edit favorites', exact: true }).click();
  await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setSize(900, 480));
  await waitFor(async () => await ui.evaluate(() => innerHeight) === 480, 'Short window viewport did not resize');
  const shortFooter = await ui.getByRole('button', { name: 'Sidebar size', exact: true }).evaluate(el => ({ bottom: el.getBoundingClientRect().bottom, viewport: innerHeight }));
  assert.ok(shortFooter.bottom <= shortFooter.viewport - 8, 'Three-dot control must remain inside a short window with twelve favorites');
  await ui.getByRole('button', { name: 'Sidebar size', exact: true }).click();
  await ui.getByRole('menu', { name: 'Sidebar size', exact: true }).waitFor({ state: 'visible' });
  await ui.getByRole('menuitemradio', { name: /Comfortable/ }).click();
  await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setSize(1280, 840));
  await waitFor(async () => await ui.evaluate(() => innerHeight) === 840, 'Normal viewport did not restore after short-window menu check');

  await ui.getByRole('button', { name: 'Edit favorites', exact: true }).click();
  await ui.getByTitle('Edit Local 10', { exact: true }).click();
  await ui.getByRole('textbox', { name: 'Favorite name', exact: true }).fill('Local renamed');
  await ui.getByRole('button', { name: 'Save favorite', exact: true }).click();
  await waitFor(async () => (await getState(ui)).favorites.some(f => f.name === 'Local renamed'), 'Renaming favorite failed');
  for (const name of ['Local renamed', 'Local 11', 'Local 12']) await ui.getByRole('button', { name: `Remove favorite ${name}`, exact: true }).click();
  await ui.getByRole('button', { name: 'Done editing favorites', exact: true }).click();
  assert.equal((await getState(ui)).favorites.length, 9);
  for (const [label, width] of [['Compact', 252], ['Wide', 320], ['Comfortable', 288]]) {
    await ui.getByRole('button', { name: 'Sidebar size', exact: true }).click();
    await ui.getByRole('menuitemradio', { name: new RegExp(label) }).click();
    await waitFor(async () => await ui.locator('.sidebar').evaluate(el => el.getBoundingClientRect().width) === width, 'Sidebar width choice did not apply');
    assert.equal(await ui.locator('.webpage-frame').evaluate(el => el.getBoundingClientRect().x), width + 16);
  }

  await shortcut(application, 't');
  assert.equal((await getState(ui)).overlay,null,'An empty Space already has its search field');
  await ui.getByRole('combobox').waitFor();
  assert.equal((await getState(ui)).tabs.length, 0, 'Cmd+T must wait for confirmation before creating a tab');
  assert.equal((await native(application)).length, 0);
  assert.equal(await ui.getByRole('combobox').evaluate(el => el === document.activeElement), true);
  await send(ui, { type:'preferences', preferences:{ searchEngine:'duckduckgo' } });
  await ui.getByRole('combobox').fill('a quiet morning');
  await ui.getByRole('option').filter({ hasText:'DuckDuckGo' }).waitFor();
  await ui.getByRole('combobox').fill(address);
  await settleVisuals(ui);
  await ui.screenshot({ path:'test-results/new-tab-light.png' });
  await ui.getByRole('combobox').press('Enter');
  await waitFor(async () => (await getState(ui)).tabs[0]?.title === 'A real Chromium page', 'Local website did not load');
  assert.equal((await getState(ui)).tabs.length,1);
  let views = await native(application);
  assert.equal(views.length, 1);
  assert.equal(views[0].bounds.x, 304);
  assert.equal(views[0].bounds.y, 8, 'Native webpage must align with the inset canvas');
  let firstNativeId = views[0].id;
  const firstTabId = (await getState(ui)).activeTabId;
  for (const [size, inset] of [['compact', 268], ['wide', 336], ['comfortable', 304]]) {
    await send(ui, { type: 'preferences', preferences: { sidebarSize: size } });
    assert.equal((await native(application))[0].bounds.x, inset);
    assert.equal((await native(application))[0].id, firstNativeId, 'Width changes must preserve the live webpage');
  }
  await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].maximize());
  await waitFor(async () => (await getState(ui)).windowExpanded, 'Maximize did not update sidebar state');
  assert.equal((await native(application))[0].bounds.x, 0, 'Maximize must fill the window without a frame');
  assert.equal(await chrome.getByRole('button', { name: 'Show sidebar', exact: true }).count(), 0, 'Expanded mode should not overlay a separate toggle on the webpage');
  await application.evaluate(({ webContents }, id) => webContents.fromId(id).sendInputEvent({ type: 'mouseMove', x: 2, y: 220 }), firstNativeId);
  await waitFor(async () => (await getState(ui)).sidebarRevealed, 'Maximized edge hover did not reveal sidebar');
  await chrome.getByRole('button', { name: 'Keep sidebar open', exact: true }).waitFor({ state: 'visible' });
  await settleVisuals(chrome);
  const controls = await chrome.locator('.sidebar-navigation').evaluate(el => [...el.querySelectorAll('button')].map(button => ({ label: button.getAttribute('aria-label'), x: button.getBoundingClientRect().x })));
  assert.deepEqual(controls.map(control => control.label), ['Keep sidebar open', 'Go back', 'Go forward', 'Reload page']);
  assert.ok(controls.every((control, i) => i === 0 || control.x > controls[i - 1].x), 'Sidebar toggle must be on the left, followed by back/forward/reload on the right');
  assert.equal(await chrome.locator('.sidebar-navigation').evaluate(el => el.getBoundingClientRect().y), 16, 'Expanded sidebar must not reserve an empty traffic-light header row');
  for (let attempt = 0; attempt < 3; attempt++) {
    await chrome.getByRole('button', { name: 'Sidebar size', exact: true }).click();
    await chrome.getByRole('menu', { name: 'Sidebar size', exact: true }).waitFor({ state: 'visible' });
    await application.evaluate(({ webContents }, id) => webContents.fromId(id).sendInputEvent({ type: 'mouseMove', x: 400, y: 200 }), firstNativeId);
    await new Promise(resolve => setTimeout(resolve, 280));
    assert.equal((await getState(ui)).sidebarRevealed, true, 'Size menu interaction must prevent automatic sidebar dismissal');
    assert.equal(await chrome.getByRole('menu', { name: 'Sidebar size', exact: true }).isVisible(), true);
    await application.evaluate(({ webContents }) => webContents.getAllWebContents().find(wc => wc.getURL().includes('chrome=1')).sendInputEvent({ type: 'mouseMove', x: 100, y: 220 }));
    await chrome.getByRole('menuitemradio', { name: /Comfortable/ }).click();
    await chrome.getByRole('menu', { name: 'Sidebar size', exact: true }).waitFor({ state: 'hidden' });
  }
  await chrome.getByRole('button', { name: 'Sidebar size', exact: true }).click();
  await chrome.getByRole('menu', { name: 'Sidebar size', exact: true }).waitFor();
  await chrome.getByRole('button', { name: 'Sidebar size', exact: true }).press('Escape');
  await chrome.getByRole('menu', { name: 'Sidebar size', exact: true }).waitFor({ state: 'hidden' });
  assert.equal((await getState(ui)).sidebarRevealed, true, 'Escape should dismiss the menu before dismissing its sidebar');

  assert.equal((await native(application))[0].bounds.x, 0, 'Hover reveal must leave full-page bounds unchanged');
  const expandedBounds = (await native(application))[0].bounds;
  const expandedSize = await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].getContentSize());
  assert.deepEqual(expandedBounds, { x: 0, y: 0, width: expandedSize[0], height: expandedSize[1] }, 'Expanded webpage must fill the entire window');
  assert.deepEqual(await ui.locator('.webpage-frame').evaluate(el => ({ radius: getComputedStyle(el).borderRadius, padding: getComputedStyle(el.parentElement).padding })), { radius: '0px', padding: '0px' });
  const expandedViewport = await application.evaluate(({ webContents }, id) => webContents.fromId(id).executeJavaScript('[innerWidth, innerHeight]'), firstNativeId);
  await chrome.getByRole('button', { name: 'Keep sidebar open', exact: true }).click();
  await waitFor(async () => (await getState(ui)).expandedSidebarMode === 'fixed', 'Sidebar top-left toggle did not keep the slider open');
  await chrome.getByRole('button', { name: 'Hide sidebar', exact: true }).waitFor({ state: 'visible' });
  assert.deepEqual((await native(application))[0].bounds, expandedBounds, 'Keeping the expanded sidebar open must not shrink the webpage');
  assert.deepEqual(await application.evaluate(({ webContents }, id) => webContents.fromId(id).executeJavaScript('[innerWidth, innerHeight]'), firstNativeId), expandedViewport);
  assert.equal(await ui.locator('.sidebar').count(), 0, 'Expanded sidebar must remain in the native overlay, outside the page layout');
  for (const size of ['wide', 'comfortable']) {
    await send(ui, { type: 'preferences', preferences: { sidebarSize: size } });
    assert.deepEqual((await native(application))[0].bounds, expandedBounds, 'Slider width choices must not resize the full-page canvas');
  }
  await chrome.getByRole('button', { name: 'Hide sidebar', exact: true }).click();
  await waitFor(async () => (await getState(ui)).expandedSidebarMode === 'hover', 'Unpinning did not restore automatic slider hiding');
  assert.deepEqual((await native(application))[0].bounds, expandedBounds);

  await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].unmaximize());
  await waitFor(async () => !(await getState(ui)).windowExpanded, 'Unmaximize did not restore normal window mode');
  assert.equal((await getState(ui)).preferences.sidebarMode, 'fixed');
  assert.equal((await native(application))[0].bounds.x, 304);
  for (let attempt = 0; attempt < 3; attempt++) {
    await ui.getByRole('button', { name: 'Sidebar size', exact: true }).click();
    await ui.getByRole('menu', { name: 'Sidebar size', exact: true }).waitFor({ state: 'visible' });
    await ui.locator('.sidebar-navigation').click({ position: { x: 100, y: 15 } });
    await ui.getByRole('menu', { name: 'Sidebar size', exact: true }).waitFor({ state: 'hidden' });
  }

  // Check native button policy independently of the host's ability to enter a fullscreen Space.
  if (process.platform === 'darwin') {
    await send(ui, { type: 'preferences', preferences: { sidebarMode: 'hidden' } });
    const buttonPolicyBounds = (await native(application))[0].bounds;
    await application.evaluate(({ BrowserWindow }) => {
      const win = BrowserWindow.getAllWindows()[0];
      globalThis.originalFullScreenCheck = win.isFullScreen;
      globalThis.originalButtonSetter = win.setWindowButtonVisibility;
      globalThis.nativeButtonChanges = [];
      win.isFullScreen = () => true;
      win.setWindowButtonVisibility = visible => { globalThis.nativeButtonChanges.push(visible); globalThis.originalButtonSetter.call(win, visible); };
    });
    try {
      await send(ui, { type: 'preferences', preferences: { theme: 'light' } });
      assert.equal(await application.evaluate(() => globalThis.nativeButtonChanges.at(-1)), true, 'Native fullscreen traffic lights must remain enabled independently of sidebar visibility');
      assert.deepEqual((await native(application))[0].bounds, buttonPolicyBounds, 'Restoring native traffic lights must not reserve webpage space');
      await send(ui, { type: 'preferences', preferences: { searchEngine: 'duckduckgo' } });
      assert.equal(await application.evaluate(() => globalThis.nativeButtonChanges.filter(value => value === false).length), 0, 'Routine updates must not hide fullscreen traffic lights again');
    } finally {
      await application.evaluate(({ BrowserWindow }) => { const win = BrowserWindow.getAllWindows()[0]; win.isFullScreen = globalThis.originalFullScreenCheck; win.setWindowButtonVisibility = globalThis.originalButtonSetter; });
      await send(ui, { type: 'preferences', preferences: { sidebarMode: 'fixed' } });
    }
  }

  // Allow the native zoom restoration to finish before requesting a different Cocoa transition.
  await new Promise(resolve => setTimeout(resolve, 300));
  await application.evaluate(({ app, BrowserWindow }) => { app.focus({ steal: true }); const win = BrowserWindow.getAllWindows()[0]; win.focus(); win.setFullScreen(true); });
  const enteredFullScreen = await waitFor(async () => (await getState(ui)).windowExpanded && await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].isFullScreen()), 'Native full-screen transition did not hide the sidebar').then(() => true).catch(async error => {
    if (await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].isFullScreen())) throw error;
    console.log('SKIP: host refused native fullscreen entry; expanded-layout/header/menu assertions passed in maximized mode.');
    return false;
  });
  if (enteredFullScreen) {

  assert.equal((await native(application))[0].bounds.x, 0);
  await application.evaluate(({ webContents }, id) => webContents.fromId(id).sendInputEvent({ type: 'mouseMove', x: 2, y: 220 }), firstNativeId);
  await waitFor(async () => (await getState(ui)).sidebarRevealed, 'Full-screen edge hover did not reveal sidebar');
  await chrome.getByRole('button', { name: 'Keep sidebar open', exact: true }).waitFor({ state: 'visible' });
  assert.equal((await native(application))[0].id, firstNativeId);
  const fullScreenBounds = (await native(application))[0].bounds;
  assert.equal(fullScreenBounds.x, 0);
  await chrome.getByRole('button', { name: 'Keep sidebar open', exact: true }).click();
  await waitFor(async () => (await getState(ui)).expandedSidebarMode === 'fixed', 'Full-screen slider did not stay open');
  assert.deepEqual((await native(application))[0].bounds, fullScreenBounds, 'Full-screen pinning must preserve the full webpage');
  await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setFullScreen(false));
  await waitFor(async () => !(await getState(ui)).windowExpanded, 'Leaving full screen did not restore normal sidebar mode');
  await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setSize(1280, 840));
  await waitFor(async () => (await native(application))[0].bounds.width === 968, 'Normal window layout did not restore after full screen');

  }

  // Exercise shortcuts while the actual untrusted native webpage has keyboard focus.
  const page = await application.evaluate(({ webContents }, id) => webContents.fromId(id).executeJavaScript(`document.querySelector('textarea').value='my unsaved thought'; localStorage.setItem('session-check','retained'); document.cookie='derivative_session=retained; Max-Age=86400; Path=/; SameSite=Lax'; typeof window.browser + ':' + typeof require`), firstNativeId);
  assert.equal(page, 'undefined:undefined', 'Websites must not receive the privileged bridge or Node');
  await shortcut(application, 't', firstNativeId);
  await chrome.getByRole('combobox').waitFor();
  await chrome.getByRole('combobox').fill(`${address}/two`);
  await chrome.getByRole('combobox').press('Enter');
  await waitFor(async () => (await getState(ui)).tabs.some(t => t.title === 'Second page'), 'Second tab did not load');
  const secondTabId = (await getState(ui)).activeTabId;
  const secondNativeId = (await native(application))[0].id;
  await ui.getByRole('button', { name:'New tab ⌘ T', exact:true }).click();
  await chrome.getByRole('combobox').waitFor();
  assert.equal((await getState(ui)).tabs.length,2, 'Sidebar New Tab must wait for confirmation');
  assert.equal((await getState(ui)).activeTabId,secondTabId);
  await send(ui,{type:'preferences', preferences:{theme:'dark'}});
  await settleVisuals(chrome);
  await chrome.screenshot({path:'test-results/new-tab-dark.png'});
  await chrome.getByRole('combobox').press('Escape');
  assert.equal((await native(application))[0].id,secondNativeId);
  await send(ui,{type:'preferences',preferences:{theme:'light'}});

  // Exercise actual HTML drag gestures inside the trusted sidebar.
  async function drag(source, target) {
    await application.evaluate(({ BrowserWindow }) => { const win = BrowserWindow.getAllWindows()[0]; win.focus(); win.webContents.focus(); });
    await source.waitFor({ state: 'visible' });
    await settleVisuals(ui);
    await source.dragTo(target);
    await settleVisuals(ui);
  }
  await ui.getByRole('button', { name: 'New folder', exact: true }).click();
  await ui.getByRole('textbox', { name: 'Folder name', exact: true }).fill('Research');
  await ui.getByRole('textbox', { name: 'Folder name', exact: true }).press('Enter');
  await waitFor(async () => (await getState(ui)).folders.some(f => f.name === 'Research'), 'Folder creation failed');
  const folderId = (await getState(ui)).folders.find(f => f.name === 'Research').id;
  const folder = ui.locator(`[data-folder-id="${folderId}"]`);
  await drag(ui.locator(`[data-tab-id="${firstTabId}"]`), folder.locator('.folder-row'));
  await waitFor(async () => (await getState(ui)).tabs.find(t => t.id === firstTabId).folderId === folderId, 'Dragging into a folder failed');
  assert.equal((await getState(ui)).tabs.find(t => t.id === firstTabId).pinned, true);
  await settleVisuals(ui);
  await ui.screenshot({ path: 'test-results/folder-expanded.png' });
  await drag(ui.locator(`[data-tab-id="${secondTabId}"]`), ui.getByRole('region', { name: 'Pinned tabs', exact: true }).locator('.section-label'));
  await waitFor(async () => (await getState(ui)).tabs.find(t => t.id === secondTabId).pinned, 'Dragging into the pinned area failed');
  await drag(ui.locator(`[data-tab-id="${firstTabId}"]`), ui.getByRole('button', { name: 'New tab ⌘ T', exact: true }));
  await waitFor(async () => !(await getState(ui)).tabs.find(t => t.id === firstTabId).pinned, 'Dragging out of a folder failed');
  await drag(ui.locator(`[data-tab-id="${secondTabId}"]`), ui.getByRole('button', { name: 'New tab ⌘ T', exact: true }));
  await waitFor(async () => !(await getState(ui)).tabs.find(t => t.id === secondTabId).pinned, 'Dragging out of pinned area failed');
  await ui.getByRole('button', { name: 'New folder', exact: true }).click();
  await ui.getByRole('textbox', { name: 'Folder name', exact: true }).fill('Later');
  await ui.getByRole('textbox', { name: 'Folder name', exact: true }).press('Enter');
  await waitFor(async () => (await getState(ui)).folders.length === 2, 'Second folder was not created');
  const laterId = (await getState(ui)).folders.find(f => f.name === 'Later').id;
  await drag(ui.locator(`[data-folder-id="${laterId}"] .folder-row`), folder.locator('.folder-row'));
  await waitFor(async () => (await getState(ui)).folders[0].id === laterId, 'Folder drag reordering failed');
  await ui.getByRole('button', { name: 'Options for folder Research', exact: true }).click();
  await ui.getByRole('menuitem', { name: 'Rename folder', exact: true }).click();
  await ui.getByRole('textbox', { name: 'Rename folder', exact: true }).fill('Reading');
  await ui.getByRole('textbox', { name: 'Rename folder', exact: true }).press('Enter');
  await ui.getByRole('button', { name: 'Collapse folder Reading', exact: true }).waitFor();
  await ui.getByRole('button', { name: 'Options for folder Later', exact: true }).click();
  await ui.getByRole('menuitem', { name: 'Remove folder, keep tabs', exact: true }).click();
  await waitFor(async () => (await getState(ui)).folders.length === 1, 'Folder removal failed');
  await drag(ui.locator('[data-space-id="study"]'), ui.locator('[data-space-id="personal"]'));
  await waitFor(async () => (await getState(ui)).spaces[0].id === 'study', 'Space icon reordering failed');
  await drag(ui.locator('[data-space-id="personal"]'), ui.locator('[data-space-id="study"]'));
  await waitFor(async () => (await getState(ui)).spaces[0].id === 'personal', 'Personal Space did not move back to the first position');
  await drag(ui.locator('[data-space-id="work"]'), ui.locator('[data-space-id="study"]'));
  await waitFor(async () => (await getState(ui)).spaces.map(s => s.id).join() === 'personal,work,study', 'Space ordering did not restore');
  const iconGeometry = await ui.locator('.sidebar').evaluate(sidebar => {
    const sidebarRect = sidebar.getBoundingClientRect();
    const icons = [...sidebar.querySelectorAll('.space-button')].map(el => {
      const r = el.getBoundingClientRect(); const svg = el.querySelector('svg').getBoundingClientRect();
      return { x: r.x, y: r.y, width: r.width, height: r.height, svgWidth: svg.width, svgHeight: svg.height, centerX: svg.x + svg.width / 2 - r.x, centerY: svg.y + svg.height / 2 - r.y };
    });
    return { center: sidebarRect.x + sidebarRect.width / 2, icons };
  });
  for (const icon of iconGeometry.icons) {
    assert.equal(icon.width, 32); assert.equal(icon.height, 32); assert.equal(icon.svgWidth, 18); assert.equal(icon.svgHeight, 18);
    assert.equal(icon.centerX, 16); assert.equal(icon.centerY, 16);
  }
  assert.ok(Math.abs((iconGeometry.icons[0].x + iconGeometry.icons.at(-1).x + 32) / 2 - iconGeometry.center) < 1, 'Space icons must center on the whole sidebar');
  await drag(ui.locator(`[data-tab-id="${firstTabId}"]`), ui.locator('[data-space-id="work"]'));
  await waitFor(async () => (await getState(ui)).tabs.find(t => t.id === firstTabId).spaceId === 'work', 'Dragging tab to another Space failed');
  await ui.getByRole('button', { name: 'Switch to Work Space', exact: true }).click();
  await ui.getByTitle('Current Space: Work', { exact: true }).waitFor();
  assert.notEqual((await native(application))[0].id, firstNativeId, 'Moving across Spaces must load the destination profile');
  assert.equal((await getState(ui)).tabs.find(t => t.id === firstTabId).profileId, 'work');
  await drag(ui.locator(`[data-tab-id="${firstTabId}"]`), ui.locator('[data-space-id="personal"]'));
  await waitFor(async () => (await getState(ui)).activeSpaceId === 'personal', 'Moving active tab back should follow its Space');
  firstNativeId = (await native(application))[0].id;
  await waitFor(async () => (await getState(ui)).tabs.find(t => t.id === firstTabId)?.loading === false, 'Moved tab did not reload in Personal');
  await application.evaluate(({ webContents }, id) => webContents.fromId(id).executeJavaScript(`document.querySelector('textarea').value='my unsaved thought'`), firstNativeId);
  await drag(ui.locator(`[data-tab-id="${firstTabId}"]`), ui.getByRole('button', { name: 'New tab ⌘ T', exact: true }));
  await waitFor(async () => !(await getState(ui)).tabs.find(t => t.id === firstTabId).pinned, 'Tab did not return to regular tabs');

  await send(ui, { type: 'tab.select', id: firstTabId });
  views = await native(application);
  assert.equal(views[0].id, firstNativeId, 'Switching must reuse the native view');
  assert.equal(await application.evaluate(({ webContents }, id) => webContents.fromId(id).executeJavaScript(`document.querySelector('textarea').value`), firstNativeId), 'my unsaved thought');
  await ui.screenshot({ path: 'test-results/native-page.png' });
  await shortcut(application, 'l', firstNativeId);
  await chrome.getByRole('combobox').waitFor();
  assert.equal(await chrome.getByRole('combobox').inputValue(), `${address}/`);
  assert.equal((await native(application)).length, 1, 'Palette must preserve the live native page');
  assert.deepEqual((await native(application))[0].bounds, views[0].bounds, 'Opening a popup must not reflow the webpage');
  const modalNative = await application.evaluate(({ BrowserWindow }) => {
    const win = BrowserWindow.getAllWindows()[0];
    const last = win.contentView.children.at(-1);
    return { url: last.webContents.getURL(), bounds: last.getBounds() };
  });
  assert.ok(modalNative.url.includes('chrome=1'), 'Trusted popup must be above the live website');
  assert.equal(modalNative.bounds.width, 1280);
  await settleVisuals(chrome);
  await chrome.getByRole('combobox').press('Escape');
  await waitFor(async () => application.evaluate(({ BrowserWindow }) => !BrowserWindow.getAllWindows()[0].contentView.children.some(v => 'webContents' in v && v.webContents.getURL().includes('chrome=1'))), 'Closing popup left an invisible native input layer');
  assert.equal(await application.evaluate(({ webContents }, id) => webContents.fromId(id).executeJavaScript(`document.querySelector('textarea').value`), firstNativeId), 'my unsaved thought');
  assert.equal((await native(application))[0].id, firstNativeId);
  // Rapidly reopening must cancel the previous native detach timer.
  await send(ui, { type: 'palette', mode: 'new' });
  await send(ui, { type: 'overlay.close' });
  await send(ui, { type: 'palette', mode: 'new' });
  await chrome.getByRole('combobox').waitFor();
  await new Promise(resolve => setTimeout(resolve, 220));
  assert.equal(await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].contentView.children.at(-1).webContents.getURL().includes('chrome=1')), true, 'Stale close timer detached a reopened popup');
  assert.equal((await native(application))[0].id, firstNativeId);
  await send(ui, { type: 'overlay.close' });
  await chrome.getByRole('combobox').waitFor({ state: 'hidden' });
  // Keep the host's physical pointer from competing with scripted native hover events.
  await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setIgnoreMouseEvents(true));
  await shortcut(application, 's', firstNativeId);
  assert.equal((await getState(ui)).preferences.sidebarMode, 'hover');
  assert.equal((await native(application))[0].bounds.x, 8);
  assert.equal((await native(application))[0].bounds.y, 8);
  // Native events on the thin UI edge reveal the sidebar; webpage-native events hide it.
  await ui.getByRole('button', { name: 'Reveal sidebar', exact: true }).waitFor();
  await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].webContents.sendInputEvent({ type: 'mouseMove', x: 2, y: 220 }));
  await waitFor(async () => (await getState(ui)).sidebarRevealed, 'Hover edge did not reveal sidebar');
  assert.equal((await native(application))[0].bounds.x, 8, 'Hover reveal must not resize the webpage');
  await chrome.getByRole('button', { name: 'Keep sidebar open', exact: true }).waitFor();
  await settleVisuals(chrome);
  const floatingGeometry = await chrome.locator('.floating-sidebar').evaluate(el => {
    const rect = el.getBoundingClientRect();
    return { x: rect.x, y: rect.y, width: rect.width, height: rect.height, viewportHeight: innerHeight, radius: getComputedStyle(el).borderRadius };
  });
  assert.equal(floatingGeometry.x, 8);
  assert.equal(floatingGeometry.y, 8);
  assert.equal(floatingGeometry.width, 288);
  assert.equal(floatingGeometry.height, floatingGeometry.viewportHeight - 16);
  assert.equal(floatingGeometry.radius, '16px');
  assert.equal(await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].contentView.children.at(-1).getBounds().width), 316, 'Native layer must leave room for the floating panel shadow');
  await chrome.screenshot({ path: 'test-results/sidebar-floating.png' });
  const hoverChrome = (x, y, type = 'mouseMove') => application.evaluate(({ webContents }, { x, y, type }) => {
    webContents.getAllWebContents().find(wc => wc.getURL().includes('chrome=1')).sendInputEvent({ type, x, y });
  }, { x, y, type });
  // Insets, shadow, and rounded corners are one continuous hover surface.
  for (const [x, y] of [[3, 3], [311, 220], [130, floatingGeometry.viewportHeight - 3]]) {
    await hoverChrome(x, y);
    await new Promise(resolve => setTimeout(resolve, 260));
    assert.equal((await getState(ui)).sidebarRevealed, true, `Moving over floating margin (${x},${y}) must not hide the sidebar`);
  }
  await application.evaluate(({ webContents }, id) => webContents.fromId(id).sendInputEvent({ type: 'mouseMove', x: 180, y: 180 }), firstNativeId);
  await new Promise(resolve => setTimeout(resolve, 260));
  assert.equal((await getState(ui)).sidebarRevealed, true, 'Late native website events underneath the panel must not dismiss it');
  await hoverChrome(316, 220, 'mouseLeave');
  await new Promise(resolve => setTimeout(resolve, 80));
  await hoverChrome(120, 220, 'mouseEnter');
  await new Promise(resolve => setTimeout(resolve, 260));
  assert.equal((await getState(ui)).sidebarRevealed, true, 'Returning before the hide delay must cancel dismissal');
  await application.evaluate(({ webContents }, id) => webContents.fromId(id).sendInputEvent({ type: 'mouseMove', x: 400, y: 180 }), firstNativeId);
  await waitFor(async () => !(await getState(ui)).sidebarRevealed, 'Sidebar did not start dismissing outside its bounds');
  await hoverChrome(120, 220, 'mouseEnter');
  await new Promise(resolve => setTimeout(resolve, 260));
  assert.equal((await getState(ui)).sidebarRevealed, true, 'Reentering during exit must reopen the sidebar');
  assert.equal(await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].contentView.children.at(-1).webContents.getURL().includes('chrome=1')), true, 'Stale detach timer removed a reopened sidebar');

  await settleVisuals(chrome);
  await application.evaluate(({ webContents }, id) => webContents.fromId(id).sendInputEvent({ type: 'mouseMove', x: 400, y: 180 }), firstNativeId);
  await waitFor(async () => !(await getState(ui)).sidebarRevealed, 'Native webpage mouse did not dismiss hover sidebar');
  await send(ui, { type: 'palette', mode: 'new' });
  await chrome.getByRole('combobox').waitFor();
  await send(ui, { type: 'overlay.close' });
  await hoverChrome(500, 220);
  await new Promise(resolve => setTimeout(resolve, 260));
  assert.equal((await getState(ui)).sidebarRevealed, false, 'Closing a modal must not turn the full window into a sidebar hover trigger');

  await send(ui, { type: 'preferences', preferences: { sidebarMode: 'hidden' } });
  assert.equal(await ui.getByRole('button', { name: 'Reveal sidebar', exact: true }).count(), 0);
  await ui.mouse.move(2, 250);
  assert.equal((await getState(ui)).sidebarRevealed, false, 'Hidden mode must not reveal on hover');
  await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setSize(900, 650));
  await waitFor(async () => (await native(application))[0].bounds.width === 884, 'Resize bounds were not updated');
  const layout = await application.evaluate(({ BrowserWindow }) => {
    const win = BrowserWindow.getAllWindows()[0];
    return { window: win.getContentSize(), ui: win.contentView.getBounds() };
  });
  assert.equal(layout.ui.width, layout.window[0], 'Trusted UI native bounds must resize with the window');
  assert.equal(layout.ui.height, layout.window[1], 'Trusted UI native height must resize with the window');
  console.log('Resized native UI:', layout, 'CSS viewport:', await ui.evaluate(() => [innerWidth, innerHeight]));
  await shortcut(application, 's', firstNativeId);
  assert.equal((await getState(ui)).preferences.sidebarMode, 'fixed');
  assert.equal((await native(application))[0].bounds.x, 304);
  await send(ui, { type: 'navigate', input: `${address}/two`, newTab: false });
  await waitFor(async () => (await getState(ui)).tabs.find(t => t.id === firstTabId)?.canGoBack, 'Back navigation missing');
  await send(ui, { type: 'back' });
  await waitFor(async () => (await getState(ui)).tabs.find(t => t.id === firstTabId)?.url === `${address}/`, 'Back failed');
  await shortcut(application, 'Down', firstNativeId, ['meta', 'alt']);
  assert.equal((await getState(ui)).activeTabId, secondTabId, 'Option+Command+Down should follow sidebar order');
  await shortcut(application, 'Tab', secondNativeId, ['control']);
  await chrome.getByRole('dialog', { name: 'Recent tabs' }).waitFor();
  assert.equal((await getState(ui)).tabSwitcher.ids[(await getState(ui)).tabSwitcher.index], firstTabId);
  assert.equal((await native(application)).length, 1, 'Recent tab switcher must preserve the live native page');
  await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].webContents.sendInputEvent({ type: 'keyUp', keyCode: 'Control' }));
  await waitFor(async () => (await getState(ui)).activeTabId === firstTabId, 'Releasing Control did not commit recent tab selection');
  await shortcut(application, 'd', firstNativeId);
  assert.equal((await getState(ui)).tabs.find(t => t.id === firstTabId).pinned, true);
  await shortcut(application, 'd', firstNativeId);
  await shortcut(application, 'Right', firstNativeId, ['meta', 'alt']);
  assert.equal((await getState(ui)).activeSpaceId, 'work');
  await shortcut(application, '1', undefined, ['control']);
  assert.equal((await getState(ui)).activeSpaceId, 'personal');
  await send(ui, { type: 'tab.close', id: secondTabId });
  assert.equal((await getState(ui)).tabs.length, 1);
  await shortcut(application, 't', firstNativeId, ['meta', 'shift']);
  assert.equal((await getState(ui)).tabs.length, 2, 'Shift+Command+T must reopen the last closed tab');
  const reopenedId = (await getState(ui)).activeTabId;
  assert.equal((await getState(ui)).tabs.find(t => t.id === reopenedId).url, `${address}/two`);
  await send(ui, { type: 'tab.close', id: reopenedId });
  assert.equal(await application.evaluate(({ webContents }, id) => !!webContents.fromId(id), secondNativeId), false);
  await send(ui, { type: 'navigate', input: `${address}/three`, newTab: true });
  const lazyTabId = (await getState(ui)).activeTabId;
  await ui.getByRole('button', { name: 'Collapse folder Reading', exact: true }).click();
  await drag(ui.locator(`[data-tab-id="${lazyTabId}"]`), ui.locator(`[data-folder-id="${folderId}"] .folder-row`));
  await waitFor(async () => (await getState(ui)).tabs.find(t => t.id === lazyTabId).folderId === folderId, 'Folder membership before restart failed');
  await ui.getByRole('button', { name: 'Collapse folder Reading', exact: true }).click();
  await send(ui, { type: 'tab.select', id: firstTabId });
  await settleVisuals(ui);
  await ui.screenshot({ path: 'test-results/folders.png' });
  await send(ui, { type: 'preferences', preferences: { theme: 'dark' } });
  await send(ui, { type: 'palette', mode: 'new' });
  await chrome.getByRole('combobox').fill('a cozy corner of the internet');
  await settleVisuals(chrome);
  await chrome.screenshot({ path: 'test-results/palette-dark.png' });
  await send(ui, { type: 'overlay.close' });
  await send(ui, { type: 'preferences', preferences: { sidebarMode: 'hidden' } });
  await send(ui, { type: 'tab.new' });
  assert.equal((await getState(ui)).tabs.length,2, 'Unconfirmed search must not add saved tabs');
  await send(ui, { type: 'favorite.save', name: 'Saved local favorite', url: `${address}/` });
  await send(ui, { type: 'tab.select', id: firstTabId });
  // Check forged privileged IPC originating in an untrusted page is rejected by lack of any bridge.
  await application.close(); application = undefined;
  const saved = JSON.parse(await readFile(join(userData, 'browser-state.json'), 'utf8'));
  assert.equal(saved.tabs.length, 2);
  assert.equal(saved.preferences.theme, 'dark');
  application = await electron.launch({ executablePath, args: [resolve('.')], env, timeout: 30000 });
  await application.firstWindow();
  await application.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setIgnoreMouseEvents(true));
  await waitFor(() => application.context().pages().some(page => page.url().includes('chrome=1')) && application.context().pages().some(page => page.url().includes('index.html') && !page.url().includes('chrome=1')), 'Restored chrome did not load');
  chrome = application.context().pages().find(page => page.url().includes('chrome=1'));
  ui = application.context().pages().find(page => page.url().includes('index.html') && !page.url().includes('chrome=1'));
  await waitFor(async () => (await getState(ui)).preferences.sidebarMode !== 'fixed', 'Sidebar did not hide');
  assert.equal(await ui.getByRole('button', { name: 'Expand sidebar', exact: true }).count(), 0);
  assert.equal((await getState(ui)).preferences.sidebarMode, 'hidden', 'Sidebar mode must survive restart');
  await send(ui, { type: 'preferences', preferences: { sidebarMode: 'fixed' } });
  await waitFor(async () => (await getState(ui)).tabs[0]?.loading === false && (await native(application)).length === 1, 'Session restoration failed');
  const restored = await getState(ui);
  assert.equal(restored.activeTabId, firstTabId);
  assert.ok(restored.favorites.some(f => f.name === 'Saved local favorite'));
  assert.equal(restored.preferences.sidebarSize, 'comfortable');
  assert.equal(restored.folders.find(f => f.id === folderId).name, 'Reading');
  assert.equal(restored.folders.find(f => f.id === folderId).collapsed, true);
  assert.equal(restored.tabs.find(t => t.id === lazyTabId).folderId, folderId);
  assert.equal(restored.tabs.find(t => t.id === lazyTabId).pinned, true);
  assert.equal(restored.tabs.find(t => t.id === lazyTabId).status, 'discarded', 'Background restored tab must remain unloaded');
  assert.equal(await application.evaluate(({ webContents }) => webContents.getAllWebContents().filter(wc => wc.getType() !== 'remote').length), 3, 'Restoration should create two trusted UI renderers and only the active webpage');
  const cookies = await application.evaluate(async ({ session }, url) => session.fromPartition('persist:personal').cookies.get({ url }), address);
  assert.ok(cookies.some(c => c.name === 'derivative_session' && c.value === 'retained'), 'Persistent website cookie was not restored');
  const restoredViews = await native(application);
  assert.equal(await application.evaluate(({ webContents }, id) => webContents.fromId(id).executeJavaScript(`localStorage.getItem('session-check')`), restoredViews[0].id), 'retained');
  await send(ui, { type: 'tab.close', id: firstTabId });
  assert.equal(await application.evaluate(({ webContents }, id) => !!webContents.fromId(id), restoredViews[0].id), false, 'Closed view leaked');
  await send(ui, { type: 'tab.close', id: lazyTabId });
  await ui.getByRole('heading', { name: 'New tab', exact: true }).waitFor();
  await settleVisuals(ui);
  assert.equal((await native(application)).length, 0);
  assert.equal(await application.evaluate(({ webContents }, id) => !!webContents.fromId(id), restoredViews[0].id), false, 'Closed view leaked');
  await ui.screenshot({ path: 'test-results/home-dark.png' });
  await send(ui, { type: 'space.select', id: 'work' });
  await send(ui, { type: 'preferences', preferences: { theme: 'light' } });
  await settleVisuals(ui);
  await ui.screenshot({ path: 'test-results/home-mint.png' });
  await send(ui, { type: 'settings' });
  await chrome.getByRole('dialog', { name: 'Settings' }).waitFor();
  await chrome.getByLabel('Sidebar behavior').selectOption('hidden');
  assert.equal((await getState(ui)).preferences.sidebarMode, 'hidden');
  await chrome.getByLabel('Sidebar behavior').selectOption('hover');
  assert.equal((await getState(ui)).preferences.sidebarMode, 'hover');
  await chrome.getByLabel('Sidebar behavior').selectOption('fixed');
  await chrome.getByRole('button', { name: 'Shortcuts', exact: true }).click();
  await chrome.getByText('Show / hide sidebar', { exact: true }).waitFor();
  await chrome.screenshot({ path: 'test-results/shortcuts.png' });
  await chrome.getByRole('button', { name: 'General', exact: true }).click();
  await chrome.screenshot({ path: 'test-results/settings.png' });
  await chrome.getByRole('button', { name: 'Close settings', exact: true }).click();
  await chrome.getByRole('dialog', { name: 'Settings' }).waitFor({ state: 'hidden' });
  await send(ui, { type: 'sidebar.toggle' });
  await waitFor(async () => (await getState(ui)).preferences.sidebarMode !== 'fixed', 'Sidebar did not hide');
  assert.equal(await ui.getByRole('button', { name: 'Expand sidebar', exact: true }).count(), 0);
  await settleVisuals(ui);
  await ui.screenshot({ path: 'test-results/sidebar-hidden.png' });
  console.log('PASS: native Chromium, folders, tab/folder/Space drag-and-drop, centered icon geometry, shortcuts, sidebar modes, persistence, and view cleanup.');
} finally {
  if (application) await application.close();
  await new Promise(resolve => server.close(resolve));
  await rm(userData, { recursive: true, force: true });
}
