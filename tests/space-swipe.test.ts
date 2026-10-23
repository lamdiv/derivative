import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SpaceSwipeGesture } from '../src/hooks/space-swipe';

test('horizontal gestures retain diagonal deltas after choosing an axis', () => {
  const gesture = new SpaceSwipeGesture();
  assert.equal(gesture.update(14,2,0,0,3).consumed,true);
  assert.equal(gesture.update(20,28,16,0,3).step,0);
  assert.equal(gesture.update(20,25,32,0,3).step,1);
  assert.equal(gesture.update(90,1,48,1,3).step,0,'Momentum must not skip another Space');
});

test('vertical scrolling stays separate from horizontal swipes', () => {
  const gesture = new SpaceSwipeGesture();
  assert.equal(gesture.update(2,20,0,1,3).consumed,false);
  assert.equal(gesture.update(80,2,16,1,3).consumed,false,'Keep the vertical axis for this gesture');
  assert.equal(gesture.update(60,1,200,1,3).step,1,'A new gesture chooses its own axis');
});

test('rapid intentional reversals work while small momentum bounce is ignored', () => {
  const gesture = new SpaceSwipeGesture();
  assert.equal(gesture.update(65,1,0,0,3).step,1);
  assert.equal(gesture.update(-6,0,16,1,3).step,0);
  assert.equal(gesture.update(12,0,32,1,3).step,0);
  assert.equal(gesture.update(-30,0,48,1,3).step,0);
  assert.equal(gesture.update(-25,1,64,1,3).step,-1);
  assert.equal(gesture.update(-80,1,80,0,3).step,0);
});

test('the ends rubber-band without wrapping or dispatching, including a single Space', () => {
  const gesture = new SpaceSwipeGesture();
  const first=gesture.update(-80,1,0,0,3);
  assert.equal(first.edge,'first'); assert.equal(first.step,0); assert.ok(first.x>0 && first.x<28);
  const far=gesture.update(-800,0,16,0,3);
  assert.ok(far.x>first.x && far.x<=28);
  const last=gesture.update(80,0,200,2,3);
  assert.equal(last.edge,'last'); assert.equal(last.step,0); assert.ok(last.x<0);
  assert.equal(gesture.update(80,0,400,0,1).edge,'last');
});

test('a short gesture resets after quiet so repeated swipes do not accumulate', () => {
  const gesture=new SpaceSwipeGesture();
  assert.equal(gesture.update(30,1,0,0,3).step,0);
  assert.equal(gesture.update(30,1,180,0,3).step,0);
  assert.equal(gesture.update(25,1,196,0,3).step,1);
});
