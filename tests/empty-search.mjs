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
  await writeFile(join(userData,'browser-state.json'),JSON.stringify({version:1,activeSpaceId:'personal',activeTabId:'blank',tabs:[{id:'blank',url:'derivative://new-tab',title:'New tab',spaceId:'personal',profileId:'personal',pinned:false,lastActive:1}]}));
  const first=await launch(); application=first.app; const ui=first.ui;
  // Publishers survive renderer reloads; the bridge must recover a complete snapshot.
  await ui.reload();
  await chrome.reload();
  await ui.getByRole('heading',{name:'New tab',exact:true}).waitFor();
  assert.equal((await getState(ui)).activeTabId,'blank');
  await ui.getByRole('combobox').fill('keep this draft');
  for (const key of ['t','t','l']) {
    await ui.getByRole('button',{name:'Add favorite',exact:true}).focus();
    await shortcut(key);
    await ui.waitForFunction(()=>{const input=document.querySelector('.new-tab-input input');return document.activeElement===input && input.selectionStart===0 && input.selectionEnd===input.value.length;});
    assert.equal((await getState(ui)).overlay,null);
    assert.equal((await getState(ui)).activeTabId,'blank');
    assert.equal((await getState(ui)).tabs.length,1);
    assert.equal((await native(application)).length,0);
    assert.equal(await chrome.getByRole('dialog').count(),0);
  }
  await send(ui,{type:'tab.close',id:'blank'});
  await ui.getByRole('heading',{name:'New tab',exact:true}).waitFor();
  await shortcut('t');
  await ui.waitForFunction(()=>document.activeElement===document.querySelector('.new-tab-input input'));
  assert.equal((await getState(ui)).tabs.length,0);
  assert.equal((await getState(ui)).overlay,null);
  console.log('PASS: Cmd+T/Cmd+L focus the existing internal New Tab or empty-Space search without overlays or extra tabs.');
} finally {
  if (application) await application.close();
  await new Promise(resolve => server.close(resolve));
  await rm(userData, { recursive: true, force: true });
}
