export type SpaceColor = 'lavender' | 'mint' | 'peach' | 'blue' | 'blush';
export interface Space { id: string; name: string; icon: string; color: SpaceColor }
export interface TabFolder { id: string; spaceId: string; name: string; collapsed: boolean }
export interface Tab {
  id: string; spaceId: string; profileId: string; url: string; title: string;
  favicon?: string; favoriteId?: string; pinned: boolean; folderId?: string; lastActive: number; loading: boolean;
  canGoBack: boolean; canGoForward: boolean; status: 'active' | 'background' | 'discarded'; error?: string;
}
export interface Favorite { id: string; name: string; url: string }
export interface HistoryEntry { url: string; title: string; favicon?: string; visitedAt: number }
export interface Preferences { theme: 'system' | 'light' | 'dark'; sidebarMode: 'fixed' | 'hover' | 'hidden'; sidebarSize: 'compact' | 'comfortable' | 'wide'; restoreSession: boolean; searchEngine: 'google' | 'duckduckgo' }
export interface Download { id: string; name: string; received: number; total: number; state: 'progressing' | 'completed' | 'cancelled' | 'interrupted' }
export interface BrowserState {
  version: 1; favorites: Favorite[]; spaces: Space[]; folders: TabFolder[]; tabs: Tab[]; activeSpaceId: string; activeTabId: string | null;
  history: HistoryEntry[]; preferences: Preferences; downloads: Download[];
  windowExpanded: boolean; expandedSidebarMode: 'fixed' | 'hover' | 'hidden'; sidebarRevealed: boolean; tabSwitcher: { ids: string[]; index: number } | null;
  splitView: { ids: [string, string] } | null;
  overlay: 'palette' | 'settings' | 'switcher' | null; paletteMode: 'new' | 'navigate'; dark: boolean;
}
export type Action =
  | { type: 'palette'; mode: 'new' | 'navigate' }
  | { type: 'overlay.close' | 'tab.new' }
  | { type: 'sidebar.interaction'; id: string; active: boolean }
  | { type: 'sidebar.reveal'; visible: boolean }
  | { type: 'navigate'; input: string; newTab?: boolean }
  | { type: 'favorite.save'; id?: string; name: string; url: string }
  | { type: 'favorite.reorder'; id: string; beforeId: string | null }
  | { type: 'split.open'; id: string; withId?: string }
  | { type: 'split.close' }
  | { type: 'favorite.delete' | 'favorite.open' | 'favorite.copy'; id: string }
  | { type: 'tab.select' | 'tab.close' | 'tab.pin' | 'tab.duplicate'; id: string }
  | { type: 'tab.reorder'; id: string; beforeId: string }
  | { type: 'tab.move'; id: string; spaceId: string }
  | { type: 'tab.place'; id: string; spaceId: string; pinned: boolean; folderId?: string; beforeId?: string }
  | { type: 'folder.create'; spaceId: string; name: string }
  | { type: 'folder.rename'; id: string; name: string }
  | { type: 'folder.toggle' | 'folder.delete'; id: string }
  | { type: 'folder.reorder' | 'space.reorder'; id: string; beforeId: string }
  | { type: 'back' | 'forward' | 'reload' | 'stop' | 'sidebar.toggle' | 'settings' }
  | { type: 'space.select' | 'space.delete'; id: string }
  | { type: 'space.create'; name: string; color: SpaceColor; icon: string }
  | { type: 'space.rename'; id: string; name: string }
  | { type: 'preferences'; preferences: Partial<Preferences> }
  | { type: 'clear'; target: 'history' | 'cache' | 'cookies' }
  | { type: 'download.cancel' | 'download.open' | 'download.reveal'; id: string };
export interface BrowserBridge {
  getState(): Promise<BrowserState>;
  onSearchFocus(listener: () => void): () => void;
  dispatch(action: Action): Promise<void>;
  subscribe(listener: (state: Partial<BrowserState>) => void): () => void;
}
