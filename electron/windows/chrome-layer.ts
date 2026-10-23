import { BrowserWindow, WebContentsView } from 'electron';
import { effectiveSidebarMode, floatingSidebarWidth, sidebarReservesSpace } from '../../shared/layout';
import type { BrowserState } from '../../shared/types';

type Role = 'none' | 'sidebar' | 'modal';
/** Transparent trusted controls above live websites, with bounded native input coverage. */
export class ChromeLayer {
  readonly view: WebContentsView;
  readonly url: string;
  private role: Role = 'none';
  private sidebar = false;
  private attached = false;
  private closing = false;
  private buttonsVisible?: boolean;
  private buttonsInSidebar = false;
  private timer?: ReturnType<typeof setTimeout>;
  constructor(private window: BrowserWindow, url: string, preload: string) {
    const location = new URL(url); location.searchParams.set('chrome', '1'); this.url = location.href;
    this.view = new WebContentsView({ webPreferences: { preload, nodeIntegration: false, contextIsolation: true, sandbox: true, webSecurity: true, navigateOnDragDrop: false } });
    this.view.setBackgroundColor('#00000000');
    this.view.webContents.on('will-navigate', event => event.preventDefault());
    this.view.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  }
  async load(): Promise<void> { await this.view.webContents.loadURL(this.url); }
  sync(state: BrowserState): void {
    const visible = effectiveSidebarMode(state) === 'fixed' || state.sidebarRevealed;
    const wanted: Role = state.overlay ? 'modal' : visible && !sidebarReservesSpace(state) ? 'sidebar' : 'none';
    if (wanted === 'none' && sidebarReservesSpace(state) && this.role === 'sidebar') {
      // The fixed sidebar is now owned by the root renderer. A duplicate floating
      // copy would swallow the first click on its menus during the detach delay.
      clearTimeout(this.timer); this.timer = undefined; this.closing = false; this.role = 'none';
    }
    if (wanted === 'modal' || wanted === 'sidebar') {
      clearTimeout(this.timer); this.timer = undefined; this.closing = false; this.role = wanted;
    } else if (!this.closing && (this.role === 'sidebar' || this.role === 'modal' || (this.sidebar && !visible))) {
      this.closing = true;
      if (this.role === 'none') this.role = 'sidebar';
      this.timer = setTimeout(() => {
        this.detach();
        this.closing = false; this.role = 'none'; this.timer = undefined; this.sync(state);
      }, 180);
    } else if (!this.closing) this.role = wanted;
    this.sidebar = visible;
    if (this.role === 'none') this.detach();
    else {
      const [width, height] = this.window.getContentSize();
      const target = { x: 0, y: 0, width: this.role === 'modal' ? width : floatingSidebarWidth(state.preferences), height };
      const bounds = this.view.getBounds();
      if (Object.entries(target).some(([key, value]) => bounds[key as keyof typeof bounds] !== value)) this.view.setBounds(target);
      if (!this.attached || this.window.contentView.children.at(-1) !== this.view) { this.window.contentView.addChildView(this.view); this.attached=true; }
    }
    // In native fullscreen, macOS owns a separate, auto-revealing titlebar.
    // Hiding the buttons here also hides them in that top-edge reveal surface.
    const showButtons = this.window.isFullScreen() || (visible && !state.windowExpanded);
    if (process.platform === 'darwin') {
      const visibilityChanged = this.buttonsVisible !== showButtons;
      if (visibilityChanged) this.window.setWindowButtonVisibility(showButtons);
      const inSidebar = showButtons && !state.windowExpanded;
      // AppKit can reset geometry when controls become visible or leave fullscreen.
      // Apply their position after visibility so they share the sidebar's control row.
      if (inSidebar && (visibilityChanged || !this.buttonsInSidebar)) this.window.setWindowButtonPosition({ x: 20, y: 20 });
      this.buttonsVisible = showButtons;
      this.buttonsInSidebar = inSidebar;
    }
  }
  private detach(): void {
    if (!this.attached) return;
    this.window.contentView.removeChildView(this.view); this.attached=false;
  }
  get visible(): boolean { return this.role !== 'none'; }
  focus(): void { this.view.webContents.focus(); }
  destroy(): void { clearTimeout(this.timer); if (!this.view.webContents.isDestroyed()) this.view.webContents.close(); }
}
