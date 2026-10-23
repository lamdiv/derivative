export function isWebURL(value: string): boolean {
  try { return ['http:', 'https:'].includes(new URL(value).protocol); } catch { return false; }
}

export function searchURL(query: string, engine: 'google' | 'duckduckgo' = 'google'): string {
  return engine === 'google' ? `https://www.google.com/search?q=${encodeURIComponent(query.trim())}` : `https://duckduckgo.com/?q=${encodeURIComponent(query.trim())}`;
}

export function resolveInput(input: string, engine: 'google' | 'duckduckgo' = 'google'): string {
  const value = input.trim().slice(0, 8192);
  if (!value) throw new Error('Enter a URL or search');
  if (/^[a-z][a-z\d+.-]*:\/\//i.test(value)) {
    if (!isWebURL(value)) throw new Error('Only HTTP and HTTPS addresses are supported');
    return new URL(value).href;
  }
  if (!/\s/.test(value) && /^(localhost(?::\d+)?|\[[\da-f:]+\](?::\d+)?|(?:[\p{L}\d-]+\.)+[\p{L}\d-]+(?::\d+)?)(?:[/?#].*)?$/iu.test(value)) {
    const protocol = /^(localhost|127\.|\[::1\])/.test(value) ? 'http' : 'https';
    return new URL(`${protocol}://${value}`).href;
  }
  if (/^(javascript|data|file|vbscript|about):/i.test(value)) throw new Error('This address type is not supported');
  return searchURL(value, engine);
}

export function displayURL(url: string): string {
  try { const u = new URL(url); return u.host.replace(/^www\./, '') + (u.pathname === '/' ? '' : u.pathname); } catch { return url; }
}
