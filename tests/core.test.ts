import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { resolveInput, searchURL } from '../shared/navigation';
import { freshState, restoreState, Store } from '../electron/storage/store';
import { validAction } from '../electron/ipc';
import { suggestions } from '../shared/suggestions';
import type { Tab } from '../shared/types';
import { sidebarWidth, floatingSidebarWidth, fixedSidebarInset, effectiveSidebarMode, sidebarReservesSpace } from '../shared/layout';
import { NEW_TAB_URL } from '../shared/pages';
import { shortcutAction, type ShortcutInput } from '../shared/shortcuts';

const tab = (id: string, url: string, title: string): Tab => ({ id, url, title, spaceId: 'personal', profileId: 'personal', pinned: false, loading: false, canGoBack: false, canGoForward: false, lastActive: 0, status: 'background' });
test('Arc-style shortcuts use exact modifiers and preserve unrelated website input', () => {
  const key = (key: string, modifiers: Partial<ShortcutInput> = {}) => shortcutAction({ key, type: 'keyDown', meta: true, control: false, shift: false, alt: false, ...modifiers });
  assert.equal(key('s'), 'sidebar');
  assert.equal(key('s', { shift: true }), undefined);
  assert.equal(key('t', { shift: true }), 'reopen');
  assert.equal(key('c', { shift: true }), 'copy');
  assert.equal(key('ArrowDown', { alt: true }), 'tab.next');
  assert.equal(key('ArrowLeft', { alt: true }), 'space.previous');
  assert.equal(key('Tab', { meta: false, control: true }), 'recent.next');
  assert.equal(key('Tab', { meta: false, control: true, shift: true }), 'recent.previous');
  assert.equal(key('3', { meta: false, control: true }), 'space.3');
  assert.equal(key('l', { alt: true }), undefined);
  assert.equal(key('w', { shift: true }), undefined);
  assert.equal(key('t', { meta: false }), undefined);
});
test('sidebar modes persist, transient reveal resets, and legacy rail settings migrate', () => {
  const state = freshState();
  state.preferences.sidebarMode = 'hidden'; state.sidebarRevealed = true;
  const restored = restoreState(state);
  assert.equal(restored.preferences.sidebarMode, 'hidden');
  assert.equal(restored.sidebarRevealed, false);
  assert.equal(restoreState({ version: 1, preferences: { sidebarCollapsed: true } }).preferences.sidebarMode, 'hover');
  assert.equal(validAction({ type: 'preferences', preferences: { sidebarMode: 'hover' } }), true);
  assert.equal(validAction({ type: 'preferences', preferences: { sidebarMode: 'overlay' } }), false);
  assert.equal(validAction({ type: 'sidebar.reveal', visible: 'yes' }), false);
});
test('URL normalization and search preserve intent', () => {
  assert.equal(resolveInput('github.com'), 'https://github.com/');
  assert.equal(resolveInput('https://example.com/a?q=b'), 'https://example.com/a?q=b');
  assert.equal(resolveInput('localhost:8080/test'), 'http://localhost:8080/test');
  assert.equal(resolveInput('127.0.0.1:8123'), 'http://127.0.0.1:8123/');
  assert.equal(resolveInput('how does quantum computing work'), 'https://www.google.com/search?q=how%20does%20quantum%20computing%20work');
  assert.equal(resolveInput('cozy browsers', 'duckduckgo'), 'https://duckduckgo.com/?q=cozy%20browsers');
  assert.equal(searchURL('github.com'), 'https://www.google.com/search?q=github.com');
});
test('navigation rejects privileged and executable schemes', () => {
  for (const value of ['javascript:alert(1)', 'file:///etc/passwd', 'data:text/html,test', 'about:blank', 'ftp://example.com', '']) assert.throws(() => resolveInput(value));
});
test('IPC rejects malformed payloads and preference key injection', () => {
  assert.equal(validAction({ type: 'navigate', input: 'github.com', newTab: true }), true);
  assert.equal(validAction({ type: 'sidebar.interaction', id: 'floating:menu', active: true }), true);
  assert.equal(validAction({ type: 'sidebar.interaction', id: 'floating:menu', active: 'yes' }), false);
  for (const action of [null, [], { type: 'anything' }, { type: 'navigate', input: 1 }, { type: 'tab.close' }, { type: 'preferences', preferences: { webSecurity: false } }, { type: 'preferences', preferences: [] }, { type: 'space.create', name: 'Work', color: 'neon', icon: 'A' }, { type: 'clear', target: 'all' }]) assert.equal(validAction(action), false);
});
test('restoration sanitizes tabs and restores metadata without loading background pages', () => {
  const state = freshState();
  state.tabs = [tab('one', 'https://example.com/', 'Example'), tab('bad', 'file:///secret', 'Bad')];
  state.activeTabId = 'one';
  const restored = restoreState(state);
  assert.equal(restored.tabs.length, 1);
  assert.equal(restored.tabs[0].status, 'discarded');
  assert.equal(restored.tabs[0].loading, false);
  assert.equal(restored.activeTabId, 'one');
  state.preferences.restoreSession = false;
  assert.equal(restoreState(state).tabs.length, 0);
  assert.deepEqual(restoreState({ version: 7 }), freshState());
});
test('atomic storage queues writes and recovers from malformed metadata', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'derivative-store-'));
  try {
    const path = join(dir, 'state.json');
    const store = new Store(path);
    const state = freshState();
    const first = store.write(state);
    state.preferences.theme = 'dark';
    const second = store.write(state);
    await Promise.all([first, second]);
    assert.equal((await store.read()).preferences.theme, 'dark');
    assert.equal(JSON.parse(await readFile(path, 'utf8')).version, 1);
    await writeFile(path, '{broken');
    assert.deepEqual(await store.read(), freshState());
  } finally { await rm(dir, { recursive: true, force: true }); }
});
test('palette ranks exact URLs before tabs, history, commands and fallback', () => {
  const state = freshState();
  state.tabs = [tab('one', 'https://github.com/issues', 'GitHub issues')];
  state.history = [{ url: 'https://github.com/', title: 'GitHub', visitedAt: 1 }];
  const result = suggestions('github.com', state);
  assert.equal(result[0].kind, 'history');
  assert.equal(result[1].kind, 'tab');
  assert.equal(result.at(-1)?.kind, 'search');
  assert.equal(suggestions('sidebar', state)[0].command, 'sidebar.toggle');
  assert.equal(suggestions('example.org', state)[0].kind, 'url');
  assert.equal(suggestions('javascript:alert(1)', state).some(r => r.kind === 'url'), false);
});

test('internal new tabs restore exactly, stay out of website suggestions, and cannot be navigated to as privileged URLs', () => {
  const state = freshState();
  state.tabs = [tab('draft', NEW_TAB_URL, 'New tab'), tab('forged', 'derivative://settings', 'Fake')];
  state.activeTabId = 'draft';
  const restored = restoreState(state);
  assert.equal(restored.tabs.length, 1);
  assert.equal(restored.activeTabId, 'draft');
  assert.equal(suggestions('', restored).some(result => result.kind === 'tab'), false);
  assert.throws(() => resolveInput(NEW_TAB_URL));
  assert.equal(validAction({ type: 'tab.new' }), true);
});

test('sidebar widths migrate safely and expanded mode leaves the saved normal-window choice intact', () => {
  const state = freshState();
  assert.equal(sidebarWidth(state.preferences), 288);
  for (const [size, width] of [['compact', 252], ['comfortable', 288], ['wide', 320]] as const) {
    state.preferences.sidebarSize = size;
    assert.equal(sidebarWidth(restoreState(state).preferences), width);
    assert.equal(floatingSidebarWidth(state.preferences), width + 28);
    assert.equal(fixedSidebarInset(state.preferences), width + 16);
    assert.equal(validAction({ type: 'preferences', preferences: { sidebarSize: size } }), true);
  }
  assert.equal(validAction({ type: 'preferences', preferences: { sidebarSize: 'huge' } }), false);
  state.windowExpanded = true; state.expandedSidebarMode = 'hover';
  assert.equal(effectiveSidebarMode(state), 'hover');
  assert.equal(restoreState(state).preferences.sidebarMode, 'fixed');
  assert.equal(restoreState(state).windowExpanded, false);
});
test('favorites sanitize privileged URLs, keep intentional empty grids, and cap saved grids at twelve', () => {
  const state = freshState();
  assert.equal(state.favorites.length, 9);
  state.favorites = Array.from({ length: 15 }, (_, i) => ({ id: `f${i}`, name: `Site ${i}`, url: `https://example.com/${i}` }));
  assert.equal(restoreState(state).favorites.length, 12);
  state.favorites = [{ id: 'bad', name: 'Bad', url: 'file:///secret' }];
  assert.equal(restoreState(state).favorites.length, 0);
  assert.equal(validAction({ type: 'favorite.save', name: '', url: 'https://example.com' }), false);
  assert.equal(validAction({ type: 'favorite.save', name: 'Example', url: 'https://example.com' }), true);
});

test('expanded sidebar pinning never reserves or shrinks the page canvas', () => {
  const state = freshState();
  assert.equal(sidebarReservesSpace(state), true);
  state.windowExpanded = true;
  state.expandedSidebarMode = 'hover';
  assert.equal(sidebarReservesSpace(state), false);
  state.sidebarRevealed = true;
  assert.equal(sidebarReservesSpace(state), false);
  state.expandedSidebarMode = 'fixed';
  assert.equal(sidebarReservesSpace(state), false);
  state.windowExpanded = false;
  assert.equal(sidebarReservesSpace(state), true);
});


test('search only offers open tabs from the current Space for empty and matching queries', () => {
  const state=freshState();
  state.tabs=[tab('personal','https://example.com/shared','Shared personal'),{...tab('work','https://example.com/shared','Shared work'),spaceId:'work',profileId:'work',lastActive:100}];
  state.activeTabId='personal';
  for (const query of ['', 'shared', 'example.com/shared']) {
    const tabs=suggestions(query,state).filter(result=>result.kind==='tab');
    assert.deepEqual(tabs.map(result=>result.id),['personal']);
    assert.match(tabs[0].detail,/Current tab/);
  }
  state.activeSpaceId='work';state.activeTabId='work';
  assert.deepEqual(suggestions('shared',state).filter(result=>result.kind==='tab').map(result=>result.id),['work']);
  state.activeSpaceId='study';state.activeTabId=null;
  assert.equal(suggestions('',state).some(result=>result.kind==='tab'),false,'Empty Spaces must not offer other Spaces’ tabs');
  assert.equal(suggestions('shared',state).some(result=>result.kind==='tab'),false);
});
