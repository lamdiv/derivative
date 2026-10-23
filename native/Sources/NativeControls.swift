import AppKit
import SwiftUI
import Combine

@MainActor final class BrowserModel: ObservableObject {
    let store: BrowserStore
    private var subscription: AnyCancellable?
    @Published var expanded = false
    @Published var pinned = true
    @Published var error = ""
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
    func pin(_ id: String) {
        guard let index = store.state.tabs.firstIndex(where: { $0.id == id }) else { return }
        store.state.tabs[index].pinned.toggle(); store.state.tabs[index].favoriteId = nil; store.persist()
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
            else { Text(String(title.prefix(1)).uppercased()).font(.system(size: size*0.7, weight: .semibold)).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4)) }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct SidebarView: View {
    @ObservedObject var model: BrowserModel
    private var regular: [BrowserTab] { model.store.currentTabs.filter { $0.favoriteId == nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                if !model.expanded { Spacer().frame(width: 64) }
                Button(action: model.toggle) { Image(systemName: "sidebar.left") }.help("Show or hide sidebar · ⌘S").accessibilityLabel("Toggle sidebar")
                Spacer(minLength: 8)
                Button(action: { DerivativeBack() }) { Image(systemName: "arrow.left") }.disabled(!model.canBack).accessibilityLabel("Go back")
                Button(action: { DerivativeForward() }) { Image(systemName: "arrow.right") }.disabled(!model.canForward).accessibilityLabel("Go forward")
                Button(action: { DerivativeReload() }) { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Reload page")
            }.font(.system(size: 15, weight: .medium)).frame(height: 28)
            if model.store.active != nil {
                Button(action: model.search) {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass")
                        Text(model.address).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        Text("⌘L").font(.system(size: 10)).foregroundStyle(.secondary)
                    }.font(.system(size: 12)).padding(11).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
                }.accessibilityLabel("Edit address")
            }
            Text("Favorites").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                ForEach(model.store.state.favorites) { favorite in
                    Button { model.openFavorite(favorite.id) } label: {
                        SiteIcon(url: favorite.url, title: favorite.name, size: 22)
                            .frame(maxWidth: .infinity).frame(height: 43)
                            .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 11))
                            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(model.store.active?.favoriteId == favorite.id ? model.accent.opacity(0.8) : .clear, lineWidth: 1.5))
                    }.help(favorite.name).accessibilityLabel("Open favorite \(favorite.name)")
                }
            }
            HStack(spacing: 8) {
                Image(systemName: model.store.space.icon).foregroundStyle(model.accent)
                Text(model.store.space.name).font(.system(size: 13, weight: .semibold))
                Spacer()
            }.padding(.top, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if regular.contains(where: \.pinned) {
                        Label("Pinned", systemImage: "pin").font(.system(size: 10)).foregroundStyle(.secondary).padding(.vertical, 6)
                        ForEach(regular.filter(\.pinned)) { tabRow($0) }
                        Divider().opacity(0.3).padding(.vertical, 6)
                    }
                    ForEach(regular.filter { !$0.pinned }) { tabRow($0) }
                    if model.store.active != nil {
                        Button(action: model.newSearch) { Label("New tab", systemImage: "plus").font(.system(size: 12)).foregroundStyle(.secondary).padding(10) }.accessibilityLabel("New tab")
                    }
                }
            }.scrollIndicators(.hidden)
            if !model.error.isEmpty { Text(model.error).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3) }
            HStack {
                Spacer()
                ForEach(model.store.state.spaces) { space in
                    Button { model.selectSpace(space.id) } label: {
                        Image(systemName: space.icon).font(.system(size: 13)).frame(width: 27, height: 27)
                            .background(.white.opacity(model.store.state.activeSpaceId == space.id ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 8))
                    }.help(space.name).accessibilityLabel("Switch to \(space.name) Space")
                }
                Spacer()
            }.frame(height: 28)
        }
        .buttonStyle(.plain).padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 14)
        .foregroundStyle(Color.white.opacity(0.9))
        .background {
            LinearGradient(colors: [model.accent.opacity(0.27), model.accent.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .background(Color(red: 0.12, green: 0.1, blue: 0.16)).background(.ultraThinMaterial)
        }
        .preferredColorScheme(.dark).ignoresSafeArea()
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.13), lineWidth: 1))
    }
    private func tabRow(_ tab: BrowserTab) -> some View {
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
        .font(.system(size: 12)).background(.white.opacity(tab.id == model.store.state.activeTabId ? 0.11 : 0), in: RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button(tab.pinned ? "Unpin tab" : "Pin tab") { model.pin(tab.id) }
            Button("Duplicate tab") { model.duplicate(tab.id) }
            Button("Close tab") { model.closeTab(tab.id) }
        }
    }
}

@MainActor final class SearchModel: ObservableObject {
    @Published var query: String
    @Published var selected = 0
    init(query: String) { self.query = query }
}
struct SearchView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var browser: BrowserModel
    let submit: (String) -> Void
    let dismiss: () -> Void
    let choose: (String) -> Void
    private var results: [BrowserTab] {
        let query = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(browser.store.currentTabs.filter { query.isEmpty || "\($0.title) \($0.url)".localizedCaseInsensitiveContains(query) }.sorted { $0.lastActive > $1.lastActive }.prefix(5))
    }
    private func confirm() {
        if !results.isEmpty { choose(results[max(0, min(model.selected, results.count-1))].id) }
        else { submit(model.query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.white.opacity(0.6))
                TextField("Search or enter URL", text: $model.query, prompt: Text("Search or enter URL").foregroundStyle(Color.white.opacity(0.55))).textFieldStyle(.plain)
                    .font(.system(size: 20)).foregroundStyle(Color.white).onSubmit(confirm).accessibilityLabel("Search or enter URL")
                Button("esc", action: dismiss).buttonStyle(.plain).font(.system(size: 10)).padding(5).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
            }.padding(20)
            if !results.isEmpty { ScrollView { VStack(spacing: 0) { ForEach(Array(results.enumerated()), id: \.element.id) { index, tab in
                HStack(spacing: 8) {
                    Button { choose(tab.id) } label: {
                        HStack(spacing: 12) {
                            SiteIcon(url: tab.url, title: tab.title, size: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tab.title).font(.system(size: 13, weight: .medium))
                                Text("\(tab.id == browser.store.state.activeTabId ? "Current tab" : "Switch to tab") · \(tab.url)").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.6))
                            }.lineLimit(1)
                            Spacer()
                        }.padding(12)
                    }
                    Button { browser.closeTab(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 11)).padding(10) }.accessibilityLabel("Close result \(tab.title)")
                }.buttonStyle(.plain).background(.white.opacity(index == min(max(0, model.selected), results.count-1) ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 8)
            }
            } }.frame(maxHeight: CGFloat(results.count)*60).scrollIndicators(.hidden) }
            HStack { Text(model.query.isEmpty ? "Type an address or a search" : "Press Return to open"); Spacer(); Text("↵ Open") }
                .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.6)).padding(.horizontal, 20).padding(.vertical, 12)
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .background(Color(red: 0.19, green: 0.17, blue: 0.25).opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
        .padding(1).preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).ignoresSafeArea()
        .onExitCommand(perform: dismiss)
        .onMoveCommand { direction in
            guard !results.isEmpty else { return }
            if direction == .down { model.selected = min(results.count-1, model.selected+1) }
            if direction == .up { model.selected = max(0, model.selected-1) }
        }
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
                Text("New tab").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.white.opacity(0.65))
                SearchView(model: search, browser: model, submit: submit, dismiss: { search.query = "" }, choose: choose).frame(width: min(720, max(200, geometry.size.width-48)))
            }.frame(maxWidth: .infinity).padding(.top, max(24, geometry.size.height*0.38-110))
        }.background(Color(red: 0.15, green: 0.13, blue: 0.19)).preferredColorScheme(.dark).ignoresSafeArea()
    }
}
