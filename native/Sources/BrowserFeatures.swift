import AppKit
import SwiftUI

@MainActor extension BrowserController {
    @objc func resizeSplit(_ gesture: NSPanGestureRecognizer) {
        guard model.splitIDs.count == 2 else { return }
        let point = gesture.location(in: pageHost)
        splitRatio = min(0.8, max(0.2, point.x / max(1, pageHost.bounds.width-6)))
        if let first = model.splitIDs.first, let second = model.splitIDs.last { first.withCString { a in second.withCString { b in DerivativeSetSplit(a, b, splitRatio) } } }
        layout()
    }
    func layoutErrors() {
        let visible = model.splitIDs.count == 2 ? model.splitIDs : [store.state.activeTabId ?? ""]
        let errors = store.state.tabs.filter { visible.contains($0.id) && $0.error != nil }
        for id in Array(errorPanels.keys) where !errors.contains(where: { $0.id == id }) { errorPanels.removeValue(forKey: id)?.removeFromSuperview() }
        for tab in errors {
            let panel: NSView
            if let existing = errorPanels[tab.id] { panel = existing }
            else { let hosting = NSHostingView(rootView: PageErrorView(model: model, id: tab.id)); hosting.safeAreaRegions = []; hosting.sizingOptions = []; panel = hosting; errorPanels[tab.id] = panel }
            var frame = pageHost.bounds
            if visible.count == 2 { let left = (frame.width-6)*splitRatio; if visible[0] == tab.id { frame.size.width = left } else { frame.origin.x = left+6; frame.size.width -= left+6 } }
            panel.frame = frame; pageHost.addSubview(panel, positioned: .above, relativeTo: nil)
        }
    }
    func ensurePage(_ tab: BrowserTab) { tab.id.withCString { id in tab.spaceId.withCString { space in tab.url.withCString { url in DerivativeCreatePage(id, space, url) } } } }
    func animateIn(_ view: NSView) {
        view.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.13; view.animator().alphaValue = 1 }
    }
    func applyPreferences() {
        let theme = store.state.preferences.theme
        window.appearance = theme == "system" ? nil : NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
        model.dark = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        window.backgroundColor = model.dark ? NSColor(red: 0.13, green: 0.11, blue: 0.17, alpha: 1) : NSColor(red: 0.94, green: 0.92, blue: 0.97, alpha: 1)
    }
    func closeOverlay(focus: Bool = true) {
        model.siteControlsOpen = false
        auxiliaryPanel?.removeFromSuperview(); auxiliaryPanel = nil; overlayKind = ""; model.recentIDs = []
        closeSearch(focus: focus)
    }
    @objc func settings() {
        closeOverlay(focus: false)
        let panel = NSHostingView(rootView: SettingsView(model: model)); panel.safeAreaRegions = []; panel.sizingOptions = []
        auxiliaryPanel = panel; overlayKind = "settings"; hideWork?.cancel(); layout(); animateIn(panel)
        window.makeFirstResponder(panel)
    }
    @objc func about() { model.settingsSection = "General"; settings() }
    @objc func reopenTab() {
        guard var tab = closedTabs.first else { return }
        closedTabs.removeFirst(); tab.id = UUID().uuidString
        if !store.state.spaces.contains(where: { $0.id == tab.spaceId }) { tab.spaceId = store.state.activeSpaceId; tab.folderId = nil }
        guard !store.state.tabs.contains(where: { $0.id == tab.id }) else { return }
        tab.loading = false; store.state.tabs.append(tab); store.state.sanitize(); store.select(tab.id); showActive()
    }
    func prompt(_ title: String, fields: [(String, String)], confirm: String = "Save", complete: @escaping ([String]) -> Void) {
        hideWork?.cancel(); setRevealed(true)
        let alert = NSAlert(); alert.messageText = title; alert.addButton(withTitle: confirm); alert.addButton(withTitle: "Cancel")
        let view = NSStackView(); view.orientation = .vertical; view.alignment = .leading; view.spacing = 10
        let inputs = fields.map { label, value -> NSTextField in
            let field = NSTextField(string: value); field.placeholderString = label; field.setAccessibilityLabel(label); field.frame.size = NSSize(width: 320, height: 24)
            field.widthAnchor.constraint(equalToConstant: 320).isActive = true; view.addArrangedSubview(field); return field
        }
        view.setFrameSize(view.fittingSize)
        alert.accessoryView = view; alert.window.initialFirstResponder = inputs.first
        alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { complete(inputs.map(\.stringValue)) } }
    }
    func perform(_ name: String, _ values: [String: String] = [:]) {
        let id = values["id"] ?? ""
        switch name {
        case "settings": settings()
        case "overlay.close": closeOverlay()
        case "site.controls":
            guard store.active != nil else { return }
            hideWork?.cancel(); hideWork = nil; model.downloadsExpanded = false; model.siteControlsOpen.toggle()
        case "page.zoom": if let percent = Int(values["percent"] ?? "") { DerivativeSetPageZoom(Int32(clamping: percent)) }
        case "page.mute": DerivativeSetPageMuted(values["muted"] == "true")
        case "sidebar.toggle": toggleSidebar()
        case "favorite.edit":
            let favorite = store.state.favorites.first { $0.id == id }
            prompt(favorite == nil ? "Add favorite" : "Edit favorite", fields: [("Name", favorite?.name ?? store.active?.title ?? ""), ("Website address", favorite?.url ?? store.active?.url ?? "")]) { [weak self] fields in self?.store.saveFavorite(id: favorite?.id, name: fields[0], input: fields[1]) }
        case "favorite.newTab":
            if let favorite = store.state.favorites.first(where: { $0.id == id }) { store.open(favorite.url); showActive() }
        case "favorite.save": store.saveFavorite(id: id.isEmpty ? nil : id, name: values["name"] ?? "", input: values["url"] ?? "")
        case "favorite.delete": store.deleteFavorite(id)
        case "favorite.reorder": store.reorderFavorite(id, before: values["beforeId"])
        case "folder.create":
            if let name = values["name"] { store.createFolder(name: name) }
            else { prompt("New folder", fields: [("Folder name", "")], confirm: "Create") { [weak self] fields in self?.store.createFolder(name: fields[0]) } }
        case "folder.rename":
            if let name = values["name"] { store.renameFolder(id, name: name) }
            else if let folder = store.state.folders.first(where: { $0.id == id }) { prompt("Rename folder", fields: [("Folder name", folder.name)]) { [weak self] in self?.store.renameFolder(id, name: $0[0]) } }
        case "folder.toggle": store.toggleFolder(id)
        case "folder.delete": store.deleteFolder(id)
        case "folder.reorder": store.reorderFolder(id, before: values["beforeId"] ?? "")
        case "tab.place": placeTab(id, values: values)
        case "tab.reload": selectTab(id); DerivativeReload()
        case "space.rename":
            if let name = values["name"] { store.renameSpace(id, name: name) }
            else if let space = store.state.spaces.first(where: { $0.id == id }) { prompt("Rename Space", fields: [("Space name", space.name)]) { [weak self] in self?.store.renameSpace(id, name: $0[0]) } }
        case "space.create": store.createSpace(name: values["name"] ?? "", color: values["color"] ?? "lavender", icon: values["icon"] ?? "✳")
        case "space.delete": store.deleteSpace(id); showActive()
        case "space.color": if let index = store.state.spaces.firstIndex(where: { $0.id == id }), let color = values["color"], ["lavender", "mint", "peach", "blue", "blush"].contains(color) { store.state.spaces[index].color = color; store.persist() }
        case "space.reorder": store.reorderSpace(id, before: values["beforeId"] ?? "")
        case "split.open":
            guard let base = store.state.tabs.first(where: { $0.id == (values["withId"] ?? store.state.activeTabId) }), let other = store.state.tabs.first(where: { $0.id == id }), base.id != id, base.spaceId == other.spaceId else { return }
            if let folder = store.state.folders.firstIndex(where: { $0.id == base.folderId }) { store.state.folders[folder].collapsed = false }
            model.splitIDs = [base.id, other.id]; store.select(base.id); splitRatio = 0.5; showActive()
        case "split.close": model.splitIDs = []; showActive()
        case "split.ratio": splitRatio = min(0.8, max(0.2, Double(values["ratio"] ?? "") ?? 0.5)); showActive(preserveSearch: true)
        case "preferences":
            if let value = values["theme"], ["system", "light", "dark"].contains(value) { store.state.preferences.theme = value }
            if let value = values["sidebarSize"], ["compact", "comfortable", "wide"].contains(value) { store.state.preferences.sidebarSize = value }
            if let value = values["sidebarMode"], ["fixed", "hover", "hidden"].contains(value) {
                if model.expanded { model.expandedSidebarMode = value }
                else { store.state.preferences.sidebarMode = value; normalPinned = value == "fixed" }
                model.pinned = value == "fixed"; revealed = false
            }
            if let value = values["searchEngine"], ["google", "duckduckgo"].contains(value) { store.state.preferences.searchEngine = value }
            if let value = values["restoreSession"] { store.state.preferences.restoreSession = value == "true" }
            store.persist(); applyPreferences(); layout()
        case "clear.request":
            guard ["history", "cache", "cookies"].contains(id), window.attachedSheet == nil else { return }
            let alert = NSAlert(); alert.messageText = "Clear \(id)?"; alert.informativeText = id == "cookies" ? "This signs you out of websites in all Spaces." : "This clears browsing \(id) in all Spaces."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Clear")
            alert.beginSheetModal(for: window) { [weak self] response in if response == .alertSecondButtonReturn { self?.perform("clear", ["id": id]) } }
        case "clear":
            if id == "history" { store.state.history = []; store.persist() }
            else if ["cache", "cookies"].contains(id) { id.withCString { DerivativeClearData($0) } }
        case "download.cancel": id.withCString { DerivativeCancelDownload($0) }
        case "download.open", "download.reveal":
            guard let download = model.downloads.first(where: { $0.id == id }), !download.path.isEmpty, download.status == "completed" else { return }
            let url = URL(fileURLWithPath: download.path)
            if name == "download.open" { NSWorkspace.shared.open(url) } else { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case "copy": NSPasteboard.general.clearContents(); NSPasteboard.general.setString(id.isEmpty ? model.address : id, forType: .string)
        case "reopen": reopenTab()
        default: break
        }
    }
    func placeTab(_ id: String, values: [String: String], afterClose: Bool = false) {
        guard let tab = store.state.tabs.first(where: { $0.id == id }) else { return }
        let space = values["spaceId"] ?? tab.spaceId
        let folder = values["folderId"].flatMap { $0.isEmpty ? nil : $0 }
        guard store.state.spaces.contains(where: { $0.id == space }), folder == nil || store.state.folders.contains(where: { $0.id == folder && $0.spaceId == space }) else { return }
        if space != tab.spaceId && !afterClose {
            pendingMoves[id] = values; id.withCString { DerivativeClosePage($0) }; return
        }
        store.placeTab(id, space: space, pinned: values["pinned"] == "true", folder: folder, before: values["beforeId"])
        if space != tab.spaceId { store.select(id) }
        showActive()
    }
    func handleSwipe(dx: Double, dy: Double, time: Double, began: Bool) -> Bool {
        let index = store.state.spaces.firstIndex { $0.id == store.state.activeSpaceId } ?? 0
        let result = swipe.update(dx: dx, dy: dy, time: time, index: index, count: store.state.spaces.count, began: began)
        guard result.consumed else { return false }
        model.swipeOffset = result.offset; model.swipeEdge = result.edge
        if result.step != 0 {
            selectSpace(store.state.spaces[index+result.step].id)
            model.swipeOffset = CGFloat(result.step)*35
            withAnimation(.easeOut(duration: 0.18)) { model.swipeOffset = 0 }
        }
        swipeReset?.cancel()
        let work = DispatchWorkItem { [weak self] in withAnimation(.easeOut(duration: 0.18)) { self?.model.swipeOffset = 0; self?.model.swipeEdge = nil } }
        swipeReset = work; DispatchQueue.main.asyncAfter(deadline: .now()+0.18, execute: work)
        return true
    }
    func stepTab(_ step: Int) {
        let tabs = store.orderedTabs; guard !tabs.isEmpty else { return }
        let index = tabs.firstIndex { $0.id == store.state.activeTabId } ?? 0
        selectTab(tabs[(index+step+tabs.count)%tabs.count].id)
    }
    func stepSpace(_ step: Int) {
        let spaces = store.state.spaces; let index = spaces.firstIndex { $0.id == store.state.activeSpaceId } ?? 0
        guard spaces.indices.contains(index+step) else { model.swipeEdge = step < 0 ? "First Space" : "Last Space"; return }
        selectSpace(spaces[index+step].id)
    }
    func recent(_ step: Int) {
        if model.recentIDs.isEmpty {
            closeOverlay(focus: false)
            model.recentIDs = Array(store.state.tabs.sorted { a, b in if (a.id == store.state.activeTabId) != (b.id == store.state.activeTabId) { return a.id == store.state.activeTabId }; return a.lastActive > b.lastActive }.prefix(5)).map(\.id)
            model.recentIndex = 0
            guard model.recentIDs.count > 1 else { model.recentIDs = []; return }
            let panel = NSHostingView(rootView: RecentTabsView(model: model)); panel.safeAreaRegions = []; panel.sizingOptions = []
            auxiliaryPanel = panel; overlayKind = "recent"; layout(); animateIn(panel)
        }
        model.recentIndex = (model.recentIndex+step+model.recentIDs.count)%model.recentIDs.count
    }
    func commitRecent() {
        guard !model.recentIDs.isEmpty else { return }
        guard model.recentIDs.indices.contains(model.recentIndex) else { closeOverlay(); return }
        let id = model.recentIDs[model.recentIndex]; selectTab(id)
    }
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if !flags.contains(.command), !flags.contains(.control), !flags.contains(.option), auxiliaryPanel == nil, (event.keyCode == 125 || event.keyCode == 126), let search = searchModel ?? (home?.isHidden == false ? homeSearch : nil) {
            let count = nativeSuggestions(search.query, store: store).count
            if count > 0 { search.selected = (search.selected+(event.keyCode == 125 ? 1 : -1)+count)%count; return true }
        }
        if flags.contains([.control, .command]), !flags.contains(.option), !flags.contains(.shift), key == "f" { maximizeWindowControl(); return true }
        if flags.contains(.control), !flags.contains(.command), !flags.contains(.option) {
            if event.keyCode == 48 { recent(flags.contains(.shift) ? -1 : 1); return true }
            if !flags.contains(.shift), let number = Int(key), (1...9).contains(number), store.state.spaces.indices.contains(number-1) { selectSpace(store.state.spaces[number-1].id); return true }
        }
        if event.keyCode == 53 { model.dragging = nil; model.dropTarget = nil; if auxiliaryPanel != nil || searchPanel != nil { closeOverlay(); return true }; DerivativeStop(); return false }
        guard flags.contains(.command), !flags.contains(.control) else { return false }
        if flags.contains(.option) {
            guard !flags.contains(.shift) else { return false }
            switch event.keyCode { case 126: stepTab(-1); case 125: stepTab(1); case 123: stepSpace(-1); case 124: stepSpace(1); default: return false }; return true
        }
        if flags.contains(.shift) {
            switch key { case "t": reopenTab(); case "c": perform("copy"); case "r": DerivativeHardReload(); case "{", "[": stepTab(-1); case "}", "]": stepTab(1); default: return false }; return true
        }
        switch key {
        case "t": newSearch()
        case "l": editSearch()
        case "s": toggleSidebar()
        case "w": closeActiveTab()
        case "d": pinActiveTab()
        case "r": reload()
        case "[": back()
        case "]": forward()
        case ",": settings()
        case "q": window.performClose(nil)
        case "1"..."9": let tabs = store.orderedTabs; let index = key == "9" ? tabs.count-1 : (Int(key) ?? 1)-1; if tabs.indices.contains(index) { selectTab(tabs[index].id) }
        default: return false
        }
        return true
    }
}

@_cdecl("DerivativeDownloadUpdate") @MainActor func downloadUpdate(_ id: UnsafePointer<CChar>, _ name: UnsafePointer<CChar>, _ path: UnsafePointer<CChar>, _ status: UnsafePointer<CChar>, _ received: Double, _ total: Double) {
    guard let controller = currentController else { return }
    let identifier = String(cString: id), fullPath = String(cString: path)
    let suggested = String(cString: name)
    let fallback = fullPath.isEmpty ? (controller.model.downloads.first { $0.id == identifier }?.name ?? "Download") : URL(fileURLWithPath: fullPath).lastPathComponent
    let item = BrowserDownload(id: identifier, name: suggested.isEmpty ? fallback : suggested, path: fullPath, status: String(cString: status), received: received, total: total)
    if let index = controller.model.downloads.firstIndex(where: { $0.id == item.id }) { controller.model.downloads[index] = item } else { controller.model.downloads.insert(item, at: 0) }
}
@_cdecl("DerivativeCancelTabClose") @MainActor func cancelTabClose(_ id: UnsafePointer<CChar>) { currentController?.pendingMoves.removeValue(forKey: String(cString: id)) }
@_cdecl("DerivativePageFocused") @MainActor func pageFocused(_ id: UnsafePointer<CChar>) { currentController?.selectTab(String(cString: id)) }

@MainActor final class SplitDivider: NSView {
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override var isOpaque: Bool { false }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityLabel() -> String? { "Resize split view" }
    override func accessibilityRole() -> NSAccessibility.Role? { .splitter }
}

@_cdecl("DerivativeContextAction") @MainActor func contextAction(_ opener: UnsafePointer<CChar>, _ value: UnsafePointer<CChar>, _ kind: UnsafePointer<CChar>) {
    guard let controller = currentController, let tab = controller.store.state.tabs.first(where: { $0.id == String(cString: opener) }) else { return }
    let action = String(cString: kind), input = String(cString: value)
    var url = input
    if action == "search" {
        var parts = URLComponents(string: controller.store.state.preferences.searchEngine == "duckduckgo" ? "https://duckduckgo.com/" : "https://www.google.com/search")!
        parts.queryItems = [URLQueryItem(name: "q", value: input)]; url = parts.url!.absoluteString
    }
    guard let id = controller.store.open(url, spaceId: tab.spaceId) else { return }
    if action == "split" { controller.perform("split.open", ["id": id, "withId": tab.id]) }
    else { controller.showActive() }
}
