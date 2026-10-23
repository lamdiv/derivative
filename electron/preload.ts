import { contextBridge, ipcRenderer } from 'electron';
import type { Action, BrowserBridge, BrowserState } from '../shared/types';
let current: BrowserState | undefined;
let complete=false, revision=0;
const listeners=new Set<{ listener:(patch:Partial<BrowserState>)=>void; initialized:boolean }>();
function publish(patch:Partial<BrowserState>, initializeOnly=false) {
  if (!complete || !current) return;
  for (const entry of listeners) {
    if (initializeOnly && entry.initialized) continue;
    entry.listener(entry.initialized ? patch : current);
    entry.initialized=true;
  }
}
ipcRenderer.on('browser:patch', (_event, patch:Partial<BrowserState>) => {
  current={...current,...patch} as BrowserState; revision++;
  if (patch.version===1) complete=true;
  publish(patch);
});
const bridge: BrowserBridge = {
  async getState() {
    const before=revision;
    const state:BrowserState=await ipcRenderer.invoke('browser:state');
    if (revision===before || !current) current=state;
    else if (!complete) current={...state,...current};
    complete=true; publish({},true);
    return current;
  },
  onSearchFocus(listener) {
    const handler = () => listener();
    ipcRenderer.on('browser:focus-search', handler);
    return () => ipcRenderer.removeListener('browser:focus-search', handler);
  },
  dispatch: (action: Action) => ipcRenderer.invoke('browser:action', action),
  subscribe(listener) {
    const entry={listener,initialized:false}; listeners.add(entry);
    if (complete && current) { listener(current); entry.initialized=true; }
    return () => { listeners.delete(entry); };
  },
};
contextBridge.exposeInMainWorld('browser', bridge);
