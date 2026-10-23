import { useEffect, type RefObject } from 'react';

export function useDialogKeyboard(ref: RefObject<HTMLElement | null>) {
  useEffect(() => {
    const panel = ref.current;
    if (!panel) return;
    const previous = document.activeElement;
    const focusable = () => [...panel.querySelectorAll<HTMLElement>('button:not(:disabled), input, select, [tabindex="0"]')].filter(el => el.offsetParent !== null);
    focusable()[0]?.focus();
    const keydown = (event: KeyboardEvent) => {
      if (event.key !== 'Tab') return;
      const items = focusable();
      if (!items.length) return;
      const index = items.indexOf(document.activeElement as HTMLElement);
      if (event.shiftKey && index <= 0) { event.preventDefault(); items.at(-1)?.focus(); }
      else if (!event.shiftKey && (index === -1 || index === items.length - 1)) { event.preventDefault(); items[0].focus(); }
    };
    panel.addEventListener('keydown', keydown);
    return () => { panel.removeEventListener('keydown', keydown); if (previous instanceof HTMLElement) previous.focus(); };
  }, [ref]);
}
