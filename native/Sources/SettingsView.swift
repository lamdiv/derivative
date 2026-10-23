import SwiftUI

let browserShortcuts: [(String, String)] = [
    ("New tab", "⌘ T"), ("Edit address", "⌘ L"), ("Show / hide sidebar", "⌘ S"),
    ("Close tab", "⌘ W"), ("Reopen closed tab", "⇧ ⌘ T"), ("Pin / unpin tab", "⌘ D"),
    ("Copy page URL", "⇧ ⌘ C"), ("Reload", "⌘ R"), ("Reload without cache", "⇧ ⌘ R"),
    ("Recent tabs", "⌃ Tab"), ("Previous recent tab", "⇧ ⌃ Tab"),
    ("Previous / next tab", "⌥ ⌘ ↑ / ↓"), ("Previous / next Space", "⌥ ⌘ ← / →"),
    ("Switch to Space 1–9", "⌃ 1–9"), ("Switch to tab 1–8 / last", "⌘ 1–8 / 9"),
    ("Back / forward", "⌘ [ / ]"), ("Settings", "⌘ ,")
]
struct SettingsView: View {
    @ObservedObject var model: BrowserModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Settings").font(.system(size: 24, weight: .semibold)); Spacer(); Button { model.send("overlay.close") } label: { Image(systemName: "xmark").padding(8) }.buttonStyle(.plain).accessibilityLabel("Close settings") }
            Picker("Section", selection: $model.settingsSection) { ForEach(["General", "Spaces", "Downloads", "Shortcuts"], id: \.self) { Text($0) } }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch model.settingsSection {
                    case "Spaces": spaces
                    case "Downloads": downloads
                    case "Shortcuts": ForEach(browserShortcuts, id: \.0) { title, keys in HStack { Text(title); Spacer(); Text(keys).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary) }.padding(.vertical, 3) }
                    default: general
                    }
                }.padding(.vertical, 5)
            }.scrollIndicators(.hidden)
        }.padding(26).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(model.ink).background(model.surface, in: RoundedRectangle(cornerRadius: 20)).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.15), lineWidth: 1))
            .preferredColorScheme(model.dark ? .dark : .light).onExitCommand { model.send("overlay.close") }
    }
    private func choice(_ title: String, key: String, value: String, options: [(String, String)]) -> some View {
        HStack { Text(title).fontWeight(.medium); Spacer(); Picker(title, selection: Binding(get: { value }, set: { model.send("preferences", [key: $0]) })) { ForEach(options, id: \.0) { id, label in Text(label).tag(id) } }.labelsHidden().frame(width: 180) }
    }
    private var general: some View {
        VStack(alignment: .leading, spacing: 22) {
            choice("Appearance", key: "theme", value: model.store.state.preferences.theme, options: [("system", "System"), ("light", "Light"), ("dark", "Dark")])
            choice("Sidebar", key: "sidebarMode", value: model.effectiveSidebarMode, options: [("fixed", "Fixed"), ("hover", "Floating on hover"), ("hidden", "Hidden")])
            choice("Sidebar width", key: "sidebarSize", value: model.store.state.preferences.sidebarSize, options: [("compact", "Compact"), ("comfortable", "Comfortable"), ("wide", "Wide")])
            choice("Search engine", key: "searchEngine", value: model.store.state.preferences.searchEngine, options: [("google", "Google"), ("duckduckgo", "DuckDuckGo")])
            Toggle("Restore tabs when you return", isOn: Binding(get: { model.store.state.preferences.restoreSession }, set: { model.send("preferences", ["restoreSession": String($0)]) })).toggleStyle(.switch)
            Divider().opacity(0.3)
            VStack(alignment: .leading, spacing: 10) {
                Text("Browsing data").font(.headline)
                Text("Your browsing data stays on this Mac.").font(.system(size: 12)).foregroundStyle(.secondary)
                HStack { ForEach(["history", "cache", "cookies"], id: \.self) { target in Button("Clear "+target) { model.send("clear.request", id: target) } } }
            }
            Divider().opacity(0.3)
            HStack(spacing: 12) { NativeBrand().scaleEffect(0.7).frame(width: 40, height: 40).foregroundStyle(model.accent); VStack(alignment: .leading, spacing: 3) { Text("Derivative").fontWeight(.semibold); Text("A little space for a curious internet.\nVersion 0.1.0").font(.system(size: 11)).foregroundStyle(.secondary) } }
        }
    }
    private var spaces: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Each Space has its own website sign-ins and cookies. Swipe sideways on the sidebar to switch.").font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(model.store.state.spaces) { space in
                HStack(spacing: 12) {
                    SpaceGlyph(icon: space.icon).frame(width: 25)
                    TextField("Space name", text: Binding(get: { model.store.state.spaces.first { $0.id == space.id }?.name ?? space.name }, set: { model.store.renameSpace(space.id, name: $0) })).textFieldStyle(.roundedBorder).accessibilityLabel("Rename \(space.name)")
                    Picker("Color", selection: Binding(get: { model.store.state.spaces.first { $0.id == space.id }?.color ?? space.color }, set: { model.send("space.color", id: space.id, ["color": $0]) })) { ForEach(["lavender", "mint", "peach", "blue", "blush"], id: \.self) { Text($0.capitalized) } }.labelsHidden().frame(width: 110)
                    Button { model.send("space.delete", id: space.id) } label: { Image(systemName: "trash") }.disabled(model.store.state.spaces.count == 1 || model.store.state.tabs.contains { $0.spaceId == space.id }).help("Only empty Spaces can be deleted")
                }
            }
            Divider().opacity(0.3)
            HStack {
                TextField("New Space name", text: $model.newSpaceName).textFieldStyle(.roundedBorder).onSubmit(createSpace)
                Picker("Color", selection: $model.newSpaceColor) { ForEach(["lavender", "mint", "peach", "blue", "blush"], id: \.self) { Text($0.capitalized) } }.labelsHidden().frame(width: 110)
                Button(action: createSpace) { Image(systemName: "plus") }.disabled(model.newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Create Space")
            }
        }
    }
    private func createSpace() { model.store.createSpace(name: model.newSpaceName, color: model.newSpaceColor, icon: model.newSpaceColor == "blush" ? "✿" : model.newSpaceColor == "blue" ? "☁" : "✳"); model.newSpaceName = "" }
    private var downloads: some View {
        VStack(spacing: 14) {
            if model.downloads.isEmpty { VStack(spacing: 12) { Image(systemName: "arrow.down.circle").font(.system(size: 32, weight: .light)); Text("No downloads yet").font(.headline); Text("Your downloads will appear here.").font(.system(size: 12)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 50) }
            ForEach(model.downloads) { download in
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc")
                    VStack(alignment: .leading, spacing: 5) {
                        Text(download.name).fontWeight(.medium).lineLimit(1)
                        Text(download.status == "progressing" ? "\(Int(download.received/1024)) KB of \(Int(download.total/1024)) KB" : download.status.capitalized).font(.system(size: 11)).foregroundStyle(.secondary)
                        if download.status == "progressing" { ProgressView(value: download.total > 0 ? download.received/download.total : nil).controlSize(.small) }
                    }
                    Spacer()
                    if download.status == "completed" {
                        Button { model.send("download.reveal", id: download.id) } label: { Image(systemName: "folder") }.help("Show in Finder")
                        Button { model.send("download.open", id: download.id) } label: { Image(systemName: "arrow.up.right") }.help("Open download")
                    } else if download.status == "progressing" { Button { model.send("download.cancel", id: download.id) } label: { Image(systemName: "xmark") }.help("Cancel download") }
                }.padding(12).background(model.wash, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
struct RecentTabsView: View {
    @ObservedObject var model: BrowserModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent tabs").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(8)
            ForEach(Array(model.recentIDs.enumerated()), id: \.element) { index, id in
                if let tab = model.store.state.tabs.first(where: { $0.id == id }) {
                    Button { model.selectTab(id) } label: { HStack(spacing: 12) { SiteIcon(url: tab.url, title: tab.title, size: 20); Text(tab.title).lineLimit(1); Spacer() }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(model.wash.opacity(index == model.recentIndex ? 1 : 0), in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain)
                }
            }
        }.padding(12).foregroundStyle(model.ink).background(model.surface, in: RoundedRectangle(cornerRadius: 18)).preferredColorScheme(model.dark ? .dark : .light)
    }
}

struct PageErrorView: View {
    @ObservedObject var model: BrowserModel
    let id: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud").font(.system(size: 36, weight: .light)).foregroundStyle(model.accent)
            Text("A little trouble loading this page").font(.system(size: 19, weight: .medium)).multilineTextAlignment(.center)
            Text(model.store.state.tabs.first { $0.id == id }?.error ?? "Please try again.").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Try again") { model.send("tab.reload", id: id) }.buttonStyle(.bordered)
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).background(model.surface).foregroundStyle(model.ink).preferredColorScheme(model.dark ? .dark : .light)
    }
}
