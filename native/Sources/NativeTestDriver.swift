import AppKit
import Foundation

/// Local integration driver, enabled only by an explicit test-launch environment.
/// Watches a disposable directory; websites receive no access to this interface.
@MainActor final class NativeTestDriver {
    private weak var controller: BrowserController?
    private let directory: URL
    private var source: DispatchSourceFileSystemObject?
    init(directory: URL, controller: BrowserController) {
        self.directory = directory; self.controller = controller
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { return }
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        watcher.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.drain() } }
        watcher.setCancelHandler { close(descriptor) }; source = watcher; watcher.resume(); drain()
    }
    private func drain() {
        guard let controller, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files.filter({ $0.lastPathComponent.hasSuffix(".command.json") }).sorted(by: { $0.path < $1.path }) {
            guard let data = try? Data(contentsOf: file), let command = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            try? FileManager.default.removeItem(at: file)
            let id = command["id"] as? String ?? ""
            var dropOperation = ""
            var keyHandled = false
            switch command["action"] as? String {
            case "selectSpace": controller.selectSpace(id)
            case "selectTab": controller.selectTab(id)
            case "closeTab": controller.closeTab(id)
            case "openFavorite": controller.openFavorite(id)
            case "drop":
                controller.model.dragging = command["token"] as? String
                let drop = SidebarDrop(model: controller.model, kind: command["kind"] as? String ?? "", id: id)
                dropOperation = drop.canDrop ? (drop.operation == .copy ? "copy" : "move") : "none"
                _ = drop.performTokenDrop(y: command["y"] as? Double ?? 0)
                controller.model.dragging = nil
            case "context.closeTools": DerivativeCloseDevTools()
            case "context.command": _ = DerivativeTestContextCommand(Int32(command["command"] as? Int ?? 0))
            case "window.fullscreen": controller.maximizeWindowControl()
            case "window.minimize": controller.windowButtons[1].performClick(nil)
            case "window.restore": controller.window.deminiaturize(nil)
            case "downloads.toggle": controller.model.downloadsExpanded.toggle()
            case "homeQuery": controller.homeSearch.query = command["query"] as? String ?? ""
            case "searchQuery": controller.searchModel?.query = command["query"] as? String ?? ""
            case "search": controller.showSearch(edit: command["edit"] as? Bool ?? false)
            case "dismissSearch": controller.closeSearch()
            case "submit": controller.navigate(command["input"] as? String ?? "", newTab: command["newTab"] as? Bool ?? true)
            case "toggleSidebar": controller.toggleSidebar()
            case "systemControlsReveal":
                for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { controller.window.standardWindowButton(type)?.isHidden = false }
                NSApp.updateWindows()
            case "relayoutTitlebar":
                let titlebar = controller.window.standardWindowButton(.closeButton)?.superview
                titlebar?.needsLayout = true
                titlebar?.layoutSubtreeIfNeeded()
                NSApp.updateWindows()
            case "revealSidebar": controller.setRevealed(command["visible"] as? Bool ?? true)
            case "sidebarSize":
                controller.store.state.preferences.sidebarSize = id
                controller.store.state.preferences.customSidebarWidth = nil
                controller.layout()
            case "fullscreenPhase":
                let notice = Notification(name: NSWindow.didResizeNotification, object: controller.window)
                switch command["phase"] as? String {
                case "entering": controller.windowWillEnterFullScreen(notice)
                case "entered": controller.windowDidEnterFullScreen(notice)
                case "exiting": controller.windowWillExitFullScreen(notice)
                case "exited": controller.windowDidExitFullScreen(notice)
                case "failedEntering": controller.windowDidFailToEnterFullScreen(controller.window)
                default: break
                }
            case "expandedLayout":
                // Exercise fullscreen composition without moving the user's desktop into a Space.
                controller.model.expanded = command["expanded"] as? Bool ?? true
                controller.nativeFullscreen = controller.model.expanded
                controller.model.pinned = !controller.model.expanded
                controller.revealed = false
                controller.layout()
            case "sidebarDrag":
                let handle = controller.sidebarResizeHandle
                guard !handle.isHidden else { break }
                let start = handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil)
                let end = NSPoint(x: start.x+(command["dx"] as? Double ?? 0), y: start.y)
                for (type, point) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)] {
                    if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controller.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                        switch type {
                        case .leftMouseDown: handle.mouseDown(with: event)
                        case .leftMouseDragged: handle.mouseDragged(with: event)
                        default: handle.mouseUp(with: event)
                        }
                    }
                }
            case "sidebarResize":
                if !controller.sidebarResizing { controller.beginSidebarResize() }
                controller.resizeSidebar(rawWidth: CGFloat(command["width"] as? Double ?? 288), finished: command["finished"] as? Bool ?? true)
            case "resize":
                controller.window.setContentSize(NSSize(width: command["width"] as? Double ?? 1280, height: command["height"] as? Double ?? 840))
                controller.layout()
            case "swipe": _ = controller.handleSwipe(dx: command["dx"] as? Double ?? 0, dy: command["dy"] as? Double ?? 0, time: command["time"] as? Double ?? 0, phase: SpaceSwipePhase(rawValue: command["phase"] as? String ?? "") ?? (command["began"] as? Bool == true ? .began : .unphased))
            case "chromiumKey":
                keyHandled = DerivativeTestZoomKey(Int32(command["code"] as? Int ?? 187), command["shift"] as? Bool ?? false, command["command"] as? Bool ?? true, command["option"] as? Bool ?? false)
            case "keyEvent":
                var flags: NSEvent.ModifierFlags = []
                if command["command"] as? Bool ?? true { flags.insert(.command) }
                if command["shift"] as? Bool ?? false { flags.insert(.shift) }
                if command["option"] as? Bool ?? false { flags.insert(.option) }
                let text = command["characters"] as? String ?? "="
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controller.window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: UInt16(command["code"] as? Int ?? 24)) { keyHandled = controller.handleKey(event) }
            case "shortcut": shortcut(Int32(command["key"] as? Int ?? 0))
            case "recent": controller.recent(command["step"] as? Int ?? 1)
            case "commitRecent": controller.commitRecent()
            default:
                var values: [String: String] = [:]
                for (key, value) in command { if let string = value as? String { values[key] = string } }
                controller.perform(command["action"] as? String ?? "", values)
            }
            controller.root.layoutSubtreeIfNeeded()
            let state = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(controller.store.state))) ?? [:]
            let bounds = controller.pageHost.frame
            let buttons = controller.windowButtons.map { button -> [String: Any] in
                let center = controller.root.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
                let hit = controller.root.hitTest(controller.root.convert(center, to: controller.root.superview))
                return ["bounds": rect(controller.root.convert(button.bounds, from: button)), "hidden": button.isHidden, "hitTarget": hit === button]
            }
            let reply: [String: Any] = [
                "displayAddress": controller.model.displayAddress, "keyHandled": keyHandled, "pageZoom": DerivativePageZoom(), "pageMuted": DerivativePageMuted(), "siteControlsOpen": controller.model.siteControlsOpen,
                "devToolsOpen": DerivativeHasDevTools(),
                "contextMenu": (try? JSONSerialization.jsonObject(with: Data(String(cString: DerivativeContextMenuSnapshot()).utf8))) ?? [:],
                "visibleFavoriteIDs": controller.store.currentFavorites.map(\.id), "dropOperation": dropOperation, "favoriteRows": favoriteRowSizes(controller.store.currentFavorites.count),
                "systemControlsHidden": [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { controller.window.standardWindowButton($0)?.isHidden },
                "fullscreenTransitioning": controller.fullscreenTransitioning,
                "windowFullscreen": controller.window.styleMask.contains(.fullScreen), "rootHidden": controller.root.isHidden, "rootAttached": controller.root.window === controller.window,
                "windowMiniaturized": controller.window.isMiniaturized,
                "downloadsExpanded": controller.model.downloadsExpanded, "sidebarTransitioning": controller.sidebarTransitioning,
                "sidebarPresentationX": controller.sidebar.layer?.presentation()?.frame.minX ?? controller.sidebar.frame.minX,
                "splitIDs": controller.model.splitIDs, "overlay": controller.overlayKind,
                "sidebarMode": controller.model.effectiveSidebarMode, "dark": controller.model.dark, "swipeEdge": controller.model.swipeEdge ?? "", "swipeOffset": controller.model.swipeOffset,
                "swipeAnimating": controller.model.swipeOutgoing != nil, "swipePreviewCaptured": controller.swipeCapture != nil,
                "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                "suggestions": nativeSuggestions(command["query"] as? String ?? "", store: controller.store).map { ["id": $0.id, "kind": $0.kind, "url": $0.url] },
                "downloads": controller.model.downloads.map { ["id": $0.id, "path": $0.path, "name": $0.name, "status": $0.status] },
                "pageFrames": controller.pageHost.subviews.filter { $0 !== controller.home && $0 !== controller.splitDivider && !$0.isHidden }.map { rect($0.frame) },
                "state": state, "loadedPages": DerivativePageCount(),
                "searchSelectionLength": (controller.window.firstResponder as? NSTextView)?.selectedRange.length ?? -1,
                "searchBounds": rect(controller.searchPanel?.frame ?? .zero), "searchOpen": controller.searchPanel != nil, "homeVisible": !controller.home.isHidden, "clearingTabs": controller.model.clearingTabs,
                "sidebarVisible": !controller.sidebar.isHidden, "pageBounds": rect(bounds),
                "rootBounds": rect(controller.root.bounds), "sidebarBounds": rect(controller.sidebar.frame),
                "sidebarResizeBounds": rect(controller.sidebarResizeHandle.frame), "sidebarResizeHidden": controller.sidebarResizeHandle.isHidden,
                "sidebarResizeHitTarget": controller.root.hitTest(NSPoint(x: controller.sidebarResizeHandle.frame.midX, y: controller.sidebarResizeHandle.frame.midY)) === controller.sidebarResizeHandle,
                "sidebarResizing": controller.sidebarResizing, "pageCornerRadius": controller.pageHost.layer?.cornerRadius ?? 0,
                "sidebarControls": controls(in: controller.sidebar, controller: controller), "windowButtons": buttons
            ]
            let result = directory.appendingPathComponent(file.lastPathComponent.replacingOccurrences(of: ".command.json", with: ".result.json"))
            if let data = try? JSONSerialization.data(withJSONObject: reply) { try? data.write(to: result, options: .atomic) }
            if command["action"] as? String == "quit" { controller.window.performClose(nil) }
        }
    }
    private func rect(_ value: NSRect) -> [String: CGFloat] {
        ["x": value.minX, "y": value.minY, "width": value.width, "height": value.height]
    }
    private func controls(in view: NSView, controller: BrowserController) -> [[String: Any]] {
        var result: [[String: Any]] = []
        if let id = view.identifier?.rawValue, id == "sidebar-header-layout" || id.hasPrefix("sidebar-tab-") {
            result.append(["label": id == "sidebar-header-layout" ? "header" : id, "bounds": rect(controller.root.convert(view.bounds, from: view))])
        }
        for child in view.subviews {
            result += controls(in: child, controller: controller)
        }
        return result
    }
    deinit { source?.cancel() }
}
