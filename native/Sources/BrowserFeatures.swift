import AppKit
import SwiftUI

@MainActor extension BrowserController {
    func clearCurrentSpaceTabs() {
        guard !model.clearingTabs else { return }
        let tabs = store.currentTabs.filter { !$0.pinned && $0.favoriteId == nil }
        guard !tabs.isEmpty else { return }
        clearingSpaceID = store.state.activeSpaceId
        // Close the active tab last so lazy/background tabs are never opened just to close them.
        clearTabQueue = tabs.filter { $0.id != store.state.activeTabId }.map(\.id) + tabs.filter { $0.id == store.state.activeTabId }.map(\.id)
        model.clearingTabs = true; advanceClearingTabs()
    }
    private func advanceClearingTabs() {
        while !clearTabQueue.isEmpty {
            let id = clearTabQueue.removeFirst()
            guard let tab = store.state.tabs.first(where: { $0.id == id }), tab.spaceId == clearingSpaceID, !tab.pinned, tab.favoriteId == nil else { continue }
            clearingTabID = id; closeTab(id); return
        }
        clearingTabID = nil; clearingSpaceID = nil; model.clearingTabs = false
    }
    func finishClearingTab(_ id: String) {
        guard clearingTabID == id else { return }
        clearingTabID = nil
        DispatchQueue.main.async { [weak self] in self?.advanceClearingTabs() }
    }
    func cancelClearingTabs(_ id: String) {
        guard clearingTabID == id else { return }
        clearTabQueue = []; clearingTabID = nil; clearingSpaceID = nil; model.clearingTabs = false
    }
    func setPageZoom(_ percent: Int) {
        let value = min(300, max(25, percent))
        DerivativeSetPageZoom(Int32(value)); model.pageZoom = value
    }
    @objc func zoomInPage() { setPageZoom(PageZoom.next(Int(DerivativePageZoom()), direction: 1)) }
    @objc func zoomOutPage() { setPageZoom(PageZoom.next(Int(DerivativePageZoom()), direction: -1)) }
    @objc func resetPageZoom() { setPageZoom(100) }
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
        window.backgroundColor = NSColor(model.surface)
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
        case "page.zoom": if let percent = Int(values["percent"] ?? "") { setPageZoom(percent) }
        case "page.mute": DerivativeSetPageMuted(values["muted"] == "true")
        case "sidebar.toggle": toggleSidebar()
        case "tabs.clear": clearCurrentSpaceTabs()
        case "favorite.edit":
            let favorite = store.state.favorites.first { $0.id == id }
            prompt(favorite == nil ? "Add favorite" : "Edit favorite", fields: [("Name", favorite?.name ?? store.active?.title ?? ""), ("Website address", favorite?.url ?? store.active?.url ?? "")]) { [weak self] fields in self?.store.saveFavorite(id: favorite?.id, name: fields[0], input: fields[1]) }
        case "favorite.toToday": favoriteToToday(id)
        case "favorite.close":
            if let tab = store.currentTabs.first(where: { $0.favoriteId == id }) { closeTab(tab.id) }
        case "favorite.save": store.saveFavorite(id: id.isEmpty ? nil : id, name: values["name"] ?? "", input: values["url"] ?? "")
        case "favorite.delete": store.deleteFavorite(id)
        case "favorite.reorder": store.reorderFavorite(id, before: values["beforeId"])
        case "favorite.move": _ = store.moveFavorite(id, to: values["spaceId"] ?? "")
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
        case "space.color": if let index = store.state.spaces.firstIndex(where: { $0.id == id }), let color = values["color"], ["lavender", "mint", "peach", "blue", "blush"].contains(color) { store.state.spaces[index].color = color; store.persist(); applyPreferences() }
        case "space.reorder": store.reorderSpace(id, before: values["beforeId"] ?? "")
        case "split.open":
            guard let base = store.state.tabs.first(where: { $0.id == (values["withId"] ?? store.state.activeTabId) }), let other = store.state.tabs.first(where: { $0.id == id }), base.id != id, base.spaceId == other.spaceId else { return }
            if let folder = store.state.folders.firstIndex(where: { $0.id == base.folderId }) { store.state.folders[folder].collapsed = false }
            model.splitIDs = [base.id, other.id]; store.select(base.id); splitRatio = 0.5; showActive()
        case "split.close": model.splitIDs = []; showActive()
        case "split.ratio": splitRatio = min(0.8, max(0.2, Double(values["ratio"] ?? "") ?? 0.5)); showActive(preserveSearch: true)
        case "preferences":
            if let side = values["sidebarSide"], ["left", "right"].contains(side), store.state.preferences.sidebarSide != side {
                hideWork?.cancel(); hideWork = nil
                sidebarAnimation += 1; sidebar.layer?.removeAllAnimations()
                sidebarTransitioning = false; sidebarHiding = false
                store.state.preferences.sidebarSide = side
            }
            if let value = values["theme"], ["system", "light", "dark"].contains(value) { store.state.preferences.theme = value }
            if let value = values["sidebarSize"], ["compact", "comfortable", "wide"].contains(value) { store.state.preferences.sidebarSize = value; store.state.preferences.customSidebarWidth = nil }
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
    func handleSidebarScroll(_ event: NSEvent, point: NSPoint) -> Bool {
        guard !sidebarResizing else { return false }
        let phase: SpaceSwipePhase
        if !event.momentumPhase.isEmpty {
            phase = event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) ? .momentumEnded : .momentum
        } else if event.phase.contains(.cancelled) { phase = .cancelled }
        else if event.phase.contains(.ended) { phase = .ended }
        else if event.phase.contains(.began) || event.phase.contains(.mayBegin) { phase = .began }
        else if event.phase.contains(.changed) || event.phase.contains(.stationary) { phase = .changed }
        else { phase = .unphased }
        let available = !sidebar.isHidden && auxiliaryPanel == nil && searchPanel == nil && !model.siteControlsOpen && !model.downloadsExpanded && model.dragging == nil && window.attachedSheet == nil
        let inside = sidebar.frame.contains(point)
        if !available || (phase == .began && !inside) {
            if swipe.tracking || swipe.consumesMomentum || model.swipeOffset != 0 || model.swipeEdge != nil {
                swipe = SpaceSwipe(); settleSwipe()
            }
            return false
        }
        guard inside || swipe.tracking || swipe.consumesMomentum else { return false }
        return handleSwipe(dx: -event.scrollingDeltaX, dy: -event.scrollingDeltaY, time: event.timestamp, phase: phase)
    }
    func settleSwipe() {
        swipeReset?.cancel()
        swipeCapture = nil
        if model.swipeOutgoing == nil {
            withAnimation(swipeAnimation) { model.swipeOffset = 0 }
        }
        let work = DispatchWorkItem { [weak self] in self?.model.swipeEdge = nil }
        swipeReset = work; DispatchQueue.main.asyncAfter(deadline: .now()+0.4, execute: work)
        let pointer = root.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if !model.pinned && !sidebar.frame.contains(pointer) { scheduleHide() }
    }
    var swipeAnimation: Animation {
        .timingCurve(0.2, 0.75, 0.25, 1, duration: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.30)
    }
    func captureSpaceForSwipe() -> (image: NSImage, origin: CGPoint)? {
        func anchor(_ id: String, in view: NSView) -> NSView? {
            if view.identifier?.rawValue == id { return view }
            for child in view.subviews { if let found = anchor(id, in: child) { return found } }
            return nil
        }
        guard let content = anchor("sidebar-space-content", in: sidebarContent),
              let viewport = anchor("sidebar-space-viewport", in: sidebarContent) else { return nil }
        let contentRect = sidebarContent.convert(content.bounds, from: content)
        let rect = contentRect.intersection(sidebarContent.convert(viewport.bounds, from: viewport)).intersection(sidebarContent.bounds)
        guard !rect.isEmpty, let bitmap = sidebarContent.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        sidebarContent.cacheDisplay(in: rect, to: bitmap)
        let image = NSImage(size: rect.size); image.addRepresentation(bitmap)
        return (image, CGPoint(x: rect.minX-contentRect.minX, y: rect.minY-contentRect.minY))
    }
    func animateSpaceSwipe(to id: String, direction: Int, offset: CGFloat) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let distance = sidebar.bounds.width-16
        swipeTransition += 1
        let generation = swipeTransition
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.swipeOutgoing = reduceMotion ? nil : swipeCapture?.image
            model.swipeOutgoingOrigin = swipeCapture?.origin ?? .zero
            model.swipeOutgoingOffset = offset
            model.swipeOffset = reduceMotion ? 0 : CGFloat(direction)*distance + offset
            selectSpace(id, duringSwipe: true)
        }
        swipeCapture = nil
        // Give the incoming content one layout pass at its starting position.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.swipeTransition == generation else { return }
            withAnimation(self.swipeAnimation) {
                self.model.swipeOffset = 0
                self.model.swipeOutgoingOffset = -CGFloat(direction)*distance
            }
            DispatchQueue.main.asyncAfter(deadline: .now()+0.32) { [weak self] in
                guard let self, self.swipeTransition == generation else { return }
                self.model.swipeOutgoing = nil
            }
        }
    }
    func handleSwipe(dx: Double, dy: Double, time: Double, phase: SpaceSwipePhase) -> Bool {
        let index = store.state.spaces.firstIndex { $0.id == store.state.activeSpaceId } ?? 0
        let result = swipe.update(dx: dx, dy: dy, time: time, index: index, count: store.state.spaces.count, phase: phase)
        if phase == .ended || phase == .cancelled || phase == .momentumEnded { settleSwipe(); return result.consumed }
        if phase == .momentum { return result.consumed }
        if phase == .began {
            swipeTransition += 1; swipeCapture = nil; model.swipeOutgoing = nil
            swipeReset?.cancel(); model.swipeEdge = nil; model.swipeOffset = 0
        }
        swipeReset?.cancel()
        if phase == .unphased {
            let work = DispatchWorkItem { [weak self] in self?.swipe = SpaceSwipe(); self?.settleSwipe() }
            swipeReset = work; DispatchQueue.main.asyncAfter(deadline: .now()+0.25, execute: work)
        }
        guard result.consumed else { return false }
        hideWork?.cancel(); hideWork = nil
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !reduceMotion && swipeCapture == nil && (!swipe.committed || result.step != 0) { swipeCapture = captureSpaceForSwipe() }
        if !swipe.committed { model.swipeOffset = reduceMotion ? 0 : result.offset; model.swipeEdge = result.edge }
        if result.step != 0 {
            model.swipeEdge = nil
            animateSpaceSwipe(to: store.state.spaces[index+result.step].id, direction: result.step, offset: reduceMotion ? 0 : result.offset)
        }
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
        if !flags.contains(.option) {
            if key == "=" || key == "+" || event.keyCode == 69 { zoomInPage(); return true }
            if key == "-" || event.keyCode == 78 { zoomOutPage(); return true }
            if !flags.contains(.shift), key == "0" || event.keyCode == 82 { resetPageZoom(); return true }
        }
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
@_cdecl("DerivativeCancelTabClose") @MainActor func cancelTabClose(_ id: UnsafePointer<CChar>) {
    let value = String(cString: id)
    currentController?.pendingMoves.removeValue(forKey: value)
    currentController?.cancelClearingTabs(value)
}
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
