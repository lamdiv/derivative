// Shared by native input routing and the Settings reference. Unmatched modifiers
// remain available to websites (e.g. Shift+Command+S and Option+Command+L).
export const shortcuts = [
  ['New tab', '⌘ T'], ['Edit address', '⌘ L'], ['Show / hide sidebar', '⌘ S'],
  ['Close tab', '⌘ W'], ['Reopen closed tab', '⇧ ⌘ T'], ['Pin / unpin tab', '⌘ D'],
  ['Copy page URL', '⇧ ⌘ C'], ['Reload', '⌘ R'], ['Reload without cache', '⇧ ⌘ R'],
  ['Recent tabs', '⌃ Tab'], ['Previous recent tab', '⇧ ⌃ Tab'],
  ['Previous / next tab', '⌥ ⌘ ↑ / ↓'], ['Previous / next Space', '⌥ ⌘ ← / →'],
  ['Switch to Space 1–9', '⌃ 1–9'], ['Switch to tab 1–8 / last', '⌘ 1–8 / 9'],
  ['Back / forward', '⌘ [ / ]'], ['Settings', '⌘ ,'],
] as const;

export interface ShortcutInput { type: string; key: string; code?: string; meta: boolean; control: boolean; alt: boolean; shift: boolean }
export function shortcutAction(input: ShortcutInput, mac = true): string | undefined {
  if (input.type !== 'keyDown') return;
  const { shift, alt, control, meta } = input;
  const key = input.key.toLowerCase();
  const command = mac ? meta : control;
  if (control && !meta && !alt && key === 'tab') return shift ? 'recent.previous' : 'recent.next';
  if (mac && control && !meta && !alt && !shift && /^[1-9]$/.test(key)) return `space.${key}`;
  if (!command || (mac && control) || (!mac && meta)) return;
  if (alt) {
    if (shift) return;
    return ({ arrowup: 'tab.previous', arrowdown: 'tab.next', arrowleft: 'space.previous', arrowright: 'space.next' } as Record<string, string>)[key];
  }
  if (shift) {
    if (key === 't') return 'reopen';
    if (key === 'c') return 'copy';
    if (key === 'r') return 'reload.hard';
    if (input.code === 'BracketLeft') return 'tab.previous';
    if (input.code === 'BracketRight') return 'tab.next';
    return;
  }
  if (/^[1-9]$/.test(key)) return `tab.${key}`;
  return ({ t: 'new', l: 'location', s: 'sidebar', w: 'close', d: 'pin', r: 'reload', ',': 'settings', '[': 'back', ']': 'forward' } as Record<string, string>)[key];
}
