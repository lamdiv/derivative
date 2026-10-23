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
  assert.equal(await ui.locator('.sidebar .new-tab').count(),0,'An empty Space should not show another New Tab prompt');
  assert.equal(await ui.locator('.sidebar-search').count(),0,'The focused empty-page search needs no duplicate sidebar search');
  assert.deepEqual(await ui.locator('.new-tab-mark').evaluate(el=>({tag:el.tagName.toLowerCase(),paths:el.querySelectorAll('path').length,width:el.getBoundingClientRect().width,height:el.getBoundingClientRect().height})),{tag:'svg',paths:2,width:52,height:52});
  const fixed=await ui.locator('.favorites').boundingBox();
  await ui.locator('.sidebar').dispatchEvent('wheel',{deltaX:25,deltaY:1});
  await waitFor(async ()=>await ui.locator('.space-pages').evaluate(el=>new DOMMatrix(getComputedStyle(el).transform).m41)<-10,'Space content did not follow partial swipe');
  assert.equal((await getState(ui)).activeSpaceId,'personal');
  assert.deepEqual(await ui.locator('.favorites').boundingBox(),fixed,'Favorites should stay anchored while Space content moves');
  await ui.locator('.sidebar').dispatchEvent('wheel',{deltaX:40,deltaY:1});
  await waitFor(async ()=>(await getState(ui)).activeSpaceId==='work','Swipe did not complete');
  await waitFor(async ()=>await ui.locator('.space-pages').evaluate(el=>Math.abs(new DOMMatrix(getComputedStyle(el).transform).m41))<.1,'Incoming Space did not settle');
  await new Promise(resolve=>setTimeout(resolve,240));
  await ui.locator('.sidebar').dispatchEvent('wheel',{deltaX:-25,deltaY:1});
  await waitFor(async ()=>await ui.locator('.space-pages').evaluate(el=>new DOMMatrix(getComputedStyle(el).transform).m41)>10,'Reverse swipe did not follow the trackpad');
  await waitFor(async ()=>await ui.locator('.space-pages').evaluate(el=>Math.abs(new DOMMatrix(getComputedStyle(el).transform).m41))<.1,'Aborted swipe did not spring back');
  assert.equal((await getState(ui)).activeSpaceId,'work');
  await ui.emulateMedia({reducedMotion:'reduce'});
  await ui.locator('.sidebar').dispatchEvent('wheel',{deltaX:80,deltaY:1});
  await waitFor(async ()=>(await getState(ui)).activeSpaceId==='study','Reduced-motion Space switching failed');
  assert.equal(await ui.locator('.space-pages').evaluate(el=>getComputedStyle(el).transform),'none');
  await ui.emulateMedia({reducedMotion:'no-preference'});
  await new Promise(resolve=>setTimeout(resolve,240));
  const iconSizes=await ui.locator('.space-button').evaluateAll(buttons=>buttons.map(button=>({button:button.getBoundingClientRect().width,icon:button.querySelector('.space-icon').getBoundingClientRect().width})));
  assert.ok(iconSizes.every(size=>size.button===27 && size.icon===14),'Bottom Space controls should be small and uniform');
  await ui.locator('.sidebar').dispatchEvent('wheel',{deltaX:120,deltaY:1});
  await ui.locator('.space-edge-feedback.is-visible').waitFor();
  assert.equal((await getState(ui)).activeSpaceId,'study','Swiping past the last Space must not wrap');
  assert.equal(await ui.locator('.space-edge-feedback').innerText(),'Last Space');
  await ui.screenshot({path:'test-results/space-swipe-edge.png'});
  assert.ok(await ui.locator('.space-pages').evaluate(el=>new DOMMatrix(getComputedStyle(el).transform).m41)>-28,'Boundary movement must resist the swipe');
  await waitFor(async()=>await ui.locator('.space-edge-feedback.is-visible').count()===0,'Boundary hint did not dismiss');
  await send(ui,{type:'space.select',id:'personal'});
  await new Promise(resolve=>setTimeout(resolve,240));
  await ui.locator('.sidebar').dispatchEvent('wheel',{deltaX:-90,deltaY:1});
  await ui.locator('.space-edge-feedback.is-visible').waitFor();
  assert.equal((await getState(ui)).activeSpaceId,'personal','Swiping past the first Space must not wrap');
  assert.equal(await ui.locator('.space-edge-feedback').innerText(),'First Space');
  await waitFor(async()=>await ui.locator('.space-edge-feedback.is-visible').count()===0,'First Space hint did not dismiss');
  // Lock horizontal intent once, then accept diagonal samples and suppress momentum.
  await ui.locator('.sidebar').dispatchEvent('wheel',{deltaX:16,deltaY:1});
  await ui.locator('.sidebar').dispatchEvent('wheel',{deltaX:20,deltaY:28});
  await ui.locator('.sidebar').dispatchEvent('wheel',{deltaX:20,deltaY:25});
  await waitFor(async()=>(await getState(ui)).activeSpaceId==='work','Diagonal continuation lost the swipe');
  await ui.locator('.sidebar').dispatchEvent('wheel',{deltaX:100,deltaY:1});
  assert.equal((await getState(ui)).activeSpaceId,'work','Momentum skipped a Space');
  // An intentional reversal need not wait for the momentum lock timeout.
  await ui.locator('.sidebar').dispatchEvent('wheel',{deltaX:-60,deltaY:1});
  await waitFor(async()=>(await getState(ui)).activeSpaceId==='personal','Quick reverse swipe was ignored');

  await new Promise(resolve=>setTimeout(resolve,240));
  await send(ui,{type:'preferences',preferences:{sidebarMode:'hover'}});
  for (let cycle=0;cycle<2;cycle++) {
    await send(ui,{type:'sidebar.reveal',visible:true});
    await chrome.locator('.sidebar').waitFor();
    await chrome.locator('.sidebar').dispatchEvent('wheel',{deltaX:65,deltaY:1});
    await waitFor(async()=>(await getState(ui)).activeSpaceId==='work','Reopened floating sidebar lost its swipe listener');
    await send(ui,{type:'sidebar.reveal',visible:false});
    await waitFor(async()=>!(await getState(ui)).sidebarRevealed,'Floating sidebar did not hide');
    await new Promise(resolve=>setTimeout(resolve,220));
    await send(ui,{type:'space.select',id:'personal'});
  }
  await send(ui,{type:'preferences',preferences:{sidebarMode:'fixed'}});
  await ui.screenshot({path:'test-results/clean-new-tab.png'});
  console.log('PASS: clean vector New Tab logo, no redundant empty-Space prompts, diagonal swipes, reversal/momentum, edge resistance, compact icons, floating reopen, and reduced motion.');
} finally {
  if (application) await application.close();
  await new Promise(resolve => server.close(resolve));
  await rm(userData, { recursive: true, force: true });
}
