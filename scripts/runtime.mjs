import electron from 'electron';
import { createHash } from 'node:crypto';
import { constants } from 'node:fs';
import { access, cp, readFile, writeFile, rm } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

// macOS derives its application menu name from the bundle, not app.setName().
// Brand a workspace-owned clone; never modify the installed Electron runtime.
export async function runtime() {
  if (process.platform !== 'darwin') return electron;
  const destination = resolve('dist-electron/Derivative.app');
  const marker = resolve('dist-electron/.derivative-runtime');
  const version = JSON.parse(await readFile(resolve('node_modules/electron/package.json'), 'utf8')).version;
  const iconHash = createHash('sha256').update(await readFile(resolve('assets/icon.icns'))).digest('hex');
  const signature = `${version}:${iconHash}`;
  try { if (await readFile(marker, 'utf8') === signature) return join(destination, 'Contents/MacOS/Electron'); } catch {}
  await rm(destination, { recursive: true, force: true });
  await cp(dirname(dirname(dirname(electron))), destination, { recursive: true, force: true, verbatimSymlinks: true, mode: constants.COPYFILE_FICLONE });
  const plist = join(destination, 'Contents/Info.plist');
  const run = promisify(execFile);
  for (const [key, value] of [['CFBundleDisplayName', 'Derivative'], ['CFBundleName', 'Derivative'], ['CFBundleIdentifier', 'app.derivative.browser.dev'], ['CFBundleIconFile', 'Derivative.icns']]) {
    try { await run('/usr/libexec/PlistBuddy', ['-c', `Set :${key} ${value}`, plist]); }
    catch { await run('/usr/libexec/PlistBuddy', ['-c', `Add :${key} string ${value}`, plist]); }
  }
  await cp(resolve('assets/icon.icns'), join(destination, 'Contents/Resources/Derivative.icns'));
  await access(join(destination, 'Contents/MacOS/Electron'));
  for (const attribute of ['com.apple.FinderInfo', 'com.apple.ResourceFork']) {
    try { await run('/usr/bin/xattr', ['-dr', attribute, destination]); } catch {}
  }
  await run('/usr/bin/codesign', ['--force', '--deep', '--sign', '-', destination]);
  await writeFile(marker, signature);
  return join(destination, 'Contents/MacOS/Electron');
}
