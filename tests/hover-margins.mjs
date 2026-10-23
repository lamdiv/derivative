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
  const first=await launch();application=first.app;const ui=first.ui;
  await send(ui,{type:'navigate',input:address,newTab:true});
  await waitFor(async()=>(await getState(ui)).tabs[0]?.loading===false,'Page not loaded');
  await application.evaluate(({BrowserWindow,webContents})=>{
    globalThis.hoverTrace=[];
    for(const wc of webContents.getAllWebContents())wc.on('before-mouse-event',(_event,m)=>{globalThis.hoverTrace.push({id:wc.id,type:m.type,x:m.x,y:m.y});globalThis.hoverTrace=globalThis.hoverTrace.slice(-40);});
    BrowserWindow.getAllWindows()[0].on('blur',()=>globalThis.hoverTrace.push({type:'window-blur'}));
  });
  await send(ui,{type:'preferences',preferences:{sidebarMode:'hover'}});
  const move=(x,y,type='mouseMove')=>application.evaluate(({webContents},{x,y,type})=>webContents.getAllWebContents().find(w=>w.getURL().includes('chrome=1')).sendInputEvent({type,x,y}),{x,y,type});
  const height=await chrome.evaluate(()=>innerHeight);
  for(let pass=0;pass<3;pass++) {
    await application.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].webContents.sendInputEvent({type:'mouseMove',x:2,y:220}));
    await waitFor(async()=>(await getState(ui)).sidebarRevealed,'Reveal failed');
    await chrome.getByRole('button',{name:'Keep sidebar open',exact:true}).waitFor();
    await chrome.screenshot({path:'test-results/perf-hover.png'});
    for(const [x,y]of [[3,3],[311,220],[130,height-3]]) {
      await move(x,y);await new Promise(resolve=>setTimeout(resolve,260));
      if(!(await getState(ui)).sidebarRevealed)console.log('TRACE',await application.evaluate(()=>globalThis.hoverTrace));
      assert.equal((await getState(ui)).sidebarRevealed,true,`Margin ${x},${y} must stay revealed`);
    }
    await move(316,220,'mouseLeave');
    await new Promise(resolve=>setTimeout(resolve,80));await move(120,220,'mouseEnter');
    await new Promise(resolve=>setTimeout(resolve,260));
    assert.equal((await getState(ui)).sidebarRevealed,true);
    await send(ui,{type:'sidebar.reveal',visible:false});
    await waitFor(async()=>!(await getState(ui)).sidebarRevealed,'Dismiss failed');
    await new Promise(resolve=>setTimeout(resolve,220));
  }
  console.log('PASS: floating sidebar corner/margins, screenshot, cancellation, dismissal, and three reveal cycles.');
} finally {
  if (application) await application.close();
  await new Promise(resolve => server.close(resolve));
  await rm(userData, { recursive: true, force: true });
}
