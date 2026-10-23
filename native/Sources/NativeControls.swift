import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

let derivativeDragType = UTType(exportedAs: "app.derivative.browser.item", conformingTo: .data)

struct BrowserDownload: Identifiable {
    var id: String, name: String, path: String, status: String
    var received: Double, total: Double
}
@MainActor final class BrowserModel: ObservableObject {
    let store: BrowserStore
    private var subscription: AnyCancellable?
    @Published var expanded = false
    @Published var pinned = true
    @Published var expandedSidebarMode = "hover"
    var effectiveSidebarMode: String { expanded ? expandedSidebarMode : store.state.preferences.sidebarMode }
    @Published var dark = true
    @Published var error = ""
    @Published var splitIDs: [String] = []
    @Published var swipeOffset: CGFloat = 0
    @Published var swipeEdge: String?
    @Published var dragging: String?
    @Published var dropTarget: String?
    @Published var downloads: [BrowserDownload] = []
    @Published var downloadsExpanded = false
    @Published var settingsSection = "General"
    @Published var newSpaceName = ""
    @Published var newSpaceColor = "blush"
    @Published var recentIDs: [String] = []
    @Published var recentIndex = 0
    var action: (String, [String: String]) -> Void = { _, _ in }
    var search: () -> Void = {}
    var newSearch: () -> Void = {}
    var toggle: () -> Void = {}
    var selectTab: (String) -> Void = { _ in }
    var closeTab: (String) -> Void = { _ in }
    var selectSpace: (String) -> Void = { _ in }
    var openFavorite: (String) -> Void = { _ in }
    var duplicate: (String) -> Void = { _ in }
    var title: String { store.active?.title ?? "New tab" }
    var address: String { store.active?.url ?? "" }
    var canBack: Bool { store.active?.canBack ?? false }
    var canForward: Bool { store.active?.canForward ?? false }
    var ink: Color { dark ? .white.opacity(0.9) : Color(red: 0.19, green: 0.15, blue: 0.25) }
    var surface: Color { dark ? Color(red: 0.16, green: 0.14, blue: 0.21) : Color(red: 0.97, green: 0.95, blue: 0.99) }
    var wash: Color { dark ? .white.opacity(0.07) : .white.opacity(0.4) }
    var accent: Color {
        switch store.space.color {
        case "mint": return Color(red: 0.5, green: 0.74, blue: 0.62)
        case "peach": return Color(red: 0.85, green: 0.65, blue: 0.51)
        case "blue": return Color(red: 0.53, green: 0.68, blue: 0.85)
        case "blush": return Color(red: 0.83, green: 0.56, blue: 0.7)
        default: return Color(red: 0.7, green: 0.61, blue: 0.86)
        }
    }
    init(store: BrowserStore) {
        self.store = store
        subscription = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    func send(_ name: String, id: String = "", _ values: [String: String] = [:]) { var values = values; values["id"] = id; action(name, values) }
    func pin(_ id: String) {
        guard let index = store.state.tabs.firstIndex(where: { $0.id == id }) else { return }
        store.state.tabs[index].pinned.toggle(); store.state.tabs[index].favoriteId = nil; store.state.tabs[index].folderId = nil; store.persist()
    }
    func provider(_ token: String) -> NSItemProvider {
        dragging = token
        let provider = NSItemProvider()
        let data = Data(token.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: derivativeDragType.identifier, visibility: .ownProcess) { complete in complete(data, nil); return nil }
        return provider
    }
}
struct SpaceGlyph: View {
    let icon: String
    var body: some View {
        if NSImage(systemSymbolName: icon, accessibilityDescription: nil) != nil { Image(systemName: icon) }
        else { Text(icon) }
    }
}
struct SiteIcon: View {
    let url: String
    let title: String
    var size: CGFloat = 16
    private var favicon: URL? {
        guard var parts = URLComponents(string: url), ["http", "https"].contains(parts.scheme ?? "") else { return nil }
        parts.path = "/favicon.ico"; parts.query = nil; parts.fragment = nil; parts.user = nil; parts.password = nil
        return parts.url
    }
    var body: some View {
        AsyncImage(url: favicon) { phase in
            if let image = phase.image { image.resizable().scaledToFit() }
            else { Text(String(title.prefix(1)).uppercased()).font(.system(size: size*0.7, weight: .semibold)).frame(maxWidth: .infinity, maxHeight: .infinity).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4)) }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
struct SidebarView: View {
    @ObservedObject var model: BrowserModel
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            if model.store.active != nil {
                Button(action: model.search) {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass")
                        Text(model.address).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        Text("⌘L").font(.system(size: 10)).foregroundStyle(.secondary)
                    }.font(.system(size: 12)).padding(11).background(model.wash, in: RoundedRectangle(cornerRadius: 11))
                }.accessibilityLabel("Edit address")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    HStack { Text("Favorites").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary); Spacer()
                        if model.store.state.favorites.count < 12 { Button { model.send("favorite.edit") } label: { Image(systemName: "plus").font(.system(size: 11)) }.accessibilityLabel("Add favorite") }
                    }
                    favorites
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            SpaceGlyph(icon: model.store.space.icon).foregroundStyle(model.accent)
                            Text(model.store.space.name).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Menu { Button("New folder") { model.send("folder.create") }; Button("Rename Space") { model.send("space.rename", id: model.store.space.id) }; Button("Space settings") { model.settingsSection = "Spaces"; model.send("settings") } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                        }.padding(.vertical, 6)
                        groupLabel("Pinned", pinned: true)
                        if splitAnchor?.pinned == true && splitAnchor?.folderId == nil { NativeSplitGroup(model: model) }
                        ForEach(visibleTabs.filter { $0.pinned && $0.folderId == nil }) { NativeTabRow(model: model, tab: $0) }
                        ForEach(model.store.state.folders.filter { $0.spaceId == model.store.state.activeSpaceId }) { folder in FolderRow(model: model, folder: folder) }
                        Divider().opacity(0.25).padding(.vertical, 4)
                        VStack(alignment: .leading, spacing: 5) {
                            groupLabel("Today", pinned: false)
                            if splitAnchor?.pinned == false { NativeSplitGroup(model: model) }
                            ForEach(visibleTabs.filter { !$0.pinned }) { NativeTabRow(model: model, tab: $0) }
                            if model.dragging?.hasPrefix("favorite:") == true {
                                Label("Open as regular tab", systemImage: "plus").font(.system(size: 11)).foregroundStyle(.secondary).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            } else if model.store.active != nil && model.store.active?.favoriteId == nil {
                                Button(action: model.newSearch) { Label("New tab", systemImage: "plus").font(.system(size: 12)).foregroundStyle(.secondary).padding(10) }.accessibilityLabel("New tab")
                            }
                            if visibleTabs.isEmpty && model.store.active == nil { Text("A little room for something new.").font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 14) }
                        }.frame(maxWidth: .infinity, minHeight: 55, alignment: .topLeading).contentShape(Rectangle())
                            .onDrop(of: [derivativeDragType], delegate: SidebarDrop(model: model, kind: "today", id: model.store.state.activeSpaceId))
                    }
                }.padding(.bottom, 4).offset(x: model.swipeOffset)
            }.scrollIndicators(.hidden)
            if let edge = model.swipeEdge { Text(edge).font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity).transition(.opacity) }
            if !model.error.isEmpty { Text(model.error).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3) }
            footer
        }
        .buttonStyle(.plain).padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(model.ink)
        .background {
            LinearGradient(colors: [model.accent.opacity(model.dark ? 0.27 : 0.65), model.accent.opacity(model.dark ? 0.12 : 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .background(model.dark ? Color(red: 0.12, green: 0.1, blue: 0.16) : Color(red: 0.85, green: 0.82, blue: 0.9)).background(.ultraThinMaterial)
        }
        .preferredColorScheme(model.dark ? .dark : .light)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(model.dark ? 0.13 : 0.4), lineWidth: 1))
        .animation(.easeOut(duration: 0.16), value: model.store.state.favorites.map(\.id))
        .animation(.easeOut(duration: 0.16), value: model.store.state.activeSpaceId)
        .onDrop(of: [derivativeDragType], delegate: SidebarDrop(model: model, kind: "sidebar", id: ""))
    }
    private var splitAnchor: BrowserTab? { model.store.state.tabs.first { $0.id == model.splitIDs.first } }
    private var visibleTabs: [BrowserTab] { model.store.currentTabs.filter { $0.favoriteId == nil && !model.splitIDs.contains($0.id) } }
    private var header: some View {
        HStack(spacing: 8) {
            if !model.expanded { Spacer().frame(width: 64) }
            Button(action: model.toggle) { Image(systemName: "sidebar.left") }.help("Show or hide sidebar · ⌘S").accessibilityLabel("Toggle sidebar")
            Spacer(minLength: 8)
            Button { DerivativeBack() } label: { Image(systemName: "arrow.left") }.disabled(!model.canBack).accessibilityLabel("Go back")
            Button { DerivativeForward() } label: { Image(systemName: "arrow.right") }.disabled(!model.canForward).accessibilityLabel("Go forward")
            Button { model.store.active?.loading == true ? DerivativeStop() : DerivativeReload() } label: { Image(systemName: model.store.active?.loading == true ? "xmark" : "arrow.clockwise") }.accessibilityLabel(model.store.active?.loading == true ? "Stop loading" : "Reload page")
        }.font(.system(size: 15, weight: .medium)).frame(height: 28)
            .background { if ProcessInfo.processInfo.environment["DERIVATIVE_NATIVE_TEST_DIRECTORY"] != nil { SidebarLayoutProbe() } }
    }
    private var favorites: some View {
        VStack(spacing: 7) {
            ForEach(Array(favoriteRowSizes(model.store.state.favorites.count).enumerated()), id: \.offset) { row, count in
                let start = favoriteRowSizes(model.store.state.favorites.count).prefix(row).reduce(0, +)
                HStack(spacing: 7) {
                    ForEach(Array(model.store.state.favorites.dropFirst(start).prefix(count))) { favorite in
                Button { model.openFavorite(favorite.id) } label: {
                    SiteIcon(url: favorite.url, title: favorite.name, size: 22)
                        .frame(maxWidth: .infinity).frame(height: 43)
                        .background(model.wash, in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(model.store.active?.favoriteId == favorite.id ? model.accent.opacity(0.8) : .clear, lineWidth: 1.5))
                        .scaleEffect(model.dragging == "favorite:"+favorite.id ? 0.94 : 1)
                }.help(favorite.name).accessibilityLabel("Open favorite \(favorite.name)")
                    .onDrag { model.provider("favorite:"+favorite.id) }
                    .onDrop(of: [derivativeDragType], delegate: SidebarDrop(model: model, kind: "favorite", id: favorite.id))
                    .contextMenu {
                        Button("Open") { model.openFavorite(favorite.id) }
                        Button("Edit favorite") { model.send("favorite.edit", id: favorite.id) }
                        Button("Copy address") { model.send("copy", id: favorite.url) }
                        Divider(); Button("Remove favorite") { model.store.deleteFavorite(favorite.id) }
                    }
                    }
                }
            }
        }.frame(maxWidth: .infinity, minHeight: model.store.state.favorites.isEmpty ? 43 : 0)
            .overlay { if model.store.state.favorites.isEmpty { Text("Your favorite places go here").font(.system(size: 11)).foregroundStyle(.secondary).allowsHitTesting(false) } }
            .contentShape(Rectangle()).onDrop(of: [derivativeDragType], delegate: SidebarDrop(model: model, kind: "favoriteGrid", id: ""))
    }
    private func groupLabel(_ title: String, pinned: Bool) -> some View {
        Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
            .onDrop(of: [derivativeDragType], delegate: SidebarDrop(model: model, kind: pinned ? "pinned" : "today", id: model.store.state.activeSpaceId))
    }
    private var footer: some View {
        HStack(spacing: 4) {
            SidebarDownloads(model: model)
            GeometryReader { geometry in
                ScrollView(.horizontal) { HStack(spacing: 4) {
            ForEach(model.store.state.spaces) { space in
                Button { model.selectSpace(space.id) } label: { SpaceGlyph(icon: space.icon).font(.system(size: 12)).frame(width: 25, height: 25).background(model.wash.opacity(model.store.state.activeSpaceId == space.id ? 1 : 0), in: RoundedRectangle(cornerRadius: 8)) }
                    .help(space.name).accessibilityLabel("Switch to \(space.name) Space")
                    .onDrag { model.provider("space:"+space.id) }
                    .onDrop(of: [derivativeDragType], delegate: SidebarDrop(model: model, kind: "space", id: space.id))
                    .contextMenu { Button("Rename Space") { model.send("space.rename", id: space.id) }; Button("Delete empty Space") { model.send("space.delete", id: space.id) }.disabled(model.store.state.spaces.count == 1 || model.store.state.tabs.contains { $0.spaceId == space.id }) }
            }
                }.frame(minWidth: geometry.size.width) }.scrollIndicators(.hidden)
            }.frame(height: 27)
            Button { model.send("settings") } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 13)).frame(width: 22) }.accessibilityLabel("Settings")
        }.frame(height: 28)
    }
}
struct NativeTabRow: View {
    @ObservedObject var model: BrowserModel
    let tab: BrowserTab
    var body: some View {
        HStack(spacing: 5) {
            Button { model.selectTab(tab.id) } label: {
                HStack(spacing: 9) {
                    if tab.loading { ProgressView().controlSize(.mini).frame(width: 16) }
                    else { SiteIcon(url: tab.url, title: tab.title) }
                    Text(tab.title).lineLimit(1); Spacer(minLength: 0)
                }.padding(.leading, 10).frame(height: 34)
            }.accessibilityLabel("Select tab \(tab.title)")
            Button { model.closeTab(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .medium)).frame(width: 25, height: 28).foregroundStyle(.secondary) }.accessibilityLabel("Close tab \(tab.title)")
        }
        .font(.system(size: 12)).background(model.wash.opacity(tab.id == model.store.state.activeTabId ? 1 : 0), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if model.dropTarget == "split:"+tab.id { HStack { Image(systemName: "rectangle.split.2x1"); Text("Drop to split").font(.system(size: 11)) }.frame(maxWidth: .infinity, maxHeight: .infinity).background(model.accent.opacity(0.75), in: RoundedRectangle(cornerRadius: 10)).allowsHitTesting(false) }
            if model.dropTarget == "before:"+tab.id { VStack { Capsule().fill(model.accent).frame(height: 2); Spacer() }.allowsHitTesting(false) }
            if model.dropTarget == "after:"+tab.id { VStack { Spacer(); Capsule().fill(model.accent).frame(height: 2) }.allowsHitTesting(false) }
        }
        .onDrag { model.provider("tab:"+tab.id) }
        .onDrop(of: [derivativeDragType], delegate: SidebarDrop(model: model, kind: "tab", id: tab.id))
        .contextMenu {
            Button(tab.pinned ? "Unpin tab" : "Pin tab") { model.pin(tab.id) }
            Button("Duplicate tab") { model.duplicate(tab.id) }
            Button("Copy address") { model.send("copy", id: tab.url) }
            Menu("Move to Space") { ForEach(model.store.state.spaces.filter { $0.id != tab.spaceId }) { space in Button(space.name) { model.send("tab.place", id: tab.id, ["spaceId": space.id, "pinned": "true"]) } } }
            Menu("Move to folder") { ForEach(model.store.state.folders.filter { $0.spaceId == tab.spaceId }) { folder in Button(folder.name) { model.send("tab.place", id: tab.id, ["folderId": folder.id, "pinned": "true"]) } } }
            if let active = model.store.active, active.id != tab.id { Button("Split with current tab") { model.send("split.open", id: tab.id) } }
            Button("Close tab") { model.closeTab(tab.id) }
        }
    }
}
struct FolderRow: View {
    @ObservedObject var model: BrowserModel
    let folder: BrowserFolder
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button { model.store.toggleFolder(folder.id) } label: { HStack(spacing: 8) { Image(systemName: folder.collapsed ? "chevron.right" : "chevron.down").font(.system(size: 9)); Image(systemName: folder.collapsed ? "folder" : "folder.fill"); Text(folder.name); Spacer() }.font(.system(size: 12)).padding(9) }
                .background(model.wash.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
                .onDrag { model.provider("folder:"+folder.id) }
                .onDrop(of: [derivativeDragType], delegate: SidebarDrop(model: model, kind: "folder", id: folder.id))
                .contextMenu { Button("Rename folder") { model.send("folder.rename", id: folder.id) }; Button("Remove folder · keep tabs") { model.store.deleteFolder(folder.id) } }
            if !folder.collapsed {
                if model.store.state.tabs.first(where: { $0.id == model.splitIDs.first })?.folderId == folder.id { NativeSplitGroup(model: model).padding(.leading, 10) }
                ForEach(model.store.currentTabs.filter { $0.folderId == folder.id && !model.splitIDs.contains($0.id) }) { NativeTabRow(model: model, tab: $0).padding(.leading, 10) }
                if !model.store.currentTabs.contains(where: { $0.folderId == folder.id }) { Text("Drag tabs here").font(.system(size: 10)).foregroundStyle(.secondary).padding(10).frame(maxWidth: .infinity).onDrop(of: [derivativeDragType], delegate: SidebarDrop(model: model, kind: "folder", id: folder.id)) }
            }
        }
    }
}
struct SidebarDrop: DropDelegate {
    let model: BrowserModel
    let kind: String, id: String
    func validateDrop(info: DropInfo) -> Bool { canDrop }
    var canDrop: Bool {
        guard let token = model.dragging else { return false }
        if kind == "sidebar" { return token.hasPrefix("favorite:") }
        if token.hasPrefix("favorite:") { return ["favorite", "favoriteGrid", "today", "sidebar"].contains(kind) || (kind == "tab" && model.store.state.tabs.first { $0.id == id }?.pinned == false) }
        if token.hasPrefix("tab:"), ["favorite", "favoriteGrid"].contains(kind) { return model.store.state.favorites.count < 12 }
        return true
    }
    var operation: DropOperation {
        let favorite = model.dragging?.hasPrefix("favorite:") == true
        let tab = model.dragging?.hasPrefix("tab:") == true
        return (favorite && ["today", "tab"].contains(kind)) || (tab && ["favorite", "favoriteGrid"].contains(kind)) ? .copy : .move
    }
    func dropEntered(info: DropInfo) {
        if kind == "favorite", let token = model.dragging, token.hasPrefix("favorite:") {
            let source = String(token.dropFirst(9))
            let favorites = model.store.state.favorites
            if let from = favorites.firstIndex(where: { $0.id == source }), let to = favorites.firstIndex(where: { $0.id == id }), from != to {
                let before = from < to ? (favorites.indices.contains(to+1) ? favorites[to+1].id : nil) : id
                withAnimation(.easeOut(duration: 0.16)) { model.store.reorderFavorite(source, before: before) }
            }
        }
        update(info)
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { update(info); return DropProposal(operation: operation) }
    func dropExited(info: DropInfo) { model.dropTarget = nil }
    private func update(_ info: DropInfo) {
        if kind == "tab", let token = model.dragging, token.hasPrefix("tab:"), token != "tab:"+id { model.dropTarget = (info.location.y >= 8 && info.location.y <= 26 ? "split:" : info.location.y > 26 ? "after:" : "before:")+id }
    }
    func performDrop(info: DropInfo) -> Bool { performTokenDrop(y: info.location.y) }
    func performTokenDrop(y: CGFloat) -> Bool {
        guard canDrop else { return false }
        defer { model.dragging = nil; model.dropTarget = nil }
        guard let token = model.dragging else { return false }
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let source = parts[1]
        if parts[0] == "favorite" {
            if ["favorite", "favoriteGrid"].contains(kind) { return true }
            if ["today", "tab"].contains(kind) { model.send("favorite.newTab", id: source); return true }
            return false
        }
        if parts[0] == "tab", ["favorite", "favoriteGrid"].contains(kind), let tab = model.store.state.tabs.first(where: { $0.id == source }) {
            model.store.saveFavorite(name: tab.title, input: tab.url); return true
        }
        if parts[0] == "space" && kind == "space" { model.store.reorderSpace(source, before: id); return true }
        if parts[0] == "folder" && kind == "folder" { model.store.reorderFolder(source, before: id); return true }
        guard parts[0] == "tab", source != id else { return false }
        if kind == "tab", let target = model.store.state.tabs.first(where: { $0.id == id }) {
            if y >= 8 && y <= 26 { model.send("split.open", id: source, ["withId": id]) }
            else {
                let siblings = model.store.state.tabs.filter { $0.id != source && $0.spaceId == target.spaceId && $0.pinned == target.pinned && $0.folderId == target.folderId }
                let next = siblings.firstIndex { $0.id == id }.flatMap { index in siblings.indices.contains(index+1) ? siblings[index+1].id : nil }
                var values = ["spaceId": target.spaceId, "pinned": String(target.pinned), "folderId": target.folderId ?? ""]
                if y <= 8 { values["beforeId"] = id } else if let next { values["beforeId"] = next }
                model.send("tab.place", id: source, values)
            }
        } else if kind == "folder" { model.send("tab.place", id: source, ["folderId": id, "pinned": "true"]) }
        else { model.send("tab.place", id: source, ["spaceId": kind == "space" ? id : model.store.state.activeSpaceId, "pinned": String(kind != "today")]) }
        return true
    }
}
private struct SidebarLayoutProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { let view = NSView(); view.identifier = NSUserInterfaceItemIdentifier("sidebar-header-layout"); return view }
    func updateNSView(_ view: NSView, context: Context) {}
}

@MainActor final class SearchModel: ObservableObject {
    @Published var query: String
    @Published var selected = 0
    init(query: String) { self.query = query }
}
struct SearchSuggestion: Identifiable {
    var id: String, title: String, detail: String, url: String, kind: String
}
@MainActor func nativeSuggestions(_ query: String, store: BrowserStore) -> [SearchSuggestion] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    func matches(_ title: String, _ url: String) -> Bool { q.isEmpty || (title+" "+url).localizedCaseInsensitiveContains(q) }
    var results = store.currentTabs.filter { matches($0.title, $0.url) }.sorted { $0.lastActive > $1.lastActive }.prefix(5).map { SearchSuggestion(id: $0.id, title: $0.title, detail: ($0.id == store.state.activeTabId ? "Current tab" : "Switch to tab")+" · "+$0.url, url: $0.url, kind: "tab") }
    let urls = Set(results.map(\.url))
    if store.active != nil { results += store.state.history.filter { !urls.contains($0.url) && matches($0.title, $0.url) }.prefix(4).map { SearchSuggestion(id: "history:"+$0.url, title: $0.title, detail: "History · "+$0.url, url: $0.url, kind: "history") } }
    if !q.isEmpty, let url = SavedBrowserState.resolve(q, engine: store.state.preferences.searchEngine) {
        let web = !q.contains(where: \.isWhitespace) && (q.contains(".") || q.hasPrefix("http") || q.hasPrefix("localhost"))
        if web && !results.contains(where: { $0.url == url.absoluteString }) { results.insert(SearchSuggestion(id: "url", title: url.host ?? q, detail: "Open website · "+url.absoluteString, url: url.absoluteString, kind: "url"), at: 0) }
        for (id, title) in [("sidebar.toggle", "Toggle sidebar"), ("settings", "Open settings")] where title.localizedCaseInsensitiveContains(q) { results.append(SearchSuggestion(id: id, title: title, detail: "Command", url: "", kind: "command")) }
        var search = URLComponents(string: store.state.preferences.searchEngine == "duckduckgo" ? "https://duckduckgo.com/" : "https://www.google.com/search")!
        search.queryItems = [URLQueryItem(name: "q", value: q)]
        results.append(SearchSuggestion(id: "search", title: "Search for “\(q)”", detail: store.state.preferences.searchEngine == "google" ? "Google Search" : "DuckDuckGo", url: search.url!.absoluteString, kind: "search"))
    }
    return Array(results.prefix(8))
}
struct SearchView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var browser: BrowserModel
    let submit: (String) -> Void
    let dismiss: () -> Void
    let choose: (String) -> Void
    private var results: [SearchSuggestion] { nativeSuggestions(model.query, store: browser.store) }
    private func execute(_ result: SearchSuggestion) {
        if result.kind == "tab" { choose(result.id) }
        else if result.kind == "command" { dismiss(); browser.send(result.id) }
        else { submit(result.url) }
    }
    private func confirm() {
        if !results.isEmpty { execute(results[max(0, min(model.selected, results.count-1))]) }
        else { submit(model.query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search or enter URL", text: $model.query).textFieldStyle(.plain).font(.system(size: 20)).onSubmit(confirm).accessibilityLabel("Search or enter URL")
                Button("esc", action: dismiss).buttonStyle(.plain).font(.system(size: 10)).padding(5).background(browser.wash, in: RoundedRectangle(cornerRadius: 5))
            }.padding(20)
            if !results.isEmpty { ScrollViewReader { proxy in ScrollView { VStack(spacing: 0) { ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                HStack(spacing: 8) {
                    Button { execute(result) } label: {
                        HStack(spacing: 12) {
                            if result.kind == "search" || result.kind == "command" { Image(systemName: result.kind == "search" ? "magnifyingglass" : "command").frame(width: 20) }
                            else { SiteIcon(url: result.url, title: result.title, size: 20) }
                            VStack(alignment: .leading, spacing: 3) { Text(result.title).font(.system(size: 13, weight: .medium)); Text(result.detail).font(.system(size: 11)).foregroundStyle(.secondary) }.lineLimit(1)
                            Spacer()
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    if result.kind == "tab" { Button { browser.closeTab(result.id) } label: { Image(systemName: "xmark").font(.system(size: 11)).padding(10) }.accessibilityLabel("Close result \(result.title)") }
                }.buttonStyle(.plain).background(browser.wash.opacity(index == min(max(0, model.selected), results.count-1) ? 1 : 0), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 8).id(index).onHover { if $0 { model.selected = index } }
            } } }.frame(maxHeight: CGFloat(min(5, results.count))*60).scrollIndicators(.hidden).onChange(of: model.selected) { _, index in proxy.scrollTo(index, anchor: .center) } } }
            HStack { Text(model.query.isEmpty ? "Type an address or a search" : "↑ ↓ Select"); Spacer(); Text("↵ Open") }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 12)
        }
        .foregroundStyle(browser.ink).background(browser.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 18)).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.14), lineWidth: 1)).shadow(color: .black.opacity(0.18), radius: 24, y: 12)
        .padding(1).preferredColorScheme(browser.dark ? .dark : .light).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).ignoresSafeArea()
        .onExitCommand(perform: dismiss).onMoveCommand { direction in if !results.isEmpty { if direction == .down { model.selected = (model.selected+1)%results.count }; if direction == .up { model.selected = (model.selected-1+results.count)%results.count } } }
        .onChange(of: model.query) { _, _ in model.selected = 0 }
    }
}
struct NativeBrand: View {
    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width/64
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 41, y: 12)); path.addLine(to: CGPoint(x: 41, y: 40))
                    path.addCurve(to: CGPoint(x: 27, y: 54), control1: CGPoint(x: 41, y: 48.84), control2: CGPoint(x: 35.84, y: 54))
                    path.addCurve(to: CGPoint(x: 13, y: 40), control1: CGPoint(x: 18.16, y: 54), control2: CGPoint(x: 13, y: 48.84))
                    path.addCurve(to: CGPoint(x: 27, y: 26), control1: CGPoint(x: 13, y: 31.16), control2: CGPoint(x: 18.16, y: 26))
                    path.addLine(to: CGPoint(x: 41, y: 26))
                }.stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                Path { path in path.move(to: CGPoint(x: 52, y: 12)); path.addLine(to: CGPoint(x: 49, y: 20)) }.stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }.scaleEffect(scale, anchor: .topLeading)
        }.frame(width: 52, height: 52).accessibilityLabel("Derivative")
    }
}
struct HomeView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var search: SearchModel
    let submit: (String) -> Void
    let choose: (String) -> Void
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 20) {
                NativeBrand().foregroundStyle(model.accent)
                Text("New tab").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                SearchView(model: search, browser: model, submit: submit, dismiss: { search.query = "" }, choose: choose).frame(width: min(720, max(200, geometry.size.width-48)))
            }.frame(maxWidth: .infinity).padding(.top, max(24, geometry.size.height*0.38-110))
        }.background(model.surface).foregroundStyle(model.ink).preferredColorScheme(model.dark ? .dark : .light).ignoresSafeArea()
    }
}
