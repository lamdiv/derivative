import { useEffect, useRef, useState, type DragEvent } from 'react';
import { Check, Pencil, Plus, Trash2, Copy, ArrowUpRight } from 'lucide-react';
import type { Action, BrowserState, Favorite } from '../../shared/types';
import { MAX_FAVORITES } from '../../shared/favorites';
import { useSidebarInteraction } from '../hooks/useSidebarInteraction';
import { Favicon } from './Favicon';

export function Favorites({ state, send }: { state: BrowserState; send: (action: Action) => void }) {
  const [menu, setMenu] = useState<{ id:string; x:number; y:number } | null>(null);
  const [dragging, setDragging] = useState<string | null>(null);
  const [preview, setPreview] = useState<string[] | null>(null);
  const [committing, setCommitting] = useState(false);
  const [pendingOrder, setPendingOrder] = useState<string[] | null>(null);
  const grid = useRef<HTMLDivElement>(null);
  const drag = useRef<{ id:string; ids:string[]; boxes:DOMRect[]; scrollTop:number; order:string[] } | null>(null);
  const [managing, setManaging] = useState(false);
  const [editing, setEditing] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [url, setUrl] = useState('');
  const section = useRef<HTMLElement>(null);
  useSidebarInteraction(managing || !!menu || !!dragging, () => { setManaging(false); setEditing(null); setMenu(null); endDrag(); }, section, send);
  function edit(favorite?: Favorite) { setMenu(null); setEditing(favorite?.id ?? 'new'); setName(favorite?.name ?? ''); setUrl(favorite?.url ?? ''); setManaging(true); }
  useEffect(() => {
    if (!committing) return;
    const timer=setTimeout(()=>setCommitting(false),180);
    return ()=>clearTimeout(timer);
  },[committing]);
  useEffect(() => {
    if (!pendingOrder) return;
    if (pendingOrder.join() === state.favorites.map(f=>f.id).join()) { setPendingOrder(null); return; }
    const timer=setTimeout(()=>setPendingOrder(null),600);
    return ()=>clearTimeout(timer);
  },[pendingOrder,state.favorites]);
  const gridFavorites=pendingOrder ? [...state.favorites].sort((a,b)=>pendingOrder.indexOf(a.id)-pendingOrder.indexOf(b.id)) : state.favorites;
  function endDrag() { drag.current=null; setDragging(null); setPreview(null); }
  function startDrag(event: DragEvent, id: string) {
    event.stopPropagation(); setCommitting(false);
    const tiles=[...grid.current!.querySelectorAll<HTMLElement>('[data-favorite-id]')];
    const ids=tiles.map(tile=>tile.dataset.favoriteId!);
    drag.current={ id, ids, boxes:tiles.map(tile=>tile.getBoundingClientRect()), scrollTop:grid.current!.scrollTop, order:ids };
    event.dataTransfer.setData('application/x-derivative-favorite',id);
    event.dataTransfer.effectAllowed='move'; setDragging(id); setMenu(null);
  }
  function previewDrag(event: DragEvent) {
    const current=drag.current;
    if (!current || !event.dataTransfer.types.includes('application/x-derivative-favorite')) return;
    event.preventDefault(); event.stopPropagation(); event.dataTransfer.dropEffect='move';
    // Hit-test original cells, not the animated tiles, to avoid oscillating targets.
    let slot=0, nearest=Infinity;
    current.boxes.forEach((box,index)=>{
      const distance=(event.clientX-box.x-box.width/2)**2+(event.clientY+(grid.current!.scrollTop-current.scrollTop)-box.y-box.height/2)**2;
      if (distance<nearest) { nearest=distance; slot=index; }
    });
    if (!event.clientX && !event.clientY) {
      const target=(event.target as Element).closest<HTMLElement>('[data-favorite-id]');
      if (target) slot=current.ids.indexOf(target.dataset.favoriteId!);
    }
    const order=current.ids.filter(id=>id!==current.id);
    order.splice(Math.max(0,slot),0,current.id);
    if (order.join()!==current.order.join()) { current.order=order; setPreview(order); }
  }
  function drop(event: DragEvent) {
    if (!drag.current) return;
    previewDrag(event);
    const { id, order }=drag.current;
    setCommitting(true); setPendingOrder(order);
    send({ type:'favorite.reorder', id, beforeId:order[order.indexOf(id)+1] ?? null });
    endDrag();
  }
  function tileStyle(id: string) {
    const current=drag.current;
    if (!preview || !current) return undefined;
    const from=current.boxes[current.ids.indexOf(id)], to=current.boxes[preview.indexOf(id)];
    if (!from || !to) return undefined;
    return { transform:`translate(${to.x-from.x}px, ${to.y-from.y}px)` };
  }
  const activeFavoriteId = state.tabs.find(t => t.id === state.activeTabId)?.favoriteId;
  const contextFavorite = state.favorites.find(f => f.id === menu?.id);
  return <section ref={section} className="favorites-section" aria-label="Favorite websites">
    <div className="favorites-heading"><span>Favorites</span><div><button className="icon-button" aria-label="Add favorite" title="Add favorite" disabled={state.favorites.length >= MAX_FAVORITES} onClick={() => edit()}><Plus size={14} /></button><button className="icon-button" aria-label={managing ? 'Done editing favorites' : 'Edit favorites'} aria-expanded={managing} onClick={() => { setManaging(!managing); setEditing(null); }}>{managing ? <Check size={14} /> : <Pencil size={13} />}</button></div></div>
    {managing ? <div className="favorites-manager">
      {editing ? <form className="favorite-form" onSubmit={event => { event.preventDefault(); send({ type: 'favorite.save', id: editing === 'new' ? undefined : editing, name: name.trim(), url: url.trim() }); setEditing(null); }}>
        <input autoFocus aria-label="Favorite name" placeholder="Name" value={name} maxLength={40} required onChange={event => setName(event.target.value)} />
        <input aria-label="Favorite URL" type="url" placeholder="https://example.com" value={url} required onChange={event => setUrl(event.target.value)} />
        <div><button type="button" onClick={() => setEditing(null)}>Cancel</button><button type="submit" disabled={!name.trim() || !url.trim()}>Save favorite</button></div>
      </form> : state.favorites.map(favorite => <div className="favorite-edit-row" key={favorite.id}><button onClick={() => edit(favorite)} title={`Edit ${favorite.name}`}><Favicon url={new URL('/favicon.ico', favorite.url).href} title={favorite.name} /><span>{favorite.name}</span></button><button className="icon-button" aria-label={`Remove favorite ${favorite.name}`} onClick={() => send({ type: 'favorite.delete', id: favorite.id })}><Trash2 size={14} /></button></div>)}
      {!editing && <p>{state.favorites.length} of {MAX_FAVORITES} favorites</p>}
    </div> : <div ref={grid} className={`favorites ${dragging ? 'is-reordering' : ''} ${committing ? 'is-committing' : ''}`} onDragOver={previewDrag} onDrop={drop}>{gridFavorites.map(favorite => <button key={favorite.id} data-favorite-id={favorite.id} title={favorite.name} aria-label={`Open ${favorite.name}`} aria-pressed={activeFavoriteId === favorite.id} style={tileStyle(favorite.id)} className={`favorite ${activeFavoriteId === favorite.id ? 'favorite-active' : ''} ${dragging === favorite.id ? 'favorite-dragging' : ''}`} draggable onDragStart={event=>startDrag(event,favorite.id)} onDragEnd={endDrag} onClick={() => { if (!dragging) send({ type:'favorite.open', id:favorite.id }); }} onContextMenu={event => { event.preventDefault(); const tile=event.currentTarget.getBoundingClientRect(), parent=section.current!.getBoundingClientRect(); setMenu({ id:favorite.id, x:Math.max(0, Math.min(tile.x-parent.x, parent.width-196)), y:tile.bottom-parent.y+5 }); }}><Favicon url={new URL('/favicon.ico',favorite.url).href} title={favorite.name} /></button>)}</div>}

    {menu && contextFavorite && <div className="favorite-menu" role="menu" aria-label={`Options for favorite ${contextFavorite.name}`} style={{ left:menu.x, top:menu.y }}>
      <button role="menuitem" onClick={() => { send({ type:'favorite.open', id:contextFavorite.id }); setMenu(null); }}><ArrowUpRight size={14} />Open favorite</button>
      <button role="menuitem" onClick={() => { send({ type:'navigate', input:contextFavorite.url, newTab:true }); setMenu(null); }}><Plus size={14} />Open in new tab</button>
      <button role="menuitem" onClick={() => edit(contextFavorite)}><Pencil size={14} />Edit favorite</button>
      <button role="menuitem" onClick={() => { send({ type:'favorite.copy', id:contextFavorite.id }); setMenu(null); }}><Copy size={14} />Copy address</button>
      <div className="menu-separator" />
      <button role="menuitem" className="destructive" onClick={() => { send({ type:'favorite.delete', id:contextFavorite.id }); setMenu(null); }}><Trash2 size={14} />Remove favorite</button>
    </div>}
    {!state.favorites.length && !managing && <button className="favorites-empty" onClick={() => edit()}><Plus size={15} />Add your favorite places</button>}
  </section>;
}
