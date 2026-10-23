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
  await send(ui,{type:'preferences',preferences:{theme:'light'}});
  const ids=(await getState(ui)).favorites.map(f=>f.id);
  const boxes=await ui.locator('[data-favorite-id]').evaluateAll(tiles=>tiles.map(tile=>{const b=tile.getBoundingClientRect();return {x:b.x,y:b.y,width:b.width,height:b.height};}));
  const start=()=>ui.evaluate(id=>{globalThis.testGridDrag=new DataTransfer();document.querySelector(`[data-favorite-id="${id}"]`).dispatchEvent(new DragEvent('dragstart',{bubbles:true,dataTransfer:globalThis.testGridDrag}));},ids[2]);
  const over=slot=>ui.evaluate(box=>document.querySelector('.favorites').dispatchEvent(new DragEvent('dragover',{bubbles:true,cancelable:true,dataTransfer:globalThis.testGridDrag,clientX:box.x+box.width/2,clientY:box.y+box.height/2})),boxes[slot]);
  await start(); await over(0);
  await waitFor(async ()=>await ui.locator(`[data-favorite-id="${ids[2]}"]`).evaluate((tile,box)=>Math.abs(tile.getBoundingClientRect().x-box.x)<1 && Math.abs(tile.getBoundingClientRect().y-box.y)<1,boxes[0]),'Dragged placeholder did not preview the first slot');
  assert.deepEqual((await getState(ui)).favorites.map(f=>f.id),ids,'Preview must not save order before drop');
  assert.equal(await ui.locator('.favorite-drop').count(),0,'Grid preview must replace the drop border');
  await ui.screenshot({path:'test-results/grid-preview-light.png'});
  await ui.evaluate(id=>document.querySelector(`[data-favorite-id="${id}"]`).dispatchEvent(new DragEvent('dragend',{bubbles:true,dataTransfer:globalThis.testGridDrag})),ids[2]);
  await waitFor(async ()=>await ui.locator(`[data-favorite-id="${ids[2]}"]`).evaluate((tile,box)=>Math.abs(tile.getBoundingClientRect().x-box.x)<1,boxes[2]),'Cancelled preview did not restore layout');
  assert.deepEqual((await getState(ui)).favorites.map(f=>f.id),ids);
  await start(); await over(8);
  await waitFor(async ()=>await ui.locator(`[data-favorite-id="${ids[2]}"]`).evaluate((tile,box)=>Math.abs(tile.getBoundingClientRect().y-box.y)<1,boxes[8]),'Last-row preview did not move');
  await ui.evaluate(box=>document.querySelector('.favorites').dispatchEvent(new DragEvent('drop',{bubbles:true,cancelable:true,dataTransfer:globalThis.testGridDrag,clientX:box.x+box.width/2,clientY:box.y+box.height/2})),boxes[8]);
  await waitFor(async ()=>(await getState(ui)).favorites.at(-1)?.id===ids[2],'Last-slot drop failed');
  await waitFor(async ()=>{
    const actual=await ui.locator('[data-favorite-id]').evaluateAll(tiles=>tiles.map(tile=>{const box=tile.getBoundingClientRect();return {x:box.x,y:box.y};}));
    return actual.every((box,i)=>Math.abs(box.x-boxes[i].x)<1 && Math.abs(box.y-boxes[i].y)<1);
  },'Committed tiles must match the preview without doubled offsets');
  assert.equal(await ui.locator('.favorite-dragging').count(),0);
  assert.equal(await ui.getByRole('alert').count(),0);
  await send(ui,{type:'preferences',preferences:{theme:'dark'}});
  await ui.evaluate(async()=>{await new Promise(requestAnimationFrame);await Promise.all(document.getAnimations().filter(a=>a.effect?.getTiming().iterations!==Infinity).map(a=>a.finished.catch(()=>{})));});
  await ui.screenshot({path:'test-results/sidebar-contrast-dark.png'});
  console.log('PASS: animated grid preview, unchanged state before drop, cancellation, final-slot commit, and light/dark sidebar surfaces.');
} finally {
  if (application) await application.close();
  await new Promise(resolve => server.close(resolve));
  await rm(userData, { recursive: true, force: true });
}
