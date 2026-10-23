import AppKit
import SwiftUI

@MainActor final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
@MainActor final class BrowserWindow: NSWindow {
    override var canBecomeKey: Bool { ProcessInfo.processInfo.environment["DERIVATIVE_NATIVE_AUTOMATED"] != "1" }
    override var canBecomeMain: Bool { canBecomeKey }
}
@MainActor final class BrowserController: NSObject, NSWindowDelegate, NSApplicationDelegate {
    let store: BrowserStore
    let model: BrowserModel
    let window: NSWindow
    let root = FlippedView()
    let pageHost = FlippedView()
    let sidebar: NSHostingView<SidebarView>
    let scrim = FlippedView()
    let homeSearch = SearchModel(query: "")
    var home: NSHostingView<HomeView>!
    var searchPanel: NSHostingView<SearchView>?
    var searchModel: SearchModel?
    var searchEditsCurrent = false
    var monitor: Any?
    var hideWork: DispatchWorkItem?
    var revealed = false
    var normalPinned = true
    var ready = false
    var finishingQuit = false
    var testDriver: NativeTestDriver?

    override init() {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DERIVATIVE_NATIVE_USER_DATA"] ?? NSHomeDirectory()+"/Library/Application Support/Derivative Native Prototype")
        store = BrowserStore(directory: directory)
        model = BrowserModel(store: store)
        window = BrowserWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        sidebar = NSHostingView(rootView: SidebarView(model: model))
        super.init()
        model.pinned = store.state.preferences.sidebarMode == "fixed"; normalPinned = model.pinned
        window.title = "Derivative Native"; window.appearance = NSAppearance(named: .darkAqua)
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 700, height: 480)
        window.isReleasedWhenClosed = false; window.acceptsMouseMovedEvents = true; window.isRestorable = false
        window.ignoresMouseEvents = ProcessInfo.processInfo.environment["DERIVATIVE_NATIVE_AUTOMATED"] == "1"
        window.backgroundColor = NSColor(red: 0.13, green: 0.11, blue: 0.17, alpha: 1)
        window.contentView = root; window.delegate = self
        root.wantsLayer = true; pageHost.wantsLayer = true
        pageHost.layer?.masksToBounds = true
        root.addSubview(pageHost); root.addSubview(sidebar)
        home = NSHostingView(rootView: HomeView(model: model, search: homeSearch, submit: { [weak self] in self?.navigate($0, newTab: true) }, choose: { [weak self] in self?.selectTab($0) }))
        pageHost.addSubview(home); home.autoresizingMask = [.width, .height]
        scrim.wantsLayer = true; scrim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.07).cgColor
        model.search = { [weak self] in self?.showSearch(edit: true) }
        model.newSearch = { [weak self] in self?.showSearch(edit: false) }
        model.toggle = { [weak self] in self?.toggleSidebar() }
        model.selectTab = { [weak self] in self?.selectTab($0) }
        model.closeTab = { [weak self] in self?.closeTab($0) }
        model.selectSpace = { [weak self] in self?.selectSpace($0) }
        model.openFavorite = { [weak self] in self?.openFavorite($0) }
        model.duplicate = { [weak self] id in
            guard let self, let tab = self.store.state.tabs.first(where: { $0.id == id }) else { return }
            _ = self.store.open(tab.url, spaceId: tab.spaceId); self.showActive()
        }
        installMenu(); NSApp.delegate = self
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            var consumed = false
            MainActor.assumeIsolated {
                guard let self, event.window === self.window else { return }
                let point = self.root.convert(event.locationInWindow, from: nil)
                if event.type == .leftMouseDown && self.searchPanel != nil && !self.searchPanel!.frame.contains(point) { self.closeSearch(); consumed = true; return }
                if event.type == .mouseMoved && !self.model.pinned && self.searchPanel == nil {
                    if point.x <= 8 && (self.model.expanded || self.store.state.preferences.sidebarMode != "hidden") { self.setRevealed(true) }
                    else if point.x > self.store.state.preferences.sidebarWidth+24 { self.scheduleHide() }
                    else { self.hideWork?.cancel(); self.hideWork = nil }
                }
            }
            return consumed ? nil : event
        }
        window.center(); layout()
        if ProcessInfo.processInfo.environment["DERIVATIVE_NATIVE_AUTOMATED"] == "1" { window.orderBack(nil) }
        else { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }
    func bootstrap(_ startup: String) {
        ready = true
        if !startup.isEmpty { store.open(startup) }
        showActive()
        if let path = ProcessInfo.processInfo.environment["DERIVATIVE_NATIVE_TEST_DIRECTORY"] {
            testDriver = NativeTestDriver(directory: URL(fileURLWithPath: path), controller: self)
        }
    }
    func layout() {
        let bounds = root.bounds
        let inset: CGFloat = model.expanded ? 0 : 8
        let width = store.state.preferences.sidebarWidth
        let offset: CGFloat = model.pinned && !model.expanded ? width+16 : inset
        pageHost.frame = NSRect(x: offset, y: inset, width: max(1, bounds.width-offset-inset), height: max(1, bounds.height-inset*2))
        pageHost.layer?.cornerRadius = model.expanded ? 0 : 14
        if home != nil { home.frame = pageHost.bounds }
        sidebar.frame = NSRect(x: 8, y: model.expanded ? 0 : 8, width: width, height: bounds.height-(model.expanded ? 8 : 16))
        sidebar.isHidden = !model.pinned && !revealed
        if !sidebar.isHidden { root.addSubview(sidebar, positioned: .above, relativeTo: pageHost) }
        scrim.frame = bounds
        if let panel = searchPanel {
            root.addSubview(scrim, positioned: .above, relativeTo: sidebar)
            root.addSubview(panel, positioned: .above, relativeTo: scrim)
            let top = min(260, bounds.height*0.28)
            panel.frame = NSRect(x: max(24, (bounds.width-720)/2), y: top, width: min(720, bounds.width-48), height: bounds.height-top-24)
        }
        if !model.expanded {
            for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                if let button = window.standardWindowButton(type) {
                    button.setFrameOrigin(NSPoint(x: 20+CGFloat(index)*20, y: button.superview!.bounds.height-30)); button.isHidden = sidebar.isHidden
                }
            }
        }
    }
    func showActive(preserveSearch: Bool = false) {
        guard ready else { return }
        if !preserveSearch { closeSearch(focus: false) }
        if let tab = store.active {
            home.isHidden = true
            tab.id.withCString { DerivativeSelectPage($0) }
            tab.id.withCString { id in tab.spaceId.withCString { space in tab.url.withCString { url in DerivativeCreatePage(id, space, url) } } }
            window.title = "\(tab.title) — Derivative Native"
        } else {
            "".withCString { DerivativeSelectPage($0) }
            home.isHidden = false
            if !preserveSearch { focusSearch(in: home, select: false) }
            window.title = "Derivative Native"
        }
        model.error = ""; layout()
    }
    func selectTab(_ id: String) { store.select(id); showActive() }
    func selectSpace(_ id: String) { store.selectSpace(id); homeSearch.query = ""; homeSearch.selected = 0; showActive() }
    func closeTab(_ id: String) { id.withCString { DerivativeClosePage($0) } }
    func tabClosed(_ id: String) { store.remove(id); showActive(preserveSearch: searchPanel != nil) }
    func openFavorite(_ id: String) {
        guard let favorite = store.state.favorites.first(where: { $0.id == id }) else { return }
        if let index = store.state.tabs.firstIndex(where: { $0.spaceId == store.state.activeSpaceId && ($0.favoriteId == id || $0.url == favorite.url) }) {
            store.state.tabs[index].favoriteId = id; selectTab(store.state.tabs[index].id)
        } else { store.open(favorite.url, favoriteId: id); showActive() }
    }
    func setRevealed(_ value: Bool) {
        hideWork?.cancel(); hideWork = nil
        guard revealed != value else { return }
        revealed = value; layout()
    }
    func scheduleHide() {
        guard revealed, hideWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.setRevealed(false) }
        hideWork = work; DispatchQueue.main.asyncAfter(deadline: .now()+0.18, execute: work)
    }
    @objc func toggleSidebar() {
        model.pinned.toggle(); revealed = false
        if !model.expanded {
            normalPinned = model.pinned; store.state.preferences.sidebarMode = model.pinned ? "fixed" : "hover"; store.persist()
        }
        layout()
    }
    @objc func newSearch() { showSearch(edit: false) }
    @objc func editSearch() { showSearch(edit: true) }
    @objc func closeActiveTab() { if let id = store.state.activeTabId { closeTab(id) } }
    @objc func pinActiveTab() { if let id = store.state.activeTabId { model.pin(id) } }
    @objc func reload() { DerivativeReload() }
    @objc func back() { DerivativeBack() }
    @objc func forward() { DerivativeForward() }
    func showSearch(edit: Bool) {
        hideWork?.cancel(); hideWork = nil
        guard store.active != nil else { focusSearch(in: home, select: true); return }
        closeSearch(focus: false); searchEditsCurrent = edit
        let search = SearchModel(query: edit ? model.address : ""); searchModel = search
        let panel = NSHostingView(rootView: SearchView(model: search, browser: model, submit: { [weak self] text in self?.navigate(text, newTab: !edit) }, dismiss: { [weak self] in self?.closeSearch() }, choose: { [weak self] in self?.selectTab($0) }))
        searchPanel = panel; root.addSubview(scrim); root.addSubview(panel); layout(); focusSearch(in: panel, select: edit)
    }
    func focusSearch(in view: NSView, select: Bool) {
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self, let view, !view.isHidden else { return }
            view.layoutSubtreeIfNeeded()
            func editable(in view: NSView) -> NSTextField? {
                if let field = view as? NSTextField, field.isEditable { return field }
                return view.subviews.lazy.compactMap { editable(in: $0) }.first
            }
            if let field = editable(in: view) { self.window.makeFirstResponder(field); if select { field.selectText(nil) } }
        }
    }
    func closeSearch(focus: Bool = true) {
        searchPanel?.removeFromSuperview(); searchPanel = nil; searchModel = nil; scrim.removeFromSuperview()
        if focus { if store.active != nil { DerivativeFocusPage() } else { focusSearch(in: home, select: false) } }
    }
    func navigate(_ text: String, newTab: Bool) {
        guard let url = SavedBrowserState.resolve(text, engine: store.state.preferences.searchEngine) else { NSSound.beep(); return }
        model.error = ""; closeSearch(focus: false)
        if newTab || store.active == nil { store.open(url.absoluteString); showActive() }
        else { url.absoluteString.withCString { DerivativeNavigate($0) }; DerivativeFocusPage() }
    }
    func update(_ id: String, title: String, url: String, loading: Bool, back: Bool, forward: Bool) {
        store.update(id, title: title, url: url, loading: loading, back: back, forward: forward)
        if id == store.state.activeTabId { window.title = "\(title) — Derivative Native" }
    }
    func windowDidResize(_ notification: Notification) { layout() }
    func windowDidEnterFullScreen(_ notification: Notification) { model.expanded = true; model.pinned = false; revealed = false; layout() }
    func windowDidExitFullScreen(_ notification: Notification) { model.expanded = false; model.pinned = normalPinned; revealed = false; layout() }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if finishingQuit { return true }
        store.flush(); DerivativeRequestQuit(); return false
    }
    func finishQuit() { finishingQuit = true; store.flush(); window.close() }
    func windowWillClose(_ notification: Notification) {
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
                item.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self; sub.addItem(item)
            }
            parent.submenu = sub; menu.addItem(parent)
        }
        section("Derivative Native", [("Quit Derivative Native", #selector(NSApplication.terminate(_:)), "q")])
        section("File", [("New Tab", #selector(newSearch), "t"), ("Open Location", #selector(editSearch), "l"), ("Close Tab", #selector(closeActiveTab), "w")])
        let edit = NSMenuItem(); edit.submenu = NSMenu(title: "Edit")
        for (label, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { edit.submenu?.addItem(withTitle: label, action: Selector(action), keyEquivalent: key) }
        menu.addItem(edit)
        section("View", [("Toggle Sidebar", #selector(toggleSidebar), "s"), ("Pin Tab", #selector(pinActiveTab), "d"), ("Reload", #selector(reload), "r"), ("Back", #selector(back), "["), ("Forward", #selector(forward), "]")])
        NSApp.mainMenu = menu
    }
}

@MainActor private var controller: BrowserController?
@_cdecl("DerivativeCreateWindow") @MainActor func createWindow() -> UnsafeMutableRawPointer {
    let created = BrowserController(); controller = created; return Unmanaged.passUnretained(created.pageHost).toOpaque()
}
@_cdecl("DerivativeReady") @MainActor func ready(_ startup: UnsafePointer<CChar>) { controller?.bootstrap(String(cString: startup)) }
@_cdecl("DerivativeUpdateTab") @MainActor func updateTab(_ id: UnsafePointer<CChar>, _ title: UnsafePointer<CChar>, _ url: UnsafePointer<CChar>, _ loading: Bool, _ back: Bool, _ forward: Bool) {
    controller?.update(String(cString: id), title: String(cString: title), url: String(cString: url), loading: loading, back: back, forward: forward)
}
@_cdecl("DerivativeTabClosed") @MainActor func tabClosed(_ id: UnsafePointer<CChar>) { controller?.tabClosed(String(cString: id)) }
@_cdecl("DerivativeFinishQuit") @MainActor func finishQuit() { controller?.finishQuit() }
@_cdecl("DerivativeCancelQuit") @MainActor func cancelQuit() { controller?.showActive() }
@_cdecl("DerivativeOpenPopup") @MainActor func openPopup(_ opener: UnsafePointer<CChar>, _ url: UnsafePointer<CChar>) {
    guard let controller, let tab = controller.store.state.tabs.first(where: { $0.id == String(cString: opener) }) else { return }
    controller.store.open(String(cString: url), spaceId: tab.spaceId); controller.showActive()
}
@_cdecl("DerivativeShowError") @MainActor func showError(_ message: UnsafePointer<CChar>) { controller?.model.error = String(cString: message) }
@_cdecl("DerivativeShortcut") @MainActor func shortcut(_ key: Int32) {
    guard let controller else { return }
    switch key {
    case 84: controller.newSearch()
    case 76: controller.editSearch()
    case 83: controller.toggleSidebar()
    case 82: controller.reload()
    case 81: controller.window.performClose(nil)
    case 87: controller.closeActiveTab()
    case 68: controller.pinActiveTab()
    case 1001...1009:
        let index = Int(key)-1001
        if controller.store.state.spaces.indices.contains(index) { controller.selectSpace(controller.store.state.spaces[index].id) }
    case 49...57:
        let tabs = controller.store.currentTabs
        let index = key == 57 ? tabs.count-1 : Int(key)-49
        if tabs.indices.contains(index) { controller.selectTab(tabs[index].id) }
    default: break
    }
}
