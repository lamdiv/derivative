import type { BrowserState } from './types';
import { displayURL, isWebURL, resolveInput, searchURL } from './navigation';
export interface Suggestion { id: string; title: string; detail: string; kind: 'tab' | 'history' | 'url' | 'search' | 'command'; url?: string; favicon?: string; command?: 'sidebar.toggle' | 'settings' }
export function suggestions(query: string, state: BrowserState): Suggestion[] {
  const q = query.trim().toLowerCase();
  const result: Suggestion[] = [];
  const matches = (title: string, url: string) => !q || `${title} ${url}`.toLowerCase().includes(q);
  let resolved: string | undefined;
  try { if (q) resolved = resolveInput(query, state.preferences.searchEngine); } catch { /* The UI reports unsupported input on submit. */ }
  const isSearch = resolved?.startsWith('https://www.google.com/search?') || resolved?.startsWith('https://duckduckgo.com/?q=');
  const exact = (url: string) => resolved === url || displayURL(url).toLowerCase() === q;
  const tabs = state.tabs.filter(t => t.spaceId === state.activeSpaceId && isWebURL(t.url) && matches(t.title, t.url)).sort((a, b) => Number(exact(b.url)) - Number(exact(a.url)) || b.lastActive - a.lastActive);
  for (const t of tabs.slice(0, 5)) result.push({ id: t.id, kind: 'tab', title: t.title, detail: `${t.id === state.activeTabId ? 'Current tab' : 'Switch to tab'} · ${displayURL(t.url)}`, url: t.url, favicon: t.favicon });
  const tabURLs = new Set(tabs.map(t => t.url));
  for (const h of state.history.filter(h => !tabURLs.has(h.url) && matches(h.title, h.url)).sort((a, b) => Number(exact(b.url)) - Number(exact(a.url)) || b.visitedAt - a.visitedAt).slice(0, 4)) {
    result.push({ id: `history:${h.url}`, kind: 'history', title: h.title, detail: displayURL(h.url), url: h.url, favicon: h.favicon });
  }
  result.sort((a, b) => Number(exact(b.url ?? '')) - Number(exact(a.url ?? '')));
  if (resolved && !isSearch && !result.some(r => exact(r.url ?? ''))) result.unshift({ id: 'url', kind: 'url', title: displayURL(resolved), detail: 'Open website', url: resolved });
  const commands: Suggestion[] = [
    { id: 'cmd:sidebar', title: 'Toggle sidebar', detail: 'Make a little more room', kind: 'command', command: 'sidebar.toggle' },
    { id: 'cmd:settings', title: 'Open settings', detail: 'Make yourself at home', kind: 'command', command: 'settings' },
  ];
  result.push(...commands.filter(c => !!q && c.title.toLowerCase().includes(q)));
  if (q && resolved) result.push({ id: 'search', kind: 'search', title: `Search for “${query.trim()}”`, detail: state.preferences.searchEngine === 'google' ? 'Google Search' : 'DuckDuckGo', url: searchURL(query, state.preferences.searchEngine) });
  return result.slice(0, 8);
}
