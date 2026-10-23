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
async function launch(restored = false) {
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
  if (!restored) await ui.getByRole('heading', { name: 'New tab', exact: true }).waitFor();
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
const shortcut = (key, id) => application.evaluate(({ BrowserWindow, webContents }, { key, id }) => {
  const wc=id ? webContents.fromId(id) : BrowserWindow.getAllWindows()[0].webContents;
  wc.focus(); wc.sendInputEvent({ type:'keyDown', keyCode:key, modifiers:['meta'] }); wc.sendInputEvent({ type:'keyUp', keyCode:key, modifiers:['meta'] });
}, { key, id });
const evaluatePage = (id, code) => application.evaluate(({ webContents }, { id, code }) => webContents.fromId(id).executeJavaScript(code), { id, code });
try {
  const first=await launch(); application=first.app; let ui=first.ui;
  await ui.getByRole('combobox').fill('unfinished search');
  await ui.getByRole('button',{name:'Add favorite',exact:true}).focus();
  for (let i=0;i<3;i++) {
    await shortcut('t');
    assert.equal((await getState(ui)).overlay,null,'Cmd+T must reuse the visible empty-page search');
    await ui.waitForFunction(()=>document.activeElement===document.querySelector('.new-tab-input input'));
    assert.equal((await getState(ui)).tabs.length,0);
    assert.equal(await chrome.getByRole('dialog',{name:'Search or enter URL',exact:true}).count(),0);
  }
  await ui.getByRole('combobox').fill(address);
  await ui.getByRole('combobox').press('Enter');
  await waitFor(async () => (await getState(ui)).tabs[0]?.loading===false && (await native(application)).length===1, 'First tab did not load');
  const firstId=(await getState(ui)).activeTabId, firstNative=(await native(application))[0].id;
  await evaluatePage(firstNative, "document.querySelector('textarea').value='keep me'; document.cookie='profile=personal; Path=/; Max-Age=86400'; localStorage.setItem('profile','personal')");
  await shortcut('t', firstNative);
  assert.equal((await getState(ui)).tabs.length, 1);
  assert.equal((await getState(ui)).activeTabId, firstId);
  assert.equal((await native(application))[0].id, firstNative);
  await chrome.getByRole('combobox').fill(`${address}/two`);
  await chrome.getByRole('combobox').press('Enter');
  await waitFor(async () => (await getState(ui)).tabs.some(t=>t.title==='Second page'), 'Second tab did not load');
  const closingId=(await getState(ui)).activeTabId;
  await shortcut('t');
  await chrome.getByRole('button', { name:'Close tab Second page', exact:true }).click();
  await waitFor(async () => !(await getState(ui)).tabs.some(t=>t.id===closingId), 'Result close failed');
  assert.equal((await getState(ui)).overlay, 'palette', 'Closing the active tab result must keep search open');
  assert.equal((await getState(ui)).activeTabId, firstId);
  await chrome.getByRole('combobox').press('Escape');
  assert.equal(await evaluatePage(firstNative, "document.querySelector('textarea').value"), 'keep me');

  const favoriteIds=(await getState(ui)).favorites.map(f=>f.id);
  const favorite=ui.locator(`[data-favorite-id="${favoriteIds[0]}"]`);
  await favorite.click({ button:'right' });
  await ui.getByRole('menu', { name:'Options for favorite GitHub' }).waitFor();
  await ui.getByRole('menuitem', { name:'Edit favorite', exact:true }).click();
  await ui.getByRole('textbox', { name:'Favorite name' }).fill('Cozy GitHub');
  await ui.getByRole('button', { name:'Save favorite', exact:true }).click();
  await ui.getByRole('button', { name:'Done editing favorites' }).click();
  await ui.locator(`[data-favorite-id="${favoriteIds[0]}"]`).click({ button:'right' });
  await ui.getByRole('menuitem', { name:'Copy address' }).waitFor();
  await ui.getByRole('menuitem', { name:'Remove favorite' }).click();
  await waitFor(async () => !(await getState(ui)).favorites.some(f=>f.id===favoriteIds[0]), 'Context remove failed');
  await ui.evaluate(({ from, to }) => {
    const dt=new DataTransfer(); const source=document.querySelector(`[data-favorite-id="${from}"]`), target=document.querySelector(`[data-favorite-id="${to}"]`);
    source.dispatchEvent(new DragEvent('dragstart', { bubbles:true, dataTransfer:dt }));
    target.dispatchEvent(new DragEvent('dragover', { bubbles:true, cancelable:true, dataTransfer:dt }));
    target.dispatchEvent(new DragEvent('drop', { bubbles:true, cancelable:true, dataTransfer:dt }));
    source.dispatchEvent(new DragEvent('dragend', { bubbles:true, dataTransfer:dt }));
  }, { from:favoriteIds[2], to:favoriteIds[1] });
  await waitFor(async () => (await getState(ui)).favorites[0].id===favoriteIds[2], 'Favorite grid reorder failed');

  await ui.locator('.sidebar').dispatchEvent('wheel', { deltaX:80, deltaY:1 });
  await waitFor(async () => (await getState(ui)).activeSpaceId==='work', 'Sidebar swipe did not switch Space');
  await ui.locator('.sidebar').dispatchEvent('wheel', { deltaX:100, deltaY:1 });
  assert.equal((await getState(ui)).activeSpaceId, 'work', 'Momentum must not skip Spaces');
  assert.equal(await ui.getByRole('button',{name:'Close tab A real Chromium page',exact:true}).count(),0,'Empty Work search must not show Personal tabs');
  await send(ui, { type:'navigate', input:address, newTab:true });
  await waitFor(async () => { const s=await getState(ui); return s.tabs.find(t=>t.id===s.activeTabId)?.loading===false; }, 'Work tab did not load');
  const workId=(await getState(ui)).activeTabId, workNative=(await native(application))[0].id;
  await shortcut('t');
  await chrome.getByRole('combobox').fill('Chromium');
  await waitFor(async()=>await chrome.getByRole('button',{name:'Close tab A real Chromium page',exact:true}).count()===1,'Work search should offer exactly its own matching tab');
  await chrome.getByRole('combobox').press('Escape');

  assert.equal(await evaluatePage(workNative, "document.cookie"), '', 'Cookies must be separate between Spaces');
  assert.equal(await evaluatePage(workNative, "localStorage.getItem('profile')"), null);
  await evaluatePage(workNative, "document.cookie='profile=work; Path=/; Max-Age=86400'; localStorage.setItem('profile','work')");
  await new Promise(resolve=>setTimeout(resolve,250));
  await ui.locator('.sidebar').dispatchEvent('wheel', { deltaX:-80, deltaY:1 });
  await waitFor(async () => (await getState(ui)).activeSpaceId==='personal', 'Reverse swipe failed');
  assert.equal((await native(application))[0].id, firstNative);
  assert.equal(await evaluatePage(firstNative, "localStorage.getItem('profile')"), 'personal');
  assert.equal(await evaluatePage(firstNative, "document.querySelector('textarea').value"), 'keep me');

  await send(ui, { type:'navigate', input:`${address}/two`, newTab:true });
  await waitFor(async () => { const s=await getState(ui); return s.tabs.find(t=>t.id===s.activeTabId)?.loading===false; }, 'Split tab did not load');
  const secondId=(await getState(ui)).activeTabId, secondNative=(await native(application))[0].id;
  await ui.locator(`[data-tab-id="${firstId}"] .tab`).click({ button:'right' });
  await ui.getByRole('menuitem', { name:'Split with current tab' }).click();
  await waitFor(async () => (await native(application)).length===2, 'Split must attach two native pages');
  let pair=await native(application);
  assert.deepEqual(new Set(pair.map(v=>v.id)), new Set([firstNative, secondNative]));
  assert.equal(pair[0].bounds.y, 42);
  assert.equal(pair[1].bounds.x-pair[0].bounds.x-pair[0].bounds.width, 6);
  await ui.getByRole('button', { name:'Focus split pane A real Chromium page' }).click();
  assert.equal((await getState(ui)).activeTabId, firstId);
  assert.equal((await native(application)).length, 2);
  await application.evaluate(({ webContents }, id) => webContents.fromId(id).focus(), secondNative);
  await waitFor(async ()=>(await getState(ui)).activeTabId===secondId, 'Focusing a native split page must select its navigation controls');
  await ui.getByRole('button', { name:'Focus split pane A real Chromium page' }).click();
  await shortcut('t', firstNative);
  assert.equal((await native(application)).length, 2, 'Search must preserve both split views');
  await chrome.getByRole('combobox').press('Escape');
  await application.evaluate(({ BrowserWindow })=>BrowserWindow.getAllWindows()[0].emit('enter-full-screen'));
  await waitFor(async ()=>(await getState(ui)).windowExpanded, 'Expanded state failed');
  pair=await native(application);
  assert.equal(pair[0].bounds.x, 0); assert.equal(pair[0].bounds.y,34);
  const size=await application.evaluate(({ BrowserWindow })=>BrowserWindow.getAllWindows()[0].getContentSize());
  assert.equal(pair[1].bounds.x+pair[1].bounds.width,size[0]);
  await ui.getByRole('button', { name:'Keep only A real Chromium page' }).click();
  assert.equal((await native(application)).length,1);
  assert.equal((await native(application))[0].bounds.y,0);
  assert.equal(await evaluatePage(firstNative,"document.querySelector('textarea').value"),'keep me');
  await send(ui,{type:'sidebar.toggle'});
  await chrome.locator(`[data-tab-id="${secondId}"]`).waitFor();
  await chrome.evaluate(id => {
    const dt=new DataTransfer();
    document.querySelector(`[data-tab-id="${id}"]`).dispatchEvent(new DragEvent('dragstart',{bubbles:true,dataTransfer:dt}));
  },secondId);
  await chrome.locator('.split-drop-zone').waitFor();
  await chrome.evaluate(id=>{
    const dt=new DataTransfer(); dt.setData('application/x-derivative-tab',id);
    document.querySelector('.split-drop-zone').dispatchEvent(new DragEvent('drop',{bubbles:true,cancelable:true,dataTransfer:dt}));
  },secondId);
  await waitFor(async ()=>(await native(application)).length===2,'Dropping a tab on the split target must join both live views');
  await send(ui,{type:'tab.close',id:secondId});
  assert.equal((await getState(ui)).splitView,null);
  assert.equal((await native(application)).length,1);
  await send(ui,{type:'space.select',id:'work'});
  assert.equal((await getState(ui)).activeTabId,workId);
  assert.equal(await evaluatePage(workNative,"localStorage.getItem('profile')"),'work');
  await application.close(); application=undefined;
  const restarted=await launch(true); application=restarted.app; ui=restarted.ui;
  await waitFor(async ()=>(await native(application)).length===1 && (await getState(ui)).tabs.find(t=>t.id===workId)?.loading===false,'Work profile did not restore');
  assert.equal((await getState(ui)).activeTabId,workId);
  assert.equal((await getState(ui)).favorites[0].id,favoriteIds[2]);
  assert.equal(await evaluatePage((await native(application))[0].id,"localStorage.getItem('profile')"),'work');
  assert.match(await evaluatePage((await native(application))[0].id,'document.cookie'),/profile=work/);
  await send(ui,{type:'space.select',id:'personal'});
  await waitFor(async ()=>(await getState(ui)).tabs.find(t=>t.id===firstId)?.loading===false,'Personal profile did not restore');
  assert.equal(await evaluatePage((await native(application))[0].id,"localStorage.getItem('profile')"),'personal');
  assert.match(await evaluatePage((await native(application))[0].id,'document.cookie'),/profile=personal/);
  console.log('PASS: deferred new tabs, close search results, favorites menu/grid reorder, sidebar swipe and profile isolation, live split views and cleanup.');
} finally {
  if (application) await application.close();
  await new Promise(resolve => server.close(resolve));
  await rm(userData, { recursive: true, force: true });
}
