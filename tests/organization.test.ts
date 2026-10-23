import { test } from 'node:test';
import assert from 'node:assert/strict';
import { freshState, restoreState } from '../electron/storage/store';
import { organize, orderedSpaceTabs } from '../shared/organization';
import { validAction } from '../electron/ipc';
import type { Tab } from '../shared/types';

const tab = (id: string): Tab => ({ id, url: `https://example.com/${id}`, title: id, spaceId: 'personal', profileId: 'personal', pinned: false, loading: false, canGoBack: false, canGoForward: false, lastActive: 0, status: 'discarded' });
test('folder placement pins tabs, rejects cross-Space folders, and ungroups without closing', () => {
  const state = freshState(); state.tabs = [tab('a'), tab('b')]; state.activeTabId = 'a';
  organize(state, { type: 'folder.create', spaceId: 'personal', name: ' Reading ' }, () => 'reading');
  organize(state, { type: 'folder.create', spaceId: 'work', name: 'Projects' }, () => 'projects');
  organize(state, { type: 'tab.place', id: 'a', spaceId: 'personal', folderId: 'reading', pinned: false });
  assert.equal(state.tabs.find(t => t.id === 'a')?.pinned, true);
  assert.equal(state.tabs.find(t => t.id === 'a')?.folderId, 'reading');
  const before = JSON.stringify(state);
  organize(state, { type: 'tab.place', id: 'a', spaceId: 'work', folderId: 'reading', pinned: true });
  assert.equal(JSON.stringify(state), before, 'Invalid cross-Space folder must be a no-op');
  organize(state, { type: 'folder.delete', id: 'reading' });
  assert.equal(state.tabs.length, 2);
  assert.equal(state.activeTabId, 'a');
  assert.equal(state.tabs.find(t => t.id === 'a')?.folderId, undefined);
  assert.equal(state.tabs.find(t => t.id === 'a')?.pinned, true);
  organize(state, { type: 'tab.place', id: 'a', spaceId: 'work', folderId: 'projects', pinned: true });
  organize(state, { type: 'tab.place', id: 'a', spaceId: 'personal', pinned: false });
  assert.equal(state.tabs.find(t => t.id === 'a')?.folderId, undefined);
  assert.equal(state.tabs.find(t => t.id === 'a')?.pinned, false);
});
test('tab, folder, and Space ordering stay stable and match keyboard order', () => {
  const state = freshState(); state.tabs = [tab('a'), tab('b'), tab('c')];
  organize(state, { type: 'folder.create', spaceId: 'personal', name: 'First' }, () => 'first');
  organize(state, { type: 'folder.create', spaceId: 'personal', name: 'Second' }, () => 'second');
  organize(state, { type: 'tab.place', id: 'a', spaceId: 'personal', folderId: 'first', pinned: true });
  organize(state, { type: 'tab.place', id: 'b', spaceId: 'personal', folderId: 'first', pinned: true, beforeId: 'a' });
  organize(state, { type: 'tab.place', id: 'c', spaceId: 'personal', folderId: 'second', pinned: true });
  assert.deepEqual(orderedSpaceTabs(state, 'personal').map(t => t.id), ['b', 'a', 'c']);
  organize(state, { type: 'folder.reorder', id: 'second', beforeId: 'first' });
  assert.deepEqual(orderedSpaceTabs(state, 'personal').map(t => t.id), ['c', 'b', 'a']);
  organize(state, { type: 'folder.reorder', id: 'second', beforeId: 'second' });
  assert.deepEqual(state.folders.map(f => f.id), ['second', 'first']);
  organize(state, { type: 'space.reorder', id: 'study', beforeId: 'personal' });
  assert.deepEqual(state.spaces.map(s => s.id), ['study', 'personal', 'work']);
  organize(state, { type: 'space.reorder', id: 'study', beforeId: 'study' });
  assert.equal(state.spaces[0].id, 'study');
});
test('folders and membership restore safely, including legacy files without folders', () => {
  const state = freshState(); state.tabs = [tab('a'), tab('b')];
  state.folders = [{ id: 'reading', spaceId: 'personal', name: 'Reading', collapsed: true }];
  state.tabs[0].folderId = 'reading';
  state.tabs[1].folderId = 'orphan';
  const restored = restoreState(state);
  assert.deepEqual(restored.folders, state.folders);
  assert.equal(restored.tabs[0].folderId, 'reading');
  assert.equal(restored.tabs[0].pinned, true);
  assert.equal(restored.tabs[1].folderId, undefined);
  assert.deepEqual(restoreState({ version: 1 }).folders, []);
  assert.equal(validAction({ type: 'tab.place', id: 'a', spaceId: 'personal', pinned: true, folderId: 'reading' }), true);
  assert.equal(validAction({ type: 'tab.place', id: 'a', spaceId: 'personal', pinned: 'yes' }), false);
  assert.equal(validAction({ type: 'folder.create', spaceId: 'personal', name: '   ' }), false);
  assert.equal(validAction({ type: 'folder.rename', id: 'reading', name: 'A'.repeat(41) }), false);
});

test('favorites reorder persists and rejects stale targets without deleting items', () => {
  const state=freshState(); const [first, second, third]=state.favorites;
  organize(state, { type:'favorite.reorder', id:third.id, beforeId:first.id });
  assert.deepEqual(state.favorites.slice(0,3).map(f=>f.id), [third.id,first.id,second.id]);
  const before=JSON.stringify(state.favorites);
  organize(state, { type:'favorite.reorder', id:first.id, beforeId:'missing' });
  assert.equal(JSON.stringify(state.favorites), before);
  assert.deepEqual(restoreState(state).favorites, state.favorites);
  assert.equal(validAction({ type:'favorite.reorder', id:first.id }), false);
});
test('restoration derives website profiles from Space ownership and drops transient split state', () => {
  const state=freshState(); state.tabs=[{ ...tab('work-tab'), spaceId:'work', profileId:'personal' }];
  state.splitView={ ids:['work-tab','forged'] };
  const restored=restoreState(state);
  assert.equal(restored.tabs[0].profileId, 'work');
  assert.equal(restored.splitView, null);
  assert.equal(validAction({ type:'split.open', id:'work-tab' }), true);
  assert.equal(validAction({ type:'split.open', id:'work-tab', withId:'target' }), true);
  assert.equal(validAction({ type:'split.open', id:'work-tab', withId:123 }), false);
  assert.equal(validAction({ type:'split.open' }), false);
});

test('favorite ownership survives navigation/restoration and ignores deleted favorite IDs', () => {
  const state=freshState(); const favorite=state.favorites[0];
  state.tabs=[{...tab('owned'), favoriteId:favorite.id, url:'https://github.com/features'}, {...tab('stale'),favoriteId:'deleted'}];
  const restored=restoreState(state);
  assert.equal(restored.tabs[0].favoriteId,favorite.id);
  assert.equal(restored.tabs[1].favoriteId,undefined);
  organize(restored,{type:'tab.place',id:'owned',spaceId:'personal',pinned:true});
  assert.equal(restored.tabs[0].favoriteId,undefined,'Moving a favorite into the normal tab list should release grid ownership');
});

test('favorite reorder can commit the last preview slot without a synthetic target', () => {
  const state=freshState(), first=state.favorites[0];
  organize(state,{type:'favorite.reorder',id:first.id,beforeId:null});
  assert.equal(state.favorites.at(-1)?.id,first.id);
  assert.equal(validAction({type:'favorite.reorder',id:first.id,beforeId:null}),true);
  assert.equal(validAction({type:'favorite.reorder',id:first.id}),false);
});
