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
        restored.select(personal)
        restored.createFolder(name: "Reading")
        let folder = restored.state.folders.last!.id
        restored.placeTab(personal, space: "personal", pinned: false, folder: folder)
        assert(restored.active?.pinned == true && restored.active?.folderId == folder)
        restored.toggleFolder(folder); assert(restored.state.folders.last!.collapsed)
        restored.renameFolder(folder, name: "Read later"); assert(restored.state.folders.last!.name == "Read later")
        restored.deleteFolder(folder); assert(restored.active?.folderId == nil && restored.active?.pinned == true)
        let before = restored.state
        restored.placeTab(personal, space: "missing", pinned: true)
        assert(restored.state == before)
        restored.saveFavorite(name: "Test", input: "example.org")
        let favorite = restored.state.favorites.last!.id
        restored.reorderFavorite(favorite, before: restored.state.favorites.first!.id)
        assert(restored.state.favorites.first!.id == favorite)
        restored.saveFavorite(id: favorite, name: "Updated", input: "https://example.org/new")
        assert(restored.state.favorites.first!.name == "Updated")
        restored.deleteFavorite(favorite); assert(!restored.state.favorites.contains { $0.id == favorite })
        restored.createSpace(name: "Art", color: "blush", icon: "✿")
        let art = restored.state.spaces.last!.id
        restored.reorderSpace(art, before: "personal"); assert(restored.state.spaces.first!.id == art)
        restored.renameSpace(art, name: "Studio"); assert(restored.state.spaces.first!.name == "Studio")
        restored.deleteSpace("personal"); assert(restored.state.spaces.contains { $0.id == "personal" })
        restored.deleteSpace(art); assert(!restored.state.spaces.contains { $0.id == art })
        assert(favoriteRowSizes(2) == [2])
        assert(favoriteRowSizes(4) == [2, 2])
        assert(favoriteRowSizes(8) == [3, 3, 2])
        assert(favoriteRowSizes(12) == [3, 3, 3, 3])
        var swipe = SpaceSwipe()
        assert(swipe.update(dx: 1, dy: 40, time: 1, index: 0, count: 3).consumed == false)
        assert(swipe.update(dx: 80, dy: 0, time: 1.01, index: 0, count: 3).consumed == false)
        assert(swipe.update(dx: 60, dy: 0, time: 2, index: 0, count: 3).step == 1)
        assert(swipe.update(dx: 80, dy: 0, time: 2.02, index: 1, count: 3).step == 0)
        assert(swipe.update(dx: -60, dy: 0, time: 2.03, index: 1, count: 3).step == 0)
        assert(swipe.update(dx: -80, dy: 0, time: 3, index: 0, count: 3).edge == "First Space")
        // A finger pause and a direction reversal must not become new swipes.
        swipe = SpaceSwipe()
        assert(swipe.update(dx: 30, dy: 1, time: 4, index: 0, count: 3, phase: .began).step == 0)
        assert(swipe.update(dx: 30, dy: 0, time: 5, index: 0, count: 3, phase: .changed).step == 1)
        assert(swipe.update(dx: -100, dy: 0, time: 6, index: 1, count: 3, phase: .changed).step == 0)
        assert(swipe.update(dx: 0, dy: 0, time: 6.01, index: 1, count: 3, phase: .ended).consumed)
        assert(swipe.update(dx: 200, dy: 0, time: 6.02, index: 1, count: 3, phase: .momentum).step == 0)
        assert(swipe.update(dx: -60, dy: 0, time: 6.03, index: 1, count: 3, phase: .began).step == -1)
        // Gestures beginning on a webpage must not be acquired on sidebar entry.
        swipe = SpaceSwipe()
        assert(!swipe.update(dx: 200, dy: 0, time: 7, index: 0, count: 3, phase: .changed).consumed)
        assert(!swipe.update(dx: 200, dy: 0, time: 7.1, index: 0, count: 3, phase: .momentum).consumed)
        // Vertical intent remains vertical even after a long pause or diagonal tail.
        assert(!swipe.update(dx: 2, dy: 20, time: 8, index: 0, count: 3, phase: .began).consumed)
        assert(!swipe.update(dx: 100, dy: 0, time: 9, index: 0, count: 3, phase: .changed).consumed)
        _ = swipe.update(dx: 0, dy: 0, time: 9.1, index: 0, count: 3, phase: .cancelled)
        assert(!swipe.tracking)
        assert(swipe.update(dx: -100, dy: 0, time: 10, index: 0, count: 3, phase: .began).edge == "First Space")
        _ = swipe.update(dx: 0, dy: 0, time: 10.1, index: 0, count: 3, phase: .ended)
        _ = swipe.update(dx: 0, dy: 0, time: 10.2, index: 0, count: 3, phase: .momentumEnded)
        assert(!swipe.consumesMomentum)
        dirty.preferences.restoreSession = false
        try JSONEncoder().encode(dirty).write(to: restored.file, options: .atomic)
        assert(BrowserStore(directory: directory).state.tabs.isEmpty)
        try Data("broken".utf8).write(to: restored.file, options: .atomic)
        assert(BrowserStore(directory: directory).state.spaces.count == 3)
        assert(SavedBrowserState.displayAddress("https://www.github.com/lamdiv/derivative?q=private#top") == "github.com")
        assert(SavedBrowserState.displayAddress("http://localhost:3000/path") == "localhost:3000")
        assert(SavedBrowserState.displayAddress("https://user:password@example.org/path") == "example.org")
        print("PASS: native tab/Space selection, restoration, isolated empty Spaces, URL validation, sanitization, and atomic metadata.")
    }
}
