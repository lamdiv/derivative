import Foundation
import Combine

struct BrowserSpace: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var icon: String
    var color: String
}
struct BrowserFavorite: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var url: String
    var spaceId: String? = nil
}
struct BrowserFolder: Codable, Identifiable, Equatable {
    var id: String
    var spaceId: String
    var name: String
    var collapsed = false
}
struct BrowserTab: Codable, Identifiable, Equatable {
    var id: String
    var spaceId: String
    var url: String
    var title: String
    var pinned = false
    var favoriteId: String?
    var folderId: String?
    var lastActive: Double
    var loading = false
    var canBack = false
    var canForward = false
    var error: String?
    enum CodingKeys: String, CodingKey { case id, spaceId, url, title, pinned, favoriteId, folderId, lastActive }
}
struct BrowserHistory: Codable, Equatable {
    var url: String
    var title: String
    var visitedAt: Double
}
struct BrowserPreferences: Codable, Equatable {
    var theme = "system"
    var sidebarMode = "fixed"
    var sidebarSize = "comfortable"
    var sidebarSide: String? = nil
    var sidebarOnRight: Bool { sidebarSide == "right" }
    var customSidebarWidth: Double? = nil
    var restoreSession = true
    var searchEngine = "google"
    var sidebarWidth: CGFloat { CGFloat(customSidebarWidth ?? (sidebarSize == "compact" ? 252 : sidebarSize == "wide" ? 320 : 288)) }
}
enum PageZoom {
    static let steps = [25, 50, 67, 75, 80, 90, 100, 110, 125, 150, 175, 200, 250, 300]
    static func next(_ current: Int, direction: Int) -> Int {
        direction > 0 ? (steps.first { $0 > current } ?? 300) : (steps.last { $0 < current } ?? 25)
    }
}
enum SidebarSizing {
    static let minimum: CGFloat = 220
    static let collapseThreshold: CGFloat = 132
    static func width(_ preferred: CGFloat, available: CGFloat) -> CGFloat {
        min(max(minimum, preferred), max(minimum, available * 2 / 3))
    }
}
struct SavedBrowserState: Codable, Equatable {
    var version = 2
    var spaces = [BrowserSpace(id: "personal", name: "Personal", icon: "camera.macro", color: "lavender"), BrowserSpace(id: "work", name: "Work", icon: "diamond", color: "mint"), BrowserSpace(id: "study", name: "Study", icon: "sun.max", color: "peach")]
    var tabs: [BrowserTab] = []
    var folders: [BrowserFolder] = []
    static let defaultFavorites = [
        BrowserFavorite(id: "github", name: "GitHub", url: "https://github.com/lamdiv/derivative"),
        BrowserFavorite(id: "derivative", name: "Derivative", url: "https://derivativebrowser.com/"),
        BrowserFavorite(id: "youtube", name: "YouTube", url: "https://www.youtube.com/")
    ]
    var favorites = Self.defaultFavorites
    var history: [BrowserHistory] = []
    var activeSpaceId = "personal"
    var activeTabId: String?
    var preferences = BrowserPreferences()

    /// Replace only the complete, unedited starter collection. Custom collections stay intact.
    @discardableResult mutating func updateLegacyDefaultFavorites() -> Bool {
        let legacy = ["GitHub": "https://github.com/", "Wikipedia": "https://wikipedia.org/", "Are.na": "https://www.are.na/", "YouTube": "https://www.youtube.com/", "Reddit": "https://www.reddit.com/", "Figma": "https://www.figma.com/", "Notion": "https://www.notion.so/", "Gmail": "https://mail.google.com/", "Calendar": "https://calendar.google.com/"]
        let collections = Dictionary(grouping: favorites, by: \.spaceId)
        var changed = false
        for (owner, collection) in collections {
            guard collection.count == legacy.count, Set(collection.map(\.name)).count == legacy.count,
                  collection.allSatisfy({ legacy[$0.name] == $0.url }) else { continue }
            let replacements = Self.defaultFavorites.map { template -> BrowserFavorite in
                var item = template; item.spaceId = owner
                item.id = collection.first(where: { $0.name == template.name })?.id ?? UUID().uuidString
                return item
            }
            let oldIDs = Set(collection.map(\.id))
            for index in tabs.indices where tabs[index].favoriteId.map(oldIDs.contains) == true {
                if !replacements.contains(where: { $0.id == tabs[index].favoriteId && $0.url == tabs[index].url }) {
                    tabs[index].favoriteId = nil
                }
            }
            favorites.removeAll { $0.spaceId == owner }; favorites.append(contentsOf: replacements); changed = true
        }
        return changed
    }

    mutating func sanitize() {
        let validID: (String) -> Bool = { !$0.isEmpty && $0.count <= 80 && $0.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil }
        func unique<T>(_ values: [T], id: (T) -> String) -> [T] {
            var seen = Set<String>(); return values.filter { seen.insert(id($0)).inserted }
        }
        spaces = unique(Array(spaces.filter { validID($0.id) && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.prefix(30)), id: { $0.id })
        if spaces.isEmpty { spaces = SavedBrowserState().spaces }
        let spaceIDs = Set(spaces.map(\.id))
        if !spaceIDs.contains(activeSpaceId) { activeSpaceId = spaces[0].id }
        var scoped: [BrowserFavorite] = []
        var counts: [String: Int] = [:]
        var migrated: [String: [String: String]] = [:]
        for favorite in unique(favorites.filter { validID($0.id) && Self.webURL($0.url) != nil }, id: { $0.id }) {
            let owners = favorite.spaceId.map { [$0] } ?? spaces.map(\.id)
            for owner in owners where spaceIDs.contains(owner) && counts[owner, default: 0] < 12 {
                var copy = favorite; copy.spaceId = owner
                if favorite.spaceId == nil {
                    if owner != activeSpaceId { copy.id = UUID().uuidString }
                    migrated[favorite.id, default: [:]][owner] = copy.id
                }
                scoped.append(copy); counts[owner, default: 0] += 1
            }
        }
        favorites = scoped; version = 2
        folders = unique(folders.filter { validID($0.id) && spaceIDs.contains($0.spaceId) }, id: { $0.id })
        tabs = unique(tabs.filter { validID($0.id) && spaceIDs.contains($0.spaceId) && Self.webURL($0.url) != nil }, id: { $0.id })
        for index in tabs.indices {
            if let id = tabs[index].favoriteId {
                let mapped = migrated[id]?[tabs[index].spaceId] ?? id
                tabs[index].favoriteId = favorites.contains { $0.id == mapped && $0.spaceId == tabs[index].spaceId } ? mapped : nil
            }
            if let id = tabs[index].folderId, !folders.contains(where: { $0.id == id && $0.spaceId == tabs[index].spaceId }) { tabs[index].folderId = nil }
        }
        if !tabs.contains(where: { $0.id == activeTabId && $0.spaceId == activeSpaceId }) {
            activeTabId = tabs.filter { $0.spaceId == activeSpaceId }.max(by: { $0.lastActive < $1.lastActive })?.id
        }
        history = Array(history.filter { Self.webURL($0.url) != nil }.prefix(2000))
        if !["system", "light", "dark"].contains(preferences.theme) { preferences.theme = "system" }
        if !["fixed", "hover", "hidden"].contains(preferences.sidebarMode) { preferences.sidebarMode = "fixed" }
        if !["compact", "comfortable", "wide"].contains(preferences.sidebarSize) { preferences.sidebarSize = "comfortable" }
        if let side = preferences.sidebarSide, !["left", "right"].contains(side) { preferences.sidebarSide = nil }
        if let width = preferences.customSidebarWidth, !width.isFinite || width < Double(SidebarSizing.minimum) { preferences.customSidebarWidth = nil }
        if !["google", "duckduckgo"].contains(preferences.searchEngine) { preferences.searchEngine = "google" }
    }
    static func displayAddress(_ text: String) -> String {
        guard let parts = URLComponents(string: text), var host = parts.host, !host.isEmpty else { return text }
        if host.lowercased().hasPrefix("www.") { host = String(host.dropFirst(4)) }
        return host + (parts.port.map { ":\($0)" } ?? "")
    }
    static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, !host.isEmpty else { return nil }
        return url
    }
    static func resolve(_ input: String, engine: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) != nil && !value.hasPrefix("localhost:") && value.range(of: "^[^/:]+\\.[^/:]+:[0-9]+", options: .regularExpression) == nil {
            return webURL(value)
        }
        if !value.contains(where: \.isWhitespace) && (value.contains(".") || value.hasPrefix("localhost")) {
            return webURL((value.hasPrefix("localhost") || value.hasPrefix("127.0.0.1") ? "http://" : "https://") + value)
        }
        var url = URLComponents(string: engine == "duckduckgo" ? "https://duckduckgo.com/" : "https://www.google.com/search")!
        url.queryItems = [URLQueryItem(name: "q", value: value)]
        return url.url
    }
}

@MainActor final class BrowserStore: ObservableObject {
    @Published var state: SavedBrowserState
    let file: URL
    private let writes = DispatchQueue(label: "app.derivative.native.metadata")
    private var pending: DispatchWorkItem?
    var active: BrowserTab? { state.tabs.first { $0.id == state.activeTabId } }
    var space: BrowserSpace { state.spaces.first { $0.id == state.activeSpaceId } ?? state.spaces[0] }
    var currentTabs: [BrowserTab] { state.tabs.filter { $0.spaceId == state.activeSpaceId } }
    var currentFavorites: [BrowserFavorite] { favorites(in: state.activeSpaceId) }
    func favorites(in space: String) -> [BrowserFavorite] { state.favorites.filter { $0.spaceId == space } }
    init(directory: URL) {
        file = directory.appendingPathComponent("native-state.json")
        if let data = try? Data(contentsOf: file), var saved = try? JSONDecoder().decode(SavedBrowserState.self, from: data), [1, 2].contains(saved.version) {
            if saved.favorites.contains(where: { $0.spaceId == nil }) {
                let backup = directory.appendingPathComponent("native-state-before-space-favorites.json")
                if !FileManager.default.fileExists(atPath: backup.path) { try? FileManager.default.copyItem(at: file, to: backup) }
            }
            if saved.updateLegacyDefaultFavorites() {
                let backup = directory.appendingPathComponent("native-state-before-default-favorites.json")
                if !FileManager.default.fileExists(atPath: backup.path) { try? FileManager.default.copyItem(at: file, to: backup) }
            }
            saved.sanitize()
            if !saved.preferences.restoreSession { saved.tabs = []; saved.activeTabId = nil }
            state = saved
        } else { state = SavedBrowserState(); state.sanitize() }
    }
    func persist() {
        pending?.cancel()
        guard let data = try? JSONEncoder().encode(state) else { return }
        let file = file
        let work = DispatchWorkItem {
            do { try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true); try data.write(to: file, options: .atomic) }
            catch { NSLog("Derivative metadata: %@", error.localizedDescription) }
        }
        pending = work; writes.asyncAfter(deadline: .now()+0.2, execute: work)
    }
    func flush() {
        pending?.cancel()
        let snapshot = state; let file = file
        writes.sync {
            do { try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true); try JSONEncoder().encode(snapshot).write(to: file, options: .atomic) }
            catch { NSLog("Derivative metadata: %@", error.localizedDescription) }
        }
    }
    @discardableResult func open(_ url: String, spaceId: String? = nil, favoriteId: String? = nil) -> String? {
        let space = spaceId ?? state.activeSpaceId
        guard SavedBrowserState.webURL(url) != nil, state.spaces.contains(where: { $0.id == space }) else { return nil }
        let ownedFavorite = favoriteId.flatMap { id in state.favorites.contains { $0.id == id && $0.spaceId == space } ? id : nil }
        let tab = BrowserTab(id: UUID().uuidString, spaceId: space, url: url, title: URL(string: url)?.host ?? url, favoriteId: ownedFavorite, lastActive: Date().timeIntervalSince1970)
        state.tabs.append(tab); select(tab.id); return tab.id
    }
    func select(_ id: String) {
        guard let index = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        state.activeTabId = id; state.activeSpaceId = state.tabs[index].spaceId
        state.tabs[index].lastActive = Date().timeIntervalSince1970; persist()
    }
    func selectSpace(_ id: String) {
        guard state.spaces.contains(where: { $0.id == id }) else { return }
        state.activeSpaceId = id
        state.activeTabId = state.tabs.filter { $0.spaceId == id }.max(by: { $0.lastActive < $1.lastActive })?.id
        persist()
    }
    func remove(_ id: String) {
        guard let index = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        state.tabs.remove(at: index)
        if state.activeTabId == id {
            let nearby = currentTabs
            state.activeTabId = nearby.max(by: { $0.lastActive < $1.lastActive })?.id
        }
        persist()
    }
    func update(_ id: String, title: String, url: String, loading: Bool, back: Bool, forward: Bool) {
        guard let index = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        state.tabs[index].title = title; state.tabs[index].loading = loading
        state.tabs[index].canBack = back; state.tabs[index].canForward = forward
        if SavedBrowserState.webURL(url) != nil { state.tabs[index].url = url }
        if !loading && SavedBrowserState.webURL(url) != nil {
            state.history.removeAll { $0.url == url }
            state.history.insert(BrowserHistory(url: url, title: title, visitedAt: Date().timeIntervalSince1970), at: 0)
            state.history = Array(state.history.prefix(2000)); persist()
        }
    }
}
