<p align="center">
  <img src="assets/icon.svg" width="80" height="80" alt="Derivative logo" />
</p>

<h1 align="center">Derivative</h1>
<p align="center">A little space for a curious internet.<br />A pastel Chromium browser for macOS.</p>
<p align="center"><strong>Because Arc had a limit.</strong><br />By A Browser Guy.</p>

Derivative brings your tabs, favorite places, and separate browsing profiles into one cozy sidebar. Soft colors, a floating search panel, and familiar keyboard shortcuts keep the interface simple while real Chromium pages do the browsing.

**Early development · macOS · Apple Silicon**

Derivative’s macOS interface is built with SwiftUI and AppKit, with Chromium rendering real webpages. The [native build guide](native/README.md) covers setup, storage, and verification. The Electron implementation remains available in this repository.

## A place for every part of your day

- **Spaces with separate sign-ins.** Each Space has its own persistent cookies and website storage. Swipe across the sidebar or use the bottom icons to switch.
- **A sidebar that fits.** Keep it fixed, reveal it on hover, or hide it. Choose from three widths and pastel themes, with light, dark, and system appearances.
- **Search without the clutter.** Press **⌘T** to search or enter an address. A tab opens only when you confirm. Open-tab suggestions stay within your current Space.
- **Your favorites, up front.** Arrange up to twelve favorites in balanced rows, with pairs filling half a row each. Drag to reorder; right-click to edit or remove. An open favorite stays highlighted in the grid.
- **Tabs with a little organization.** Pin tabs, group them in folders, and drag them between Spaces. Tabs and organization restore when you return.
- **Two pages, side by side.** Drag a tab onto the center of another to join them in split view. Both pages remain live, with a joined sidebar row for switching between them.

When maximized or fullscreen, the webpage fills the window. The sidebar floats over it when revealed, keeping the page's layout and input state intact. In a normal window, the sidebar returns to your chosen mode.

## Run locally

You'll need **Apple Silicon macOS 14+**, **Python 3.12+**, and Apple's command-line tools.

```sh
git clone https://github.com/lamdiv/derivative.git
cd derivative
python3 native/scripts/build.py
open "native/build/Derivative.app"
```

The first build downloads a pinned Chromium framework and local build tools. Later builds reuse them. See the [build guide](native/README.md) for details.

The Electron implementation can still be run with Node.js 22.12+ and npm:

```sh
npm ci
npm run dev
```

## Make yourself at home

**Spaces.** Manage Spaces in Settings. Swipe horizontally over the fixed or floating sidebar to switch profiles. Short gestures spring back; swiping past either end gives a gentle bounce instead of wrapping around. Moving a tab to another Space reloads it using that Space's profile.

**Sidebar.** Choose Fixed, Floating on hover, or Hidden in Settings. Press **⌘S** to toggle it. In hover mode, move to the left edge to reveal it and use the top-left toggle to keep it open. Settings offers Compact, Comfortable, and Wide sizes.

**Folders and favorites.** Use the menu beside the Space name to create a folder. Drag tabs into Pinned or a folder, or onto a Space icon to move and pin them there. Use the controls above the favorites grid to add or edit favorites. Right-click menus offer the same everyday actions without dragging.

**Search.** **⌘T** opens the floating search panel over a webpage. If you're already on an empty New Tab page, it focuses the existing search field. **⌘L** edits the current address. Choose a tab result to switch to it, or use its close control to close it. Empty Spaces show history matches only after typing. Escape dismisses the panel without creating a tab.

**Split view.** Drop a tab onto the center of another tab, or use its context menu to split. The top and bottom edges still reorder tabs. Click either page to focus it, drag the divider to resize, or right-click the joined row to separate the tabs. Split arrangements are temporary, while the underlying tabs persist.

**Webpage menus.** Right-click links, images, or selected text to open, split, save, copy, search, or inspect. Editable fields keep their standard editing commands.

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
| ↑ / ↓, Return, Esc | Select, open, or dismiss search results |

The shortcut reference is also available in **Settings → Shortcuts**.

## Development

| Command | Purpose |
| --- | --- |
| `python3 native/scripts/build.py` | Build and sign the native macOS app locally |
| `node native/scripts/verify.mjs` | Check Chromium rendering, input, and navigation |
| `node native/scripts/tabs-profiles.mjs` | Check tabs, isolated Space profiles, and restoration |
| `node native/scripts/sidebar-layout.mjs` | Check sidebar geometry and window controls |
| `node native/scripts/features.mjs` | Check organization, split panes, downloads, settings, and swipes |
| `npm run dev` | Run the Electron implementation with live React UI updates |
| `npm run build` | Build the Electron implementation |
| `npm test` | Run shared TypeScript unit tests |
| `npm run build:icon` | Regenerate macOS icons |

Run GUI tests sequentially; they create temporary profiles and local website fixtures. Native integration checks require `npm ci` for the test dependencies. The [native guide](native/README.md) includes pure Swift checks and verification limits. The [architecture guide](docs/architecture.md) covers both implementations.

Distribution signing and notarization require your own Developer ID credentials.

## Current limits

Derivative is an early browser built around one main window. It does not yet include extensions, a password manager, private browsing, automatic updates, or automatic tab discarding. Some sign-in providers and DRM media depend on the embedded Chromium distribution.

Session restoration saves tab URLs, titles, and organization. Unsaved forms and back/forward history survive ordinary tab switches, but do not survive restarting the app. Download progress is available during the current session; durable download history and quit handling need more work.
