import Foundation

@main struct StateTests {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DerivativeStateTests-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserStore(directory: directory)
        let personal = store.open("https://example.com/")!
        store.selectSpace("work")
        assert(store.active == nil && store.currentTabs.isEmpty)
        let work = store.open("https://example.com/work")!
        store.select(personal)
        assert(store.state.activeSpaceId == "personal" && store.currentTabs.map(\.id) == [personal])
        store.update(personal, title: "Personal", url: "https://example.com/", loading: false, back: false, forward: false)
        store.flush()
        let restored = BrowserStore(directory: directory)
        assert(restored.state.activeTabId == personal && restored.state.tabs.count == 2)
        assert(restored.active?.title == "Personal" && restored.state.history.count == 1)
        restored.selectSpace("work"); assert(restored.active?.id == work)
        restored.remove(work); assert(restored.active == nil && restored.state.tabs.count == 1)
        assert(restored.open("javascript:alert(1)") == nil)
        assert(SavedBrowserState.resolve("file:///tmp/private", engine: "google") == nil)
        assert(SavedBrowserState.resolve("localhost:8123", engine: "google")?.absoluteString == "http://localhost:8123")
        assert(SavedBrowserState.resolve("two words", engine: "duckduckgo")?.host == "duckduckgo.com")
        var dirty = restored.state
        dirty.spaces.append(BrowserSpace(id: "../unsafe", name: "Bad", icon: "", color: ""))
        dirty.tabs.append(BrowserTab(id: "invalid", spaceId: "missing", url: "https://example.com/", title: "Invalid", lastActive: 0))
        dirty.activeSpaceId = "missing"; dirty.activeTabId = "invalid"
        dirty.sanitize()
        assert(!dirty.spaces.contains { $0.id == "../unsafe" } && !dirty.tabs.contains { $0.id == "invalid" })
        assert(dirty.activeSpaceId == "personal" && dirty.activeTabId == personal)
        dirty.preferences.restoreSession = false
        try JSONEncoder().encode(dirty).write(to: restored.file, options: .atomic)
        assert(BrowserStore(directory: directory).state.tabs.isEmpty)
        try Data("broken".utf8).write(to: restored.file, options: .atomic)
        assert(BrowserStore(directory: directory).state.spaces.count == 3)
        print("PASS: native tab/Space selection, restoration, isolated empty Spaces, URL validation, sanitization, and atomic metadata.")
    }
}
