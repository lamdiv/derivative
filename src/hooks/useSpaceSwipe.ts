import { useEffect, useLayoutEffect, useRef, useState, type RefObject } from 'react';
import type { Action, BrowserState } from '../../shared/types';
import { SpaceSwipeGesture, swipeQuietMs, type SpaceEdge } from './space-swipe';

type Motion = { x:number; following:boolean; edge:SpaceEdge };
const resting: Motion = { x:0, following:false, edge:null };

export function useSpaceSwipe(ref: RefObject<HTMLElement | null>, state: BrowserState, send: (action: Action) => void, enabled = true) {
  const current = useRef({ state, send }); current.current = { state, send };
  const previousSpace = useRef(state.activeSpaceId);
  const direction = useRef(0);
  const [motion, setMotion] = useState<Motion>(resting);
  useLayoutEffect(() => {
    if (previousSpace.current === state.activeSpaceId) return;
    const oldIndex = state.spaces.findIndex(s => s.id === previousSpace.current);
    const newIndex = state.spaces.findIndex(s => s.id === state.activeSpaceId);
    const sign = direction.current || Math.sign(newIndex-oldIndex) || 1;
    previousSpace.current = state.activeSpaceId; direction.current = 0;
    setMotion({ x:sign*40, following:true, edge:null });
    let nextFrame = 0;
    const frame = requestAnimationFrame(() => { nextFrame = requestAnimationFrame(() => setMotion(resting)); });
    return () => { cancelAnimationFrame(frame); cancelAnimationFrame(nextFrame); };
  }, [state.activeSpaceId]);
  useEffect(() => {
    const node = ref.current;
    if (!node || !enabled) return;
    const gesture = new SpaceSwipeGesture();
    let settle: ReturnType<typeof setTimeout>;
    let frame = 0;
    let pending: Motion = resting;
    const follow = (next: Motion) => {
      pending = next;
      if (!frame) frame = requestAnimationFrame(() => { frame=0; setMotion(pending); });
    };
    const wheel = (event: WheelEvent) => {
      if (event.ctrlKey || event.target instanceof Element && event.target.closest('input,select,textarea,[contenteditable="true"],[role="menu"]')) return;
      const { state, send } = current.current;
      const scale = event.deltaMode===1 ? 16 : event.deltaMode===2 ? node.clientWidth : 1;
      const index = state.spaces.findIndex(s=>s.id===state.activeSpaceId);
      const result = gesture.update(event.deltaX*scale,event.deltaY*scale,performance.now(),index,state.spaces.length);
      clearTimeout(settle);
      settle=setTimeout(() => { gesture.reset(); follow(resting); },swipeQuietMs);
      if (!result.consumed) return;
      event.preventDefault();
      if (result.step) {
        cancelAnimationFrame(frame); frame=0;
        direction.current=result.step;
        send({ type:'space.select', id:state.spaces[index+result.step].id });
      } else if (result.x || result.edge) follow({ x:result.x, following:true, edge:result.edge });
    };
    node.addEventListener('wheel',wheel,{passive:false});
    return () => { clearTimeout(settle); cancelAnimationFrame(frame); node.removeEventListener('wheel',wheel); };
  }, [ref,enabled]);
  return motion;
}
