import type { BrowserState } from '../../shared/types';

function equal(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (!a || !b || typeof a !== 'object' || typeof b !== 'object') return false;
  if (Array.isArray(a)) return Array.isArray(b) && a.length === b.length && a.every((value,index)=>equal(value,b[index]));
  if (Array.isArray(b)) return false;
  const first=a as Record<string,unknown>, second=b as Record<string,unknown>;
  const keys=Object.keys(first);
  return keys.length===Object.keys(second).length && keys.every(key=>Object.hasOwn(second,key) && equal(first[key],second[key]));
}

/** Per-renderer snapshots let a hidden surface catch up without retransmitting history. */
export class StatePublisher {
  private snapshot?: BrowserState;
  private historySource?: BrowserState['history'];
  update(state: BrowserState): Partial<BrowserState> | null {
    const patch: Record<string,unknown> = {};
    const previous=this.snapshot;
    for (const key of Object.keys(state) as (keyof BrowserState)[]) {
      const value=state[key];
      // History is replaced, never edited in place, by the tab manager.
      if (key==='history' && previous && value===this.historySource) continue;
      if (!previous || !equal(value,previous[key])) patch[key]=typeof value==='object' && value!==null ? structuredClone(value) : value;
    }
    this.historySource=state.history;
    if (!Object.keys(patch).length) return null;
    this.snapshot={...previous,...patch} as BrowserState;
    return patch as Partial<BrowserState>;
  }
}
