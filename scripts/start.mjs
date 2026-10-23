import { spawn } from 'node:child_process';
import { runtime } from './runtime.mjs';
const child = spawn(await runtime(), ['.'], { stdio: 'inherit', env: process.env });
child.on('exit', code => process.exit(code ?? 0));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => child.kill(signal));
