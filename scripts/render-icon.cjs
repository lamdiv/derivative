const { app, BrowserWindow } = require('electron');
const { writeFileSync, mkdtempSync, rmSync } = require('node:fs');
const { join, resolve } = require('node:path');
const { tmpdir } = require('node:os');
const data = mkdtempSync(join(tmpdir(), 'derivative-icon-'));
app.setPath('userData', data);
app.whenReady().then(async () => {
  const win = new BrowserWindow({ width: 1024, height: 1024, useContentSize: true, show: false, frame: false, transparent: true, webPreferences: { sandbox: true, contextIsolation: true, nodeIntegration: false } });
  const painted = new Promise(resolve => win.once('ready-to-show', resolve));
  await win.loadFile(resolve('assets/icon.svg'));
  await painted;
  const image = await win.webContents.capturePage({ x: 0, y: 0, width: 1024, height: 1024 });
  writeFileSync(resolve('assets/icon.png'), image.toPNG());
  win.destroy(); app.quit();
}).catch(error => { console.error(error); app.exit(1); });
app.on('will-quit', () => rmSync(data, { recursive: true, force: true }));
