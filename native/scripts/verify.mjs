import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtemp, rm, realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { command, waitFor } from './driver.mjs';

const server=createServer((req,res)=>{
  res.setHeader('content-type','text/html');
  res.end(`<!doctype html><title>${req.url==='/two'?'Second page':'Native Chromium fixture'}</title><style>body{font:18px system-ui;padding:60px;background:#faf7f2;color:#453f4d}textarea{display:block;margin:25px 0;width:300px;height:80px}</style><h1>Chromium, with native controls</h1><textarea aria-label="Draft" placeholder="Type here"></textarea><a href="/two">Next page</a>`);
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const address=`http://127.0.0.1:${server.address().port}`;
const portServer=createServer();await new Promise(resolve=>portServer.listen(0,'127.0.0.1',resolve));
const port=portServer.address().port;await new Promise(resolve=>portServer.close(resolve));
const profile=await mkdtemp(join(tmpdir(),'derivative-native-'));
const driver=join(profile,'test-driver');
const app=spawn(await realpath(resolve(process.env.DERIVATIVE_NATIVE_APP || 'native/build/Derivative.app', 'Contents/MacOS/Derivative')),['--use-mock-keychain',`--url=${address}`,`--remote-debugging-port=${port}`],{env:{...process.env,DERIVATIVE_NATIVE_USER_DATA:profile,DERIVATIVE_NATIVE_TEST_DIRECTORY:driver,DERIVATIVE_NATIVE_TRACE:'1',DERIVATIVE_NATIVE_AUTOMATED:process.env.KEEP_NATIVE==='1'?'0':'1'},stdio:['ignore','pipe','pipe']});
let logs='';app.stderr.on('data',chunk=>{logs+=chunk;});
let browser;
try {
  const end=Date.now()+20000;
  while(Date.now()<end){
    if(app.exitCode!==null)throw new Error(`Native app exited (${app.exitCode}): ${logs}`);
    try{browser=await chromium.connectOverCDP(`http://127.0.0.1:${port}`,{timeout:1000});break;}catch{await new Promise(resolve=>setTimeout(resolve,200));}
  }
  assert.ok(browser,`Native browser debugging endpoint did not start: ${logs}`);
  let page;await waitFor(()=>{page=browser.contexts().flatMap(context=>context.pages()).find(page=>page.url()===address+'/');return !!page;},'Native page did not appear: '+logs);
  await page.waitForURL(address+'/');
  await page.getByRole('heading',{name:'Chromium, with native controls'}).waitFor();
  assert.equal(await page.evaluate(()=>typeof process),'undefined');
  await page.getByRole('textbox',{name:'Draft'}).fill('A native browser with a real Chromium page');
  assert.equal(await page.getByRole('textbox',{name:'Draft'}).inputValue(),'A native browser with a real Chromium page');
  await page.getByRole('link',{name:'Next page'}).click();
  await page.waitForURL(address+'/two');
  await page.evaluate(()=>history.back());
  await page.waitForURL(address+'/',{waitUntil:'commit'});
  assert.equal(await page.getByRole('textbox',{name:'Draft'}).inputValue(),'A native browser with a real Chromium page');
  console.log('PASS: sandboxed native Chromium renders, accepts input, navigates, and restores live form state.');
  console.log('Native PID:',app.pid);
  if(process.env.KEEP_NATIVE==='1'){
    console.log('Keeping native browser open for UI inspection.');
    await new Promise(resolve=>app.once('exit',resolve));
    assert.equal(app.exitCode,0,logs);
    console.log('PASS: native window/menu quit exits cleanly.');
  }else{
    const exited=new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('Native app did not shut down: '+logs)),8000);app.once('exit',()=>{clearTimeout(timer);resolve();});});
    await command(driver,'quit');
    await exited;
    assert.equal(app.exitCode,0,logs);
    console.log('PASS: Chromium and native host shut down cleanly.');
  }
}finally{
  if(app.exitCode===null)app.kill('SIGTERM');
  if(browser)await browser.close().catch(()=>{});
  await new Promise(resolve=>server.close(resolve));
  await rm(profile,{recursive:true,force:true});
}
