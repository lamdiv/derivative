# d′ — Derivative

A simple, pastel Chromium browser for macOS. **Because Arc had a limit.**

By A Browser Guy.

## Run

Requires Node.js 22.12+ (Node 24 recommended), npm, and macOS. Apple Silicon is the primary target.

```sh
npm install
npm run dev
```

The development command builds Electron and starts Vite and the native app together. React and CSS changes update live. Changes in `electron/` or `shared/` automatically rebuild and restart the native app so action validation stays in sync with the UI.

```sh
npm run build       # strict TypeScript, production UI, main process, preload
npm start           # launch the production build
npm test            # URL handling, IPC validation, suggestion ranking, persistence
npm run test:electron # actual macOS Electron integration checks; writes screenshots to test-results/
npm run package:mac # Apple Silicon DMG and ZIP in release/
```

Packaging requires Electron Builder's downloadable tools. Distribution requires your own Developer ID signing/notarization credentials; none are included. The original lavender `d′` icon is included; `npm run build:icon` regenerates the macOS icons from the editable SVG using Chromium, ImageIO, and iconutil.

## First usable version

Milestone 1 implements native `WebContentsView` tabs, a collapsible sidebar, local history, keyboard navigation, session restoration, and a persistent default website profile. Loaded tabs retain their native webpage view when switching. Restored background tabs load only when selected. Closing a tab explicitly closes its web contents.

The interface includes a soft lavender default, mint and peach Spaces, fixed/hover/hidden sidebar modes, system/light/dark appearances, favorites shortcuts, pinned tabs, tab reordering by drag and drop, and a floating command palette. Right-click a tab to pin, duplicate, close, or move it. Settings include themes, search engine, restoration, Space creation/renaming, data clearing, and a basic download list.

Favorites start as an editable 3×3 grid. Use the plus and pencil controls above the grid to add, rename, or remove websites. The grid keeps three equal columns and allows up to twelve favorites (four rows), with consistently sized icons. Favorites support right-click menus and drag reordering. Each Space has its own persistent website profile. Private browsing, automatic tab discarding, and durable download history remain follow-up work.

## Keyboard

| Shortcut | Action |
| --- | --- |
| ⌘T | Open search; create a tab only after confirmation |
| ⌘L | Edit current address in the palette |
| ↑ / ↓, Return, Esc | Select, open, dismiss palette |
| ⌘W | Close active tab |
| ⌘R | Reload |
| ⌘[ / ⌘] | Back / forward |
| ⌘⇧[ / ⌘⇧] | Previous / next tab in Space |
| ⌘1–8 / ⌘9 | Select numbered / last tab in Space |
| ⌘S | Show / hide sidebar |
| ⌃Tab / ⌃⇧Tab | Recent tabs (release Control to switch) |
| ⌥⌘↑ / ⌥⌘↓ | Previous / next tab in sidebar order |
| ⌥⌘← / ⌥⌘→ | Previous / next Space |
| ⌃1–9 | Select Space |
| ⌘⇧T | Reopen last closed tab (current app session) |
| ⌘D | Pin / unpin active tab |
| ⌘⇧C | Copy current URL |
| ⌘⇧R | Reload without cache |
| ⌘, | Settings |

Main-process input handling is attached to both the trusted UI and every website view. Native app menu accelerators handle the primary commands too. Ordinary website input is left alone.

## Architecture

- `electron/main.ts`: window, native macOS titlebar controls, menu, trusted IPC origin checks.
- `electron/tabs/manager.ts`: tab lifecycle, webpage navigation, view composition, permissions, download events.
- `electron/preload.ts`: three-method isolated bridge, exposed only to the local UI.
- `electron/storage/store.ts`: versioned metadata, validated restoration, debounced serialized atomic writes.
- `shared/`: typed state/actions, URL resolution, local suggestion ranking.
- `src/`: React controls and CSS/Tailwind styling. No website iframes or webviews.

Website views use `nodeIntegration: false`, `contextIsolation: true`, sandboxing, and web security, without a preload. IPC checks both the exact local UI URL and the sender's main frame identity; action payloads are validated separately. UI navigation and popups are blocked. HTTP(S) website popups open as tabs. Mail and telephone links require a native confirmation; other external schemes are blocked. Certificates are not bypassed. Supported website permissions ask through a native dialog; unsupported permissions are denied.

### Native layout

The main UI is a `BrowserWindow`; the active website is a native child. Background website views remain alive but detached. The sidebar offers Compact (252px), Comfortable (288px, default), and Wide (320px) widths, plus 16px of frame spacing in fixed mode. In normal windows, hidden and hover modes give the page an 8px inset on every side, including while the hover sidebar is open. Maximized and fullscreen pages fill the entire window with zero padding, no frame shadow, and square webpage corners. Native traffic lights follow sidebar visibility in normal windows. Expanded windows use a compact header without a reserved traffic-light row. In native fullscreen, traffic lights remain enabled for macOS to reveal when hovering at the top edge. The toggle lives inside the sidebar; Command-S and the View menu restore it when hidden. Maximizing or entering full screen temporarily hides it. Hover the left edge to reveal the floating sidebar, then use its top-left toggle to keep it open as an overlay. In maximized and full-screen windows, the sidebar floats over the edge-to-edge page and never reserves webpage width, even while pinned or resized. Back, forward, and reload sit together on the right of that row. Returning to a normal window restores its normal mode. The bottom-left sidebar menu and Settings both offer the three width choices. Electron’s native border-radius API rounds the webpage itself.

A preloaded transparent `WebContentsView` renders trusted floating UI above the live website. Modal panels cover the window; hover reveal covers only the sidebar width. Websites stay attached behind popups, preserving their viewport and form state. Short opacity/transform transitions finish before the floating native layer detaches, with stale detach timers canceled on reopening. This uses an additional trusted UI renderer. Both UI identities have exact-URL, main-frame IPC checks; website views receive no privileged preload. The popup scrim does not depend on CSS blur across native renderer surfaces.

### Storage

Browser metadata is stored at `app.getPath('userData')/browser-state.json`. Website cookies, local storage, IndexedDB, and cache use a separate persistent session per Space. Personal retains **`persist:personal`**; other Spaces use **`persist:space-<Space ID>`**. Swiping horizontally over the sidebar switches Space and its profile. Moving a tab to another Space reloads it in the destination profile. Closing tabs and quitting do not clear it. Metadata excludes passwords and session tokens, although browsing URLs/history are sensitive and remain local. User-initiated clearing asks for confirmation.

`DERIVATIVE_USER_DATA=/absolute/path` selects an isolated development/test directory. The integration suite uses a temporary directory and removes it afterwards.

### Limitations and remaining milestones

Electron does not supply every Chrome browser feature: identity providers may reject embedded browsers, some DRM/media codecs may be unavailable, and this release has no password manager, extension system, or automatic updater. Authentication compatibility must be tested per service. A stored-cookie test does not prove compatibility with all real sign-in flows.

Metadata restoration preserves tab URLs and titles; navigation stacks and unsaved website form state do not survive a process restart. They do survive ordinary tab switches. If metadata is malformed, the app returns to a clean local state; a backup/recovery UI is future work. Open download progress is available for the running session; quit handling for active downloads needs further hardening.

The current app targets one main window. Private mode, deeper permission management, conservative configurable discarding, a complete security audit, release signing, and updater integration belong to later milestones.

### Performance verification

Development console instrumentation records time to window readiness and main-process tab switching. These are diagnostic measurements, not comparative benchmarks or end-to-end paint timings. No claim of being faster than Arc or Chrome is made. Inactive restored tabs are lazy; there is no automatic discarding because reliable unsaved-state detection is not yet available.

UI state crosses IPC as changed sections. Each trusted renderer has its own snapshot; the detached floating UI catches up when opened. Unchanged history is not resent during tab switches, and private hover ownership does not broadcast state. Native view attachment and corner radii update only when needed.

Run `PERF_ASSERT=1 node tests/performance.mjs` after building for a local 500-tab/2,000-history stress fixture. It reports action round-trip median/p95, transmitted state counts, and idle broadcasts. These timings include test automation and are not frame or website-loading benchmarks. See [verification notes](docs/verification.md) for measured results and test limits.

The Electron test suite uses a local HTTP fixture to check native rendering, palette shortcuts, view reuse/form retention, live-page overlay stacking and input-layer cleanup, resized bounds, navigation, cookie and local storage persistence, session restoration, and closed view destruction. Screenshots support visual inspection; tests do not establish real-world login compatibility, idle CPU, or memory performance.

### Sidebar behavior and shortcuts

Choose **Settings → General → Sidebar**:

- **Fixed:** sidebar stays open beside the page.
- **Floating on hover:** sidebar is hidden until the pointer reaches the 8px left edge, then appears as an inset, rounded floating panel over the page without resizing it. Returning to the webpage dismisses it after 220ms. Native mouse events handle crossing from the trusted UI into webpage views; no pointer polling is used.
- **Hidden:** sidebar stays hidden until ⌘S or the top-left reveal button opens it.

⌘S toggles fixed mode and the last hidden/hover mode used during the app session (hover is the initial fallback). The selected mode persists across restarts. Hover reveal is transient. The former icon-rail preference migrates to hover mode.

**Settings → Shortcuts** lists supported defaults. Arc's documented [recent-tab and sidebar-order navigation](https://resources.arc.net/hc/en-us/articles/25619402657303-How-Do-You-Switch-Between-Tabs-Quickly-on-Arc-Desktop) informs the Control-Tab and Option-Command-arrow bindings. The five-tab recent switcher snapshots its order until Control is released. Reopening closed tabs restores URLs and pin/Space metadata, not the destroyed page's form state or back/forward stack. Arc-specific features such as Split View, Little Arc, and Boosts are not implemented.

### Folders and drag organization

Use the folder-plus button beside the current Space name to create a folder. Press Return to save its name. Folders belong to a Space's pinned section; expand/collapse them with the chevron and use their hover menu to rename or remove them. Removing a folder keeps its tabs pinned in that Space.

Drag a tab into **Pinned** to pin it, onto a folder to file it there, or back into the regular tab list to unpin it. Drag over another tab to insert before it. Dropping a tab onto a Space icon moves and pins it in that Space. If you move the active tab, Derivative follows it; background tab moves leave the current Space selected. Context menus provide alternatives to dragging.

Folder headers and Space icons can be dragged before another header/icon to reorder them. Folder membership, collapse state, pinning, and ordering are stored locally and restored with the session. These changes reuse loaded webpage views rather than reloading websites.

The Space switcher is centered relative to the full sidebar, with an equal empty column balancing the Settings button. Default Space symbols share the same SVG component, 18×18 icon dimensions, and 27×27 button dimensions (14px symbols in the bottom switcher); custom text/emoji symbols use the same fixed icon box.

## New tab search page

Command-T, File → New Tab, and the sidebar’s New Tab button open the floating search panel over your current webpage. If an empty Space or internal New Tab already shows search, Command-T focuses and selects that existing field instead. A tab is created only after confirming a URL/search; choosing an existing-tab suggestion switches to it. Escape or clicking outside cancels without adding a tab. Tab suggestions include close controls, including for the current tab; closing a result keeps search open. Command-L edits the current location. Existing internal blank tabs remain supported for session compatibility.

## Favorites, Space gestures, and split view

Right-click (or two-finger click) a favorite for Open, Open in new tab, Edit, Copy address, and Remove. Drag favorite tiles to reorder the three-column grid; order is saved. Opening a favorite highlights its grid tile and keeps its page out of the regular tab list. Removing the favorite keeps its page open as a normal tab. Swipe horizontally over either the fixed or floating sidebar to switch Spaces. Vertical scrolling stays within the sidebar, and trackpad momentum triggers one Space change per gesture. The tab area follows your swipe, springs back for short gestures, and slides the next Space into place. Diagonal continuation keeps horizontal intent, momentum cannot skip Spaces, and quick reverse swipes work immediately. Swiping beyond either end gives a gentle resistant bounce and First/Last Space hint instead of wrapping; reduced-motion settings are respected. Website cookies and storage are isolated by Space and retained across restarts.

Right-click another website tab and choose **Split with current tab**, or right-click the current tab and choose **Split with [tab name]**. Drag a tab onto the center of another tab to preview and join that pair in split view; the top and bottom edges still reorder tabs. You can also use the sidebar’s “Drop another tab here to split” target. Both pages remain live side by side. Click a pane or its title to focus its navigation controls; use the title-row button to keep only that pane. Closing a pane or selecting a tab outside the pair exits split view without closing the other tab. Split arrangements are temporary; the underlying tabs restore normally.
