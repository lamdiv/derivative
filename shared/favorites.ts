import type { Favorite } from './types';
export const MAX_FAVORITES = 12;
export const defaultFavorites: Favorite[] = [
  ['github', 'GitHub', 'https://github.com/'], ['wikipedia', 'Wikipedia', 'https://wikipedia.org/'], ['arena', 'Are.na', 'https://www.are.na/'],
  ['youtube', 'YouTube', 'https://www.youtube.com/'], ['reddit', 'Reddit', 'https://www.reddit.com/'], ['figma', 'Figma', 'https://www.figma.com/'],
  ['notion', 'Notion', 'https://www.notion.so/'], ['mail', 'Gmail', 'https://mail.google.com/'], ['calendar', 'Calendar', 'https://calendar.google.com/'],
].map(([id, name, url]) => ({ id, name, url }));
