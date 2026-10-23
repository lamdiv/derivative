import { createServer } from 'vite';
import { spawn } from 'node:child_process';
import { watch } from 'node:fs';
import { once } from 'node:events';
import { runtime } from './runtime.mjs';

const rebuild = () => import(`./build-electron.mjs?build=${Date.now()}`);
await rebuild();
const server = await createServer();
await server.listen();
const executable = await runtime();
let child, restarting = false, stopping = false, pending = false, timer;
const watchers = [];
function launch() {
  child = spawn(executable, ['.'], { stdio:'inherit', env:{ ...process.env, ELECTRON_RENDERER_URL:'http://127.0.0.1:5173' } });
  child.on('exit', async code => {
    if (restarting || stopping) return;
    for (const watcher of watchers) watcher.close();
    await server.close(); process.exit(code ?? 0);
  });
}
async function restart() {
  if (stopping) return;
  if (restarting) { pending = true; return; }
  restarting = true;
  try {
    await rebuild();
    if (stopping) return;
    const exited = once(child, 'exit'); child.kill('SIGTERM'); await exited;
    if (!stopping) { launch(); console.log('Derivative restarted with updated native actions.'); }
  } catch (error) { console.error('Native rebuild failed; keeping the running app:', error.message); }
  finally { restarting = false; if (pending && !stopping) { pending = false; void restart(); } }
}
for (const directory of ['electron', 'shared']) watchers.push(watch(directory, { recursive:true }, (_event, file) => {
  if (!file?.endsWith('.ts')) return;
  clearTimeout(timer); timer = setTimeout(() => void restart(), 200);
}));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => {
  if (stopping) return;
  stopping = true; clearTimeout(timer); for (const watcher of watchers) watcher.close();
  if (child?.exitCode === null && child.signalCode === null) { const exited = once(child, 'exit'); child.kill('SIGTERM'); await exited; }
  await server.close(); process.exit(0);
});
launch();
console.log('Derivative is running. Renderer changes update live; native/shared changes rebuild and restart automatically.');
