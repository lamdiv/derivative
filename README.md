<p align="center">
  <img src="assets/icon.svg" width="80" height="80" alt="Derivative logo" />
</p>

<h1 align="center">Derivative</h1>
<p align="center">A little space for a curious internet.<br />A native macOS browser, powered by Chromium.</p>
<p align="center"><strong>Because Arc had a limit.</strong><br />By A Browser Guy.</p>

Derivative (d) is an independent macOS browser inspired by the browsing habits that made Arc feel like home: Spaces, a floating sidebar, favorite places, and a search panel a shortcut away. Soft colors and familiar controls keep it simple.

**Early development · macOS · Apple Silicon**

**The current app uses SwiftUI and AppKit for its interface, and Chromium through the Chromium Embedded Framework (CEF) for webpages.** Electron was used for the original version; it is no longer the runtime for the native app. Its earlier implementation is retained separately in the repository.

See the [native build guide](native/README.md) for setup, storage, and verification.

## A place for every part of your day

- **Spaces with separate sign-ins.** Each Space has its own persistent cookies and website storage. Swipe across the sidebar or use the bottom icons to switch.
- **A sidebar that fits.** Keep it fixed, reveal it on hover, or hide it. Choose from three widths and pastel themes, with light, dark, and system appearances. Native blur, soft highlights, and a subtle glass rim add depth without heavy borders.
- **Search without the clutter.** Press **⌘T** to search or enter an address. A tab opens only when you confirm. Open-tab suggestions stay within your current Space.
- **Your favorites, up front.** Arrange up to twelve favorites in balanced rows, with pairs filling half a row each. Drag to reorder; right-click to edit or remove. An open favorite stays highlighted in the grid.
- **Tabs with a little organization.** Pin tabs, group them in folders, and drag them between Spaces. Tabs and organization restore when you return.
- **Two pages, side by side.** Drag a tab onto the center of another to join them in split view. Both pages remain live, with a joined sidebar row for switching between them.

When maximized or fullscreen, the webpage fills the window. The sidebar floats over it when revealed, keeping the page's layout and input state intact. In a normal window, the sidebar returns to your chosen mode. Fullscreen traffic lights live in the native top bar and appear when you reveal it; normal-window controls align with the sidebar.

## Run locally

You'll need **an Apple Silicon Mac running macOS 14 or later**, **Python 3.12+**, and **Apple’s command-line tools** with Swift and C++ support. Install the tools with `xcode-select --install` if needed. Node.js is only needed for the development checks below.

```sh
git clone https://github.com/lamdiv/derivative.git
cd derivative
python3 native/scripts/build.py
open "native/build/Derivative.app"
```

The first build downloads a pinned Chromium framework and local build tools. Later builds reuse them. See the [build guide](native/README.md) for details.

## Make yourself at home

**Spaces.** Manage Spaces in Settings. Swipe horizontally over the fixed or floating sidebar to switch profiles. Short gestures spring back; swiping past either end gives a gentle bounce instead of wrapping around. Moving a tab to another Space reloads it using that Space's profile.

**Sidebar.** Choose Fixed, Floating on hover, or Hidden in Settings. Press **⌘S** to toggle it. In hover mode, move to the left edge to reveal it and use the top-left toggle to keep it open. Settings offers Compact, Comfortable, and Wide sizes.

**Folders and favorites.** Use the menu beside the Space name to create a folder. Drag tabs into Pinned or a folder, or onto a Space icon to move and pin them there. Use the controls above the favorites grid to add or edit favorites. Right-click menus offer the same everyday actions without dragging.

**Address bar.** The sidebar shows the current domain, with a copy-link button and a site-controls button. Copying briefly shows a checkmark. Site controls adjust page zoom or mute the current tab; click the domain to edit the full address.

**Search.** **⌘T** opens the floating search panel over a webpage. On an empty New Tab page, it focuses the existing field; typing opens the same floating panel used over webpages. **⌘L** edits the current address. Choose a tab result to switch to it, or use its close control to close it. Empty Spaces show history matches only after typing. Escape dismisses the panel without creating a tab.

**Split view.** Drop a tab onto the center of another tab, or use its context menu to split. The top and bottom edges still reorder tabs. Click either page to focus it, drag the divider to resize, or right-click the joined row to separate the tabs. Split arrangements are temporary, while the underlying tabs persist.

**Webpage menus.** Right-click links, images, or selected text to open, split, save, copy, search, or inspect. Editable fields keep their standard editing commands.

**Downloads.** The button at the bottom-left of the sidebar opens a floating downloads panel. Track progress, cancel a download, open a completed file, or reveal it in Finder.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘T | Search or open a new tab after confirmation |
| ⌘L | Edit the current address |
| ⌘S | Show / hide the sidebar |
| ⌘W | Close the active tab |
| ⌘⇧T | Reopen the last closed tab in this app session |
| ⌘D | Pin / unpin the active tab |
| ⌘R / ⌘⇧R | Reload / reload without cache |
| ⌘[ / ⌘] | Back / forward |
| ⌃Tab / ⌃⇧Tab | Cycle recent tabs; release Control to switch |
| ⌥⌘↑ / ⌥⌘↓ | Previous / next tab in sidebar order |
| ⌘⇧[ / ⌘⇧] | Previous / next tab in the Space |
| ⌘1–8 / ⌘9 | Select a numbered tab / the last tab |
| ⌥⌘← / ⌥⌘→ | Previous / next Space |
| ⌃1–9 | Select a Space |
| ⌘⇧C | Copy the current URL |
| ⌘, | Open Settings |
| ⌘M | Minimize the window |
| ⌃⌘F | Enter / exit fullscreen |
| ↑ / ↓, Return, Esc | Select, open, or dismiss search results |

The shortcut reference is also available in **Settings → Shortcuts**.

## Development

Native app code lives in `native/Sources/`; Chromium integration is in `Browser.mm`, with a narrow C bridge to Swift. Build dependencies are pinned in `native/cef.lock.json`.

For integration checks, install **Node.js 22.12+** and run `npm ci` to install the repository’s test dependencies.

| Command | Purpose |
| --- | --- |
| `python3 native/scripts/build.py` | Build and sign the native macOS app locally |
| `node native/scripts/verify.mjs` | Check Chromium rendering, input, and navigation |
| `node native/scripts/tabs-profiles.mjs` | Check tabs, isolated Space profiles, and restoration |
| `node native/scripts/sidebar-layout.mjs` | Check sidebar geometry and window controls |
| `node native/scripts/sidebar-animation.mjs` | Check sidebar animation, reversal, and new-tab search |
| `node native/scripts/context-menu.mjs` | Check webpage menus, image copying, downloads, and Inspect |
| `node native/scripts/features.mjs` | Check organization, split panes, downloads, settings, and swipes |

Run GUI tests sequentially; they create temporary profiles and local website fixtures. The [native guide](native/README.md) includes pure Swift checks and verification limits. The [architecture guide](docs/architecture.md) covers both implementations.

The local build uses ad-hoc signing. Distribution signing and notarization require your own Developer ID credentials.

<details>
<summary>Legacy Electron implementation</summary>

The original React/Electron app remains in `src/`, `electron/`, and `shared/`. Its npm commands build and run that earlier app, with separate profile storage. They do not launch the current native macOS app.

With Node.js 22.12+:

```sh
npm ci
npm run dev
```

- `npm run build`: build the legacy Electron app.
- `npm test`: run its TypeScript unit tests.
- `npm run build:icon`: regenerate the shared macOS icon assets.

</details>

## Performance

The native interface removes Electron from the running app, while CEF retains Chromium’s browser, renderer, and helper processes. Restored tabs load lazily, and loaded background pages retain their live state while their views are detached.

Memory use and responsiveness are still being evaluated. There is no current-build memory-saving claim; the [native guide](native/README.md#performance) explains the comparison tooling and its limits.

## Current limits

Derivative is an early browser built around one main window. Separate browser windows, private browsing, a mini-browser, region capture, extensions, a password manager, automatic updates, and automatic tab discarding are not yet implemented. Some sign-in providers and DRM media depend on the embedded Chromium distribution.

Session restoration saves tab URLs, titles, and organization. Unsaved forms and back/forward history survive ordinary tab switches, but do not survive restarting the app. Download history, split arrangements, and recently closed tabs last for the current app session. Website sign-ins persist within each Space.
