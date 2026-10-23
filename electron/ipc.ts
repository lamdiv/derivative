import type { Action } from '../shared/types';

const string = (value: unknown, max = 200): value is string => typeof value === 'string' && value.length > 0 && value.length <= max;
export function validAction(value: unknown): value is Action {
  if (!value || typeof value !== 'object' || !('type' in value)) return false;
  const a = value as Record<string, unknown>;
  switch (a.type) {
    case 'split.close': case 'tab.new': case 'overlay.close': case 'back': case 'forward': case 'reload': case 'stop': case 'sidebar.toggle': case 'settings': return true;
    case 'sidebar.interaction': return string(a.id, 100) && typeof a.active === 'boolean';
    case 'sidebar.reveal': return typeof a.visible === 'boolean';
    case 'favorite.save': return string(a.name, 40) && !!a.name.trim() && string(a.url, 8192) && (a.id === undefined || string(a.id));
    case 'split.open': return string(a.id) && (a.withId === undefined || string(a.withId));
    case 'favorite.copy': case 'favorite.delete': case 'favorite.open': return string(a.id);
    case 'palette': return a.mode === 'new' || a.mode === 'navigate';
    case 'navigate': return string(a.input, 8192) && (a.newTab === undefined || typeof a.newTab === 'boolean');
    case 'tab.select': case 'tab.close': case 'tab.pin': case 'tab.duplicate': case 'space.select': case 'space.delete': case 'download.cancel': case 'download.open': case 'download.reveal': return string(a.id);
    case 'favorite.reorder': return string(a.id) && (a.beforeId === null || string(a.beforeId));
    case 'tab.reorder': case 'space.reorder': case 'folder.reorder': return string(a.id) && string(a.beforeId);
    case 'folder.create': return string(a.spaceId) && string(a.name, 40) && !!a.name.trim();
    case 'folder.rename': return string(a.id) && string(a.name, 40) && !!a.name.trim();
    case 'folder.toggle': case 'folder.delete': return string(a.id);
    case 'tab.place': return string(a.id) && string(a.spaceId) && typeof a.pinned === 'boolean' && (a.folderId === undefined || string(a.folderId)) && (a.beforeId === undefined || string(a.beforeId));
    case 'tab.move': return string(a.id) && string(a.spaceId);
    case 'space.rename': return string(a.id) && string(a.name, 40) && !!a.name.trim();
    case 'space.create': return string(a.name, 40) && !!a.name.trim() && string(a.icon, 8) && ['lavender', 'mint', 'peach', 'blue', 'blush'].includes(String(a.color));
    case 'clear': return ['history', 'cache', 'cookies'].includes(String(a.target));
    case 'preferences': {
      if (!a.preferences || typeof a.preferences !== 'object' || Array.isArray(a.preferences)) return false;
      return Object.entries(a.preferences).every(([key, val]) => {
        if (key === 'theme') return ['system', 'dark', 'light'].includes(String(val));
        if (key === 'searchEngine') return val === 'google' || val === 'duckduckgo';
        if (key === 'sidebarSize') return ['compact', 'comfortable', 'wide'].includes(String(val));
        if (key === 'sidebarMode') return ['fixed', 'hover', 'hidden'].includes(String(val));
        if (key === 'restoreSession') return typeof val === 'boolean';
        return false;
      });
    }
    default: return false;
  }
}
