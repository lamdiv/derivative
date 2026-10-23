import type { Action, BrowserState, Tab } from './types';

export function orderedSpaceTabs(state: BrowserState, spaceId: string): Tab[] {
  const tabs = state.tabs.filter(t => t.spaceId === spaceId);
  return [
    ...tabs.filter(t => t.pinned && !t.folderId),
    ...state.folders.filter(f => f.spaceId === spaceId).flatMap(f => tabs.filter(t => t.folderId === f.id)),
    ...tabs.filter(t => !t.pinned),
  ];
}

// Metadata operations never create/destroy a webpage view. Returns true for
// handled actions, including stale/invalid targets that must remain no-ops.
export function organize(state: BrowserState, action: Action, idFactory: () => string = () => crypto.randomUUID()): boolean {
  switch (action.type) {
    case 'favorite.reorder': {
      const from = state.favorites.findIndex(f => f.id === action.id);
      const target = state.favorites.find(f => f.id === action.beforeId);
      if (from >= 0 && (action.beforeId === null || target && target.id !== action.id)) {
        const [favorite] = state.favorites.splice(from, 1);
        if (target) state.favorites.splice(state.favorites.findIndex(f => f.id === target.id), 0, favorite);
        else state.favorites.push(favorite);
      }
      return true;
    }
    case 'folder.create':
      if (state.folders.length < 300 && state.spaces.some(s => s.id === action.spaceId) && action.name.trim()) state.folders.push({ id: idFactory(), spaceId: action.spaceId, name: action.name.trim().slice(0, 40), collapsed: false });
      return true;
    case 'folder.rename': {
      const folder = state.folders.find(f => f.id === action.id);
      if (folder && action.name.trim()) folder.name = action.name.trim().slice(0, 40);
      return true;
    }
    case 'folder.toggle': {
      const folder = state.folders.find(f => f.id === action.id);
      if (folder) folder.collapsed = !folder.collapsed;
      return true;
    }
    case 'folder.delete':
      state.folders = state.folders.filter(f => f.id !== action.id);
      for (const tab of state.tabs) if (tab.folderId === action.id) tab.folderId = undefined;
      return true;
    case 'folder.reorder': {
      const from = state.folders.findIndex(f => f.id === action.id);
      const to = state.folders.findIndex(f => f.id === action.beforeId);
      if (from !== to && from >= 0 && to >= 0 && state.folders[from].spaceId === state.folders[to].spaceId) {
        const [folder] = state.folders.splice(from, 1); state.folders.splice(state.folders.findIndex(f => f.id === action.beforeId), 0, folder);
      }
      return true;
    }
    case 'space.reorder': {
      const from = state.spaces.findIndex(s => s.id === action.id);
      const to = state.spaces.findIndex(s => s.id === action.beforeId);
      if (from !== to && from >= 0 && to >= 0) { const [space] = state.spaces.splice(from, 1); state.spaces.splice(state.spaces.findIndex(s => s.id === action.beforeId), 0, space); }
      return true;
    }
    case 'tab.place': {
      const tab = state.tabs.find(t => t.id === action.id);
      if (!tab || !state.spaces.some(s => s.id === action.spaceId)) return true;
      const folder = action.folderId ? state.folders.find(f => f.id === action.folderId && f.spaceId === action.spaceId) : undefined;
      if (action.folderId && !folder) return true;
      const before = action.beforeId ? state.tabs.find(t => t.id === action.beforeId) : undefined;
      if (action.beforeId && (!before || before.spaceId !== action.spaceId || before.folderId !== folder?.id || before.pinned !== (folder ? true : action.pinned))) return true;
      tab.favoriteId = undefined; tab.spaceId = action.spaceId; tab.profileId = action.spaceId; tab.folderId = folder?.id; tab.pinned = folder ? true : action.pinned;
      if (folder) folder.collapsed = false;
      if (before && before !== tab) {
        state.tabs = state.tabs.filter(t => t.id !== tab.id);
        state.tabs.splice(state.tabs.findIndex(t => t.id === before.id), 0, tab);
      } else if (!before) { state.tabs = [...state.tabs.filter(t => t.id !== tab.id), tab]; }
      return true;
    }
    default: return false;
  }
}
