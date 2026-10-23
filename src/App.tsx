import { BrandMark } from './components/BrandMark';
import { useCallback, useEffect, useLayoutEffect, useRef, useState, type CSSProperties } from 'react';
import { X, RotateCw, Columns2 } from 'lucide-react';
import type { Action, BrowserState } from '../shared/types';
import { displayURL } from '../shared/navigation';
import { effectiveSidebarMode, sidebarWidth, sidebarReservesSpace } from '../shared/layout';
import { isNewTab } from '../shared/pages';
import { NewTabPage } from './components/NewTabPage';
import { Sidebar } from './components/Sidebar';
import { CommandPalette } from './components/CommandPalette';
import { Settings } from './components/Settings';
import { Favicon } from './components/Favicon';

const chromeSurface = new URLSearchParams(location.search).get('chrome') === '1';
if (chromeSurface) document.documentElement.dataset.surface = 'chrome';

function usePresence<T>(value: T | null) {
  const latest=useRef(value);
  const [present,setPresent]=useState(value!==null);
  const visible=value!==null;
  if (visible) latest.current=value;
  useEffect(()=>{
    if (visible) { setPresent(true); return; }
    if (!latest.current) return;
    const timer=setTimeout(()=>{latest.current=null;setPresent(false);},160);
    return ()=>clearTimeout(timer);
  },[visible]);
  return value ?? (present ? latest.current : null);
}

export default function App() {
  const [state, setState] = useState<BrowserState>();
  const [error, setError] = useState('');
  const send = useCallback((action: Action) => { void window.browser?.dispatch(action).catch(e => setError(e.message.replace(/^Error invoking remote method '[^']+': Error: /, ''))); }, []);
  useEffect(() => {
    if (!window.browser) return;
    let received = false;
    const unsubscribe = window.browser.subscribe(s => { received = true; setState(previous=>({...previous,...s} as BrowserState)); });
    if (!received) void window.browser.getState().then(s => { if (!received) setState(s); }).catch(e => setError(e.message));
    return unsubscribe;
  }, []);
  useLayoutEffect(() => { document.documentElement.dataset.appearance = state?.dark ? 'dark' : 'light'; }, [state?.dark]);
  const modal = usePresence(state?.overlay ? state : null);
  const sidebar = usePresence(state && (effectiveSidebarMode(state) === 'fixed' || state.sidebarRevealed) ? state : null);
  if (chromeSurface && !state) return null;
  if (!window.browser) return <div className="launch-message"><BrandMark className="wordmark" /><h1>A browser deserves its own window.</h1><p>Launch Derivative with <code>npm run dev</code> to browse with Chromium.</p></div>;
  if (!state) return <div className="launch-message"><BrandMark className="wordmark" /><p>{error || 'Opening Derivative…'}</p></div>;
  const active = state.tabs.find(t => t.id === state.activeTabId);
  const space = state.spaces.find(s => s.id === state.activeSpaceId)!;
  const sidebarStyle = { '--sidebar-width': `${sidebarWidth(state.preferences)}px` } as CSSProperties;
  const sidebarVisible = sidebarReservesSpace(state);
  if (chromeSurface) return <div style={sidebarStyle} className={`chrome-surface theme-${space.color}`}>
    {sidebar && <div className={`floating-sidebar browser-shell ${state.windowExpanded ? 'is-expanded' : ''} ${sidebarReservesSpace(sidebar) ? 'docked' : ''} theme-${space.color} ${effectiveSidebarMode(state) !== 'fixed' && !state.sidebarRevealed ? 'exiting' : ''}`}><Sidebar state={{ ...sidebar, sidebarRevealed: true }} send={send} /></div>}
    {modal && <div className={`modal-presence ${!state.overlay ? 'exiting' : ''}`}><BrowserOverlays state={modal} send={send} /></div>}
    {error && <div className="toast" role="alert">{error}</div>}
  </div>;
  return <div style={sidebarStyle} className={`browser-shell theme-${space.color} ${state.windowExpanded ? 'is-expanded' : ''} ${sidebarVisible ? '' : 'sidebar-hidden'}`}>
    {sidebarVisible && <Sidebar state={state} send={send} />}
    {!sidebarVisible && effectiveSidebarMode(state) === 'hover' && <button className="sidebar-edge" aria-label="Reveal sidebar" onMouseEnter={() => send({ type: 'sidebar.reveal', visible: true })} onFocus={() => send({ type: 'sidebar.reveal', visible: true })} onClick={() => send({ type: 'sidebar.toggle' })} />}
    <main className="canvas-area">
      <div className={`webpage-frame ${state.splitView ? 'is-split' : ''} ${active && !isNewTab(active.url) && !active.error ? 'has-page' : ''}`}>
        {state.splitView && <div className="split-header" aria-label="Split view tabs">{state.splitView.ids.map(id => {
          const tab=state.tabs.find(t => t.id===id)!;
          return <div className={`split-pane-title ${id===state.activeTabId ? 'active' : ''}`} key={id}><button aria-label={`Focus split pane ${tab.title}`} onClick={() => send({ type:'tab.select', id })}><Favicon url={tab.favicon} title={tab.title} /><span>{tab.title}</span></button><button className="icon-button" aria-label={`Keep only ${tab.title}`} title="Return to one tab" onClick={() => { send({ type:'tab.select', id }); send({ type:'split.close' }); }}><Columns2 size={15} /></button></div>;
        })}</div>}
        {active?.error ? <div className="page-error"><span className="error-flower">✳</span><h1>Couldn’t load this page.</h1><p>We couldn’t open {displayURL(active.url)}.</p><small>{active.error}</small><button onClick={() => send({ type: 'reload' })}><RotateCw size={15} />Try again</button></div> : (!active || isNewTab(active.url)) && <NewTabPage key={active?.id ?? 'home'} state={state} send={send} />}
      </div>
    </main>
    {error && <div className="toast" role="alert">{error}<button aria-label="Dismiss error" onClick={() => setError('')}><X size={14} /></button></div>}
  </div>;
}

function BrowserOverlays({ state, send }: { state: BrowserState; send: (action: Action) => void }) {
  return <>
    {state.overlay === 'palette' && <CommandPalette key={state.paletteMode} state={state} send={send} />}
    {state.overlay === 'settings' && <Settings state={state} send={send} />}
    {state.overlay === 'switcher' && state.tabSwitcher && <div className="overlay switcher-overlay"><section className="tab-switcher" role="dialog" aria-label="Recent tabs"><p>Recent tabs</p>{state.tabSwitcher.ids.map((id, index) => {
      const tab = state.tabs.find(t => t.id === id);
      return tab && <button key={id} className={`suggestion ${index === state.tabSwitcher!.index ? 'is-selected' : ''}`} aria-current={index === state.tabSwitcher!.index ? 'true' : undefined} onClick={() => send({ type: 'tab.select', id })}><Favicon url={tab.favicon} title={tab.title} /><span className="suggestion-text"><span>{tab.title}</span><small>{displayURL(tab.url)}</small></span></button>;
    })}<small>Release Control to switch</small></section></div>}
  </>;
}
