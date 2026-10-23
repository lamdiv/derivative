import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtemp, rm, readFile, writeFile, realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import assert from 'node:assert/strict';
import { NativeTarget } from './target.mjs';
import { command, waitFor } from './driver.mjs';

const server=createServer((req,res)=>{res.setHeader('content-type','text/html');res.end(`<!doctype html><title>${req.url}</title><h1>Native tab ${req.url}</h1><textarea aria-label="Draft"></textarea>`);});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const address=`http://127.0.0.1:${server.address().port}`;
const profile=await mkdtemp(join(tmpdir(),'derivative-native-tabs-'));
const driver=join(profile,'test-driver');
const executable=await realpath(resolve('native/build/Derivative Native.app/Contents/MacOS/Derivative Native'));
let app,logs='',debugPort;let connections=[];
const snapshot=()=>command(driver,'snapshot');
async function launch(){
  const ports=createServer();await new Promise(resolve=>ports.listen(0,'127.0.0.1',resolve));const port=ports.address().port;await new Promise(resolve=>ports.close(resolve));
  logs='';debugPort=port;
  app=spawn(executable,[`--remote-debugging-port=${port}`],{env:{...process.env,DERIVATIVE_NATIVE_USER_DATA:profile,DERIVATIVE_NATIVE_TEST_DIRECTORY:driver,DERIVATIVE_NATIVE_TRACE:'1',DERIVATIVE_NATIVE_AUTOMATED:process.env.KEEP_NATIVE==='1'?'0':'1'},stdio:['ignore','ignore','pipe']});
  app.stderr.on('data',chunk=>{logs+=chunk;});
  await waitFor(async()=>{try{return (await fetch(`http://127.0.0.1:${port}/json/list`)).ok;}catch{return false;}},'Native browser did not start');
}
async function page(path){
  let info;await waitFor(async()=>{const targets=await fetch(`http://127.0.0.1:${debugPort}/json/list`).then(r=>r.json());info=targets.find(p=>p.url===address+path);return !!info;},'Missing native page '+path);
  const target=new NativeTarget(info.webSocketDebuggerUrl);connections.push(target);await target.ready;
  await waitFor(async()=>await target.evaluate(()=>document.querySelector('h1')?.textContent)==='Native tab '+path,'Page did not render '+path);
  return target;
}
async function quit(){
  const exited=new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('Native quit failed: '+logs)),10000);app.once('exit',()=>{clearTimeout(timer);resolve();});});
  await command(driver,'quit');await exited;assert.equal(app.exitCode,0,logs);
  assert.doesNotMatch(logs,/Defaulting to in-memory|cache_path is invalid/);
  for(const connection of connections)connection.close();connections=[];
}
try{
  const tab=(id,spaceId,path)=>({id,spaceId,url:address+path,title:path,pinned:false,lastActive:1});
  await writeFile(join(profile,'native-state.json'),JSON.stringify({version:1,spaces:[{id:'personal',name:'Personal',icon:'camera.macro',color:'lavender'},{id:'work',name:'Work',icon:'diamond',color:'mint'},{id:'study',name:'Study',icon:'sun.max',color:'peach'}],tabs:[tab('one','personal','/one'),tab('two','personal','/two'),tab('work-tab','work','/work')],folders:[],favorites:[],history:[],activeSpaceId:'personal',activeTabId:'one',preferences:{theme:'dark',sidebarMode:'fixed',sidebarSize:'comfortable',restoreSession:true,searchEngine:'google'}}));
  await launch();const first=await page('/one');
  assert.equal((await snapshot()).loadedPages,1,'Restore background tabs lazily');
  await first.evaluate(()=>{document.querySelector('textarea').value='Keep this live form';});
  await first.evaluate(()=>{document.cookie='profile=personal; Path=/; Max-Age=86400';localStorage.setItem('profile','personal');});
  const original=(await snapshot()).pageBounds;
  const search=await command(driver,'search');assert.equal(search.searchOpen,true);assert.equal(search.state.tabs.length,3);assert.deepEqual(search.pageBounds,original,'Search must not resize the page');
  await command(driver,'dismissSearch');
  await command(driver,'selectSpace',{id:'work'});const work=await page('/work');
  assert.equal(await work.evaluate(()=>document.cookie),'');assert.equal(await work.evaluate(()=>localStorage.getItem('profile')),null);
  await work.evaluate(()=>{document.cookie='profile=work; Path=/; Max-Age=86400';localStorage.setItem('profile','work');});
  await command(driver,'selectSpace',{id:'personal'});
  assert.equal(await first.evaluate(()=>document.querySelector('textarea').value),'Keep this live form');
  assert.match(await first.evaluate(()=>document.cookie),/profile=personal/);
  await command(driver,'selectTab',{id:'two'});const second=await page('/two');
  assert.equal((await snapshot()).loadedPages,3);
  assert.match(await second.evaluate(()=>document.cookie),/profile=personal/,'Tabs in one Space share their profile');
  await command(driver,'closeTab',{id:'two'});
  await waitFor(async()=>{const s=await snapshot();return s.loadedPages===2&&!s.state.tabs.some(t=>t.id==='two');},'Closing a tab did not destroy only that view');
  assert.equal(await first.evaluate(()=>document.querySelector('textarea').value),'Keep this live form');
  await command(driver,'selectSpace',{id:'study'});
  for(let i=0;i<2;i++){const s=await command(driver,'search');assert.equal(s.homeVisible,true);assert.equal(s.searchOpen,false);assert.equal(s.loadedPages,2);assert.equal(s.state.tabs.length,2);}
  await command(driver,'submit',{input:address+'/study',newTab:true});const study=await page('/study');
  assert.equal(await study.evaluate(()=>document.cookie),'');
  await study.evaluate(()=>{document.cookie='profile=study; Path=/; Max-Age=86400';localStorage.setItem('profile','study');});
  await command(driver,'selectSpace',{id:'work'});
  await work.evaluate(url=>{window.open(url);return true;},address+'/popup',true);const popup=await page('/popup');
  assert.match(await popup.evaluate(()=>document.cookie),/profile=work/,'Popup tab must use its opener’s profile');
  assert.equal((await snapshot()).state.activeSpaceId,'work');
  await quit();
  const saved=JSON.parse(await readFile(join(profile,'native-state.json'),'utf8'));assert.equal(saved.tabs.length,4,'Quit must preserve session metadata');
  await launch();const restored=await page('/popup');
  assert.equal((await snapshot()).loadedPages,1,'Restart should load only the selected tab');
  assert.match(await restored.evaluate(()=>document.cookie),/profile=work/);assert.equal(await restored.evaluate(()=>localStorage.getItem('profile')),'work');
  await command(driver,'selectSpace',{id:'personal'});const restoredPersonal=await page('/one');
  assert.match(await restoredPersonal.evaluate(()=>document.cookie),/profile=personal/);
  await command(driver,'selectSpace',{id:'study'});const restoredStudy=await page('/study');
  assert.match(await restoredStudy.evaluate(()=>document.cookie),/profile=study/);
  await quit();
  console.log('PASS: lazy native tabs, live form retention, view destruction, deferred search, profile isolation, popup ownership, restart persistence, and clean multi-tab quit.');
}catch(error){
  console.error(logs);
  console.error('Native snapshot:',await snapshot().catch(()=>null));
  console.error('Targets:',await fetch(`http://127.0.0.1:${debugPort}/json/list`).then(r=>r.json()).catch(()=>null));
  throw error;
}finally{
  if(app?.exitCode===null)app.kill('SIGTERM');for(const connection of connections)connection.close();
  await new Promise(resolve=>server.close(resolve));await rm(profile,{recursive:true,force:true});
}
