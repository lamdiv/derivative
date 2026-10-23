import AppKit
import SwiftUI

@MainActor final class BrowserModel: ObservableObject {
    @Published var title = "New tab"
    @Published var address = ""
    @Published var loading = false
    @Published var canBack = false
    @Published var canForward = false
    @Published var expanded = false
    @Published var pinned = true
    @Published var error = ""
    var search: () -> Void = {}
    var toggle: () -> Void = {}
}

struct SidebarView: View {
    @ObservedObject var model: BrowserModel
    private let accent = Color(red: 0.68, green: 0.58, blue: 0.83)
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                if !model.expanded { Spacer().frame(width: 64) }
                Button(action: model.toggle) { Image(systemName: "sidebar.left") }
                    .help("Show or hide sidebar · ⌘S").accessibilityLabel("Toggle sidebar")
                Spacer(minLength: 8)
                Button(action: { DerivativeBack() }) { Image(systemName: "arrow.left") }.disabled(!model.canBack)
                Button(action: { DerivativeForward() }) { Image(systemName: "arrow.right") }.disabled(!model.canForward)
                Button(action: { DerivativeReload() }) { Image(systemName: "arrow.clockwise") }
            }
            .font(.system(size: 15, weight: .medium)).frame(height: 28)
            Button(action: model.search) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                    Text(model.address.isEmpty ? "Search or enter URL" : model.address)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text("⌘L").font(.system(size: 10)).foregroundStyle(.secondary)
                }.font(.system(size: 12)).padding(11)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
            }.accessibilityLabel("Search or enter URL")
            HStack { Text("Favorites").font(.system(size: 11, weight: .medium)); Spacer() }.foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                favorite("globe", "Google", "https://www.google.com")
                favorite("book.closed", "Wikipedia", "https://www.wikipedia.org")
                favorite("curlybraces", "GitHub", "https://github.com")
            }
            HStack(spacing: 8) {
                Image(systemName: "sparkle").foregroundStyle(accent)
                Text("Personal").font(.system(size: 13, weight: .semibold))
                Spacer()
            }.padding(.top, 8)
            if !model.address.isEmpty && model.address != "about:blank" {
                Button(action: { DerivativeFocusPage() }) {
                    HStack(spacing: 9) {
                        if model.loading { ProgressView().controlSize(.mini) }
                        else { Image(systemName: "globe").foregroundStyle(accent) }
                        Text(model.title).lineLimit(1)
                        Spacer(minLength: 0)
                    }.font(.system(size: 12)).padding(10)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                }
            } else {
                Button(action: model.search) { Label("New tab", systemImage: "plus").font(.system(size: 12)) }.padding(8)
            }
            if !model.error.isEmpty { Text(model.error).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3) }
            Spacer(minLength: 8)
            Text("Derivative Native").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain).padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 17)
        .background {
            LinearGradient(colors: [Color(red: 0.29, green: 0.25, blue: 0.37), Color(red: 0.19, green: 0.17, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.9).background(.ultraThinMaterial)
        }
        .preferredColorScheme(.dark).ignoresSafeArea()
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.13), lineWidth: 1))
    }
    private func favorite(_ symbol: String, _ label: String, _ url: String) -> some View {
        Button { url.withCString { DerivativeNavigate($0) } } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 11))
        }.help(label).accessibilityLabel(label)
    }
}

@MainActor final class SearchModel: ObservableObject {
    @Published var query: String
    init(query: String) { self.query = query }
}

struct SearchView: View {
    @ObservedObject var model: SearchModel
    private var query: String { model.query }
    let currentTitle: String
    let currentURL: String
    let submit: (String) -> Void
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.white.opacity(0.6))
                TextField("Search or enter URL", text: $model.query, prompt: Text("Search or enter URL").foregroundStyle(Color.white.opacity(0.55))).textFieldStyle(.plain)
                    .font(.system(size: 20)).foregroundStyle(Color.white).onSubmit { submit(query) }
                    .accessibilityLabel("Search or enter URL")
                Button("esc", action: dismiss).buttonStyle(.plain).font(.system(size: 10))
                    .padding(5).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
            }.padding(20)
            if !currentURL.isEmpty && currentURL != "about:blank" && (query.isEmpty || "\(currentTitle) \(currentURL)".localizedCaseInsensitiveContains(query)) {
                Button { dismiss() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(currentTitle).font(.system(size: 13, weight: .medium))
                            Text("Current page · \(currentURL)").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.6))
                        }.lineLimit(1)
                        Spacer()
                        Image(systemName: "return").font(.system(size: 12))
                    }.padding(12).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).padding([.horizontal, .bottom], 8)
            }
            HStack {
                Text(query.isEmpty ? "Type an address or a search" : "Press Return to open")
                Spacer()
                Text("↵ Open").foregroundStyle(Color.white.opacity(0.6))
            }.font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.6)).padding(.horizontal, 20).padding(.vertical, 12)
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .background(Color(red: 0.19, green: 0.17, blue: 0.25).opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
        .padding(1).preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea().onExitCommand(perform: dismiss)
    }
}

@MainActor final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor final class BrowserController: NSObject, NSWindowDelegate, NSApplicationDelegate {
    let model = BrowserModel()
    let window: NSWindow
    let root = FlippedView()
    let pageHost = FlippedView()
    let sidebar: NSHostingView<SidebarView>
    let scrim = FlippedView()
    var searchPanel: NSHostingView<SearchView>?
    var monitor: Any?
    var hideWork: DispatchWorkItem?
    var revealed = false
    var normalPinned = true
    var didShowInitialSearch = false

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        sidebar = NSHostingView(rootView: SidebarView(model: model))
        super.init()
        window.title = "Derivative Native"
        window.appearance = NSAppearance(named: .darkAqua)
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 700, height: 480)
        window.isReleasedWhenClosed = false; window.acceptsMouseMovedEvents = true
        window.backgroundColor = NSColor(red: 0.13, green: 0.11, blue: 0.17, alpha: 1)
        window.contentView = root; window.delegate = self
        root.wantsLayer = true; pageHost.wantsLayer = true
        pageHost.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        pageHost.layer?.masksToBounds = true
        root.addSubview(pageHost); root.addSubview(sidebar)
        scrim.wantsLayer = true; scrim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.07).cgColor
        model.search = { [weak self] in self?.showSearch(edit: true) }
        model.toggle = { [weak self] in self?.toggleSidebar() }
        installMenu()
        NSApp.delegate = self
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            var consumed = false
            MainActor.assumeIsolated {
                guard let self, event.window === self.window else { return }
                let point = self.root.convert(event.locationInWindow, from: nil)
                if event.type == .leftMouseDown && self.searchPanel != nil && !self.searchPanel!.frame.contains(point) { self.closeSearch(); consumed = true; return }
                if event.type == .mouseMoved && !self.model.pinned && self.searchPanel == nil {
                    if point.x <= 8 { self.setRevealed(true) }
                    else if point.x > 312 { self.scheduleHide() }
                    else { self.hideWork?.cancel(); self.hideWork = nil }
                }
            }
            return consumed ? nil : event
        }
        window.center(); layout(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func layout() {
        let bounds = root.bounds
        let inset: CGFloat = model.expanded ? 0 : 8
        let offset: CGFloat = model.pinned && !model.expanded ? 304 : inset
        pageHost.frame = NSRect(x: offset, y: inset, width: max(1, bounds.width-offset-inset), height: max(1, bounds.height-inset*2))
        pageHost.layer?.cornerRadius = model.expanded ? 0 : 14
        sidebar.frame = NSRect(x: 8, y: model.expanded ? 0 : 8, width: 288, height: bounds.height-(model.expanded ? 8 : 16))
        sidebar.isHidden = !model.pinned && !revealed
        if !sidebar.isHidden { root.addSubview(sidebar, positioned: .above, relativeTo: pageHost) }
        scrim.frame = bounds
        if let panel = searchPanel {
            panel.frame = NSRect(x: max(24, (bounds.width-720)/2), y: min(260, bounds.height*0.28), width: min(720, bounds.width-48), height: 230)
        }
        if !model.expanded {
            for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                if let button = window.standardWindowButton(type) {
                    button.setFrameOrigin(NSPoint(x: 20 + CGFloat(index)*20, y: button.superview!.bounds.height - 30))
                    button.isHidden = sidebar.isHidden
                }
            }
        }
    }
    func setRevealed(_ value: Bool) { hideWork?.cancel(); hideWork = nil; revealed = value; layout() }
    func scheduleHide() {
        guard revealed, hideWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.setRevealed(false) }
        hideWork = work; DispatchQueue.main.asyncAfter(deadline: .now()+0.18, execute: work)
    }
    @objc func toggleSidebar() {
        model.pinned.toggle(); revealed = false
        if !model.expanded { normalPinned = model.pinned }
        layout()
    }
    @objc func newSearch() { showSearch(edit: false) }
    @objc func editSearch() { showSearch(edit: true) }
    @objc func reload() { DerivativeReload() }
    @objc func back() { DerivativeBack() }
    @objc func forward() { DerivativeForward() }
    func showSearch(edit: Bool) {
        hideWork?.cancel(); hideWork = nil
        closeSearch(focus: false)
        let panel = NSHostingView(rootView: SearchView(model: SearchModel(query: edit && model.address != "about:blank" ? model.address : ""), currentTitle: model.title, currentURL: model.address, submit: { [weak self] text in self?.navigate(text) }, dismiss: { [weak self] in self?.closeSearch() }))
        searchPanel = panel
        root.addSubview(scrim); root.addSubview(panel)
        layout()
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, self.searchPanel === panel else { return }
            panel.layoutSubtreeIfNeeded()
            func editable(in view: NSView) -> NSTextField? {
                if let field = view as? NSTextField, field.isEditable { return field }
                return view.subviews.lazy.compactMap { editable(in: $0) }.first
            }
            if let field = editable(in: panel) { self.window.makeFirstResponder(field); if edit { field.selectText(nil) } }
        }
    }
    func closeSearch(focus: Bool = true) {
        searchPanel?.removeFromSuperview(); searchPanel = nil; scrim.removeFromSuperview()
        if focus { DerivativeFocusPage() }
    }
    func navigate(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let url: URL?
        if text.contains("://") {
            url = URL(string: text)
        } else if !text.contains(where: \.isWhitespace) && (text.contains(".") || text.hasPrefix("localhost")) {
            url = URL(string: "https://"+text)
        } else {
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: text)]
            url = components.url
        }
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { NSSound.beep(); return }
        model.error = ""; closeSearch()
        url.absoluteString.withCString { DerivativeNavigate($0) }
    }
    func update(title: String, url: String, loading: Bool, back: Bool, forward: Bool) {
        model.title = title; model.address = url; model.loading = loading; model.canBack = back; model.canForward = forward
        window.title = title.isEmpty ? "Derivative Native" : "\(title) — Derivative Native"
        if !didShowInitialSearch {
            didShowInitialSearch = true
            if url.isEmpty || url == "about:blank" { DispatchQueue.main.async { [weak self] in self?.showSearch(edit: false) } }
        }
    }
    func windowDidResize(_ notification: Notification) { layout() }
    func windowDidEnterFullScreen(_ notification: Notification) { model.expanded = true; model.pinned = false; revealed = false; layout() }
    func windowDidExitFullScreen(_ notification: Notification) { model.expanded = false; model.pinned = normalPinned; revealed = false; layout() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { DerivativeCanCloseBrowser() }
    func windowWillClose(_ notification: Notification) {
        pageHost.subviews.forEach { $0.removeFromSuperview() }
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        hideWork?.cancel()
    }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func installMenu() {
        let menu = NSMenu()
        func section(_ title: String, _ items: [(String, Selector, String)]) {
            let parent = NSMenuItem(); let sub = NSMenu(title: title)
            for (label, action, key) in items {
                let item = NSMenuItem(title: label, action: action, keyEquivalent: key)
                item.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
                sub.addItem(item)
            }
            parent.submenu = sub; menu.addItem(parent)
        }
        section("Derivative Native", [("Quit Derivative Native", #selector(NSApplication.terminate(_:)), "q")])
        section("File", [("Search", #selector(newSearch), "t"), ("Open Location", #selector(editSearch), "l")])
        let edit = NSMenuItem(); edit.submenu = NSMenu(title: "Edit")
        for (label, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.submenu?.addItem(withTitle: label, action: Selector(action), keyEquivalent: key)
        }
        menu.addItem(edit)
        section("View", [("Toggle Sidebar", #selector(toggleSidebar), "s"), ("Reload", #selector(reload), "r"), ("Back", #selector(back), "["), ("Forward", #selector(forward), "]")])
        NSApp.mainMenu = menu
    }
}

@MainActor private var controller: BrowserController?
@_cdecl("DerivativeCreateWindow") @MainActor func createWindow() -> UnsafeMutableRawPointer {
    let created = BrowserController(); controller = created
    return Unmanaged.passUnretained(created.pageHost).toOpaque()
}
@_cdecl("DerivativeUpdatePage") @MainActor func updatePage(_ title: UnsafePointer<CChar>, _ url: UnsafePointer<CChar>, _ loading: Bool, _ back: Bool, _ forward: Bool) {
    controller?.update(title: String(cString: title), url: String(cString: url), loading: loading, back: back, forward: forward)
}
@_cdecl("DerivativeShowError") @MainActor func showError(_ message: UnsafePointer<CChar>) {
    controller?.model.error = String(cString: message)
    NSLog("Derivative Native: %@", String(cString: message))
}
@_cdecl("DerivativeShortcut") @MainActor func shortcut(_ key: Int32) {
    switch key {
    case 84: controller?.newSearch()
    case 76: controller?.editSearch()
    case 83: controller?.toggleSidebar()
    case 82: controller?.reload()
    default: break
    }
}
