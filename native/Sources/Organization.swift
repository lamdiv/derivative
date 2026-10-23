import Foundation

@MainActor extension BrowserStore {
    var orderedTabs: [BrowserTab] {
        let tabs = currentTabs
        return tabs.filter { $0.pinned && $0.folderId == nil } + state.folders.filter { $0.spaceId == state.activeSpaceId }.flatMap { folder in tabs.filter { $0.folderId == folder.id } } + tabs.filter { !$0.pinned }
    }
    func saveFavorite(id: String? = nil, name: String, input: String) {
        guard let url = SavedBrowserState.resolve(input, engine: state.preferences.searchEngine), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let favorite = BrowserFavorite(id: id ?? UUID().uuidString, name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)), url: url.absoluteString)
        if let index = state.favorites.firstIndex(where: { $0.id == id }) { state.favorites[index] = favorite }
        else if state.favorites.count < 12 { state.favorites.append(favorite) }
        persist()
    }
    func deleteFavorite(_ id: String) {
        state.favorites.removeAll { $0.id == id }
        for index in state.tabs.indices where state.tabs[index].favoriteId == id { state.tabs[index].favoriteId = nil }
        persist()
    }
    func reorderFavorite(_ id: String, before: String?) {
        guard id != before, let from = state.favorites.firstIndex(where: { $0.id == id }), before == nil || state.favorites.contains(where: { $0.id == before }) else { return }
        let item = state.favorites.remove(at: from)
        state.favorites.insert(item, at: before.flatMap { target in state.favorites.firstIndex { $0.id == target } } ?? state.favorites.count); persist()
    }
    func createFolder(name: String) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !name.isEmpty, state.folders.count < 300 else { return }
        state.folders.append(BrowserFolder(id: UUID().uuidString, spaceId: state.activeSpaceId, name: name)); persist()
    }
    func renameFolder(_ id: String, name: String) {
        guard let index = state.folders.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        state.folders[index].name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)); persist()
    }
    func toggleFolder(_ id: String) {
        guard let index = state.folders.firstIndex(where: { $0.id == id }) else { return }
        state.folders[index].collapsed.toggle(); persist()
    }
    func deleteFolder(_ id: String) {
        state.folders.removeAll { $0.id == id }
        for index in state.tabs.indices where state.tabs[index].folderId == id { state.tabs[index].folderId = nil }
        persist()
    }
    func placeTab(_ id: String, space: String, pinned: Bool, folder: String? = nil, before: String? = nil) {
        guard var tab = state.tabs.first(where: { $0.id == id }), state.spaces.contains(where: { $0.id == space }), before != id else { return }
        if let folder, !state.folders.contains(where: { $0.id == folder && $0.spaceId == space }) { return }
        if let before, !state.tabs.contains(where: { $0.id == before && $0.spaceId == space && $0.folderId == folder && $0.pinned == (folder != nil || pinned) }) { return }
        tab.spaceId = space; tab.pinned = folder != nil || pinned; tab.folderId = folder; tab.favoriteId = nil
        state.tabs.removeAll { $0.id == id }
        state.tabs.insert(tab, at: before.flatMap { id in state.tabs.firstIndex { $0.id == id } } ?? state.tabs.count)
        if let index = state.folders.firstIndex(where: { $0.id == folder }) { state.folders[index].collapsed = false }
        state.sanitize(); persist()
    }
    func reorderFolder(_ id: String, before: String) {
        guard id != before, let from = state.folders.firstIndex(where: { $0.id == id }), let target = state.folders.first(where: { $0.id == before }), state.folders[from].spaceId == target.spaceId else { return }
        let item = state.folders.remove(at: from)
        state.folders.insert(item, at: state.folders.firstIndex { $0.id == before }!); persist()
    }
    func createSpace(name: String, color: String, icon: String) {
        guard state.spaces.count < 30, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        state.spaces.append(BrowserSpace(id: UUID().uuidString, name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)), icon: icon, color: color)); persist()
    }
    func renameSpace(_ id: String, name: String) {
        guard let index = state.spaces.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        state.spaces[index].name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)); persist()
    }
    func deleteSpace(_ id: String) {
        guard state.spaces.count > 1, !state.tabs.contains(where: { $0.spaceId == id }) else { return }
        state.spaces.removeAll { $0.id == id }; state.folders.removeAll { $0.spaceId == id }; state.sanitize(); persist()
    }
    func reorderSpace(_ id: String, before: String) {
        guard id != before, let from = state.spaces.firstIndex(where: { $0.id == id }), state.spaces.contains(where: { $0.id == before }) else { return }
        let item = state.spaces.remove(at: from); state.spaces.insert(item, at: state.spaces.firstIndex { $0.id == before }!); persist()
    }
}

struct SpaceSwipe {
    var last = -Double.infinity, x = 0.0, y = 0.0, committed = 0.0, reverse = 0.0
    var axis = 0
    mutating func update(dx: Double, dy: Double, time: Double, index: Int, count: Int, began: Bool = false) -> (consumed: Bool, offset: Double, edge: String?, step: Int) {
        if began || time-last > 0.16 { self = SpaceSwipe() }
        last = time; x += dx; y += dy
        if axis == 0 {
            if abs(x) >= 8 && abs(x) > abs(y)*1.15 { axis = 1 }
            else if abs(y) >= 8 && abs(y) > abs(x)*1.25 { axis = 2 }
        }
        guard axis == 1 else { return (false, 0, nil, 0) }
        if committed != 0 {
            reverse = dx.sign == (-committed).sign ? reverse+dx : 0
            if abs(reverse) < 24 { return (true, 0, nil, 0) }
            x = reverse; y = 0; reverse = 0; committed = 0
        }
        let sign = x < 0 ? -1 : 1
        let outside = index+sign < 0 || index+sign >= count
        let offset = -Double(sign)*(outside ? 28*(1-exp(-abs(x)/75)) : min(48, abs(x)*0.7))
        if !outside && abs(x) >= 52 { committed = Double(sign); return (true, 0, nil, sign) }
        return (true, offset, outside ? (sign < 0 ? "First Space" : "Last Space") : nil, 0)
    }
}
