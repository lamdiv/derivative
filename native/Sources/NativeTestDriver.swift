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
            default: break
            }
            let state = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(controller.store.state))) ?? [:]
            let bounds = controller.pageHost.frame
            let reply: [String: Any] = ["state": state, "loadedPages": DerivativePageCount(), "searchOpen": controller.searchPanel != nil, "homeVisible": !controller.home.isHidden, "sidebarVisible": !controller.sidebar.isHidden, "pageBounds": ["x": bounds.minX, "y": bounds.minY, "width": bounds.width, "height": bounds.height]]
            let result = directory.appendingPathComponent(file.lastPathComponent.replacingOccurrences(of: ".command.json", with: ".result.json"))
            if let data = try? JSONSerialization.data(withJSONObject: reply) { try? data.write(to: result, options: .atomic) }
            if command["action"] as? String == "quit" { controller.window.performClose(nil) }
        }
    }
    deinit { source?.cancel() }
}
