<p align="center">
  <img src="assets/icon.svg" width="88" height="88" alt="Derivative logo" />
</p>

<h1 align="center">Derivative</h1>
<p align="center">A little space for a curious internet.</p>
<p align="center"><strong>A native macOS browser, powered by Chromium.</strong><br />Inspired by the little things that made Arc feel like home.</p>
<p align="center">
  <a href="#get-started">Get started</a> ·
  <a href="native/README.md">Build guide</a> ·
  <a href="docs/shortcuts.md">Shortcuts</a> ·
  <a href="docs/architecture.md">Architecture</a>
</p>

---

Derivative (d) is a small, independent browser for macOS. Spaces for different parts of your day. Favorite places within reach. A floating sidebar that gets out of the way. Soft pastel themes and native glass that make it feel at home on your Mac.

**Early development · macOS 14+ · Apple Silicon**

## A little room for everything

| | |
| :--- | :--- |
| **Spaces** | Separate website sign-ins, colors, and favorites. Swipe to switch. |
| **Your favorite places** | Up to 12 favorites per Space. Drag to arrange or move between Spaces. |
| **A quieter sidebar** | Fixed, floating, or hidden. Three widths, with light and dark pastel themes. |
| **Search, one shortcut away** | Press **⌘T**, type, and confirm. A new tab opens when you're ready. |
| **Tabs that stay tidy** | Pin tabs, make folders, and pick up where you left off. |
| **Two pages together** | Drag one tab onto another for a live, resizable split view. |

The interface is built with **SwiftUI and AppKit**. Websites run in **Chromium through CEF**. Liquid Glass is available on macOS 26+, with a frosted fallback on earlier systems.

## Get started

You'll need **Python 3.12+** and **Apple's command-line tools** with Swift and C++ support. Install the tools with `xcode-select --install` if needed.

```sh
git clone https://github.com/lamdiv/derivative.git
cd derivative
python3 native/scripts/build.py
open "native/build/Derivative.app"
```

The first build downloads the pinned browser engine and build tools. Later builds reuse them. Node.js is needed only for development tests.

For setup details, profile storage, and custom engine builds, see the **[build guide](native/README.md)**.

## Make yourself at home

- **⌘T** — search or open a new tab.
- **⌘L** — edit the current address.
- **⌘S** — show or hide the sidebar.
- **⌘,** — choose your appearance, sidebar size, and Space colors.

Right-click favorites and tabs for their menus. The bottom-left sidebar button opens Downloads. Find every shortcut in **[the shortcut reference](docs/shortcuts.md)**.

## Still taking shape

Derivative is an early project built around one main window. Extensions, password management, sync, automatic updates, and private browsing are not implemented yet.

The default engine plays WebM/VP9/Opus; **H.264/AAC playback is not enabled**. Some media and sign-in services need further work. See [media compatibility](native/README.md#video-compatibility-and-engine-builds) for details.

Tabs and organization restore after restarting. Unsaved forms, split arrangements, and download history last for the current session. Builds are locally signed for development; distribution signing and notarization are still required.

## For contributors

The app lives in [`native/Sources`](native/Sources). The [architecture guide](docs/architecture.md) explains how the native interface and Chromium fit together.

```sh
npm ci                 # Node.js 22.12+; test tools only
npm test               # Swift state + engine package checks
npm run build          # Build the native app
npm run test:integration
```

Run GUI tests sequentially. They use temporary profiles and local webpages. See the [testing guide](native/README.md#verify) and [verification notes](docs/verification.md) for coverage and limits.
