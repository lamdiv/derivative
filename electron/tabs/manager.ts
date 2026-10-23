import { app, BrowserWindow, WebContentsView, clipboard, dialog, shell, session as electronSession, type Session, type Input, type DownloadItem } from 'electron';
import { randomUUID } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import type { Action, BrowserState, Download, Tab } from '../../shared/types';
import { effectiveSidebarMode, fixedSidebarInset, floatingSidebarWidth, sidebarReservesSpace } from '../../shared/layout';
import { MAX_FAVORITES } from '../../shared/favorites';
import { NEW_TAB_URL, isNewTab } from '../../shared/pages';
import { isWebURL, resolveInput } from '../../shared/navigation';
import { Store } from '../storage/store';
import { StatePublisher } from '../windows/state-publisher';
import { ChromeLayer } from '../windows/chrome-layer';
import { shortcutAction } from '../../shared/shortcuts';
import { organize, orderedSpaceTabs } from '../../shared/organization';

export class TabManager {
  readonly views = new Map<string, WebContentsView>();
  private publishers = new Map<number, StatePublisher>();
  private radii = new WeakMap<WebContentsView, number>();
  private attached = new Set<WebContentsView>();
  private sessions = new Map<string, Session>();
  private saveTimer?: ReturnType<typeof setTimeout>;
  private downloads = new Map<string, { item: DownloadItem; path: string }>();
  private shuttingDown = false;
  private closedTabs: Tab[] = [];
  private lastHiddenMode: 'hover' | 'hidden' = 'hover';
  private sidebarInteractions = new Set<string>();
  private hoverInside = false;
  private hoverTimer?: ReturnType<typeof setTimeout>;

  constructor(readonly window: BrowserWindow, readonly state: BrowserState, session: Session, private store: Store, private chrome: ChromeLayer) {
    if (effectiveSidebarMode(state) === 'hidden') this.lastHiddenMode = 'hidden';
    const updateWindowMode = (expanded: boolean) => {
      if (this.state.windowExpanded === expanded) return;
      this.state.windowExpanded = expanded; this.state.expandedSidebarMode = 'hover'; this.state.sidebarRevealed = false;
      this.present(); this.emit(false);
    };
    window.on('maximize', () => updateWindowMode(true));
    window.on('unmaximize', () => updateWindowMode(window.isFullScreen()));
    window.on('enter-full-screen', () => updateWindowMode(true));
    window.on('leave-full-screen', () => updateWindowMode(window.isMaximized()));
    window.on('resize', () => this.layout());
    window.webContents.on('before-mouse-event', (_event, mouse) => {
      if (mouse.type !== 'mouseMove' && mouse.type !== 'mouseEnter') return;
      const [width, height] = window.getContentSize();
      if (mouse.x < 0 || mouse.y < 0 || mouse.x >= width || mouse.y >= height) return;
      this.revealSidebar(mouse.x < (state.sidebarRevealed ? floatingSidebarWidth(state.preferences) : 8));
    });
    chrome.view.webContents.on('before-mouse-event', (_event, mouse) => {
      if (state.overlay) return;
      if (mouse.type === 'mouseLeave') {
        const bounds = chrome.view.getBounds();
        // Resizing a full-window popup to sidebar width can queue a leave event
        // with coordinates from the previous viewport. The page handles real exits.
        const outside = mouse.x < 0 || mouse.x >= bounds.width || mouse.y < 0 || mouse.y >= bounds.height;
        if (outside && mouse.x >= -8 && mouse.x <= bounds.width + 8 && mouse.y >= -8 && mouse.y <= bounds.height + 8) this.revealSidebar(false);
        return;
      }
      if (!['mouseMove', 'mouseEnter', 'mouseDown'].includes(mouse.type)) return;
      const bounds = chrome.view.getBounds();
      // The inset and shadow belong to the same hover surface as the panel.
      if (mouse.x >= 0 && mouse.y >= 0 && mouse.x < bounds.width && mouse.y < bounds.height) this.revealSidebar(mouse.x < floatingSidebarWidth(state.preferences));
    });
    window.on('blur', () => { this.sidebarInteractions.clear(); this.revealSidebar(false); if (state.overlay === 'switcher') void this.dispatch({ type: 'overlay.close' }); });
    this.configureSession('personal', session);
  }

  private configureSession(id: string, browsingSession: Session): Session {
    if (this.sessions.has(id)) return this.sessions.get(id)!;
    this.sessions.set(id, browsingSession);
    browsingSession.setPermissionCheckHandler(() => false);
    browsingSession.setPermissionRequestHandler((contents, permission, callback, details) => {
      const supported = ['media', 'geolocation', 'notifications', 'fullscreen', 'clipboard-sanitized-write'];
      const owner = [...this.views.values()].some(v => v.webContents === contents);
      if (!owner || !supported.includes(permission) || !isWebURL(details.requestingUrl)) { callback(false); return; }
      void dialog.showMessageBox(this.window, { type: 'question', title: 'Website permission', message: `${new URL(details.requestingUrl).origin} wants to use ${permission}.`, buttons: ['Don’t allow', 'Allow once'], defaultId: 0, cancelId: 0 }).then(({ response }) => callback(response === 1)).catch(() => callback(false));
    });
    browsingSession.on('will-download', (_event, item) => {
      const id = randomUUID();
      const entry: Download = { id, name: item.getFilename(), received: 0, total: item.getTotalBytes(), state: 'progressing' };
      this.state.downloads.unshift(entry);
      this.downloads.set(id, { item, path: '' });
      item.on('updated', (_e, status) => { entry.received = item.getReceivedBytes(); entry.total = item.getTotalBytes(); entry.state = status; this.emit(false); });
      item.once('done', (_e, status) => { entry.state = status; this.downloads.set(id, { item, path: item.getSavePath() }); this.emit(false); });
      this.emit(false);
    });
    return browsingSession;
  }

  emit(persist = true): void {
    if (this.shuttingDown) return;
    if (!this.window.isDestroyed()) {
      this.chrome.sync(this.state);
      const recipients = [this.window.webContents, ...(this.chrome.visible ? [this.chrome.view.webContents] : [])];
      for (const wc of recipients) {
        if (wc.isDestroyed()) continue;
        let publisher=this.publishers.get(wc.id);
        if (!publisher) { publisher=new StatePublisher(); this.publishers.set(wc.id,publisher); }
        const patch=publisher.update(this.state);
        if (patch) wc.send('browser:patch',patch);
      }
    }
    if (persist) {
      clearTimeout(this.saveTimer);
      this.saveTimer = setTimeout(() => { void this.store.write(this.state).catch(error => console.error('Could not save browser metadata:', error.message)); }, 200);
    }
  }

  layout(): void {
    if (this.window.isDestroyed()) return;
    this.chrome.sync(this.state);
    if (!this.attached.size) return;
    const [width, height] = this.window.getContentSize();
    const inset = this.state.windowExpanded ? 0 : 8;
    const x = sidebarReservesSpace(this.state) ? fixedSidebarInset(this.state.preferences) : inset;
    const split = this.state.splitView;
    const total = Math.max(1, width - x - inset);
    const firstWidth = Math.floor((total - 6) / 2);
    for (const view of this.attached) {
      const second = !!split && this.views.get(split.ids[1]) === view;
      const target = split
        ? { x: second ? x + firstWidth + 6 : x, y: inset + 34, width: Math.max(1, second ? total - firstWidth - 6 : firstWidth), height: Math.max(1, height - inset * 2 - 34) }
        : { x, y: inset, width: total, height: Math.max(1, height - inset * 2) };
      const radius=this.state.windowExpanded ? 0 : 12;
      if (this.radii.get(view)!==radius) { view.setBorderRadius(radius); this.radii.set(view,radius); }
      const bounds = view.getBounds();
      if (Object.entries(target).some(([key, value]) => bounds[key as keyof typeof bounds] !== value)) view.setBounds(target);
    }
  }

  present(): void {
    const active = this.active();
    if (this.state.splitView && (!active || !this.state.splitView.ids.includes(active.id) || this.state.splitView.ids.some(id => {
      const tab = this.state.tabs.find(t => t.id === id);
      return !tab || tab.spaceId !== this.state.activeSpaceId || isNewTab(tab.url) || !!tab.error;
    }))) this.state.splitView = null;
    const tabs = this.state.splitView ? this.state.splitView.ids.map(id => this.state.tabs.find(t => t.id === id)!) : active ? [active] : [];
    const wanted = new Set(tabs.filter(tab => !isNewTab(tab.url) && !tab.error).map(tab => this.ensureView(tab)));
    for (const view of this.attached) if (!wanted.has(view)) this.window.contentView.removeChildView(view);
    for (const view of wanted) if (!this.attached.has(view)) this.window.contentView.addChildView(view);
    this.attached = wanted;
    this.layout();
  }

  active(): Tab | undefined { return this.state.tabs.find(t => t.id === this.state.activeTabId); }

  async external(url: string): Promise<void> {
    let protocol: string;
    try { protocol = new URL(url).protocol; } catch { return; }
    if (!['mailto:', 'tel:'].includes(protocol)) return;
    const { response } = await dialog.showMessageBox(this.window, { message: `Open ${protocol === 'mailto:' ? 'Mail' : 'your calling app'}?`, detail: url.slice(0, 300), buttons: ['Cancel', 'Open'], defaultId: 0, cancelId: 0 });
    if (response === 1) await shell.openExternal(url);
  }

  private ensureView(tab: Tab): WebContentsView {
    if (!isWebURL(tab.url)) throw new Error('Website views require an HTTP or HTTPS URL');
    const profile = tab.spaceId;
    const browsingSession = this.sessions.get(profile) ?? this.configureSession(profile, electronSession.fromPartition(`persist:${profile === 'personal' ? 'personal' : `space-${profile}`}`));
    const existing = this.views.get(tab.id);
    if (existing?.webContents.session === browsingSession) return existing;
    if (existing) {
      if (this.attached.delete(existing)) this.window.contentView.removeChildView(existing);
      existing.webContents.close(); this.views.delete(tab.id);
    }
    tab.profileId = profile;
    const view = new WebContentsView({ webPreferences: { session: browsingSession, nodeIntegration: false, contextIsolation: true, sandbox: true, webSecurity: true, navigateOnDragDrop: false } });
    view.setBorderRadius(12); this.radii.set(view,12);
    view.setBackgroundColor('#ffffff');
    this.views.set(tab.id, view);
    tab.status = tab.id === this.state.activeTabId ? 'active' : 'background';
    tab.loading = true;
    const wc = view.webContents;
    wc.on('focus', () => {
      if (this.state.splitView?.ids.includes(tab.id) && this.state.activeTabId !== tab.id) {
        this.state.activeTabId = tab.id; tab.lastActive = Date.now(); this.emit(false);
      }
    });
    wc.on('before-mouse-event', (_event, mouse) => {
      if (!['mouseMove', 'mouseEnter', 'mouseDown'].includes(mouse.type)) return;
      const bounds = view.getBounds();
      if (mouse.x < 0 || mouse.y < 0 || mouse.x >= bounds.width || mouse.y >= bounds.height) return;
      // Native renderers can deliver crossing events after the chrome attaches.
      // Normalize to window coordinates so those events cannot dismiss a panel above them.
      const revealWidth = this.state.sidebarRevealed ? floatingSidebarWidth(this.state.preferences) : 8;
      this.revealSidebar(bounds.x + mouse.x < revealWidth);
    });
    const update = () => {
      if (wc.isDestroyed() || !this.views.has(tab.id)) return;
      tab.canGoBack = wc.navigationHistory.canGoBack();
      tab.canGoForward = wc.navigationHistory.canGoForward();
      const url = wc.getURL();
      if (isWebURL(url)) tab.url = url;
      this.emit();
    };
    wc.on('did-start-loading', () => { tab.loading = true; tab.error = undefined; this.present(); update(); });
    wc.on('did-stop-loading', () => { tab.loading = false; update(); });
    wc.on('page-title-updated', (_event, title) => { tab.title = title; update(); });
    wc.on('page-favicon-updated', (_event, urls) => { tab.favicon = urls.find(isWebURL); update(); });
    wc.on('did-navigate-in-page', update);
    wc.on('did-navigate', () => { tab.error = undefined; update(); this.present(); });
    wc.on('did-finish-load', () => {
      if (!isWebURL(wc.getURL())) return;
      this.state.history = [{ url: tab.url, title: tab.title, favicon: tab.favicon, visitedAt: Date.now() }, ...this.state.history.filter(h => h.url !== tab.url)].slice(0, 2000);
      update();
    });
    wc.on('did-fail-load', (_event, code, description, _url, isMainFrame) => {
      if (!isMainFrame || code === -3) return;
      tab.loading = false; tab.error = description; this.present(); this.emit();
    });
    wc.on('render-process-gone', () => {
      tab.loading = false; tab.error = 'This page stopped responding. Reload to give it a fresh start.';
      this.present(); this.views.delete(tab.id); wc.close(); tab.status = 'discarded'; this.emit();
    });
    const guard = (event: Electron.Event, url: string) => {
      if (!isWebURL(url)) { event.preventDefault(); void this.external(url); }
    };
    wc.on('will-navigate', guard);
    wc.on('will-redirect', guard);
    wc.setWindowOpenHandler(({ url }) => {
      if (isWebURL(url)) this.create(url); else void this.external(url);
      return { action: 'deny' };
    });
    wc.on('before-input-event', (event, input) => { if (this.shortcut(input)) event.preventDefault(); });
    void wc.loadURL(tab.url).catch(() => { /* did-fail-load provides the visible error. */ });
    return view;
  }

  newTab(): void { this.openPalette('new'); }

  create(url: string, favoriteId?: string): void {
    if (!isNewTab(url) && !isWebURL(url)) return;
    const tab: Tab = { id: randomUUID(), favoriteId, url, title: isNewTab(url) ? 'New tab' : new URL(url).hostname, spaceId: this.state.activeSpaceId, profileId: this.state.activeSpaceId, pinned: false, lastActive: Date.now(), loading: !isNewTab(url), canGoBack: false, canGoForward: false, status: 'active' };
    this.state.tabs.push(tab); this.select(tab.id);
  }

  select(id: string): void {
    const started = performance.now();
    const tab = this.state.tabs.find(t => t.id === id);
    if (!tab) return;
    this.state.activeSpaceId = tab.spaceId;
    this.state.activeTabId = id;
    this.state.overlay = null;
    this.state.tabSwitcher = null;
    tab.lastActive = Date.now();
    if (!isNewTab(tab.url)) this.ensureView(tab);
    for (const item of this.state.tabs) item.status = this.views.has(item.id) || isNewTab(item.url) ? (item.id === id ? 'active' : 'background') : 'discarded';
    this.present();
    if (isNewTab(tab.url)) this.window.webContents.focus(); else this.views.get(id)?.webContents.focus();
    this.emit();
    if (!app.isPackaged) console.debug(`[performance] tab-switch ${Math.round((performance.now() - started) * 100) / 100}ms`);
  }

  close(id: string): void {
    const index = this.state.tabs.findIndex(t => t.id === id);
    if (index < 0) return;
    this.closedTabs.unshift({ ...this.state.tabs[index] });
    this.closedTabs = this.closedTabs.slice(0, 30);
    const wasActive = id === this.state.activeTabId;
    const view = this.views.get(id);
    this.state.tabs.splice(index, 1);
    if (view && this.attached.delete(view)) this.window.contentView.removeChildView(view);
    if (this.state.splitView?.ids.includes(id)) this.state.splitView = null;
    this.views.delete(id);
    if (view && !view.webContents.isDestroyed()) view.webContents.close();
    if (wasActive) {
      const remaining = this.state.tabs.filter(t => t.spaceId === this.state.activeSpaceId);
      const next = remaining[Math.min(index, remaining.length - 1)];
      this.state.activeTabId = next?.id ?? null;
      if (next && this.state.overlay !== 'palette') this.select(next.id); else this.window.webContents.focus();
    }
    this.present(); this.emit();
    if (this.state.overlay === 'palette') this.chrome.focus();
  }

  openPalette(mode: 'new' | 'navigate'): void {
    this.state.tabSwitcher = null;
    const active = this.active();
    if (!active || isNewTab(active.url) && !active.error) {
      this.state.overlay = null; this.present(); this.emit(false);
      this.window.webContents.focus();
      this.window.webContents.send('browser:focus-search');
      return;
    }
    this.state.overlay = 'palette'; this.state.paletteMode = mode;
    this.present(); this.chrome.focus(); this.emit(false);
  }

  revealSidebar(visible: boolean): void {
    this.hoverInside = visible;
    if (effectiveSidebarMode(this.state) !== 'hover') return;
    if (visible) {
      clearTimeout(this.hoverTimer); this.hoverTimer = undefined;
      if (!this.state.sidebarRevealed) { this.state.sidebarRevealed = true; this.layout(); this.emit(false); }
    } else if (this.state.sidebarRevealed && !this.state.overlay && !this.hoverTimer && !this.sidebarInteractions.size) {
      this.hoverTimer = setTimeout(() => {
        this.hoverTimer = undefined;
        if (effectiveSidebarMode(this.state) !== 'hover' || this.state.overlay || this.sidebarInteractions.size) return;
        this.state.sidebarRevealed = false; this.layout(); this.emit(false);
      }, 220);
    }
  }

  private sidebarTabs(): Tab[] {
    return orderedSpaceTabs(this.state, this.state.activeSpaceId);
  }

  private cycleTab(direction: number): void {
    const tabs = this.sidebarTabs();
    const index = tabs.findIndex(t => t.id === this.state.activeTabId);
    const next = tabs[(index + direction + tabs.length) % tabs.length];
    if (next) this.select(next.id);
  }

  private cycleSpace(direction: number): void {
    const index = this.state.spaces.findIndex(s => s.id === this.state.activeSpaceId);
    const next = this.state.spaces[(index + direction + this.state.spaces.length) % this.state.spaces.length];
    if (next) void this.dispatch({ type: 'space.select', id: next.id });
  }

  shortcut(input: Input): boolean {
    if (input.type === 'keyUp' && input.key === 'Control' && this.state.overlay === 'switcher') {
      const switcher = this.state.tabSwitcher;
      const id = switcher?.ids[switcher.index];
      if (id) this.select(id); else void this.dispatch({ type: 'overlay.close' });
      return true;
    }
    if (input.type !== 'keyDown') return false;
    if (input.key === 'Escape') {
      if (this.state.overlay) { void this.dispatch({ type: 'overlay.close' }); return true; }
      if (this.sidebarInteractions.size) return false;
      if (this.state.sidebarRevealed) { this.revealSidebar(false); return true; }
      return false;
    }
    const action = shortcutAction(input, process.platform === 'darwin');
    if (!action) return false;
    if (action.startsWith('recent.')) {
      if (!this.state.tabSwitcher) {
        const ids = this.state.tabs.slice().sort((a, b) => Number(b.id === this.state.activeTabId) - Number(a.id === this.state.activeTabId) || b.lastActive - a.lastActive).slice(0, 5).map(t => t.id);
        if (!ids.length) return true;
        this.state.tabSwitcher = { ids, index: 0 };
      }
      const switcher = this.state.tabSwitcher;
      switcher.index = (switcher.index + (action === 'recent.next' ? 1 : -1) + switcher.ids.length) % switcher.ids.length;
      this.state.overlay = 'switcher'; this.present(); this.chrome.focus(); this.emit(false);
      return true;
    }
    const tab = this.active();
    const wc = tab && this.views.get(tab.id)?.webContents;
    switch (action) {
      case 'new': this.newTab(); break;
      case 'location': this.openPalette('navigate'); break;
      case 'sidebar': void this.dispatch({ type: 'sidebar.toggle' }); break;
      case 'settings': void this.dispatch({ type: 'settings' }); break;
      case 'close': if (tab) this.close(tab.id); break;
      case 'pin': if (tab) void this.dispatch({ type: 'tab.pin', id: tab.id }); break;
      case 'copy': if (tab && isWebURL(tab.url)) clipboard.writeText(tab.url); break;
      case 'reload': void this.dispatch({ type: 'reload' }); break;
      case 'reload.hard': if (wc) wc.reloadIgnoringCache(); else void this.dispatch({ type: 'reload' }); break;
      case 'back': case 'forward': void this.dispatch({ type: action }); break;
      case 'tab.previous': this.cycleTab(-1); break;
      case 'tab.next': this.cycleTab(1); break;
      case 'space.previous': this.cycleSpace(-1); break;
      case 'space.next': this.cycleSpace(1); break;
      case 'reopen': {
        const index = this.closedTabs.findIndex(t => this.state.spaces.some(s => s.id === t.spaceId));
        if (index >= 0) {
          const [restored] = this.closedTabs.splice(index, 1);
          restored.id = randomUUID(); restored.error = undefined; restored.status = 'discarded';
          restored.canGoBack = false; restored.canGoForward = false;
          if (!this.state.folders.some(f => f.id === restored.folderId && f.spaceId === restored.spaceId)) restored.folderId = undefined;
          this.state.tabs.push(restored); this.select(restored.id);
        }
        break;
      }
      default: {
        const [kind, number] = action.split('.');
        if (kind === 'space') {
          const space = this.state.spaces[Number(number) - 1];
          if (space) void this.dispatch({ type: 'space.select', id: space.id });
        } else if (kind === 'tab') {
          const tabs = this.sidebarTabs();
          const target = number === '9' ? tabs.at(-1) : tabs[Number(number) - 1];
          if (target) this.select(target.id);
        }
      }
    }
    return true;
  }

  async dispatch(action: Action): Promise<void> {
    if (organize(this.state, action)) {
      const active = this.active();
      if (active && active.spaceId !== this.state.activeSpaceId) this.select(active.id);
      else { this.present(); this.emit(); }
      return;
    }
    const tab = this.active();
    const wc = tab && this.views.get(tab.id)?.webContents;
    switch (action.type) {
      case 'split.open': {
        const base = action.withId === undefined ? tab : this.state.tabs.find(t => t.id === action.withId);
        const other = this.state.tabs.find(t => t.id === action.id);
        if (!base || !other || other.id === base.id || base.spaceId !== this.state.activeSpaceId || other.spaceId !== base.spaceId || !isWebURL(base.url) || !isWebURL(other.url) || base.error || other.error) return;
        this.state.activeTabId = base.id; base.lastActive = Date.now();
        this.state.splitView = { ids: [base.id, other.id] }; this.state.overlay = null;
        this.present();
        for (const item of this.state.tabs) item.status = this.views.has(item.id) || isNewTab(item.url) ? (item.id === base.id ? 'active' : 'background') : 'discarded';
        this.views.get(base.id)?.webContents.focus(); break;
      }
      case 'split.close': this.state.splitView = null; this.present(); break;
      case 'favorite.save': {
        const url = resolveInput(action.url, this.state.preferences.searchEngine);
        if (!isWebURL(action.url)) throw new Error('Enter a full website URL, starting with https://');
        const existing = this.state.favorites.find(f => f.id === action.id);
        if (action.id && !existing) return;
        if (existing) Object.assign(existing, { name: action.name.trim(), url });
        else if (this.state.favorites.length < MAX_FAVORITES) this.state.favorites.push({ id: randomUUID(), name: action.name.trim(), url });
        break;
      }
      case 'favorite.copy': { const favorite = this.state.favorites.find(f => f.id === action.id); if (favorite) clipboard.writeText(favorite.url); return; }
      case 'favorite.delete':
        this.state.favorites = this.state.favorites.filter(f => f.id !== action.id);
        for (const tab of this.state.tabs) if (tab.favoriteId === action.id) tab.favoriteId = undefined;
        break;
      case 'favorite.open': {
        const favorite = this.state.favorites.find(f => f.id === action.id);
        if (!favorite) return;
        const localTabs = this.state.tabs.filter(t => t.spaceId === this.state.activeSpaceId);
        const existing = localTabs.find(t => t.favoriteId === favorite.id) ?? localTabs.find(t => t.url === favorite.url);
        if (existing) { existing.favoriteId = favorite.id; this.select(existing.id); } else this.create(favorite.url, favorite.id);
        return;
      }
      case 'tab.new': this.newTab(); return;
      case 'palette': this.openPalette(action.mode); return;
      case 'sidebar.interaction':
        if (action.active) {
          this.sidebarInteractions.add(action.id); clearTimeout(this.hoverTimer); this.hoverTimer = undefined;
        } else {
          this.sidebarInteractions.delete(action.id);
          if (!this.sidebarInteractions.size && !this.hoverInside) this.revealSidebar(false);
        }
        return;
      case 'sidebar.reveal': this.revealSidebar(action.visible); return;
      case 'overlay.close': this.state.overlay = null; this.state.tabSwitcher = null; this.present(); if (tab && !isNewTab(tab.url)) wc?.focus(); else this.window.webContents.focus(); break;
      case 'navigate': {
        const url = resolveInput(action.input, this.state.preferences.searchEngine);
        if (action.newTab || !tab) this.create(url);
        else {
          tab.url = url; tab.error = undefined;
          if (wc) void wc.loadURL(url).catch(() => {}); else this.ensureView(tab);
          this.state.overlay = null; this.present(); this.views.get(tab.id)?.webContents.focus();
        }
        break;
      }
      case 'tab.select': this.select(action.id); return;
      case 'tab.close': this.close(action.id); return;
      case 'tab.pin': { const t = this.state.tabs.find(t => t.id === action.id); if (t) { t.favoriteId = undefined; t.pinned = !t.pinned; if (!t.pinned) t.folderId = undefined; } break; }
      case 'tab.duplicate': { const t = this.state.tabs.find(t => t.id === action.id); if (t) this.create(t.url); break; }
      case 'tab.reorder': {
        const a = this.state.tabs.findIndex(t => t.id === action.id); const b = this.state.tabs.findIndex(t => t.id === action.beforeId);
        if (a >= 0 && b >= 0 && this.state.tabs[a].spaceId === this.state.tabs[b].spaceId) { const [t] = this.state.tabs.splice(a, 1); this.state.tabs.splice(b, 0, t); }
        break;
      }
      case 'tab.move': { const t = this.state.tabs.find(t => t.id === action.id); if (t && this.state.spaces.some(s => s.id === action.spaceId)) { t.favoriteId = undefined; t.spaceId = action.spaceId; t.profileId = action.spaceId; t.folderId = undefined; this.select(t.id); } break; }
      case 'back': if (wc?.navigationHistory.canGoBack()) wc.navigationHistory.goBack(); break;
      case 'forward': if (wc?.navigationHistory.canGoForward()) wc.navigationHistory.goForward(); break;
      case 'reload': if (tab && !isNewTab(tab.url)) { tab.error = undefined; if (wc) wc.reload(); else this.ensureView(tab); this.present(); } break;
      case 'stop': wc?.stop(); break;
      case 'sidebar.toggle': {
        this.sidebarInteractions.clear();
        clearTimeout(this.hoverTimer);
        const mode = effectiveSidebarMode(this.state);
        if (mode !== 'fixed') this.lastHiddenMode = mode;
        if (this.state.windowExpanded) this.state.expandedSidebarMode = mode === 'fixed' ? 'hover' : 'fixed';
        else this.state.preferences.sidebarMode = mode === 'fixed' ? this.lastHiddenMode : 'fixed';
        this.state.sidebarRevealed = false; this.layout();
        if (wc) wc.focus(); else this.window.webContents.focus();
        break;
      }
      case 'settings': this.state.tabSwitcher = null; this.state.overlay = 'settings'; this.present(); this.chrome.focus(); break;
      case 'space.select': {
        this.state.splitView = null;
        if (!this.state.spaces.some(s => s.id === action.id)) return;
        this.state.activeSpaceId = action.id;
        const next = this.state.tabs.filter(t => t.spaceId === action.id).sort((a, b) => b.lastActive - a.lastActive)[0];
        this.state.activeTabId = next?.id ?? null;
        if (next) { this.select(next.id); return; }
        this.state.overlay = null; this.present(); this.window.webContents.focus();
        break;
      }
      case 'space.create': {
        if (this.state.spaces.length >= 30) return;
        const id = randomUUID(); this.state.spaces.push({ id, name: action.name, color: action.color, icon: action.icon });
        await this.dispatch({ type: 'space.select', id }); return;
      }
      case 'space.rename': { const space = this.state.spaces.find(s => s.id === action.id); if (space) space.name = action.name; break; }
      case 'space.delete': {
        if (this.state.spaces.length <= 1) return;
        this.state.spaces = this.state.spaces.filter(s => s.id !== action.id);
        this.state.folders = this.state.folders.filter(f => f.spaceId !== action.id);
        for (const t of [...this.state.tabs]) if (t.spaceId === action.id) this.close(t.id);
        if (this.state.activeSpaceId === action.id) await this.dispatch({ type: 'space.select', id: this.state.spaces[0].id });
        break;
      }
      case 'preferences':
        Object.assign(this.state.preferences, action.preferences);
        if (action.preferences.sidebarMode) { if (this.state.windowExpanded) this.state.expandedSidebarMode = action.preferences.sidebarMode; clearTimeout(this.hoverTimer); this.state.sidebarRevealed = false; }
        this.layout(); break;
      case 'clear': {
        const { response } = await dialog.showMessageBox(this.window, { message: `Clear ${action.target}?`, detail: action.target === 'cookies' ? 'This signs you out of websites in all Spaces.' : 'This cannot be undone.', buttons: ['Cancel', 'Clear'], defaultId: 0, cancelId: 0 });
        if (response !== 1) return;
        for (const space of this.state.spaces) if (!this.sessions.has(space.id)) this.configureSession(space.id, electronSession.fromPartition(`persist:${space.id === 'personal' ? 'personal' : `space-${space.id}`}`));
        if (action.target === 'history') this.state.history = [];
        else if (action.target === 'cache') await Promise.all([...this.sessions.values()].map(s => s.clearCache()));
        else await Promise.all([...this.sessions.values()].map(s => s.clearStorageData({ storages: ['cookies'] })));
        break;
      }
      case 'download.cancel': this.downloads.get(action.id)?.item.cancel(); break;
      case 'download.open': { const d = this.downloads.get(action.id); if (d?.path && this.state.downloads.find(d => d.id === action.id)?.state === 'completed') await shell.openPath(d.path); break; }
      case 'download.reveal': { const d = this.downloads.get(action.id); if (d?.path) shell.showItemInFolder(d.path); break; }
    }
    this.emit(action.type !== 'overlay.close' && action.type !== 'settings' && action.type !== 'split.close');
  }

  async shutdown(): Promise<void> {
    this.shuttingDown = true;
    clearTimeout(this.hoverTimer);
    clearTimeout(this.saveTimer);
    await this.store.write(this.state);
    for (const session of this.sessions.values()) session.flushStorageData();
    await Promise.all([...this.sessions.values()].map(s => s.cookies.flushStore()));
    for (const view of this.views.values()) if (!view.webContents.isDestroyed()) view.webContents.close();
    this.views.clear();
  }
}
