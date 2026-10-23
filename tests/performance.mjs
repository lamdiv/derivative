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
  const tabs=Array.from({length:500},(_,i)=>({id:`tab-${i}`,spaceId:'personal',profileId:'personal',url:`${address}/tab-${i}`,title:`Page ${i}`,pinned:false,lastActive:i}));
  const history=Array.from({length:2000},(_,i)=>({url:`${address}/history-${i}`,title:`History page ${i}`,visitedAt:i}));
  await writeFile(join(userData,'browser-state.json'),JSON.stringify({version:1,tabs,history,activeSpaceId:'personal',activeTabId:'tab-0'}));
  const first=await launch(true); application=first.app; const ui=first.ui;
  await send(ui,{type:'tab.select',id:'tab-1'});await send(ui,{type:'tab.select',id:'tab-0'});
  await waitFor(async()=>{const s=await getState(ui);return s.tabs.slice(0,2).every(t=>!t.loading) && (await native(application)).length===1;},'Warm tabs did not load');
  await new Promise(resolve=>setTimeout(resolve,350));
  await application.evaluate(({BrowserWindow,webContents})=>{
    globalThis.broadcasts=[];
    for(const wc of [BrowserWindow.getAllWindows()[0].webContents,webContents.getAllWebContents().find(w=>w.getURL().includes('chrome=1'))]) {
      const original=wc.send.bind(wc);
      wc.send=(channel,payload,...args)=>{
        if(channel==='browser:changed'||channel==='browser:patch')globalThis.broadcasts.push({channel,tabs:payload?.tabs?.length??0,history:payload?.history?.length??0});
        return original(channel,payload,...args);
      };
    }
  });
  async function measure(name,actions) {
    await application.evaluate(()=>{globalThis.broadcasts=[];});
    const durations=[];
    for(const action of actions){const start=performance.now();await send(ui,action);durations.push(performance.now()-start);}
    durations.sort((a,b)=>a-b);
    const messages=await application.evaluate(()=>globalThis.broadcasts);
    return {name,actions:actions.length,medianMs:+durations[Math.floor(durations.length/2)].toFixed(2),p95Ms:+durations[Math.floor(durations.length*.95)].toFixed(2),messages:messages.length,tabItems:messages.reduce((n,m)=>n+m.tabs,0),historyItems:messages.reduce((n,m)=>n+m.history,0)};
  }
  const results=[];
  results.push(await measure('warm tab switches',Array.from({length:30},(_,i)=>({type:'tab.select',id:`tab-${i%2}`}))));
  results.push(await measure('sidebar interaction ownership',Array.from({length:40},(_,i)=>({type:'sidebar.interaction',id:'benchmark',active:i%2===0}))));
  results.push(await measure('palette open/close',Array.from({length:20},(_,i)=>i%2===0?{type:'palette',mode:'new'}:{type:'overlay.close'})));
  await new Promise(resolve=>setTimeout(resolve,350));
  await application.evaluate(()=>{globalThis.broadcasts=[];});
  await new Promise(resolve=>setTimeout(resolve,1000));
  const idleMessages=await application.evaluate(()=>globalThis.broadcasts.length);
  const stats={tabs:500,history:2000,results,idleMessages};
  if(process.env.PERF_ASSERT==='1') {
    assert.ok(results[0].messages<=30,'Warm switches should emit at most one update each while chrome is hidden');
    assert.equal(results[0].historyItems,0,'Tab switching must not resend unchanged history');
    assert.equal(results[1].messages,0,'Private sidebar ownership must not broadcast UI state');
    assert.equal(idleMessages,0,'Idle chrome must not broadcast updates');
  }
  const output=process.env.PERF_OUTPUT;
  if(output)await writeFile(output,JSON.stringify(stats,null,2));
  console.log(JSON.stringify(stats,null,2));
} finally {
  if (application) await application.close();
  await new Promise(resolve => server.close(resolve));
  await rm(userData, { recursive: true, force: true });
}
