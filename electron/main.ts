import { app, BrowserWindow, ipcMain, Menu, nativeTheme, session, type IpcMainInvokeEvent, type MenuItemConstructorOptions } from 'electron';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { performance } from 'node:perf_hooks';
import { existsSync } from 'node:fs';
import { Store } from './storage/store';
import { TabManager } from './tabs/manager';
import { validAction } from './ipc';
import { ChromeLayer } from './windows/chrome-layer';

const started = performance.now();
app.setName('Derivative');
if (process.env.DERIVATIVE_USER_DATA) app.setPath('userData', process.env.DERIVATIVE_USER_DATA);
if (!app.requestSingleInstanceLock()) app.exit(0);
const devURL = !app.isPackaged ? process.env.ELECTRON_RENDERER_URL : undefined;
if (devURL) for (const signal of ['SIGINT', 'SIGTERM'] as const) process.once(signal, () => app.quit());
const uiURL = devURL ? new URL(devURL).href : pathToFileURL(join(__dirname, '../dist/index.html')).href;
let window: BrowserWindow | undefined;
let manager: TabManager | undefined;
let chrome: ChromeLayer | undefined;
let quitting = false;
app.on('second-instance', () => { if (window) { if (window.isMinimized()) window.restore(); window.show(); window.focus(); } });

function assertTrusted(event: IpcMainInvokeEvent): void {
  const trusted = window && ((event.sender === window.webContents && event.senderFrame?.url === uiURL) || (event.sender === chrome?.view.webContents && event.senderFrame?.url === chrome.url));
  if (!trusted || event.senderFrame !== event.sender.mainFrame) throw new Error('Untrusted IPC sender');
}
ipcMain.handle('browser:state', event => { assertTrusted(event); return manager?.state; });
ipcMain.handle('browser:action', async (event, action: unknown) => {
  assertTrusted(event);
  if (!validAction(action)) {
    const type = action && typeof action === 'object' && 'type' in action && typeof action.type === 'string' ? action.type.slice(0, 64) : 'unknown';
    throw new Error(`Invalid browser action: ${type}`);
  }
  if (manager && action.type === 'preferences' && action.preferences.theme && nativeTheme.themeSource !== action.preferences.theme) {
    nativeTheme.themeSource = action.preferences.theme;
    manager.state.dark = nativeTheme.shouldUseDarkColors;
  }
  await manager?.dispatch(action);
});

async function createWindow(): Promise<void> {
  const store = new Store(join(app.getPath('userData'), 'browser-state.json'));
  const state = await store.read();
  nativeTheme.themeSource = state.preferences.theme;
  state.dark = nativeTheme.shouldUseDarkColors;
  window = new BrowserWindow({
    width: 1280, height: 840, minWidth: 700, minHeight: 480,
    title: 'Derivative', backgroundColor: state.dark ? '#292536' : '#e8e0f4',
    titleBarStyle: 'hiddenInset', trafficLightPosition: { x: 20, y: 20 }, show: false,
    webPreferences: { preload: join(__dirname, 'preload.cjs'), nodeIntegration: false, contextIsolation: true, sandbox: true, webSecurity: true, navigateOnDragDrop: false },
  });
  const current = window;
  chrome = new ChromeLayer(current, uiURL, join(__dirname, 'preload.cjs'));
  manager = new TabManager(current, state, session.fromPartition('persist:personal'), store, chrome);
  chrome.view.webContents.on('before-input-event', (event, input) => { if (manager?.shortcut(input)) event.preventDefault(); });
  current.webContents.on('will-navigate', event => event.preventDefault());
  current.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  current.webContents.on('before-input-event', (event, input) => { if (manager?.shortcut(input)) event.preventDefault(); });
  current.once('ready-to-show', () => {
    current.show();
    if (state.activeTabId) manager?.select(state.activeTabId);
    if (!app.isPackaged) console.info(`[performance] main-entry-to-window-ready ${Math.round(performance.now() - started)}ms`);
  });
  current.on('closed', () => { chrome?.destroy(); chrome = undefined; window = undefined; });
  await Promise.all([current.loadURL(uiURL), chrome.load()]);
  manager.emit(false);
}

void app.whenReady().then(async () => {
  const invokeKey = (key: string, shift = false) => manager?.shortcut({ type: 'keyDown', key, code: '', isAutoRepeat: false, isComposing: false, location: 0, modifiers: [], shift, meta: process.platform === 'darwin', control: process.platform !== 'darwin', alt: false });
  const iconPath = join(__dirname, '../assets/icon.png');
  if (process.platform === 'darwin' && existsSync(iconPath)) app.dock?.setIcon(iconPath);
  const template: MenuItemConstructorOptions[] = [
    { label: 'Derivative', submenu: [{ role: 'about' }, { label: 'Settings…', accelerator: 'CmdOrCtrl+,', click: () => void manager?.dispatch({ type: 'settings' }) }, { type: 'separator' }, { role: 'services' }, { role: 'hide' }, { role: 'hideOthers' }, { role: 'unhide' }, { type: 'separator' }, { role: 'quit' }] },
    { label: 'File', submenu: [{ label: 'New Tab', accelerator: 'CmdOrCtrl+T', click: () => manager?.newTab() }, { label: 'Open Location', accelerator: 'CmdOrCtrl+L', click: () => manager?.openPalette('navigate') }, { label: 'Reopen Closed Tab', accelerator: 'CmdOrCtrl+Shift+T', click: () => invokeKey('t', true) }, { label: 'Pin / Unpin Tab', accelerator: 'CmdOrCtrl+D', click: () => invokeKey('d') }, { label: 'Copy Page URL', accelerator: 'CmdOrCtrl+Shift+C', click: () => invokeKey('c', true) }, { label: 'Close Tab', accelerator: 'CmdOrCtrl+W', click: () => { const tab = manager?.active(); if (tab) manager?.close(tab.id); } }] },
    { role: 'editMenu' },
    { label: 'View', submenu: [{ label: 'Toggle Sidebar', accelerator: 'CmdOrCtrl+S', click: () => void manager?.dispatch({ type: 'sidebar.toggle' }) }, { label: 'Reload Page', accelerator: 'CmdOrCtrl+R', click: () => void manager?.dispatch({ type: 'reload' }) }, { role: 'togglefullscreen' }, ...(!app.isPackaged ? [{ role: 'toggleDevTools' as const }] : [])] },
    { role: 'windowMenu' },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
  nativeTheme.on('updated', () => { if (manager && manager.state.dark !== nativeTheme.shouldUseDarkColors) { manager.state.dark = nativeTheme.shouldUseDarkColors; manager.emit(false); } });
  await createWindow();
}).catch(error => { console.error('Derivative could not start:', error); app.quit(); });

app.on('before-quit', event => {
  if (quitting) return;
  event.preventDefault(); quitting = true;
  void (async () => { try { await manager?.shutdown(); } catch (error) { console.error('Could not save session:', (error as Error).message); } finally { app.quit(); } })();
});
app.on('window-all-closed', () => { app.quit(); });
app.on('activate', () => { if (!window) void createWindow(); });
