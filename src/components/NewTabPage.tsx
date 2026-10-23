import { BrandMark } from './BrandMark';
import { useEffect, useMemo, useRef, useState } from 'react';
import { ArrowUpRight, CornerDownLeft, Search, Command, Layers2, X } from 'lucide-react';
import type { Action, BrowserState } from '../../shared/types';
import { suggestions, type Suggestion } from '../../shared/suggestions';
import { Favicon } from './Favicon';

export function NewTabPage({ state, send }: { state: BrowserState; send: (action: Action) => void }) {
  const [query, setQuery] = useState('');
  const [selected, setSelected] = useState(0);
  const input = useRef<HTMLInputElement>(null);
  const resultList = useRef<HTMLDivElement>(null);
  const results = useMemo(() => suggestions(query, state), [query, state.activeSpaceId, state.activeTabId, state.tabs, state.history, state.preferences.searchEngine]);
  const index = Math.min(selected, Math.max(0, results.length - 1));
  useEffect(() => { resultList.current?.children[index]?.scrollIntoView({ block:'nearest' }); }, [index, results]);
  useEffect(() => {
    input.current?.focus();
    return window.browser?.onSearchFocus?.(() => { input.current?.focus(); input.current?.select(); });
  }, []);
  function execute(result?: Suggestion) {
    if (result?.kind === 'tab') send({ type: 'tab.select', id: result.id });
    else if (result?.kind === 'command' && result.command) send({ type: result.command });
    else if (result?.url || query.trim()) send({ type: 'navigate', input: result?.url ?? query });
  }
  return <div className="new-tab-page">
    <div className="new-tab-content">
      <BrandMark className="new-tab-mark" />
      <h1>New tab</h1>
      <section className="new-tab-search" aria-label="New tab search">
        <form className="new-tab-input" onSubmit={event => { event.preventDefault(); execute(results[index]); }}>
          <Search size={21} strokeWidth={1.7} />
          <input ref={input} role="combobox" aria-label="Search or enter URL" aria-autocomplete="list" aria-expanded={results.length > 0} aria-controls="new-tab-results" aria-activedescendant={results[index] ? `new-tab-result-${index}` : undefined} placeholder="Search or enter URL" value={query} autoComplete="off" spellCheck={false} onChange={event => { setQuery(event.target.value); setSelected(0); }} onKeyDown={event => {
            if (event.key === 'ArrowDown' || event.key === 'ArrowUp') { event.preventDefault(); setSelected(results.length ? (index + (event.key === 'ArrowDown' ? 1 : -1) + results.length) % results.length : 0); }
            if (event.key === 'Escape') { setQuery(''); setSelected(0); }
          }} />
          <button type="submit" aria-label="Open search or address" disabled={!query.trim() && !results.length}><CornerDownLeft size={16} /></button>
        </form>
        {results.length > 0 && <div ref={resultList} className="new-tab-results" role="listbox" id="new-tab-results">{results.map((result, i) => <div tabIndex={0} key={result.id} id={`new-tab-result-${i}`} role="option" aria-selected={i === index} className={`suggestion ${i === index ? 'is-selected' : ''}`} onMouseMove={() => setSelected(i)} onClick={() => execute(result)} onKeyDown={e => { if (e.key === 'Enter' && e.target === e.currentTarget) execute(result); }}>
          <span className="suggestion-icon">{result.kind === 'search' ? <Search size={18} /> : result.kind === 'command' ? <Command size={18} /> : <Favicon url={result.favicon} title={result.title} />}</span>
          <span className="suggestion-text"><span>{result.title}</span><small>{result.detail}</small></span>
          <span className="suggestion-kind">{result.kind === 'tab' ? <Layers2 size={14} /> : <ArrowUpRight size={14} />}</span>
          {result.kind === 'tab' && <button className="suggestion-close" aria-label={`Close tab ${result.title}`} title="Close tab" onMouseDown={e => e.preventDefault()} onClick={e => { e.stopPropagation(); send({ type:'tab.close', id:result.id }); }}><X size={14} /></button>}
        </div>)}</div>}
      </section>
      <p className="new-tab-hint"><kbd>↑ ↓</kbd> to choose <span>·</span> <kbd>↵</kbd> to open</p>
    </div>
  </div>;
}
