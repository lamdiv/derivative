import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import type { BrowserState, Space, Tab } from '../../shared/types';
import { defaultFavorites, MAX_FAVORITES } from '../../shared/favorites';
import { isNewTab } from '../../shared/pages';
import { isWebURL } from '../../shared/navigation';

export const defaultSpaces: Space[] = [
  { id: 'personal', name: 'Personal', icon: '✳', color: 'lavender' },
  { id: 'work', name: 'Work', icon: '◈', color: 'mint' },
  { id: 'study', name: 'Study', icon: '☀', color: 'peach' },
];
export function freshState(): BrowserState {
  return { version: 1, favorites: defaultFavorites.map(f => ({ ...f })), spaces: defaultSpaces.map(s => ({ ...s })), folders: [], tabs: [], activeSpaceId: 'personal', activeTabId: null, history: [], preferences: { theme: 'system', sidebarMode: 'fixed', sidebarSize: 'comfortable', restoreSession: true, searchEngine: 'google' }, downloads: [], windowExpanded: false, expandedSidebarMode: 'hover', sidebarRevealed: false, tabSwitcher: null, splitView: null, overlay: null, paletteMode: 'new', dark: false };
}
export function restoreState(value: unknown): BrowserState {
  const state = freshState();
  if (!value || typeof value !== 'object' || !('version' in value) || value.version !== 1) return state;
  const saved = value as Partial<BrowserState>;
  const colors = ['lavender', 'mint', 'peach', 'blue', 'blush'];
  if (Array.isArray(saved.spaces)) {
    const ids = new Set<string>();
    const spaces = saved.spaces.filter(s => s && typeof s.id === 'string' && !ids.has(s.id) && !!ids.add(s.id) && typeof s.name === 'string' && s.name.length > 0 && typeof s.icon === 'string' && colors.includes(s.color));
    if (spaces.length) state.spaces = spaces.slice(0, 30).map(s => ({ ...s, name: s.name.slice(0, 40), icon: s.icon.slice(0, 8) }));
  }
  if (Array.isArray(saved.favorites)) {
    const ids = new Set<string>();
    state.favorites = saved.favorites.filter(f => f && typeof f.id === 'string' && !ids.has(f.id) && !!ids.add(f.id) && typeof f.name === 'string' && !!f.name.trim() && typeof f.url === 'string' && isWebURL(f.url)).slice(0, MAX_FAVORITES).map(f => ({ id: f.id, name: f.name.trim().slice(0, 40), url: f.url.slice(0, 8192) }));
  }
  const p = saved.preferences;
  if (p) {
    if (['compact', 'comfortable', 'wide'].includes(p.sidebarSize)) state.preferences.sidebarSize = p.sidebarSize;
    if (['light', 'dark', 'system'].includes(p.theme)) state.preferences.theme = p.theme;
    if (['fixed', 'hover', 'hidden'].includes(p.sidebarMode)) state.preferences.sidebarMode = p.sidebarMode;
    else if ('sidebarCollapsed' in p && p.sidebarCollapsed === true) state.preferences.sidebarMode = 'hover';
    if (typeof p.restoreSession === 'boolean') state.preferences.restoreSession = p.restoreSession;
    if (['google', 'duckduckgo'].includes(p.searchEngine)) state.preferences.searchEngine = p.searchEngine;
  }
  if (state.spaces.some(s => s.id === saved.activeSpaceId)) state.activeSpaceId = saved.activeSpaceId!;
  if (Array.isArray(saved.folders)) {
    const ids = new Set<string>();
    state.folders = saved.folders.filter(f => f && typeof f.id === 'string' && !ids.has(f.id) && !!ids.add(f.id) && typeof f.name === 'string' && !!f.name.trim() && state.spaces.some(s => s.id === f.spaceId)).slice(0, 300).map(f => ({ id: f.id, spaceId: f.spaceId, name: f.name.trim().slice(0, 40), collapsed: !!f.collapsed }));
  }
  if (state.preferences.restoreSession && Array.isArray(saved.tabs)) {
    const ids = new Set<string>();
    state.tabs = saved.tabs.filter(t => t && typeof t.id === 'string' && !ids.has(t.id) && !!ids.add(t.id) && typeof t.title === 'string' && typeof t.url === 'string' && (isWebURL(t.url) || isNewTab(t.url)) && state.spaces.some(s => s.id === t.spaceId)).slice(0, 500).map((t): Tab => ({
      id: t.id, spaceId: t.spaceId, profileId: t.spaceId, url: t.url, title: isNewTab(t.url) ? 'New tab' : t.title.slice(0, 500), favicon: t.favicon && isWebURL(t.favicon) ? t.favicon : undefined,
      favoriteId: state.favorites.find(f => f.id === t.favoriteId)?.id,
      pinned: !!t.pinned || state.folders.some(f => f.id === t.folderId && f.spaceId === t.spaceId), folderId: state.folders.find(f => f.id === t.folderId && f.spaceId === t.spaceId)?.id, lastActive: Number(t.lastActive) || 0, loading: false, canGoBack: false, canGoForward: false, status: 'discarded',
    }));
    // Adopt one existing exact-match tab per favorite/Space from older sessions.
    for (const space of state.spaces) for (const favorite of state.favorites) {
      if (!state.tabs.some(t => t.spaceId === space.id && t.favoriteId === favorite.id)) {
        const existing = state.tabs.filter(t => t.spaceId === space.id && !t.favoriteId && t.url === favorite.url).sort((a,b) => b.lastActive-a.lastActive)[0];
        if (existing) existing.favoriteId = favorite.id;
      }
    }
    state.activeTabId = state.tabs.find(t => t.id === saved.activeTabId && t.spaceId === state.activeSpaceId)?.id ?? state.tabs.find(t => t.spaceId === state.activeSpaceId)?.id ?? null;
  }
  if (Array.isArray(saved.history)) state.history = saved.history.filter(h => h && typeof h.url === 'string' && isWebURL(h.url) && typeof h.title === 'string' && Number.isFinite(h.visitedAt)).slice(0, 2000);
  return state;
}

export class Store {
  private queue: Promise<void> = Promise.resolve();
  constructor(private path: string) {}
  async read(): Promise<BrowserState> {
    try { return restoreState(JSON.parse(await readFile(this.path, 'utf8'))); } catch { return freshState(); }
  }
  write(state: BrowserState): Promise<void> {
    const data = JSON.stringify({ ...state, overlay: null, windowExpanded: false, expandedSidebarMode: 'hover', sidebarRevealed: false, tabSwitcher: null, splitView: null, downloads: [] });
    this.queue = this.queue.catch(() => {}).then(async () => {
      await mkdir(dirname(this.path), { recursive: true });
      await writeFile(`${this.path}.tmp`, data, { mode: 0o600 });
      await rename(`${this.path}.tmp`, this.path);
    });
    return this.queue;
  }
}
