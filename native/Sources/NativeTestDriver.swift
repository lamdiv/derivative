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
            switch command["action"] as? String {
            case "selectSpace": controller.selectSpace(id)
            case "selectTab": controller.selectTab(id)
            case "closeTab": controller.closeTab(id)
            case "drop":
                controller.model.dragging = command["token"] as? String
                let drop = SidebarDrop(model: controller.model, kind: command["kind"] as? String ?? "", id: id)
                dropOperation = drop.canDrop ? (drop.operation == .copy ? "copy" : "move") : "none"
                _ = drop.performTokenDrop(y: command["y"] as? Double ?? 0)
                controller.model.dragging = nil
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
            case "relayoutTitlebar":
                let titlebar = controller.window.standardWindowButton(.closeButton)?.superview
                titlebar?.needsLayout = true
                titlebar?.layoutSubtreeIfNeeded()
                NSApp.updateWindows()
            case "revealSidebar": controller.setRevealed(command["visible"] as? Bool ?? true)
            case "sidebarSize":
                controller.store.state.preferences.sidebarSize = id
                controller.layout()
            case "expandedLayout":
                // Exercise fullscreen composition without moving the user's desktop into a Space.
                controller.model.expanded = command["expanded"] as? Bool ?? true
                controller.model.pinned = !controller.model.expanded
                controller.revealed = false
                controller.layout()
            case "resize":
                controller.window.setContentSize(NSSize(width: command["width"] as? Double ?? 1280, height: command["height"] as? Double ?? 840))
                controller.layout()
            case "swipe": _ = controller.handleSwipe(dx: command["dx"] as? Double ?? 0, dy: command["dy"] as? Double ?? 0, time: command["time"] as? Double ?? 0, began: command["began"] as? Bool ?? false)
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
                "dropOperation": dropOperation, "favoriteRows": favoriteRowSizes(controller.store.state.favorites.count),
                "windowFullscreen": controller.window.styleMask.contains(.fullScreen), "rootHidden": controller.root.isHidden, "rootAttached": controller.root.window === controller.window,
                "windowMiniaturized": controller.window.isMiniaturized,
                "downloadsExpanded": controller.model.downloadsExpanded, "sidebarTransitioning": controller.sidebarTransitioning,
                "sidebarPresentationX": controller.sidebar.layer?.presentation()?.frame.minX ?? controller.sidebar.frame.minX,
                "splitIDs": controller.model.splitIDs, "overlay": controller.overlayKind,
                "sidebarMode": controller.model.effectiveSidebarMode, "dark": controller.model.dark, "swipeEdge": controller.model.swipeEdge ?? "", "swipeOffset": controller.model.swipeOffset,
                "suggestions": nativeSuggestions(command["query"] as? String ?? "", store: controller.store).map { ["id": $0.id, "kind": $0.kind, "url": $0.url] },
                "downloads": controller.model.downloads.map { ["id": $0.id, "path": $0.path, "name": $0.name, "status": $0.status] },
                "pageFrames": controller.pageHost.subviews.filter { $0 !== controller.home && $0 !== controller.splitDivider && !$0.isHidden }.map { rect($0.frame) },
                "state": state, "loadedPages": DerivativePageCount(),
                "searchBounds": rect(controller.searchPanel?.frame ?? .zero), "searchOpen": controller.searchPanel != nil, "homeVisible": !controller.home.isHidden,
                "sidebarVisible": !controller.sidebar.isHidden, "pageBounds": rect(bounds),
                "rootBounds": rect(controller.root.bounds), "sidebarBounds": rect(controller.sidebar.frame),
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
        if view.identifier?.rawValue == "sidebar-header-layout" {
            result.append(["label": "header", "bounds": rect(controller.root.convert(view.bounds, from: view))])
        }
        for child in view.subviews {
            result += controls(in: child, controller: controller)
        }
        return result
    }
    deinit { source?.cancel() }
}
