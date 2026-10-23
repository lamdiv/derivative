import { _electron as electron } from 'playwright';
import { createServer } from 'node:http';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
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
try {
  const tabs=Array.from({length:8},(_,i)=>({id:`layout-${i}`,spaceId:'personal',profileId:'personal',url:`${address}/layout-${i}`,title:`Layout item ${i}`,pinned:false,lastActive:i}));
  tabs.push({id:'blank',spaceId:'personal',profileId:'personal',url:'derivative://new-tab',title:'New tab',pinned:false,lastActive:20});
  const history=Array.from({length:4},(_,i)=>({url:`${address}/history-${i}`,title:`Layout history ${i}`,visitedAt:i}));
  await writeFile(join(userData,'browser-state.json'),JSON.stringify({version:1,tabs,history,activeSpaceId:'personal',activeTabId:'blank'}));
  const first=await launch(); application=first.app; const ui=first.ui;
  const settle=page=>page.evaluate(async()=>{await new Promise(requestAnimationFrame);await new Promise(requestAnimationFrame);});
  async function checkAnchored(page, selector, compact) {
    const input=page.getByRole('combobox');
    let anchor;
    const counts=[];
    for (const query of ['', 'layout', 'a completely unique search', 'fresh.test', 'javascript:alert(1)', 'layout', '']) {
      await input.fill(query); await settle(page);
      const box=await input.boundingBox();
      if (!anchor) anchor=box;
      assert.ok(Math.abs(box.y-anchor.y)<1,`${selector}: input moved from ${anchor.y} to ${box.y} for ${query}`);
      assert.ok(Math.abs(box.x-anchor.x)<1,`${selector}: input shifted horizontally`);
      counts.push(await page.getByRole('option').count());
      const bounds=await page.locator(selector).evaluate(el=>{const r=el.getBoundingClientRect();return {top:r.top,bottom:r.bottom,height:innerHeight};});
      assert.ok(bounds.top>=0 && bounds.bottom<=bounds.height+1,`${selector}: search extends beyond the window`);
    }
    assert.ok(counts.includes(0) && counts.includes(1) && counts.includes(8),'Fixture must exercise empty, single, and eight-result layouts');
    if (compact) {
      const scroll=page.locator(selector==='.command-palette' ? '.palette-body' : '.new-tab-results');
      assert.ok(await scroll.evaluate(el=>el.scrollHeight>el.clientHeight),'Results should scroll in a short window');
      for(let i=0;i<7;i++) await input.press('ArrowDown');
      await settle(page);
      const selected=await page.getByRole('option',{selected:true}).boundingBox();
      const viewport=await scroll.boundingBox();
      assert.ok(selected.y>=viewport.y-1 && selected.y+selected.height<=viewport.y+viewport.height+1,'Keyboard selection must scroll into view without moving the input');
      assert.ok(Math.abs((await input.boundingBox()).y-anchor.y)<1);
    }
  }
  await checkAnchored(ui,'.new-tab-search',false);
  await application.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].setSize(800,480));
  await settle(ui);
  await checkAnchored(ui,'.new-tab-search',true);
  await ui.screenshot({path:'test-results/search-anchor-new-tab.png'});
  await send(ui,{type:'tab.select',id:'layout-0'});
  await waitFor(async()=>!(await getState(ui)).tabs.find(t=>t.id==='layout-0').loading,'Website did not load');
  await send(ui,{type:'palette',mode:'new'});
  await chrome.getByRole('dialog').waitFor();
  await chrome.evaluate(async()=>{await Promise.all(document.getAnimations().filter(a=>a.effect?.getTiming().iterations!==Infinity).map(a=>a.finished.catch(()=>{})));});
  await checkAnchored(chrome,'.command-palette',true);
  await chrome.screenshot({path:'test-results/search-anchor-palette.png'});
  await application.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].setSize(1280,840));
  await settle(chrome);
  await checkAnchored(chrome,'.command-palette',false);
  console.log('PASS: New Tab and palette inputs remain anchored across 0/1/8 results, resizing, and keyboard scrolling.');
} finally {
  if(application) await application.close();
  await new Promise(resolve=>server.close(resolve));
  await rm(userData,{recursive:true,force:true});
}
