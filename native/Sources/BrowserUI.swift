import AppKit
import SwiftUI
import Combine
import QuartzCore

@MainActor final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
@MainActor final class SidebarGlassView: NSView {
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // SwiftUI owns the native glass on newer systems. Avoid a second blur
        // behind it; the older fallback still needs an AppKit backdrop.
        if #unavailable(macOS 26) {
            let backdrop = NSVisualEffectView(frame: bounds)
            backdrop.material = .sidebar; backdrop.blendingMode = .withinWindow; backdrop.state = .followsWindowActiveState
            backdrop.autoresizingMask = [.width, .height]; addSubview(backdrop)
        }
        wantsLayer = true; layer?.cornerRadius = 14; layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
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
    let sidebar = SidebarGlassView(frame: .zero)
    let sidebarContent: NSHostingView<SidebarView>
    let scrim = FlippedView()
    var windowButtons: [NSButton] = []
    let homeSearch = SearchModel(query: "")
    var home: NSHostingView<HomeView>!
    var searchPanel: NSHostingView<SearchView>?
    var searchModel: SearchModel?
    var searchObservation: AnyCancellable?
    var homeObservation: AnyCancellable?
    var searchEditsCurrent = false
    var monitor: Any?
    var hideWork: DispatchWorkItem?
    var sidebarHiding = false
    var sidebarTransitioning = false
    var sidebarAnimation = 0
    var revealed = false
    var normalPinned = true
    var ready = false
    var finishingQuit = false
    var testDriver: NativeTestDriver?
    var auxiliaryPanel: NSView?
    var errorPanels: [String: NSView] = [:]
    var overlayKind = ""
    var closedTabs: [BrowserTab] = []
    var pendingMoves: [String: [String: String]] = [:]
    var swipe = SpaceSwipe()
    var swipeReset: DispatchWorkItem?
    var swipeCapture: (image: NSImage, origin: CGPoint)?
    var swipeTransition = 0
    var splitRatio = 0.5
    let splitDivider = SplitDivider()
    let sidebarResizeHandle = SidebarResizeHandle()
    var sidebarResizing = false
    var pageEnteredFullscreen = false
    var nativeFullscreen = false
    var fullscreenTransitioning = false
    var appearanceObservation: NSKeyValueObservation?


    override init() {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DERIVATIVE_NATIVE_USER_DATA"] ?? NSHomeDirectory()+"/Library/Application Support/Derivative Native Prototype")
        store = BrowserStore(directory: directory)
        model = BrowserModel(store: store)
        window = BrowserWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        sidebarContent = NSHostingView(rootView: SidebarView(model: model))
        // AppKit owns this frame, including the title-bar area. Letting the
        // hosting view apply its own safe area offsets clips the header.
        sidebarContent.safeAreaRegions = []
        sidebarContent.sizingOptions = []
        super.init()
        model.pinned = store.state.preferences.sidebarMode == "fixed"; normalPinned = model.pinned
        window.title = "Derivative"; window.appearance = NSAppearance(named: .darkAqua)
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 700, height: 480)
        window.isReleasedWhenClosed = false; window.acceptsMouseMovedEvents = true; window.isRestorable = false
        window.ignoresMouseEvents = ProcessInfo.processInfo.environment["DERIVATIVE_NATIVE_AUTOMATED"] == "1"
        window.backgroundColor = NSColor(red: 0.13, green: 0.11, blue: 0.17, alpha: 1)
        window.contentView = root; window.delegate = self
        root.wantsLayer = true; pageHost.wantsLayer = true
        pageHost.layer?.masksToBounds = true
        sidebar.wantsLayer = true
        sidebar.addSubview(sidebarContent); sidebarContent.autoresizingMask = [.width, .height]
        root.addSubview(pageHost); root.addSubview(sidebar)
        sidebarResizeHandle.controller = self
        root.addSubview(sidebarResizeHandle)
        // Native AppKit controls in the content hierarchy avoid the title bar's
        // clipped hit area and automatic repositioning during sidebar reveals.
        let controlTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        windowButtons = controlTypes.compactMap { NSWindow.standardWindowButton($0, for: window.styleMask) }
        for (index, button) in windowButtons.enumerated() {
            button.target = self
            button.action = [#selector(closeWindowControl), #selector(minimizeWindowControl), #selector(maximizeWindowControl)][index]
            button.translatesAutoresizingMaskIntoConstraints = true; button.autoresizingMask = []
            root.addSubview(button)
        }
        splitDivider.addGestureRecognizer(NSPanGestureRecognizer(target: self, action: #selector(resizeSplit(_:))))
        pageHost.addSubview(splitDivider)
        home = NSHostingView(rootView: HomeView(model: model, search: homeSearch, submit: { [weak self] in self?.navigate($0, newTab: true) }, choose: { [weak self] in self?.selectTab($0) }))
        pageHost.addSubview(home); home.autoresizingMask = [.width, .height]
        homeObservation = homeSearch.$query.dropFirst().sink { [weak self] query in
            guard !query.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self, self.store.active == nil, self.searchPanel == nil, !self.home.isHidden else { return }
                self.showSearch(edit: false, initialQuery: self.homeSearch.query)
            }
        }
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
        model.action = { [weak self] name, values in self?.perform(name, values) }
        applyPreferences()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in DispatchQueue.main.async { self?.applyPreferences() } }
        installMenu(); NSApp.delegate = self
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseUp, .scrollWheel, .keyDown, .flagsChanged]) { [weak self] event in
            var consumed = false
            MainActor.assumeIsolated {
                guard let self, event.window === self.window else { return }
                if event.type == .keyDown, self.handleKey(event) { consumed = true; return }
                if event.type == .flagsChanged, !event.modifierFlags.contains(.control), !self.model.recentIDs.isEmpty { self.commitRecent(); return }
                if event.type == .mouseMoved && NSEvent.pressedMouseButtons & 1 == 0 { self.model.dragging = nil; self.model.dropTarget = nil }
                if event.type == .leftMouseUp { DispatchQueue.main.async { self.model.dragging = nil; self.model.dropTarget = nil } }
                let point = self.root.convert(event.locationInWindow, from: nil)
                if event.type == .scrollWheel {
                    consumed = self.handleSidebarScroll(event, point: point); if consumed { return }
                }
                if event.type == .leftMouseDown, let panel = self.auxiliaryPanel, !panel.frame.contains(point) { self.closeOverlay(); consumed = true; return }
                if event.type == .leftMouseDown && self.searchPanel != nil && !self.searchPanel!.frame.contains(point) { self.closeSearch(); consumed = true; return }
                if event.type == .mouseMoved && !self.sidebarResizing && !self.swipe.tracking && !self.model.pinned && !self.model.siteControlsOpen && !self.model.downloadsExpanded && self.searchPanel == nil && self.auxiliaryPanel == nil && self.model.dragging == nil && self.window.attachedSheet == nil {
                    if point.x <= 8 && self.model.effectiveSidebarMode != "hidden" { self.setRevealed(true) }
                    else if point.x > self.sidebar.frame.maxX+16 { self.scheduleHide() }
                    else { self.hideWork?.cancel(); self.hideWork = nil; if self.sidebarHiding { self.setRevealed(true) } }
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
        let inset: CGFloat = model.expanded && !model.pinned ? 0 : 8
        let width = SidebarSizing.width(store.state.preferences.sidebarWidth, available: bounds.width)
        let offset: CGFloat = model.pinned ? width+16 : inset
        pageHost.frame = NSRect(x: offset, y: inset, width: max(1, bounds.width-offset-inset), height: max(1, bounds.height-inset*2))
        pageHost.layer?.cornerRadius = inset == 0 ? 0 : 14
        if home != nil { home.frame = pageHost.bounds }
        sidebar.frame = NSRect(x: 8, y: 8, width: width, height: bounds.height-16)
        sidebarContent.frame = sidebar.bounds
        sidebar.isHidden = !model.pinned && !revealed && !sidebarHiding
        if !sidebar.isHidden { root.addSubview(sidebar, positioned: .above, relativeTo: pageHost) }
        sidebarResizeHandle.frame = NSRect(x: sidebar.frame.maxX-2, y: sidebar.frame.minY+14, width: 8, height: max(0, sidebar.frame.height-28))
        sidebarResizeHandle.isHidden = sidebar.isHidden || sidebarTransitioning || searchPanel != nil || auxiliaryPanel != nil
        root.addSubview(sidebarResizeHandle, positioned: .above, relativeTo: sidebar)
        scrim.frame = bounds
        if let panel = searchPanel {
            root.addSubview(scrim, positioned: .above, relativeTo: sidebar)
            root.addSubview(panel, positioned: .above, relativeTo: scrim)
            let top = min(260, bounds.height*0.28)
            let count = min(5, nativeSuggestions(searchModel?.query ?? "", store: store).count)
            let height = min(bounds.height-top-24, CGFloat(count)*60+100)
            let searchArea = pageHost.frame
            let searchWidth = min(720, max(1, searchArea.width-48))
            panel.frame = NSRect(x: searchArea.midX-searchWidth/2, y: top, width: searchWidth, height: height)
        }
        if let panel = auxiliaryPanel {
            scrim.frame = bounds
            root.addSubview(scrim, positioned: .above, relativeTo: sidebar)
            root.addSubview(panel, positioned: .above, relativeTo: scrim)
            let width = min(overlayKind == "recent" ? 460.0 : 660.0, bounds.width-48)
            let height = min(overlayKind == "recent" ? Double(model.recentIDs.count)*54+60 : 620, bounds.height-80)
            panel.frame = NSRect(x: (bounds.width-width)/2, y: max(40, (bounds.height-height)/2), width: width, height: height)
        }
        splitDivider.isHidden = model.splitIDs.count != 2
        if !splitDivider.isHidden {
            splitDivider.frame = NSRect(x: (pageHost.bounds.width-6)*splitRatio, y: 0, width: 6, height: pageHost.bounds.height)
            pageHost.addSubview(splitDivider, positioned: .above, relativeTo: nil)
        }
        if ready { DerivativeLayoutPages(); layoutErrors() }
        alignWindowButtons()
    }
    @objc func closeWindowControl() { window.performClose(nil) }
    @objc func restoreWindowControl() { window.deminiaturize(nil); window.makeKeyAndOrderFront(nil) }
    @objc func zoomWindowControl() { window.performZoom(nil) }
    @objc func minimizeWindowControl() { window.miniaturize(nil) }
    @objc func maximizeWindowControl() {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true { window.performZoom(nil) }
        else { window.toggleFullScreen(nil) }
    }
    func alignWindowButtons() {
        // AppKit's auto-hiding fullscreen title bar owns its traffic lights.
        // Normal windows use the separate controls aligned with the sidebar.
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window.standardWindowButton(type), button.isHidden != !nativeFullscreen { button.isHidden = !nativeFullscreen }
        }
        for (index, button) in windowButtons.enumerated() {
            button.isHidden = nativeFullscreen || fullscreenTransitioning || model.expanded || sidebar.isHidden || sidebarTransitioning
            button.setFrameOrigin(NSPoint(x: sidebar.frame.minX+14+CGFloat(index)*20,
                                          y: sidebar.frame.minY+14+(28-button.frame.height)/2))
        }
        if Array(root.subviews.suffix(windowButtons.count)) != windowButtons {
            for button in windowButtons { root.addSubview(button, positioned: .above, relativeTo: nil) }
        }
    }
    func showActive(preserveSearch: Bool = false) {
        guard ready else { return }
        model.siteControlsOpen = false
        if !preserveSearch || store.active == nil { closeOverlay(focus: false) }
        if model.splitIDs.count == 2 && (!model.splitIDs.contains(store.state.activeTabId ?? "") || model.splitIDs.contains(where: { id in !store.currentTabs.contains { $0.id == id } })) { model.splitIDs = [] }
        let pair = model.splitIDs
        let first = pair.count == 2 ? pair[0] : ""
        let second = pair.count == 2 ? pair[1] : ""
        first.withCString { a in second.withCString { b in DerivativeSetSplit(a, b, splitRatio) } }
        for id in pair { if let tab = store.state.tabs.first(where: { $0.id == id }) { ensurePage(tab) } }
        if let tab = store.active {
            home.isHidden = true
            tab.id.withCString { DerivativeSelectPage($0) }
            ensurePage(tab)
            window.title = "\(tab.title) — Derivative"
        } else {
            "".withCString { DerivativeSelectPage($0) }
            home.isHidden = false
            if !preserveSearch { focusSearch(in: home, select: false) }
            window.title = "Derivative"
        }
        model.error = ""; layout()
    }
    func selectTab(_ id: String) { store.select(id); showActive() }
    func selectSpace(_ id: String, duringSwipe: Bool = false) {
        if !duringSwipe {
            swipeTransition += 1; swipeCapture = nil; swipe = SpaceSwipe(); swipeReset?.cancel()
            model.swipeOutgoing = nil; model.swipeOffset = 0; model.swipeEdge = nil
        }
        store.selectSpace(id); applyPreferences(); homeSearch.query = ""; homeSearch.selected = 0; showActive()
    }
    func closeTab(_ id: String) { id.withCString { DerivativeClosePage($0) } }
    func tabClosed(_ id: String) {
        if let placement = pendingMoves.removeValue(forKey: id) { placeTab(id, values: placement, afterClose: true); return }
        if let tab = store.state.tabs.first(where: { $0.id == id }) { closedTabs.insert(tab, at: 0); closedTabs = Array(closedTabs.prefix(30)) }
        store.remove(id); showActive(preserveSearch: searchPanel != nil)
    }
    func openFavorite(_ id: String) {
        guard let favorite = store.currentFavorites.first(where: { $0.id == id }) else { return }
        if let index = store.state.tabs.firstIndex(where: { $0.spaceId == store.state.activeSpaceId && ($0.favoriteId == id || $0.url == favorite.url) }) {
            store.state.tabs[index].favoriteId = id; selectTab(store.state.tabs[index].id)
        } else { store.open(favorite.url, favoriteId: id); showActive() }
    }
    func setRevealed(_ value: Bool) {
        hideWork?.cancel(); hideWork = nil
        guard model.dragging == nil || value else { return }
        guard revealed != value else { return }
        let visible = !sidebar.isHidden
        revealed = value
        transitionSidebar(visible: model.pinned || value, wasVisible: visible)
    }
    func transitionSidebar(visible: Bool, wasVisible: Bool) {
        sidebarAnimation += 1
        let generation = sidebarAnimation
        let currentX = sidebar.layer?.presentation()?.frame.origin.x
        sidebar.layer?.removeAllAnimations()
        let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && (ProcessInfo.processInfo.environment["DERIVATIVE_NATIVE_AUTOMATED"] != "1" || ProcessInfo.processInfo.environment["DERIVATIVE_NATIVE_TEST_ANIMATIONS"] == "1")
        guard animated, visible != wasVisible || sidebarTransitioning else {
            sidebarHiding = false; sidebarTransitioning = false; sidebar.alphaValue = 1; layout(); return
        }
        sidebarHiding = !visible; sidebarTransitioning = true
        layout()
        let destination = sidebar.frame
        let sourceX = wasVisible ? (currentX ?? destination.minX) : -destination.width
        sidebar.frame = NSRect(x: visible ? 8 : -destination.width, y: destination.minY, width: destination.width, height: destination.height)
        sidebar.alphaValue = 1
        guard let layer = sidebar.layer else { sidebarHiding = false; sidebarTransitioning = false; layout(); return }
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = sourceX + layer.position.x - sidebar.frame.minX
        slide.toValue = layer.position.x
        slide.duration = 0.2
        slide.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.sidebarAnimation == generation else { return }
                self.sidebarHiding = false; self.sidebarTransitioning = false; self.layout()
            }
        }
        layer.add(slide, forKey: "sidebar-slide")
        CATransaction.commit()
    }

    func scheduleHide() {
        guard revealed, hideWork == nil, !sidebarResizing else { return }
        let work = DispatchWorkItem { [weak self] in self?.setRevealed(false) }
        hideWork = work; DispatchQueue.main.asyncAfter(deadline: .now()+0.18, execute: work)
    }
    @objc func toggleSidebar() {
        model.siteControlsOpen = false
        let visible = !sidebar.isHidden
        model.pinned.toggle(); revealed = false
        if model.expanded { model.expandedSidebarMode = model.pinned ? "fixed" : "hover" }
        else {
            normalPinned = model.pinned; store.state.preferences.sidebarMode = model.pinned ? "fixed" : "hover"; store.persist()
        }
        transitionSidebar(visible: model.pinned, wasVisible: visible)
    }
    @objc func newSearch() { showSearch(edit: false) }
    @objc func editSearch() { showSearch(edit: true) }
    @objc func closeActiveTab() { if let id = store.state.activeTabId { closeTab(id) } }
    @objc func pinActiveTab() { if let id = store.state.activeTabId { model.pin(id) } }
    @objc func reload() { DerivativeReload() }
    @objc func back() { DerivativeBack() }
    @objc func forward() { DerivativeForward() }
    func showSearch(edit: Bool, initialQuery: String? = nil) {
        hideWork?.cancel(); hideWork = nil
        guard store.active != nil || initialQuery != nil else { focusSearch(in: home, select: true); return }
        closeOverlay(focus: false); searchEditsCurrent = edit
        let search = SearchModel(query: initialQuery ?? (edit ? model.address : "")); searchModel = search
        if store.active == nil { home.isHidden = true }
        searchObservation = search.$query.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.layout() } }
        let panel = NSHostingView(rootView: SearchView(model: search, browser: model, submit: { [weak self] text in self?.navigate(text, newTab: !edit) }, dismiss: { [weak self] in self?.closeSearch() }, choose: { [weak self] in self?.selectTab($0) }))
        panel.safeAreaRegions = []; panel.sizingOptions = []
        searchPanel = panel; root.addSubview(scrim); root.addSubview(panel); layout(); animateIn(panel); focusSearch(in: panel, select: edit)
    }
    func focusSearch(in view: NSView, select: Bool) {
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self, let view, !view.isHidden else { return }
            view.layoutSubtreeIfNeeded()
            func editable(in view: NSView) -> NSTextField? {
                if let field = view as? NSTextField, field.isEditable { return field }
                return view.subviews.lazy.compactMap { editable(in: $0) }.first
            }
            if let field = editable(in: view) {
                self.window.makeFirstResponder(field)
                if select { field.selectText(nil) }
                else if let editor = field.currentEditor() { editor.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0) }
            }
        }
    }
    func closeSearch(focus: Bool = true) {
        searchObservation = nil; searchPanel?.removeFromSuperview(); searchPanel = nil; searchModel = nil; scrim.removeFromSuperview()
        if store.active == nil { homeSearch.query = ""; homeSearch.selected = 0; home.isHidden = false }
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
        if loading, let index = store.state.tabs.firstIndex(where: { $0.id == id }), store.state.tabs[index].error != nil { store.state.tabs[index].error = nil; layoutErrors() }
        if id == store.state.activeTabId { window.title = "\(title) — Derivative" }
    }
    func windowDidResize(_ notification: Notification) {
        if !fullscreenTransitioning && window.styleMask.contains(.fullScreen) == false && ProcessInfo.processInfo.environment["DERIVATIVE_NATIVE_AUTOMATED"] != "1" {
            let expanded = window.isZoomed
            if expanded != model.expanded { model.expanded = expanded; if expanded { model.expandedSidebarMode = "hover" }; model.pinned = expanded ? false : normalPinned; revealed = false }
        }
        layout()
    }
    func windowDidUpdate(_ notification: Notification) { alignWindowButtons() }
    func windowWillEnterFullScreen(_ notification: Notification) {
        fullscreenTransitioning = true; nativeFullscreen = true; alignWindowButtons()
    }
    func windowWillExitFullScreen(_ notification: Notification) {
        fullscreenTransitioning = true; alignWindowButtons()
    }
    func windowDidEnterFullScreen(_ notification: Notification) { fullscreenTransitioning = false; nativeFullscreen = true; model.expanded = true; model.expandedSidebarMode = "hover"; model.pinned = false; revealed = false; layout() }
    func windowDidExitFullScreen(_ notification: Notification) { fullscreenTransitioning = false; nativeFullscreen = false; model.expanded = false; model.pinned = normalPinned; revealed = false; layout() }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { recoverFullscreenTransition() }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { recoverFullscreenTransition() }
    private func recoverFullscreenTransition() {
        fullscreenTransitioning = false; nativeFullscreen = window.styleMask.contains(.fullScreen); layout()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if finishingQuit { return true }
        store.flush(); DerivativeRequestQuit(); return false
    }
    func finishQuit() { finishingQuit = true; store.flush(); window.close() }
    func windowWillClose(_ notification: Notification) {
        ready = false; sidebarAnimation += 1; sidebar.layer?.removeAllAnimations()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        hideWork?.cancel()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { restoreWindowControl(); return true }
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
        section("Derivative", [("About Derivative", #selector(about), ""), ("Settings…", #selector(settings), ","), ("Quit Derivative", #selector(NSApplication.terminate(_:)), "q")])
        section("File", [("New Tab", #selector(newSearch), "t"), ("Open Location", #selector(editSearch), "l"), ("Close Tab", #selector(closeActiveTab), "w")])
        let edit = NSMenuItem(); edit.submenu = NSMenu(title: "Edit")
        for (label, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { edit.submenu?.addItem(withTitle: label, action: Selector(action), keyEquivalent: key) }
        menu.addItem(edit)
        section("View", [("Toggle Sidebar", #selector(toggleSidebar), "s"), ("Pin Tab", #selector(pinActiveTab), "d"), ("Reload", #selector(reload), "r"), ("Zoom In", #selector(zoomInPage), "="), ("Zoom Out", #selector(zoomOutPage), "-"), ("Actual Size", #selector(resetPageZoom), "0"), ("Back", #selector(back), "["), ("Forward", #selector(forward), "]")])
        section("Window", [("Minimize", #selector(minimizeWindowControl), "m"), ("Zoom", #selector(zoomWindowControl), ""), ("Bring to Front", #selector(restoreWindowControl), "")])
        let fullscreen = NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullscreen.target = window; fullscreen.keyEquivalentModifierMask = [.control, .command]
        menu.items.first(where: { $0.submenu?.title == "View" })?.submenu?.addItem(fullscreen)
        let reopen = NSMenuItem(title: "Reopen Closed Tab", action: #selector(reopenTab), keyEquivalent: "t"); reopen.target = self; reopen.keyEquivalentModifierMask = [.command, .shift]; menu.items.first(where: { $0.submenu?.title == "File" })?.submenu?.addItem(reopen)
        NSApp.mainMenu = menu
    }
}

@MainActor var currentController: BrowserController?
@_cdecl("DerivativeCreateWindow") @MainActor func createWindow() -> UnsafeMutableRawPointer {
    let created = BrowserController(); currentController = created; return Unmanaged.passUnretained(created.pageHost).toOpaque()
}
@_cdecl("DerivativeReady") @MainActor func ready(_ startup: UnsafePointer<CChar>) { currentController?.bootstrap(String(cString: startup)) }
@_cdecl("DerivativeUpdateTab") @MainActor func updateTab(_ id: UnsafePointer<CChar>, _ title: UnsafePointer<CChar>, _ url: UnsafePointer<CChar>, _ loading: Bool, _ back: Bool, _ forward: Bool) {
    currentController?.update(String(cString: id), title: String(cString: title), url: String(cString: url), loading: loading, back: back, forward: forward)
}
@_cdecl("DerivativeTabClosed") @MainActor func tabClosed(_ id: UnsafePointer<CChar>) { currentController?.tabClosed(String(cString: id)) }
@_cdecl("DerivativeFinishQuit") @MainActor func finishQuit() { currentController?.finishQuit() }
@_cdecl("DerivativeCancelQuit") @MainActor func cancelQuit() { currentController?.showActive() }
@_cdecl("DerivativeOpenPopup") @MainActor func openPopup(_ opener: UnsafePointer<CChar>, _ url: UnsafePointer<CChar>) {
    guard let controller = currentController, let tab = controller.store.state.tabs.first(where: { $0.id == String(cString: opener) }) else { return }
    controller.store.open(String(cString: url), spaceId: tab.spaceId); controller.showActive()
}
@_cdecl("DerivativeShowError") @MainActor func showError(_ message: UnsafePointer<CChar>) { currentController?.model.error = String(cString: message) }
@_cdecl("DerivativeShortcut") @MainActor func shortcut(_ key: Int32) {
    guard let controller = currentController else { return }
    switch key {
    case 1100: controller.recent(1)
    case 1101: controller.recent(-1)
    case 1102: controller.reopenTab()
    case 1103: controller.perform("copy")
    case 1104: DerivativeHardReload()
    case 1105: controller.stepTab(-1)
    case 1106: controller.stepTab(1)
    case 1110: controller.commitRecent()
    case 1111: controller.maximizeWindowControl()
    case 1112: controller.zoomInPage()
    case 1113: controller.zoomOutPage()
    case 1114: controller.resetPageZoom()
    case 1200: controller.stepSpace(-1)
    case 1201: controller.stepTab(-1)
    case 1202: controller.stepSpace(1)
    case 1203: controller.stepTab(1)
    case 188: controller.settings()
    case 219: controller.back()
    case 221: controller.forward()
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
        let tabs = controller.store.orderedTabs
        let index = key == 57 ? tabs.count-1 : Int(key)-49
        if tabs.indices.contains(index) { controller.selectTab(tabs[index].id) }
    default: break
    }
}

@_cdecl("DerivativeTabError") @MainActor func tabError(_ id: UnsafePointer<CChar>, _ message: UnsafePointer<CChar>) {
    guard let controller = currentController, let index = controller.store.state.tabs.firstIndex(where: { $0.id == String(cString: id) }) else { return }
    controller.store.state.tabs[index].error = String(cString: message); controller.store.state.tabs[index].loading = false; controller.layoutErrors()
}

@_cdecl("DerivativeWebsiteFullscreen") @MainActor func websiteFullscreen(_ fullscreen: Bool) {
    guard let controller = currentController else { return }
    if fullscreen, !controller.window.styleMask.contains(.fullScreen) { controller.pageEnteredFullscreen = true; controller.window.toggleFullScreen(nil) }
    else if !fullscreen, controller.pageEnteredFullscreen { controller.pageEnteredFullscreen = false; if controller.window.styleMask.contains(.fullScreen) { controller.window.toggleFullScreen(nil) } }
}
