import { test } from 'node:test';
import assert from 'node:assert/strict';
import { freshState } from '../electron/storage/store';
import { StatePublisher } from '../electron/windows/state-publisher';

test('state publisher sends a complete snapshot once, then only changed sections', () => {
  const state=freshState();
  const publisher=new StatePublisher();
  assert.deepEqual(publisher.update(state),state);
  assert.equal(publisher.update(state),null);
  state.sidebarRevealed=true;
  assert.deepEqual(publisher.update(state),{sidebarRevealed:true});
  assert.equal(publisher.update(state),null);
  state.history=[{url:'https://example.com/',title:'Example',visitedAt:1}];
  assert.deepEqual(publisher.update(state),{history:state.history});
  state.overlay='palette';
  assert.deepEqual(publisher.update(state),{overlay:'palette'});
});

test('snapshots detect in-place mutations without leaking mutable state to previous messages', () => {
  const state=freshState();
  const publisher=new StatePublisher();
  const first=publisher.update(state)!;
  const oldName=state.favorites[0].name;
  state.favorites[0].name='Changed';
  const patch=publisher.update(state)!;
  assert.deepEqual(Object.keys(patch),['favorites']);
  assert.equal(first.favorites![0].name,oldName);
  assert.equal(patch.favorites![0].name,'Changed');
  state.tabSwitcher={ids:['one','two'],index:0};publisher.update(state);
  state.tabSwitcher.index=1;
  assert.deepEqual(publisher.update(state),{tabSwitcher:{ids:['one','two'],index:1}});
  state.tabSwitcher=null;
  assert.deepEqual(publisher.update(state),{tabSwitcher:null});
});

test('independent renderers catch up after skipping hidden updates', () => {
  const state=freshState(), root=new StatePublisher(), hidden=new StatePublisher();
  root.update(state);hidden.update(state);
  state.sidebarRevealed=true;state.favorites.reverse();root.update(state);
  state.history=[{url:'https://example.com/new',title:'New',visitedAt:2}];root.update(state);
  const patch=hidden.update(state)!;
  assert.deepEqual(patch,{favorites:state.favorites,history:state.history,sidebarRevealed:true});
  assert.equal(hidden.update(state),null);
});
