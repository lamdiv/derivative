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
try {
  const first=await launch(); application=first.app; const ui=first.ui;
  const ids=[], pageIds=[];
  for (const suffix of ['one','two','three']) {
    await send(ui,{type:'navigate',input:`${address}/${suffix}`,newTab:true});
    await waitFor(async()=>{const s=await getState(ui);return s.tabs.find(t=>t.id===s.activeTabId)?.loading===false;},'Page did not load');
    ids.push((await getState(ui)).activeTabId); pageIds.push((await native(application))[0].id);
  }
  await application.evaluate(({webContents},ids)=>Promise.all(ids.map((id,i)=>webContents.fromId(id).executeJavaScript(`document.querySelector('textarea').value='draft-${i}'`))),pageIds);
  const source=ui.locator(`[data-tab-id="${ids[0]}"]`), target=ui.locator(`[data-tab-id="${ids[1]}"]`);
  await source.dispatchEvent('dragstart',{dataTransfer:await ui.evaluateHandle(()=>new DataTransfer())});
  await ui.evaluate(({id,sourceId})=>{
    const target=document.querySelector(`[data-tab-id="${id}"]`), box=target.getBoundingClientRect(), dt=new DataTransfer();dt.setData('application/x-derivative-tab',sourceId);
    target.dispatchEvent(new DragEvent('dragover',{bubbles:true,cancelable:true,dataTransfer:dt,clientX:box.x+box.width/2,clientY:box.y+box.height/2}));
  },{id:ids[1],sourceId:ids[0]});
  await target.locator('.tab-split-preview').waitFor();
  assert.equal((await getState(ui)).splitView,null,'Hover preview should not split until drop');
  await source.dispatchEvent('dragend');
  await target.locator('.tab-split-preview').waitFor({state:'hidden'});
  await application.evaluate(({BrowserWindow})=>{const win=BrowserWindow.getAllWindows()[0];win.focus();win.webContents.focus();});
  await source.dragTo(target);
  await waitFor(async()=>!!(await getState(ui)).splitView,'Dropping one tab onto another did not split');
  assert.deepEqual((await getState(ui)).splitView.ids,[ids[1],ids[0]],'Split must use the dragged/target tabs, not the unrelated active tab');
  assert.equal((await getState(ui)).activeTabId,ids[1]);
  assert.deepEqual(new Set((await native(application)).map(v=>v.id)),new Set([pageIds[0],pageIds[1]]));
  assert.equal(await application.evaluate(({webContents},id)=>webContents.fromId(id).executeJavaScript("document.querySelector('textarea').value"),pageIds[0]),'draft-0');
  const group=ui.getByRole('group',{name:'Split view tabs',exact:true});
  await group.waitFor();
  assert.deepEqual(await group.locator('.split-tab-number').allTextContents(),['1','2']);
  assert.equal(await source.count(),0,'Joined tabs should not also appear as separate rows');
  assert.equal(await target.count(),0);
  await group.getByRole('button',{name:'Focus split tab 2: A real Chromium page',exact:true}).click();
  assert.equal((await getState(ui)).activeTabId,ids[0]);
  assert.equal((await native(application)).length,2);
  await ui.screenshot({path:'test-results/merged-split-tabs.png'});
  await group.click({button:'right'});
  await ui.getByRole('menuitem',{name:'Separate tabs',exact:true}).click();
  await source.waitFor(); await target.waitFor();
  assert.equal((await getState(ui)).splitView,null);
  const third=ui.locator(`[data-tab-id="${ids[2]}"]`);
  await third.dragTo(source,{targetPosition:{x:20,y:2}});
  await waitFor(async()=>(await getState(ui)).tabs[0].id===ids[2],'Top edge must reorder');
  assert.equal((await getState(ui)).splitView,null);
  const targetBox=await target.boundingBox();
  await third.dragTo(target,{targetPosition:{x:20,y:targetBox.height-2}});
  await waitFor(async()=>(await getState(ui)).tabs.at(-1).id===ids[2],'Bottom edge must reorder');
  assert.equal((await getState(ui)).splitView,null);
  await send(ui,{type:'split.open',id:ids[0],withId:'missing'});
  assert.equal((await getState(ui)).splitView,null);
  await send(ui,{type:'split.open',id:ids[0],withId:ids[0]});
  assert.equal((await getState(ui)).splitView,null);
  await send(ui,{type:'tab.move',id:ids[2],spaceId:'work'});
  await send(ui,{type:'space.select',id:'personal'});
  await send(ui,{type:'split.open',id:ids[2],withId:ids[1]});
  assert.equal((await getState(ui)).splitView,null,'Tabs in different profiles must not split together');
  assert.equal(await ui.getByRole('alert').count(),0);
  await send(ui,{type:'split.open',id:ids[0],withId:ids[1]});
  await group.waitFor();
  await group.getByRole('button',{name:'Close split tab 2: A real Chromium page',exact:true}).click();
  await waitFor(async()=>!(await getState(ui)).tabs.some(t=>t.id===ids[0]),'Joined pane close did not close its tab');
  assert.equal((await getState(ui)).splitView,null);
  await target.waitFor();
  assert.equal((await native(application)).length,1);
  console.log('PASS: tab-on-tab preview/cancellation, real drag-to-split, explicit target pairing, preserved page state, edge reordering, and invalid-pair guards.');
} finally {
  if (application) await application.close();
  await new Promise(resolve => server.close(resolve));
  await rm(userData, { recursive: true, force: true });
}
