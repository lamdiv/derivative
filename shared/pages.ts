// Only this exact internal address is trusted as browser-owned tab metadata.
// It is rendered by React and is never loaded into a website WebContentsView.
export const NEW_TAB_URL = 'derivative://new-tab';
export const isNewTab = (url: string): boolean => url === NEW_TAB_URL;
