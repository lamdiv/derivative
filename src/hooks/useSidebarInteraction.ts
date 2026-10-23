import { useLayoutEffect, useId, useRef, type RefObject } from 'react';
import type { Action } from '../../shared/types';

/** Keep floating chrome alive while a menu/editor is in use, and release on dismissal. */
export function useSidebarInteraction(active: boolean, dismiss: () => void, boundary: RefObject<HTMLElement | null>, send: (action: Action) => void) {
  const reactId = useId();
  const id = `${location.search.includes('chrome=1') ? 'floating' : 'docked'}:${reactId}`;
  const onDismiss = useRef(dismiss); onDismiss.current = dismiss;
  useLayoutEffect(() => {
    if (!active) return;
    send({ type: 'sidebar.interaction', id, active: true });
    const outside = (event: Event) => { if (event.target instanceof Node && !boundary.current?.contains(event.target)) onDismiss.current(); };
    const escape = (event: KeyboardEvent) => { if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); onDismiss.current(); } };
    const blur = () => onDismiss.current();
    document.addEventListener('pointerdown', outside, true);
    document.addEventListener('focusin', outside, true);
    document.addEventListener('keydown', escape, true);
    window.addEventListener('blur', blur);
    return () => {
      document.removeEventListener('pointerdown', outside, true);
      document.removeEventListener('focusin', outside, true);
      document.removeEventListener('keydown', escape, true);
      window.removeEventListener('blur', blur);
      send({ type: 'sidebar.interaction', id, active: false });
    };
  }, [active, boundary, id, send]);
}
