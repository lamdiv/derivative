import type { Preferences } from './types';
export const sidebarSizes = [
  { id: 'compact', label: 'Compact', width: 252 },
  { id: 'comfortable', label: 'Comfortable', width: 288 },
  { id: 'wide', label: 'Wide', width: 320 },
] as const;
export function sidebarWidth(preferences: Preferences): number {
  return sidebarSizes.find(size => size.id === preferences.sidebarSize)?.width ?? 288;
}
export const floatingSidebarWidth = (preferences: Preferences): number => sidebarWidth(preferences) + 28;
export const fixedSidebarInset = (preferences: Preferences): number => sidebarWidth(preferences) + 16;
export const effectiveSidebarMode = (state: import('./types').BrowserState): Preferences['sidebarMode'] => state.windowExpanded ? state.expandedSidebarMode : state.preferences.sidebarMode;
// Expanded windows always keep the complete webpage canvas underneath the sidebar.
export const sidebarReservesSpace = (state: import('./types').BrowserState): boolean => !state.windowExpanded && effectiveSidebarMode(state) === 'fixed';
