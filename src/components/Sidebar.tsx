import { ArrowLeft, ArrowRight, Plus, PanelLeftClose, PanelLeftOpen, RotateCw, Search, Settings2, X, Pin, Copy, ChevronDown, ChevronLeft, ChevronRight, Folder, FolderPlus, MoreHorizontal, Pencil, Trash2, Columns2 } from 'lucide-react';
import { useEffect, useRef, useState, type DragEvent } from 'react';
import type { Action, BrowserState, Tab, TabFolder } from '../../shared/types';
import { useSidebarInteraction } from '../hooks/useSidebarInteraction';
import { useSpaceSwipe } from '../hooks/useSpaceSwipe';
import { Favorites } from './Favorites';
import { Favicon } from './Favicon';
import { SpaceIcon } from './SpaceIcon';
import { effectiveSidebarMode, sidebarSizes } from '../../shared/layout';
import { isNewTab } from '../../shared/pages';
import { displayURL } from '../../shared/navigation';

type DragKind = 'tab' | 'folder' | 'space';
const mime = (kind: DragKind) => `application/x-derivative-${kind}`;

export function Sidebar({ state, send }: { state: BrowserState; send: (action: Action) => void }) {
  const sidebarRef = useRef<HTMLElement>(null);
  const hidden = effectiveSidebarMode(state) !== 'fixed' && !state.sidebarRevealed;
  const swipe = useSpaceSwipe(sidebarRef, state, send, !hidden);
  const sizeRef = useRef<HTMLDivElement>(null);
  const [menu, setMenu] = useState<string | null>(null);
  const [sizesOpen, setSizesOpen] = useState(false);
  const [spacesOpen, setSpacesOpen] = useState(false);
  const [editing, setEditing] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [dragging, setDragging] = useState<DragKind | null>(null);
  const draggedTab = useRef<string | null>(null);
  const [dropTarget, setDropTarget] = useState<string | null>(null);
  useSidebarInteraction(sizesOpen, () => setSizesOpen(false), sizeRef, send);
  useSidebarInteraction(spacesOpen || menu !== null || editing !== null || dragging !== null, () => { setSpacesOpen(false); setMenu(null); setEditing(null); setDragging(null); }, sidebarRef, send);
  const space = state.spaces.find(s => s.id === state.activeSpaceId)!;
  const splitTabs = state.splitView?.ids.map(id=>state.tabs.find(t=>t.id===id)).filter((tab): tab is Tab=>!!tab && tab.spaceId===space.id) ?? [];
  const splitIds = new Set(splitTabs.map(t=>t.id));
  const tabs = state.tabs.filter(t => t.spaceId === space.id && !splitIds.has(t.id) && !state.favorites.some(f => f.id === t.favoriteId));
  const folders = (state.folders ?? []).filter(f => f.spaceId === space.id);
  const active = state.tabs.find(t => t.id === state.activeTabId);
  useEffect(() => { if (hidden) { setMenu(null); setSpacesOpen(false); setSizesOpen(false); } }, [hidden]);
  useEffect(() => { setEditing(null); setMenu(null); }, [space.id]);

  function startDrag(e: DragEvent, kind: DragKind, id: string) {
    e.stopPropagation(); e.dataTransfer.effectAllowed = 'move';
    draggedTab.current = kind === 'tab' ? id : null;
    e.dataTransfer.setData(mime(kind), id); setDragging(kind); setMenu(null);
  }
  function endDrag() { draggedTab.current = null; setDragging(null); setDropTarget(null); }
  function dropZone(target: string, kinds: DragKind[], drop: (kind: DragKind, id: string) => void) {
    return {
      onDragOver(e: DragEvent) {
        if (!kinds.some(kind => e.dataTransfer.types.includes(mime(kind)))) return;
        e.preventDefault(); e.stopPropagation(); e.dataTransfer.dropEffect = 'move'; setDropTarget(target);
      },
      onDragLeave(e: DragEvent) { if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setDropTarget(null); },
      onDrop(e: DragEvent) {
        const kind = kinds.find(kind => e.dataTransfer.types.includes(mime(kind)));
        if (!kind) return;
        e.preventDefault(); e.stopPropagation();
        const id = e.dataTransfer.getData(mime(kind)); endDrag(); if (id) drop(kind, id);
      },
    };
  }
  function place(id: string, pinned: boolean, folderId?: string, beforeId?: string, spaceId = space.id) {
    send({ type: 'tab.place', id, spaceId, pinned, folderId, beforeId });
  }
  function editFolder(folder?: TabFolder) { setName(folder?.name ?? ''); setEditing(folder?.id ?? 'new'); setMenu(null); }
  function folderInput(id: string) {
    return <form className="folder-editor" onSubmit={e => {
      e.preventDefault(); if (!name.trim()) return;
      send(id === 'new' ? { type: 'folder.create', spaceId: space.id, name: name.trim() } : { type: 'folder.rename', id, name: name.trim() }); setEditing(null);
    }}><Folder size={15} /><input autoFocus aria-label={id === 'new' ? 'Folder name' : 'Rename folder'} placeholder="Folder name" maxLength={40} value={name} onChange={e => setName(e.target.value)} onKeyDown={e => { if (e.key === 'Escape') { e.stopPropagation(); setEditing(null); } }} /><button className="icon-button" type="submit" aria-label="Save folder" disabled={!name.trim()}><Plus size={14} /></button><button className="icon-button" type="button" aria-label="Cancel folder editing" onClick={() => setEditing(null)}><X size={13} /></button></form>;
  }
  function tabDropIntent(event: DragEvent, target: Tab, id: string | null) {
    const source = state.tabs.find(t => t.id === id);
    const rect = event.currentTarget.getBoundingClientRect();
    const y = (event.clientY - rect.top) / rect.height;
    if (source && source.id !== target.id && source.spaceId === target.spaceId && !isNewTab(source.url) && !isNewTab(target.url) && !source.error && !target.error && y >= .25 && y <= .75) return 'split';
    return y > .75 ? 'after' : 'before';
  }
  function tabDropZone(target: Tab) {
    return {
      onDragOver(event: DragEvent) {
        if (!event.dataTransfer.types.includes(mime('tab'))) return;
        event.preventDefault(); event.stopPropagation(); event.dataTransfer.dropEffect = 'move';
        if (draggedTab.current === target.id) { setDropTarget(null); return; }
        const intent = tabDropIntent(event, target, draggedTab.current);
        setDropTarget(`${intent}:${target.id}`);
      },
      onDragLeave(event: DragEvent) { if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setDropTarget(null); },
      onDrop(event: DragEvent) {
        if (!event.dataTransfer.types.includes(mime('tab'))) return;
        event.preventDefault(); event.stopPropagation();
        const id = event.dataTransfer.getData(mime('tab'));
        const intent = tabDropIntent(event, target, id);
        endDrag();
        if (!id || id === target.id) return;
        if (intent === 'split') { send({ type:'split.open', id, withId:target.id }); return; }
        const group = tabs.filter(t => t.pinned === target.pinned && t.folderId === target.folderId);
        const beforeId = intent === 'before' ? target.id : group[group.findIndex(t => t.id === target.id) + 1]?.id;
        place(id, target.pinned, target.folderId, beforeId);
      },
    };
  }
  function tabRow(tab: Tab) {
    return <div key={tab.id} data-tab-id={tab.id} className={`tab-wrap ${tab.id === active?.id ? 'selected' : ''} ${dropTarget === `before:${tab.id}` ? 'drop-before' : ''} ${dropTarget === `after:${tab.id}` ? 'drop-after' : ''} ${dropTarget === `split:${tab.id}` ? 'tab-split-target' : ''}`} draggable onDragStart={e => startDrag(e, 'tab', tab.id)} onDragEnd={endDrag} {...tabDropZone(tab)}>
      <button className="tab" title={isNewTab(tab.url) ? 'New tab' : `${tab.title}\n${tab.url}`} onClick={() => send({ type: 'tab.select', id: tab.id })} onContextMenu={e => { e.preventDefault(); setMenu(menu === tab.id ? null : tab.id); }}>
        {isNewTab(tab.url) ? <span className="favicon"><Search size={16} /></span> : <Favicon url={tab.favicon} loading={tab.loading} title={tab.title} />}<span className="tab-title">{tab.title}</span>{tab.status === 'discarded' && <span className="sleep-dot" title="Loads when selected" />}
      </button>
      <button className="tab-close" aria-label={`Close ${tab.title}`} onClick={() => send({ type: 'tab.close', id: tab.id })}><X size={13} /></button>
      {dropTarget === `split:${tab.id}` && <div className="tab-split-preview" aria-hidden="true"><span className="split-preview-pane"><Favicon url={tab.favicon} title={tab.title} /></span><span className="split-preview-pane"><Favicon url={state.tabs.find(t=>t.id===draggedTab.current)?.favicon} title="Dragged tab" /></span><span>Drop to split</span></div>}
      {menu === tab.id && <div className="tab-menu" role="menu" onMouseLeave={() => setMenu(null)}>
        <button role="menuitem" onClick={() => { send({ type: 'tab.pin', id: tab.id }); setMenu(null); }}><Pin size={14} />{tab.pinned ? 'Unpin tab' : 'Pin tab'}</button>
        <button role="menuitem" onClick={() => { send({ type: 'tab.duplicate', id: tab.id }); setMenu(null); }}><Copy size={14} />Duplicate</button>
        {!isNewTab(tab.url) && !tab.error && (tab.id === active?.id ? tabs.filter(t => t.id !== tab.id && !isNewTab(t.url) && !t.error) : active && !isNewTab(active.url) && !active.error ? [tab] : []).map(other => <button key={`split-${other.id}`} role="menuitem" onClick={() => { send({ type:'split.open', id:other.id }); setMenu(null); }}><Columns2 size={14} /><span>Split with {other.id === tab.id ? 'current tab' : other.title}</span></button>)}
        {state.splitView?.ids.includes(tab.id) && <button role="menuitem" onClick={() => { send({ type:'split.close' }); setMenu(null); }}><Columns2 size={14} />Exit split view</button>}
        {folders.filter(f => f.id !== tab.folderId).map(f => <button key={f.id} role="menuitem" onClick={() => { place(tab.id, true, f.id); setMenu(null); }}><Folder size={14} />Move to {f.name}</button>)}
        {tab.folderId && <button role="menuitem" onClick={() => { place(tab.id, true); setMenu(null); }}><Folder size={14} />Remove from folder</button>}
        {state.spaces.filter(s => s.id !== space.id).map(s => <button key={s.id} role="menuitem" onClick={() => { send({ type: 'tab.move', id: tab.id, spaceId: s.id }); setMenu(null); }}><SpaceIcon icon={s.icon} />Move to {s.name}</button>)}
        <button role="menuitem" onClick={() => { send({ type: 'tab.close', id: tab.id }); setMenu(null); }}><X size={14} />Close tab</button>
      </div>}
    </div>;
  }
  function folderRow(folder: TabFolder) {
    const children = tabs.filter(t => t.folderId === folder.id);
    return <div key={folder.id} data-folder-id={folder.id} className={`tab-folder ${dropTarget === folder.id ? 'drop-target' : ''}`} {...dropZone(folder.id, ['tab', 'folder'], (kind, id) => kind === 'tab' ? place(id, true, folder.id) : send({ type: 'folder.reorder', id, beforeId: folder.id }))}>
      {editing === folder.id ? folderInput(folder.id) : <div className="folder-row" draggable onDragStart={e => startDrag(e, 'folder', folder.id)} onDragEnd={endDrag}>
        <button className="folder-toggle" aria-label={`${folder.collapsed ? 'Expand' : 'Collapse'} folder ${folder.name}`} aria-expanded={!folder.collapsed} onClick={() => send({ type: 'folder.toggle', id: folder.id })} onDoubleClick={() => editFolder(folder)}>{folder.collapsed ? <ChevronRight size={12} /> : <ChevronDown size={12} />}<Folder size={16} /><span>{folder.name}</span></button>
        <button className="folder-more" aria-label={`Options for folder ${folder.name}`} onClick={() => setMenu(menu === folder.id ? null : folder.id)}><MoreHorizontal size={15} /></button>
        {menu === folder.id && <div className="tab-menu folder-menu" role="menu" onMouseLeave={() => setMenu(null)}><button role="menuitem" onClick={() => editFolder(folder)}><Pencil size={14} />Rename folder</button><button role="menuitem" onClick={() => { send({ type: 'folder.delete', id: folder.id }); setMenu(null); }}><Trash2 size={14} />Remove folder, keep tabs</button></div>}
      </div>}
      {!folder.collapsed && <div className="folder-children">{children.map(tabRow)}{!children.length && !splitTabs.some(t=>t.folderId===folder.id) && <div className="folder-empty">Drag tabs here</div>}</div>}
    </div>;
  }
  if (hidden) return null;
  return <aside ref={sidebarRef} className={`sidebar ${state.windowExpanded ? 'is-expanded' : ''} ${dragging ? `dragging-${dragging}` : ''}`} aria-label="Browser sidebar">
    <div className="window-drag" />
    <div className="sidebar-navigation"><button className="icon-button sidebar-toggle" aria-label={effectiveSidebarMode(state) === 'fixed' ? 'Hide sidebar' : 'Keep sidebar open'} aria-pressed={effectiveSidebarMode(state) === 'fixed'} title={effectiveSidebarMode(state) === 'fixed' ? 'Hide sidebar · ⌘S' : 'Keep sidebar open · ⌘S'} onClick={() => send({ type: 'sidebar.toggle' })}>{effectiveSidebarMode(state) === 'fixed' ? <PanelLeftClose size={18} /> : <PanelLeftOpen size={18} />}</button><div className="nav-pair"><button className="icon-button" aria-label="Go back" disabled={!active?.canGoBack} onClick={() => send({ type: 'back' })}><ArrowLeft size={17} /></button><button className="icon-button" aria-label="Go forward" disabled={!active?.canGoForward} onClick={() => send({ type: 'forward' })}><ArrowRight size={17} /></button><button className="icon-button" aria-label={active?.loading ? 'Stop loading' : 'Reload page'} disabled={!active} onClick={() => send({ type: active?.loading ? 'stop' : 'reload' })}>{active?.loading ? <X size={17} /> : <RotateCw size={17} />}</button></div></div>
    {active && <button className="sidebar-search" onClick={() => send({ type: 'palette', mode: active ? 'navigate' : 'new' })} aria-label="Search or enter URL"><Search size={17} /><span>{active && !isNewTab(active.url) ? displayURL(active.url) : 'Search or enter URL'}</span><kbd>⌘ L</kbd></button>}
    <Favorites state={state} send={send} />
    <div className="space-viewport"><div className={`space-pages ${swipe.following ? 'is-following' : ''}`} data-space-page={space.id} style={{ transform:`translateX(${swipe.x}px)`, opacity:1-Math.abs(swipe.x)/180 }}>
    <div className="space-heading"><button className="space-title" onClick={() => setSpacesOpen(!spacesOpen)} title={`Current Space: ${space.name}`} aria-expanded={spacesOpen}><SpaceIcon icon={space.icon} /><span>{space.name}</span><ChevronDown size={13} /></button><button className="icon-button create-folder" aria-label="New folder" title="New folder" onClick={() => editFolder()}><FolderPlus size={15} /></button>
      {spacesOpen && <div className="space-popover">{state.spaces.map(s => <button key={s.id} onClick={() => { send({ type: 'space.select', id: s.id }); setSpacesOpen(false); }}><span className={`space-mini color-${s.color}`}><SpaceIcon icon={s.icon} /></span>{s.name}{s.id === space.id && <span className="current-dot" />}</button>)}<button onClick={() => { send({ type: 'settings' }); setSpacesOpen(false); }}><Plus size={16} />Manage Spaces</button></div>}
    </div>
    <div className="tabs-scroll">
      {splitTabs.length === 2 && <div className="split-tab-group" role="group" aria-label="Split view tabs" onContextMenu={event=>{event.preventDefault();setMenu('split-pair');}}>
        {splitTabs.map((tab,index)=><div key={tab.id} className={`split-tab-segment ${tab.id===active?.id ? 'active' : ''}`} data-split-tab-id={tab.id} draggable onDragStart={event=>startDrag(event,'tab',tab.id)} onDragEnd={endDrag}>
          <button className="split-tab-select" aria-label={`Focus split tab ${index+1}: ${tab.title}`} aria-pressed={tab.id===active?.id} title={`Pane ${index+1} · ${tab.title}`} onClick={()=>send({type:'tab.select',id:tab.id})}><span className="split-tab-number">{index+1}</span><Favicon url={tab.favicon} title={tab.title}/><span className="split-tab-name">{tab.title}</span></button>
          <button className="split-tab-close" aria-label={`Close split tab ${index+1}: ${tab.title}`} title="Close pane" onClick={()=>send({type:'tab.close',id:tab.id})}><X size={12}/></button>
        </div>)}
        {menu==='split-pair' && <div className="tab-menu" role="menu" aria-label="Split view options"><button role="menuitem" onClick={()=>{send({type:'split.close'});setMenu(null);}}><Columns2 size={14}/>Separate tabs</button>{splitTabs.map((tab,index)=><button key={tab.id} role="menuitem" onClick={()=>{send({type:'tab.close',id:tab.id});setMenu(null);}}><X size={14}/>Close pane {index+1}</button>)}</div>}
      </div>}
      {editing === 'new' && folderInput('new')}
      <section className={`tab-section pinned-section ${dropTarget === 'pinned' ? 'drop-target' : ''}`} aria-label="Pinned tabs" {...dropZone('pinned', ['tab'], (_kind, id) => place(id, true))}><div className="section-label"><Pin size={11} />{dragging === 'tab' && !tabs.some(t=>t.pinned) && !folders.length ? `Drop to pin in ${space.name}` : 'Pinned'}</div>{tabs.filter(t => t.pinned && !t.folderId).map(tabRow)}{folders.map(folderRow)}</section>
      <section className={`tab-section regular-section ${dropTarget === 'regular' ? 'drop-target' : ''}`} aria-label="Open tabs" {...dropZone('regular', ['tab'], (_kind, id) => place(id, false))}>{tabs.filter(t => !t.pinned).map(tabRow)}{active && <button className="new-tab" title="New tab · ⌘T" onClick={() => send({ type: 'tab.new' })}><Plus size={17} /><span>New tab</span><kbd>⌘ T</kbd></button>}</section>
      {dragging === 'tab' && active && !isNewTab(active.url) && <div className={`split-drop-zone ${dropTarget === 'split' ? 'drop-target' : ''}`} {...dropZone('split', ['tab'], (_kind, id) => send({ type:'split.open', id }))}><Columns2 size={16} /><span>Drop another tab here to split</span></div>}
    </div>
    </div>
    </div>
    <div className={`space-edge-feedback ${swipe.edge ? 'is-visible' : ''}`} role="status">{swipe.edge === 'first' ? <><ChevronLeft size={12} />First Space</> : swipe.edge === 'last' ? <>Last Space<ChevronRight size={12} /></> : null}</div>
    <div className="sidebar-bottom"><div ref={sizeRef} className="sidebar-size-control"><button className="icon-button" aria-label="Sidebar size" title="Sidebar size" aria-haspopup="menu" aria-expanded={sizesOpen} onClick={() => setSizesOpen(open => !open)}><MoreHorizontal size={17} /></button>{sizesOpen && <div className="sidebar-size-menu" role="menu" aria-label="Sidebar size"><p>Sidebar width</p>{sidebarSizes.map(size => <button key={size.id} role="menuitemradio" aria-checked={state.preferences.sidebarSize === size.id} onClick={() => { send({ type: 'preferences', preferences: { sidebarSize: size.id } }); setSizesOpen(false); }}><span>{size.label}</span><small>{size.width}</small></button>)}</div>}</div><div className="space-switcher" aria-label="Spaces">{state.spaces.map(s => <button key={s.id} data-space-id={s.id} className={`space-button ${s.id === space.id ? 'active' : ''} ${dropTarget === `space:${s.id}` ? 'drop-target' : ''}`} title={dragging === 'tab' ? `Drop to pin in ${s.name}` : s.name} aria-label={`Switch to ${s.name} Space`} aria-pressed={s.id === space.id} draggable onDragStart={e => startDrag(e, 'space', s.id)} onDragEnd={endDrag} {...dropZone(`space:${s.id}`, ['tab', 'space'], (kind, id) => kind === 'tab' ? place(id, true, undefined, undefined, s.id) : send({ type: 'space.reorder', id, beforeId: s.id }))} onClick={() => send({ type: 'space.select', id: s.id })}><SpaceIcon icon={s.icon} /></button>)}</div><button className="icon-button settings-button" title="Settings · ⌘," aria-label="Settings" onClick={() => send({ type: 'settings' })}><Settings2 size={17} /></button></div>
  </aside>;
}
