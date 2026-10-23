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
            switch command["action"] as? String {
            case "selectSpace": controller.selectSpace(id)
            case "selectTab": controller.selectTab(id)
            case "closeTab": controller.closeTab(id)
            case "search": controller.showSearch(edit: command["edit"] as? Bool ?? false)
            case "dismissSearch": controller.closeSearch()
            case "submit": controller.navigate(command["input"] as? String ?? "", newTab: command["newTab"] as? Bool ?? true)
            case "toggleSidebar": controller.toggleSidebar()
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
            default: break
            }
            controller.root.layoutSubtreeIfNeeded()
            let state = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(controller.store.state))) ?? [:]
            let bounds = controller.pageHost.frame
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { type -> [String: Any]? in
                guard let button = controller.window.standardWindowButton(type) else { return nil }
                return ["bounds": rect(controller.root.convert(button.bounds, from: button)), "hidden": button.isHidden]
            }
            let reply: [String: Any] = [
                "state": state, "loadedPages": DerivativePageCount(),
                "searchOpen": controller.searchPanel != nil, "homeVisible": !controller.home.isHidden,
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
