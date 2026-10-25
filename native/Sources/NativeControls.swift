import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

typealias SidebarRowState<Value> = SwiftUI.State<Value>

struct SidebarImmediateButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.opacity(configuration.isPressed ? 0.72 : 1) }
}

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
    @Published var swipeOutgoing: NSImage?
    @Published var swipeOutgoingOffset: CGFloat = 0
    @Published var swipeOutgoingOrigin: CGPoint = .zero
    @Published var swipeEdge: String?
    @Published var dragging: String?
    @Published var dropTarget: String?
    @Published var downloads: [BrowserDownload] = []
    @Published var downloadsExpanded = false
    @Published var siteControlsOpen = false
    @Published var pageZoom = 100
    @Published var zoomIndicatorVisible = false
    @Published var clearingTabs = false
    @Published var settingsSection = "Appearance"
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
    var displayAddress: String { SavedBrowserState.displayAddress(address) }
    var canBack: Bool { store.active?.canBack ?? false }
    var canForward: Bool { store.active?.canForward ?? false }
    var ink: Color { dark ? .white.opacity(0.9) : Color(red: 0.17, green: 0.16, blue: 0.20) }
    var palette: SpacePalette { .named(store.space.color) }
    var surface: Color { palette.surface(dark: dark) }
    var sidebarSurface: Color { palette.sidebar(dark: dark) }
    var wash: Color { dark ? .white.opacity(0.10) : .black.opacity(0.055) }
    var accent: Color { palette.accent }
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
    @SidebarRowState<NSImage?> private var icon = nil
    var body: some View {
        Group {
            if let icon { Image(nsImage: icon).resizable().scaledToFit() }
            else { Text(String(title.prefix(1)).uppercased()).font(.system(size: size*0.7, weight: .semibold)).frame(maxWidth: .infinity, maxHeight: .infinity).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4)) }
        }.frame(width: size, height: size).accessibilityHidden(true)
            .task(id: url) {
                icon = nil
                let loaded = await FaviconLoader.shared.image(for: url)
                if !Task.isCancelled { icon = loaded }
            }
    }
}

struct SidebarView: View {
    @ObservedObject var model: BrowserModel
    @SidebarRowState<Bool> private var newTabHovered = false
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            if model.store.active != nil { SidebarAddressBar(model: model) }
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    HStack { Text("Favorites").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary); Spacer()
                        if model.store.currentFavorites.count < 12 { Button { model.send("favorite.edit") } label: { Image(systemName: "plus").font(.system(size: 11)) }.accessibilityLabel("Add favorite") }
                    }
                    favorites
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            SpaceGlyph(icon: model.store.space.icon).foregroundStyle(model.accent)
                            Text(model.store.space.name).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Menu { Button("New folder") { model.send("folder.create") }; Button("Rename Space") { model.send("space.rename", id: model.store.space.id) }; Button("Space settings") { model.settingsSection = "Spaces"; model.send("settings") } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                        }.padding(.vertical, 6)
                        VStack(alignment: .leading, spacing: 5) {
                            groupLabel("Pinned", pinned: true)
                            if splitAnchor?.pinned == true && splitAnchor?.folderId == nil { NativeSplitGroup(model: model) }
                            ForEach(visibleTabs.filter { $0.pinned && $0.folderId == nil }) { NativeTabRow(model: model, tab: $0) }
                            ForEach(model.store.state.folders.filter { $0.spaceId == model.store.state.activeSpaceId }) { folder in FolderRow(model: model, folder: folder) }
                        }.frame(maxWidth: .infinity, minHeight: 55, alignment: .topLeading).contentShape(Rectangle())
                            .onDrop(of: [derivativeDragType], delegate: SidebarDrop(model: model, kind: "pinned", id: model.store.state.activeSpaceId))
                        Divider().opacity(0.25).padding(.vertical, 4)
                        VStack(alignment: .leading, spacing: 5) {
                            groupLabel("Today", pinned: false)
                            if splitAnchor?.pinned == false { NativeSplitGroup(model: model) }
                            ForEach(visibleTabs.filter { !$0.pinned }) { NativeTabRow(model: model, tab: $0) }
                            if model.store.active != nil && model.store.active?.favoriteId == nil {
                                Button(action: model.newSearch) {
                                    Label("New tab", systemImage: "plus").font(.system(size: 12))
                                        .foregroundStyle(newTabHovered ? model.ink : model.ink.opacity(0.5))
                                        .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                                        .contentShape(Rectangle())
                                }.buttonStyle(SidebarImmediateButtonStyle()).accessibilityLabel("New tab")
                                    .background {
                                        RoundedRectangle(cornerRadius: 10).fill(model.wash.opacity(newTabHovered ? 0.65 : 0))
                                            .animation(.easeOut(duration: 0.09), value: newTabHovered).allowsHitTesting(false)
                                    }.onHover { newTabHovered = $0 }
                            }
                            if visibleTabs.isEmpty && model.store.active == nil { Text("A little room for something new.").font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 14) }
                        }.frame(maxWidth: .infinity, minHeight: 55, alignment: .topLeading).contentShape(Rectangle())
                            .onDrop(of: [derivativeDragType], delegate: SidebarDrop(model: model, kind: "today", id: model.store.state.activeSpaceId))
                    }
                }.padding(.bottom, 4)
                    .background(SidebarSpaceCaptureAnchor().allowsHitTesting(false))
                    .offset(x: model.swipeOffset)
                    .overlay(alignment: .topLeading) {
                        if let image = model.swipeOutgoing {
                            Image(nsImage: image).resizable().frame(width: image.size.width, height: image.size.height)
                                .offset(x: model.swipeOutgoingOffset + model.swipeOutgoingOrigin.x, y: model.swipeOutgoingOrigin.y)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
            }.scrollIndicators(.hidden)
                .contentShape(Rectangle())
                .onDrop(of: [derivativeDragType], delegate: SidebarDrop(model: model, kind: "today", id: model.store.state.activeSpaceId))
                .background(SidebarSpaceCaptureAnchor(identifier: "sidebar-space-viewport").allowsHitTesting(false))
                .overlay(alignment: .bottom) {
                    if let edge = model.swipeEdge {
                        Text(edge).font(.system(size: 10, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 7)
                            .derivativeGlass(model, radius: 12, kind: .control).padding(.bottom, 6)
                            .allowsHitTesting(false).transition(.opacity)
                    }
                }
            if !model.error.isEmpty { Text(model.error).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3) }
            footer
        }
        .buttonStyle(.plain).padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(model.ink)
        .derivativeGlass(model, radius: 14, kind: .sidebar)
        .preferredColorScheme(model.dark ? .dark : .light)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeOut(duration: 0.16), value: model.store.currentFavorites.map(\.id))
        .onDrop(of: [derivativeDragType], delegate: SidebarDrop(model: model, kind: "sidebar", id: ""))
    }
    private var splitAnchor: BrowserTab? { model.store.state.tabs.first { $0.id == model.splitIDs.first } }
    private var visibleTabs: [BrowserTab] { model.store.currentTabs.filter { $0.favoriteId == nil && !model.splitIDs.contains($0.id) } }
    private var header: some View {
        HStack(spacing: 8) {
            if !model.expanded { Spacer().frame(width: 64) }
            Button(action: model.toggle) { Image(systemName: model.store.state.preferences.sidebarOnRight ? "sidebar.right" : "sidebar.left") }.help("Show or hide sidebar · ⌘S").accessibilityLabel("Toggle sidebar")
            Spacer(minLength: 8)
            Button { DerivativeBack() } label: { Image(systemName: "arrow.left") }.disabled(!model.canBack).accessibilityLabel("Go back")
            Button { DerivativeForward() } label: { Image(systemName: "arrow.right") }.disabled(!model.canForward).accessibilityLabel("Go forward")
            Button { model.store.active?.loading == true ? DerivativeStop() : DerivativeReload() } label: { Image(systemName: model.store.active?.loading == true ? "xmark" : "arrow.clockwise") }.accessibilityLabel(model.store.active?.loading == true ? "Stop loading" : "Reload page")
        }.font(.system(size: 15, weight: .medium)).frame(height: 28)
            .background { if ProcessInfo.processInfo.environment["DERIVATIVE_NATIVE_TEST_DIRECTORY"] != nil { SidebarLayoutProbe() } }
    }
    private var favorites: some View {
        VStack(spacing: 7) {
            ForEach(Array(favoriteRowSizes(model.store.currentFavorites.count).enumerated()), id: \.offset) { row, count in
                let start = favoriteRowSizes(model.store.currentFavorites.count).prefix(row).reduce(0, +)
                HStack(spacing: 7) {
                    ForEach(Array(model.store.currentFavorites.dropFirst(start).prefix(count))) { favorite in
                        FavoriteTile(model: model, favorite: favorite)
                    }
                }
            }
        }.frame(maxWidth: .infinity, minHeight: model.store.currentFavorites.isEmpty ? 43 : 0)
            .overlay { if model.store.currentFavorites.isEmpty { Text("Your favorite places go here").font(.system(size: 11)).foregroundStyle(.secondary).allowsHitTesting(false) } }
            .contentShape(Rectangle()).onDrop(of: [derivativeDragType], delegate: SidebarDrop(model: model, kind: "favoriteGrid", id: ""))
    }
    private func groupLabel(_ title: String, pinned: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            if !pinned && model.store.currentTabs.contains(where: { !$0.pinned && $0.favoriteId == nil }) {
                Button { model.send("tabs.clear") } label: {
                    Text(model.clearingTabs ? "Clearing…" : "Clear").font(.system(size: 10, weight: .medium)).padding(.horizontal, 5).padding(.vertical, 4).contentShape(Rectangle())
                }.buttonStyle(SidebarImmediateButtonStyle()).foregroundStyle(.secondary)
                    .disabled(model.clearingTabs).accessibilityLabel("Clear tabs in this Space")
                    .help("Close regular tabs in this Space. Keep favorites and pinned tabs. Reopen with ⇧⌘T.")
            }
        }.padding(.vertical, 2).frame(maxWidth: .infinity, alignment: .leading)
            .onDrop(of: [derivativeDragType], delegate: SidebarDrop(model: model, kind: pinned ? "pinned" : "today", id: model.store.state.activeSpaceId))
    }
    private var footer: some View {
        HStack(spacing: 4) {
            SidebarDownloads(model: model)
            GeometryReader { geometry in
                ScrollView(.horizontal) { HStack(spacing: 4) {
            ForEach(model.store.state.spaces) { space in
                Button { model.selectSpace(space.id) } label: { SpaceGlyph(icon: space.icon).font(.system(size: 12)).frame(width: 25, height: 25).background(model.wash.opacity(model.store.state.activeSpaceId == space.id ? 1 : 0), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(model.dropTarget == "space:"+space.id ? model.accent : .clear, lineWidth: 1).allowsHitTesting(false)) }
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
private struct SidebarSpaceCaptureAnchor: NSViewRepresentable {
    var identifier = "sidebar-space-content"
    func makeNSView(context: Context) -> NSView {
        let view = NSView(); view.identifier = NSUserInterfaceItemIdentifier(identifier); return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
struct NativeTabRow: View {
    @ObservedObject var model: BrowserModel
    let tab: BrowserTab
    @SidebarRowState<Bool> private var hovered = false
    @SidebarRowState<Bool> private var closeHovered = false
    var body: some View {
        HStack(spacing: 0) {
            Button { model.selectTab(tab.id) } label: {
                HStack(spacing: 9) {
                    if tab.loading { ProgressView().controlSize(.mini).frame(width: 16) }
                    else { SiteIcon(url: tab.url, title: tab.title) }
                    Text(tab.title).lineLimit(1); Spacer(minLength: 0)
                }.padding(.leading, 10).frame(maxWidth: .infinity).frame(height: 34).contentShape(Rectangle())
                    .background { if ProcessInfo.processInfo.environment["DERIVATIVE_NATIVE_TEST_DIRECTORY"] != nil { SidebarLayoutProbe(id: "sidebar-tab-select:"+tab.id).allowsHitTesting(false) } }
            }.accessibilityLabel("Select tab \(tab.title)")
            Button { model.closeTab(tab.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .medium))
                    .foregroundStyle(closeHovered ? model.ink : model.ink.opacity(0.5))
                    .frame(width: 30, height: 34).contentShape(Rectangle())
                    .background { if closeHovered { RoundedRectangle(cornerRadius: 7).fill(model.wash).padding(4).allowsHitTesting(false) } }
                    .background { if ProcessInfo.processInfo.environment["DERIVATIVE_NATIVE_TEST_DIRECTORY"] != nil { SidebarLayoutProbe(id: "sidebar-tab-close:"+tab.id).allowsHitTesting(false) } }
            }.accessibilityLabel("Close tab \(tab.title)").onHover { closeHovered = $0 }
        }.frame(maxWidth: .infinity).contentShape(Rectangle()).buttonStyle(SidebarImmediateButtonStyle())
        .font(.system(size: 12))
        .sidebarItemGlass(model, radius: 10, selected: tab.id == model.store.state.activeTabId, hovered: hovered)
        .onHover { hovered = $0 }
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
    @SidebarRowState<Bool> private var hovered = false
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button { model.store.toggleFolder(folder.id) } label: { HStack(spacing: 8) { Image(systemName: folder.collapsed ? "chevron.right" : "chevron.down").font(.system(size: 9)); Image(systemName: folder.collapsed ? "folder" : "folder.fill"); Text(folder.name); Spacer() }.font(.system(size: 12)).padding(9).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                .buttonStyle(SidebarImmediateButtonStyle())
                .sidebarItemGlass(model, radius: 9, hovered: hovered).onHover { hovered = $0 }
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
    func validateDrop(info: DropInfo) -> Bool {
        canDrop || (model.dragging == nil && info.hasItemsConforming(to: [derivativeDragType]))
    }
    var canDrop: Bool { accepts(model.dragging) }
    private func accepts(_ token: String?) -> Bool {
        guard let token else { return false }
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let source = parts[1]
        switch parts[0] {
        case "favorite":
            guard let favorite = model.store.state.favorites.first(where: { $0.id == source }) else { return false }
            if kind == "space" { return favorite.spaceId != id && model.store.state.spaces.contains { $0.id == id } && model.store.favorites(in: id).count < 12 }
            if ["favorite", "favoriteGrid"].contains(kind) { return favorite.spaceId == model.store.state.activeSpaceId || model.store.currentFavorites.count < 12 }
            if kind == "tab" { return model.store.currentTabs.contains { $0.id == id } }
            if kind == "folder" { return model.store.state.folders.contains { $0.id == id && $0.spaceId == model.store.state.activeSpaceId } }
            return ["today", "pinned"].contains(kind)
        case "tab":
            guard let tab = model.store.state.tabs.first(where: { $0.id == source }) else { return false }
            if ["favorite", "favoriteGrid"].contains(kind) { return model.store.currentFavorites.count < 12 }
            if kind == "tab" { return source != id && model.store.state.tabs.contains { $0.id == id } }
            if kind == "folder" { return model.store.state.folders.contains { $0.id == id && $0.spaceId == tab.spaceId } }
            if kind == "space" { return model.store.state.spaces.contains { $0.id == id } }
            return ["today", "pinned"].contains(kind)
        case "folder": return kind == "folder" && source != id && model.store.state.folders.contains { $0.id == source } && model.store.state.folders.contains { $0.id == id }
        case "space": return kind == "space" && source != id && model.store.state.spaces.contains { $0.id == source } && model.store.state.spaces.contains { $0.id == id }
        default: return false
        }
    }
    var operation: DropOperation {
        if let token = model.dragging, token.hasPrefix("favorite:"), ["today", "pinned", "folder", "tab"].contains(kind) {
            let favorite = String(token.dropFirst(9))
            return model.store.currentTabs.contains(where: { $0.favoriteId == favorite }) ? .move : .copy
        }
        return model.dragging?.hasPrefix("tab:") == true && ["favorite", "favoriteGrid"].contains(kind) ? .copy : .move
    }
    func dropEntered(info: DropInfo) {
        if kind == "favorite", let token = model.dragging, token.hasPrefix("favorite:") {
            let source = String(token.dropFirst(9))
            let favorites = model.store.currentFavorites
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
        if kind == "space", model.dragging?.hasPrefix("favorite:") == true { model.dropTarget = "space:"+id }
        if kind == "tab", canDrop, let token = model.dragging, token.hasPrefix("tab:"), token != "tab:"+id {
            let source = String(token.dropFirst(4))
            let sameSpace = model.store.state.tabs.first { $0.id == source }?.spaceId == model.store.state.tabs.first { $0.id == id }?.spaceId
            model.dropTarget = (info.location.y >= 8 && info.location.y <= 26 ? (sameSpace ? "split:" : "before:") : info.location.y > 26 ? "after:" : "before:")+id
        }
    }
    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [derivativeDragType]).first else { return false }
        if let token = model.dragging, accepts(token) { return performTokenDrop(y: info.location.y, token: token) }
        return performProviderDrop(provider, y: info.location.y)
    }
    @discardableResult func performProviderDrop(_ provider: NSItemProvider, y: CGFloat) -> Bool {
        guard provider.hasItemConformingToTypeIdentifier(derivativeDragType.identifier) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: derivativeDragType.identifier) { data, _ in
            guard let data, data.count <= 256, let token = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in _ = performTokenDrop(y: y, token: token) }
        }
        return true
    }
    func performTokenDrop(y: CGFloat, token suppliedToken: String? = nil) -> Bool {
        guard let token = suppliedToken ?? model.dragging, accepts(token) else { return false }
        defer {
            if model.dragging == nil || model.dragging == token { model.dragging = nil; model.dropTarget = nil }
        }
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let source = parts[1]
        if parts[0] == "favorite" {
            if kind == "space" { return model.store.moveFavorite(source, to: id) }
            if ["favorite", "favoriteGrid"].contains(kind) {
                if model.store.currentFavorites.contains(where: { $0.id == source }) { return true }
                return model.store.moveFavorite(source, to: model.store.state.activeSpaceId)
            }
            if kind == "tab", let target = model.store.currentTabs.first(where: { $0.id == id }) {
                model.send("favorite.toToday", id: source, ["pinned": String(target.pinned), "folderId": target.folderId ?? "", "beforeId": target.id]); return true
            }
            if ["today", "pinned", "folder"].contains(kind) {
                model.send("favorite.toToday", id: source, ["pinned": String(kind != "today"), "folderId": kind == "folder" ? id : ""]); return true
            }
            return false
        }
        if parts[0] == "tab", ["favorite", "favoriteGrid"].contains(kind), let tab = model.store.state.tabs.first(where: { $0.id == source }) {
            model.store.saveFavorite(name: tab.title, input: tab.url); return true
        }
        if parts[0] == "space" && kind == "space" { model.store.reorderSpace(source, before: id); return true }
        if parts[0] == "folder" && kind == "folder" { model.store.reorderFolder(source, before: id); return true }
        guard parts[0] == "tab", source != id else { return false }
        if kind == "tab", let target = model.store.state.tabs.first(where: { $0.id == id }) {
            if y >= 8 && y <= 26 {
                guard model.store.state.tabs.first(where: { $0.id == source })?.spaceId == target.spaceId else { return false }
                model.send("split.open", id: source, ["withId": id])
            }
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
    var id = "sidebar-header-layout"
    func makeNSView(context: Context) -> NSView { let view = NSView(); view.identifier = NSUserInterfaceItemIdentifier(id); return view }
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
    if store.active != nil || !q.isEmpty { results += store.state.history.filter { !urls.contains($0.url) && matches($0.title, $0.url) }.prefix(4).map { SearchSuggestion(id: "history:"+$0.url, title: $0.title, detail: "History · "+$0.url, url: $0.url, kind: "history") } }
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
                Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(.secondary)
                    .frame(width: 28, height: 28).background(browser.wash, in: RoundedRectangle(cornerRadius: 8))
                TextField("", text: $model.query, prompt: Text("Search or enter URL").foregroundColor(browser.ink.opacity(0.62))).textFieldStyle(.plain).font(.system(size: 20, weight: .medium)).onSubmit(confirm).accessibilityLabel("Search or enter URL")
                Button("esc", action: dismiss).buttonStyle(.plain).font(.system(size: 9, weight: .medium, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 4).background(browser.wash, in: RoundedRectangle(cornerRadius: 5)).accessibilityLabel("Dismiss search")
            }.padding(.horizontal, 20).padding(.vertical, 18)
            if !results.isEmpty { ScrollViewReader { proxy in ScrollView { VStack(spacing: 0) { ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                HStack(spacing: 8) {
                    Button { execute(result) } label: {
                        HStack(spacing: 12) {
                            if result.kind == "search" || result.kind == "command" { Image(systemName: result.kind == "search" ? "magnifyingglass" : "command").frame(width: 20) }
                            else { SiteIcon(url: result.url, title: result.title, size: 20).padding(4).background(browser.wash.opacity(0.5), in: RoundedRectangle(cornerRadius: 8)) }
                            VStack(alignment: .leading, spacing: 3) { Text(result.title).font(.system(size: 13, weight: .medium)); Text(result.detail).font(.system(size: 11)).foregroundStyle(.secondary) }.lineLimit(1)
                            Spacer()
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    if result.kind == "tab" { Button { browser.closeTab(result.id) } label: { Image(systemName: "xmark").font(.system(size: 11)).padding(10) }.accessibilityLabel("Close result \(result.title)") }
                }.buttonStyle(SidebarImmediateButtonStyle()).background(browser.accent.opacity(index == min(max(0, model.selected), results.count-1) ? (browser.dark ? 0.18 : 0.13) : 0), in: RoundedRectangle(cornerRadius: 11)).padding(.horizontal, 8).id(index).onHover { if $0 { model.selected = index } }
            } } }.frame(maxHeight: CGFloat(min(5, results.count))*60).scrollIndicators(.hidden).onChange(of: model.selected) { _, index in proxy.scrollTo(index, anchor: .center) } } }
            HStack(spacing: 5) {
                if model.query.isEmpty { SpaceGlyph(icon: browser.store.space.icon); Text("Search in "+browser.store.space.name) }
                else { keycap("↑"); keycap("↓"); Text("Select") }
                Spacer(); keycap("↵"); Text("Open")
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 11)
        }
        .foregroundStyle(browser.ink).derivativeGlass(browser, radius: 20, kind: .search, elevated: true)
        .padding(1).preferredColorScheme(browser.dark ? .dark : .light).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).ignoresSafeArea()
        .onExitCommand(perform: dismiss).onMoveCommand { direction in if !results.isEmpty { if direction == .down { model.selected = (model.selected+1)%results.count }; if direction == .up { model.selected = (model.selected-1+results.count)%results.count } } }
        .onChange(of: model.query) { _, _ in model.selected = 0 }
    }
    private func keycap(_ value: String) -> some View {
        Text(value).font(.system(size: 8, weight: .medium, design: .monospaced)).padding(.horizontal, 4).padding(.vertical, 2).background(browser.wash, in: RoundedRectangle(cornerRadius: 4))
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
