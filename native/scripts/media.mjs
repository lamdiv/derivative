// Real Chromium decoding checks; capability strings alone are not a playback test.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, mkdtemp, realpath, rm, mkdir, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { tmpdir } from 'node:os';
import { NativeTarget } from './target.mjs';
import { command, waitFor } from './driver.mjs';

const appIndex = process.argv.indexOf('--app');
const bundle = resolve(appIndex >= 0 ? process.argv[appIndex+1] : 'native/build/Derivative.app');
const required = process.argv.includes('--require-proprietary');
const fixtures = new Map(await Promise.all([
  ['h264-aac.mp4', 'video/mp4'], ['aac.m4a', 'audio/mp4'], ['vp9-opus.webm', 'video/webm']
].map(async ([name, type]) => ['/'+name, { bytes: await readFile(resolve('native/Tests/Media', name)), type }])));
const server = createServer((req, res) => {
  const file = fixtures.get(req.url);
  if (file) {
    let start = 0, end = file.bytes.length-1;
    const range = req.headers.range?.match(/^bytes=(\d+)-(\d*)$/);
    if (range) { start = Number(range[1]); if (range[2]) end = Math.min(end, Number(range[2])); }
    if (start > end || start >= file.bytes.length) { res.writeHead(416).end(); return; }
    res.writeHead(range ? 206 : 200, { 'content-type': file.type, 'accept-ranges': 'bytes', 'cache-control': 'no-store',
      'content-length': end-start+1, ...(range ? { 'content-range': `bytes ${start}-${end}/${file.bytes.length}` } : {}) });
    res.end(file.bytes.subarray(start, end+1)); return;
  }
  res.writeHead(200, { 'content-type': 'text/html' });
  res.end('<!doctype html><title>Media fixture</title><h1>Media fixture</h1><video muted playsinline width="160" height="90"></video>');
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const address = `http://127.0.0.1:${server.address().port}/`;
const ports = createServer(); await new Promise(resolve => ports.listen(0, '127.0.0.1', resolve));
const port = ports.address().port; await new Promise(resolve => ports.close(resolve));
const profile = await mkdtemp(join(tmpdir(), 'derivative-media-'));
const driver = join(profile, 'driver');
const app = spawn(await realpath(join(bundle, 'Contents/MacOS/Derivative')),
  ['--use-mock-keychain', `--url=${address}`, `--remote-debugging-port=${port}`],
  { env: { ...process.env, DERIVATIVE_NATIVE_USER_DATA: profile, DERIVATIVE_NATIVE_TEST_DIRECTORY: driver, DERIVATIVE_NATIVE_AUTOMATED: '1' }, stdio: ['ignore', 'ignore', 'pipe'] });
let logs = '', target;
app.stderr.on('data', chunk => logs += chunk);
const report = { app: bundle, required, results: {} };
try {
  let info;
  await waitFor(async () => {
    if (app.exitCode !== null) throw new Error(`Native browser exited: ${logs}`);
    try { info = (await fetch(`http://127.0.0.1:${port}/json/list`).then(r => r.json())).find(t => t.url === address); return !!info; } catch { return false; }
  }, 'Media fixture did not start');
  target = new NativeTarget(info.webSocketDebuggerUrl); await target.ready;
  await waitFor(() => target.evaluate(() => document.querySelector('h1')?.textContent === 'Media fixture'), 'Media document missing');
  report.capabilities = await target.evaluate(() => {
    const video = document.querySelector('video');
    return Object.fromEntries(['video/mp4; codecs="avc1.4D400A, mp4a.40.2"', 'audio/mp4; codecs="mp4a.40.2"', 'video/webm; codecs="vp9, opus"'].map(type => [type, { file: video.canPlayType(type), mse: MediaSource.isTypeSupported(type) }]));
  });
  async function playback(name, mse = false) {
    return target.evaluate(async ({ name, mse }) => {
      const video = document.querySelector('video'); video.pause();
      const result = await new Promise(resolve => {
        let frames = 0, seeking = false, done = false, objectURL;
        const finish = value => { if (done) return; done = true; clearTimeout(timer); video.pause(); if (objectURL) URL.revokeObjectURL(objectURL); resolve(value); };
        const timer = setTimeout(() => finish({ ok: false, reason: 'playback/seek timeout', frames, time: video.currentTime }), 5000);
        video.onerror = () => finish({ ok: false, reason: video.error?.message || 'media error', code: video.error?.code });
        video.onseeked = () => { if (seeking && video.currentTime > 1.4) finish({ ok: true, frames, width: video.videoWidth, time: video.currentTime }); };
        const frame = () => {
          if (done) return;
          frames++;
          if (frames >= 3 && video.currentTime > 0.2 && !seeking) { seeking = true; video.currentTime = 1.5; }
          video.requestVideoFrameCallback(frame);
        };
        video.requestVideoFrameCallback(frame);
        if (mse) {
          const media = new MediaSource(); objectURL = URL.createObjectURL(media); video.src = objectURL;
          media.addEventListener('sourceopen', async () => {
            try {
              const buffer = media.addSourceBuffer('video/mp4; codecs="avc1.4D400A, mp4a.40.2"');
              buffer.addEventListener('error', () => finish({ ok: false, reason: 'MSE append error' }));
              buffer.addEventListener('updateend', () => { if (media.readyState === 'open') media.endOfStream(); }, { once: true });
              buffer.appendBuffer(await fetch('/'+name).then(r => r.arrayBuffer()));
            } catch (error) { finish({ ok: false, reason: String(error) }); }
          }, { once: true });
        } else video.src = '/'+name;
        video.play().catch(error => finish({ ok: false, reason: String(error) }));
      });
      video.onerror = null; video.onseeked = null;
      return result;
    }, { name, mse }, true);
  }
  report.results.webm = await playback('vp9-opus.webm');
  report.results.mp4 = await playback('h264-aac.mp4');
  report.results.aac = await target.evaluate(async () => {
    try {
      const context = new OfflineAudioContext(1, 48000, 48000);
      const audio = await context.decodeAudioData(await fetch('/aac.m4a').then(r => r.arrayBuffer()));
      const samples = audio.getChannelData(0);
      const rms = Math.sqrt(samples.reduce((sum, value) => sum+value*value, 0)/samples.length);
      return { ok: audio.duration > 2 && rms > 0.01, duration: audio.duration, rms };
    } catch (error) { return { ok: false, reason: String(error) }; }
  });
  report.results.mse = report.capabilities['video/mp4; codecs="avc1.4D400A, mp4a.40.2"'].mse
    ? await playback('h264-aac.mp4', true) : { ok: false, reason: 'MP4 MSE unsupported' };
  await mkdir(resolve('test-results'), { recursive: true });
  await writeFile(resolve('test-results/native-media.json'), JSON.stringify(report, null, 2)+'\n');
  console.log(JSON.stringify(report, null, 2));
  assert.ok(report.results.webm.ok, 'WebM decoded frames and seeking must work');
  if (required) for (const name of ['mp4', 'aac', 'mse']) assert.ok(report.results[name].ok, `${name} must actually decode; see test-results/native-media.json`);
  console.log(required ? 'PASS: WebM, H.264/AAC MP4, AAC audio, seeking, and MP4 MSE decoding.' : 'PASS: baseline media report captured; proprietary codec support is reported, not required.');
} finally {
  if (app.exitCode === null) {
    try {
      const exited = new Promise(resolve => app.once('exit', resolve));
      await command(driver, 'quit');
      await Promise.race([exited, new Promise(resolve => setTimeout(resolve, 5000))]);
    } catch {}
    if (app.exitCode === null) app.kill('SIGTERM');
  }
  target?.close();
  await new Promise(resolve => server.close(resolve));
  await rm(profile, { recursive: true, force: true });
}
