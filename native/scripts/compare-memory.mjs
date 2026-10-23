// Diagnostic RSS comparison, not unique physical memory or a production benchmark.
import { spawn, execFileSync } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtemp, rm, mkdir, writeFile, realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import assert from 'node:assert/strict';
import { _electron, chromium } from 'playwright';
import { runtime } from '../../scripts/runtime.mjs';
import { command, waitFor } from './driver.mjs';
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const server=createServer((_req,res)=>{res.setHeader('content-type','text/html');res.end('<!doctype html><title>Memory fixture</title><style>body{font:18px system-ui;padding:60px;background:#faf7f2;color:#453f4d}</style><h1>Same page, different shell</h1><textarea aria-label="Draft"></textarea>'+Array.from({length:300},(_,i)=>`<p>Local reading fixture ${i}</p>`).join(''));});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const url=`http://127.0.0.1:${server.address().port}`;
function sample(root) {
  const rows=execFileSync('ps',['-axo','pid=,ppid=,rss=,command='],{encoding:'utf8'}).trim().split('\n').map(line=>{
    const match=line.trim().match(/^(\d+)\s+(\d+)\s+(\d+)\s+(.*)$/);
    return match?{pid:+match[1],parent:+match[2],rssKiB:+match[3],command:match[4]}:null;
  }).filter(Boolean);
  const ids=new Set([root]);let changed=true;
  while(changed){changed=false;for(const row of rows)if(ids.has(row.parent)&&!ids.has(row.pid)){ids.add(row.pid);changed=true;}}
  const processes=rows.filter(row=>ids.has(row.pid));
  return {rssMiB:+(processes.reduce((n,row)=>n+row.rssKiB,0)/1024).toFixed(1),processes:processes.map(row=>({pid:row.pid,rssMiB:+(row.rssKiB/1024).toFixed(1),role:row.pid===root?'browser':row.command.match(/--type=([^ ]+)/)?.[1]??'helper'}))};
}
async function measure(name,pid,version) {
  await sleep(3000);
  const samples=[];for(let i=0;i<7;i++){samples.push(sample(pid));await sleep(300);}
  const sorted=samples.map(s=>s.rssMiB).sort((a,b)=>a-b);
  return {name,version,medianRssMiB:sorted[3],samplesRssMiB:samples.map(s=>s.rssMiB),processes:samples.at(-1).processes};
}
const results=[];
let native, browser, electron;
const nativeProfile=await mkdtemp(join(tmpdir(),'derivative-native-memory-'));
const electronProfile=await mkdtemp(join(tmpdir(),'derivative-electron-memory-'));
try {
  const portServer=createServer();await new Promise(resolve=>portServer.listen(0,'127.0.0.1',resolve));
  const port=portServer.address().port;await new Promise(resolve=>portServer.close(resolve));
  native=spawn(await realpath(resolve('native/build/Derivative Native.app/Contents/MacOS/Derivative Native')),[`--url=${url}`,`--remote-debugging-port=${port}`],{env:{...process.env,DERIVATIVE_NATIVE_USER_DATA:nativeProfile,DERIVATIVE_NATIVE_AUTOMATED:'1',DERIVATIVE_NATIVE_TEST_DIRECTORY:join(nativeProfile,'test-driver')},stdio:'ignore'});
  for(let i=0;i<60;i++){try{browser=await chromium.connectOverCDP(`http://127.0.0.1:${port}`,{timeout:1000});break;}catch{await sleep(200);}}
  assert.ok(browser,'Native browser did not start');
  let nativePage;await waitFor(()=>{nativePage=browser.contexts().flatMap(context=>context.pages()).find(page=>page.url()===url+'/');return !!nativePage;},'Native page did not appear');await nativePage.getByRole('heading',{name:'Same page, different shell'}).waitFor();
  results.push(await measure('SwiftUI/AppKit + CEF',native.pid,browser.version()));
  await command(join(nativeProfile,'test-driver'),'quit');
  await browser.close().catch(()=>{});browser=null;
  await Promise.race([new Promise(resolve=>native.once('exit',resolve)),sleep(5000)]);
  if(native.exitCode===null)throw new Error('Native app did not exit after Browser.close');
  assert.equal(native.exitCode,0);
  const env={...process.env,DERIVATIVE_USER_DATA:electronProfile};delete env.ELECTRON_RUN_AS_NODE;delete env.ELECTRON_RENDERER_URL;
  electron=await _electron.launch({executablePath:await runtime(),args:[resolve('.')],env});
  await electron.firstWindow();
  await electron.evaluate(({BrowserWindow})=>{const window=BrowserWindow.getAllWindows()[0];window.setIgnoreMouseEvents(true);window.setFocusable(false);});
  const ui=electron.context().pages().find(page=>page.url().includes('index.html')&&!page.url().includes('chrome=1'));
  await ui.waitForFunction(()=>!!window.browser);
  await ui.evaluate(input=>window.browser.dispatch({type:'navigate',input,newTab:true}),url);
  let web;
  for(let i=0;i<60;i++){web=electron.context().pages().find(p=>p.url()===url+'/');if(web)break;await sleep(100);}
  assert.ok(web,'Electron page did not load');await web.getByRole('heading',{name:'Same page, different shell'}).waitFor();
  const versions=await electron.evaluate(()=>process.versions);
  results.push(await measure('Electron + React',electron.process().pid,versions.chrome));
  const report={measuredAt:new Date().toISOString(),fixture:'One loaded local page, fixed 288px sidebar, fresh profiles; seven process-tree RSS samples after three seconds settling.',limitations:['Sum of resident sets counts shared pages more than once; this is not unique physical footprint.','The native prototype has fewer features than the Electron app.','Chromium versions differ; this does not isolate UI framework costs.','Single local run; no multi-tab, long-session, energy, or login compatibility claim.'],results};
  await mkdir('test-results',{recursive:true});await writeFile('test-results/native-memory.json',JSON.stringify(report,null,2));
  console.log(JSON.stringify(report,null,2));
}finally{
  if(electron)await electron.close();
  if(native?.exitCode===null)native.kill('SIGTERM');
  if(browser)await browser.close().catch(()=>{});
  await new Promise(resolve=>server.close(resolve));
  await rm(nativeProfile,{recursive:true,force:true});await rm(electronProfile,{recursive:true,force:true});
}
