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
const errors=[];
try {
  const first=await launch(); application=first.app; const ui=first.ui;
  application.on('console', message=>{ if (message.text().includes('Invalid browser action')) errors.push(message.text()); });
  await send(ui,{type:'navigate',input:address,newTab:true});
  await waitFor(async ()=>(await getState(ui)).tabs[0]?.loading===false,'Page did not load');
  const id=(await getState(ui)).activeTabId, nativeId=(await native(application))[0].id;
  await send(ui,{type:'favorite.save',name:'My place',url:address});
  const favoriteId=(await getState(ui)).favorites.find(f=>f.name==='My place').id;
  await ui.getByRole('button',{name:'Open My place',exact:true}).click();
  await waitFor(async ()=>(await getState(ui)).tabs.find(t=>t.id===id)?.favoriteId===favoriteId,'Favorite did not adopt the existing tab');
  assert.equal((await getState(ui)).tabs.length,1);
  assert.equal((await native(application))[0].id,nativeId);
  await ui.locator(`[data-tab-id="${id}"]`).waitFor({state:'hidden'});
  assert.equal(await ui.getByRole('button',{name:'Open My place',exact:true}).getAttribute('aria-pressed'),'true');
  await send(ui,{type:'navigate',input:`${address}/two`,newTab:false});
  await waitFor(async ()=>(await getState(ui)).tabs[0]?.title==='Second page','Favorite navigation failed');
  await ui.getByRole('button',{name:'Open My place',exact:true}).click();
  assert.equal((await getState(ui)).tabs.length,1,'Navigating within a favorite must not cause a duplicate on reopening');
  assert.equal(await ui.locator('.favorite-active').count(),1);
  await ui.evaluate(({id,beforeId})=>{
    const dt=new DataTransfer();
    const source=document.querySelector(`[data-favorite-id="${id}"]`),target=document.querySelector(`[data-favorite-id="${beforeId}"]`);
    source.dispatchEvent(new DragEvent('dragstart',{bubbles:true,dataTransfer:dt}));
    target.dispatchEvent(new DragEvent('dragover',{bubbles:true,cancelable:true,dataTransfer:dt}));
    target.dispatchEvent(new DragEvent('drop',{bubbles:true,cancelable:true,dataTransfer:dt}));
    source.dispatchEvent(new DragEvent('dragend',{bubbles:true,dataTransfer:dt}));
  },{id:favoriteId,beforeId:(await getState(ui)).favorites[0].id});
  await waitFor(async ()=>(await getState(ui)).favorites[0].id===favoriteId,'Favorite reorder failed');
  assert.equal(await ui.getByRole('alert').count(),0);
  await ui.locator('.sidebar').dispatchEvent('wheel',{deltaX:80,deltaY:1});
  await waitFor(async ()=>(await getState(ui)).activeSpaceId==='work','Swipe failed');
  assert.equal(await ui.locator('.favorite-active').count(),0,'Favorite highlight belongs to the current Space');
  assert.equal(await ui.getByRole('alert').count(),0);
  await send(ui,{type:'space.select',id:'personal'});
  await send(ui,{type:'preferences',preferences:{sidebarMode:'hover'}});
  const pageId=(await native(application))[0].id;
  await application.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].webContents.sendInputEvent({type:'mouseMove',x:2,y:220}));
  await waitFor(async ()=>(await getState(ui)).sidebarRevealed,'Edge reveal failed');
  await chrome.getByRole('button',{name:'Open My place',exact:true}).waitFor();
  assert.equal(await chrome.getByRole('button',{name:'Open My place',exact:true}).getAttribute('aria-pressed'),'true');
  await chrome.getByRole('button',{name:'Open My place',exact:true}).click({button:'right'});
  await chrome.getByRole('menuitem',{name:'Remove favorite',exact:true}).click();
  await send(ui,{type:'preferences',preferences:{sidebarMode:'fixed'}});
  await ui.locator(`[data-tab-id="${id}"]`).waitFor();
  assert.equal((await native(application))[0].id,pageId,'Removing a favorite must keep its page open');
  assert.equal(await ui.getByRole('alert').count(),0);
  assert.equal(await chrome.getByRole('alert').count(),0);
  assert.deepEqual(errors,[]);
  console.log('PASS: favorite grid ownership/highlight, navigation reuse, removal preserves tab, and drag/swipe/hover without action errors.');
} finally {
  if (application) await application.close();
  await new Promise(resolve => server.close(resolve));
  await rm(userData, { recursive: true, force: true });
}
