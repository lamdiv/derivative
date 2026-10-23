import { useEffect, useMemo, useRef, useState } from 'react';
import { ArrowUpRight, CornerDownLeft, Search, Command, ArrowUp, ArrowDown, History, Layers2, X } from 'lucide-react';
import type { Action, BrowserState } from '../../shared/types';
import { suggestions, type Suggestion } from '../../shared/suggestions';
import { isNewTab } from '../../shared/pages';
import { Favicon } from './Favicon';
import { useDialogKeyboard } from '../hooks/useDialogKeyboard';

export function CommandPalette({ state, send }: { state: BrowserState; send: (action: Action) => void }) {
  const active = state.tabs.find(t => t.id === state.activeTabId);
  const [query, setQuery] = useState(state.paletteMode === 'navigate' ? active && !isNewTab(active.url) ? active.url : '' : '');
  const [selected, setSelected] = useState(0);
  const input = useRef<HTMLInputElement>(null);
  const resultList = useRef<HTMLDivElement>(null);
  const panel = useRef<HTMLElement>(null);
  useDialogKeyboard(panel);
  const results = useMemo(() => suggestions(query, state), [query, state.activeSpaceId, state.activeTabId, state.tabs, state.history, state.preferences.searchEngine]);
  useEffect(() => { input.current?.focus(); if (state.paletteMode === 'navigate') input.current?.select(); }, []);
  const index = Math.min(selected, Math.max(0, results.length - 1));
  useEffect(() => { resultList.current?.children[index]?.scrollIntoView({ block:'nearest' }); }, [index, results]);
  const execute = (suggestion?: Suggestion) => {
    if (suggestion?.kind === 'tab') send({ type: 'tab.select', id: suggestion.id });
    else if (suggestion?.kind === 'command' && suggestion.command) { send({ type: 'overlay.close' }); send({ type: suggestion.command }); }
    else if (suggestion?.url || query.trim()) send({ type: 'navigate', input: suggestion?.url ?? query, newTab: state.paletteMode === 'new' });
  };
  return <div className="overlay palette-overlay" onMouseDown={e => { if (e.target === e.currentTarget) send({ type: 'overlay.close' }); }}>
    <section ref={panel} className="command-palette" role="dialog" aria-modal="true" aria-label="Search or enter URL">
      <div className="palette-input-row"><Search size={23} strokeWidth={1.6} /><input ref={input} aria-label="Search or enter URL" role="combobox" aria-expanded={results.length > 0} aria-controls="palette-results" aria-activedescendant={results[index] ? `result-${index}` : undefined} placeholder="Search or enter URL..." value={query} onChange={e => { setQuery(e.target.value); setSelected(0); }} onKeyDown={e => {
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); setSelected(n => results.length ? (n + (e.key === 'ArrowDown' ? 1 : -1) + results.length) % results.length : 0); }
        if (e.key === 'Enter') { e.preventDefault(); execute(results[index]); }
        if (e.key === 'Escape') send({ type: 'overlay.close' });
      }} /><button className="escape-key" onClick={() => send({ type: 'overlay.close' })} aria-label="Close command palette">esc</button></div>
      {results.length > 0 && <div className="palette-body">
        <div ref={resultList} role="listbox" id="palette-results">{results.map((s, i) => <div tabIndex={0} key={s.id} id={`result-${i}`} role="option" aria-selected={index === i} className={`suggestion ${index === i ? 'is-selected' : ''}`} onMouseMove={() => setSelected(i)} onClick={() => execute(s)} onKeyDown={e => { if (e.key === 'Enter' && e.target === e.currentTarget) execute(s); }}>
          <span className="suggestion-icon">{s.kind === 'search' ? <Search size={18} /> : s.kind === 'command' ? <Command size={18} /> : <Favicon url={s.favicon} title={s.title} />}</span>
          <span className="suggestion-text"><span>{s.title}</span><small>{s.detail}</small></span><span className="suggestion-kind">{s.kind === 'tab' ? <Layers2 size={14} /> : s.kind === 'history' ? <History size={14} /> : <ArrowUpRight size={14} />}</span>{index === i && <kbd className="enter-hint"><CornerDownLeft size={13} /></kbd>}
          {s.kind === 'tab' && <button className="suggestion-close" aria-label={`Close tab ${s.title}`} title="Close tab" onMouseDown={e => e.preventDefault()} onClick={e => { e.stopPropagation(); send({ type:'tab.close', id:s.id }); }}><X size={14} /></button>}
        </div>)}</div>
      </div>}
      <footer className="palette-footer"><span><kbd><ArrowUp size={11} /></kbd><kbd><ArrowDown size={11} /></kbd> Select</span><span><kbd>↵</kbd> Open</span></footer>
    </section>
  </div>;
}
