import SwiftUI
import AppKit

let browserShortcuts: [(String, String)] = [
    ("New tab", "⌘ T"), ("Edit address", "⌘ L"), ("Show / hide sidebar", "⌘ S"),
    ("Close tab", "⌘ W"), ("Reopen closed tab", "⇧ ⌘ T"), ("Pin / unpin tab", "⌘ D"),
    ("Copy page URL", "⇧ ⌘ C"), ("Reload", "⌘ R"), ("Reload without cache", "⇧ ⌘ R"),
    ("Zoom in / out", "⌘ + / −"), ("Actual size", "⌘ 0"),
    ("Recent tabs", "⌃ Tab"), ("Previous recent tab", "⇧ ⌃ Tab"),
    ("Previous / next tab", "⌥ ⌘ ↑ / ↓"), ("Previous / next Space", "⌥ ⌘ ← / →"),
    ("Switch to Space 1–9", "⌃ 1–9"), ("Switch to tab 1–8 / last", "⌘ 1–8 / 9"),
    ("Back / forward", "⌘ [ / ]"), ("Settings", "⌘ ,")
]
struct SettingsView: View {
    @ObservedObject var model: BrowserModel
    private let sections = [("General", "slider.horizontal.3"), ("Appearance", "paintpalette"), ("Spaces", "square.stack"), ("Downloads", "arrow.down"), ("Shortcuts", "command")]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                NativeBrand().scaleEffect(0.5).frame(width: 32, height: 32).foregroundStyle(model.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings").font(.system(size: 22, weight: .semibold))
                    Text("Make yourself at home.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.send("overlay.close") } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 28, height: 28).background(model.wash, in: Circle())
                }.accessibilityLabel("Close settings")
            }
            HStack(spacing: 3) {
                ForEach(sections, id: \.0) { title, icon in
                    Button { model.settingsSection = title } label: {
                        HStack(spacing: 5) { Image(systemName: icon); Text(title) }.font(.system(size: 11, weight: .medium))
                            .lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity).padding(.vertical, 9)
                            .foregroundStyle(model.settingsSection == title ? model.ink : model.ink.opacity(0.55))
                            .background(model.settingsSection == title ? model.wash : .clear, in: Capsule()).contentShape(Capsule())
                    }.accessibilityLabel(title+" settings").accessibilityValue(model.settingsSection == title ? "Selected" : "")
                }
            }.padding(4).background(model.wash.opacity(0.35), in: Capsule())
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch model.settingsSection {
                    case "Appearance": appearance
                    case "Spaces": spaces
                    case "Downloads": downloads
                    case "Shortcuts": shortcuts
                    default: general
                    }
                }.padding(2).padding(.bottom, 8).frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.automatic).id(model.settingsSection)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .buttonStyle(SidebarImmediateButtonStyle()).foregroundStyle(model.ink)
            .derivativeGlass(model, radius: 20, kind: .panel, elevated: true)
            .preferredColorScheme(model.dark ? .dark : .light).onExitCommand { model.send("overlay.close") }
    }
    private func heading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).derivativeGlass(model, radius: 14, kind: .control)
    }
    private func choice(_ title: String, key: String, value: String, options: [(String, String)]) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .medium)); Spacer(minLength: 12)
            Picker(title, selection: Binding(get: { value }, set: { model.send("preferences", [key: $0]) })) {
                ForEach(options, id: \.0) { id, label in Text(label).tag(id).disabled(id == "custom") }
            }.labelsHidden().frame(width: 165).controlSize(.small)
        }
    }
    private var appearance: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("A look that feels like you", "Choose your light, then give each Space its own color.")
            HStack(spacing: 10) {
                appearanceChoice("system", title: "System", detail: "Follows your Mac")
                appearanceChoice("light", title: "Light", detail: "A little daylight")
                appearanceChoice("dark", title: "Dark", detail: "Soft after hours")
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Color for "+model.store.space.name).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(model.palette.name).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack(spacing: 9) {
                    ForEach(SpacePalette.all) { palette in
                        Button { model.send("space.color", id: model.store.space.id, ["color": palette.id]) } label: {
                            VStack(spacing: 7) {
                                RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [palette.sidebar(dark: model.dark), palette.accent.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(height: 40)
                                    .overlay { if model.store.space.color == palette.id { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.black.opacity(0.65)) } }
                                Text(palette.name).font(.system(size: 10, weight: .medium))
                            }.padding(6).frame(maxWidth: .infinity)
                                .background(model.store.space.color == palette.id ? model.wash : .clear, in: RoundedRectangle(cornerRadius: 13))
                                .contentShape(RoundedRectangle(cornerRadius: 13))
                        }.accessibilityLabel(palette.name+" Space color").accessibilityValue(model.store.space.color == palette.id ? "Selected" : "")
                    }
                }
            }
            group("Sidebar") {
                choice("Position", key: "sidebarSide", value: model.store.state.preferences.sidebarSide ?? "left", options: [("left", "Left"), ("right", "Right")])
                Divider().opacity(0.2)
                choice("Behavior", key: "sidebarMode", value: model.effectiveSidebarMode, options: [("fixed", "Always visible"), ("hover", "Float on hover"), ("hidden", "Hidden")])
                Divider().opacity(0.2)
                choice("Width", key: "sidebarSize", value: model.store.state.preferences.customSidebarWidth == nil ? model.store.state.preferences.sidebarSize : "custom", options: (model.store.state.preferences.customSidebarWidth == nil ? [] : [("custom", "Custom")]) + [("compact", "Compact"), ("comfortable", "Comfortable"), ("wide", "Wide")])
                if let width = model.store.state.preferences.customSidebarWidth {
                    Text("Custom width: \(Int(width)) pt. Choose a preset to reset.").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("Drag the sidebar’s inner edge to resize.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func appearanceChoice(_ id: String, title: String, detail: String) -> some View {
        let selected = model.store.state.preferences.theme == id
        return Button { model.send("preferences", ["theme": id]) } label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    AppearancePreview(palette: model.palette, dark: id == "dark" || (id == "system" && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua))
                    if id == "system" { Image(systemName: "circle.lefthalf.filled").font(.system(size: 14)).padding(6).background(.ultraThinMaterial, in: Circle()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(5) }
                }
                HStack { Text(title).font(.system(size: 12, weight: .semibold)); Spacer(); Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? model.accent : model.ink.opacity(0.25)) }
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
                .background(model.wash.opacity(selected ? 1 : 0.3), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(selected ? model.accent.opacity(0.65) : .clear, lineWidth: 1).allowsHitTesting(false))
                .contentShape(RoundedRectangle(cornerRadius: 15))
        }.accessibilityLabel(title+" appearance").accessibilityValue(selected ? "Selected" : "")
    }
    private var general: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("The everyday things", "A few preferences to make browsing feel effortless.")
            group("Browsing") {
                choice("Search engine", key: "searchEngine", value: model.store.state.preferences.searchEngine, options: [("google", "Google"), ("duckduckgo", "DuckDuckGo")])
                Divider().opacity(0.2)
                Toggle(isOn: Binding(get: { model.store.state.preferences.restoreSession }, set: { model.send("preferences", ["restoreSession": String($0)]) })) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pick up where you left off").font(.system(size: 12, weight: .medium))
                        Text("Restore your tabs when you return.").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.toggleStyle(.switch).controlSize(.small)
            }
            group("Browsing data") {
                Text("Stored on this Mac, with website sign-ins kept separate for each Space.").font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(["history", "cache", "cookies"], id: \.self) { target in
                        Button("Clear "+target) { model.send("clear.request", id: target) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
            HStack(spacing: 12) {
                NativeBrand().scaleEffect(0.55).frame(width: 36, height: 36).foregroundStyle(model.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Derivative").font(.system(size: 13, weight: .semibold))
                    Text("A little space for a curious internet.  ·  0.1.0").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(8)
        }
    }
    private func swatches(value: String, label: String, select: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(SpacePalette.all) { palette in
                Button { select(palette.id) } label: {
                    Circle().fill(palette.accent).frame(width: 18, height: 18)
                        .overlay { if value == palette.id { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.black.opacity(0.7)) } }
                        .padding(3).contentShape(Circle())
                }.accessibilityLabel(palette.name+" for "+label).accessibilityValue(value == palette.id ? "Selected" : "").help(palette.name)
            }
        }
    }
    private var spaces: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Room for every part of your day", "Each Space keeps its own website sign-ins, tabs, and color.")
            ForEach(model.store.state.spaces) { space in
                HStack(spacing: 10) {
                    SpaceGlyph(icon: space.icon).foregroundStyle(SpacePalette.named(space.color).accent).frame(width: 30, height: 30).background(model.wash, in: RoundedRectangle(cornerRadius: 9))
                    TextField("Space name", text: Binding(get: { model.store.state.spaces.first { $0.id == space.id }?.name ?? space.name }, set: { model.store.renameSpace(space.id, name: $0) }))
                        .textFieldStyle(.plain).font(.system(size: 12, weight: .medium)).padding(8).background(model.wash.opacity(0.5), in: RoundedRectangle(cornerRadius: 8)).accessibilityLabel("Rename "+space.name)
                    swatches(value: space.color, label: space.name) { model.send("space.color", id: space.id, ["color": $0]) }
                    Button { model.send("space.delete", id: space.id) } label: { Image(systemName: "trash").font(.system(size: 12)).frame(width: 26, height: 30) }
                        .disabled(model.store.state.spaces.count == 1 || model.store.state.tabs.contains { $0.spaceId == space.id }).help("Only empty Spaces can be deleted").accessibilityLabel("Delete "+space.name)
                }.padding(10).derivativeGlass(model, radius: 13, kind: .control)
            }
            group("A new Space") {
                HStack(spacing: 10) {
                    TextField("Name your Space", text: $model.newSpaceName).textFieldStyle(.plain).padding(9).background(model.wash, in: RoundedRectangle(cornerRadius: 8)).onSubmit(createSpace)
                    Button("Add Space", action: createSpace).buttonStyle(.bordered).controlSize(.small).disabled(model.newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                swatches(value: model.newSpaceColor, label: "new Space") { model.newSpaceColor = $0 }
            }
        }
    }
    private func createSpace() { model.store.createSpace(name: model.newSpaceName, color: model.newSpaceColor, icon: model.newSpaceColor == "blush" ? "✿" : model.newSpaceColor == "blue" ? "☁" : "✳"); model.newSpaceName = "" }
    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Less reaching, more browsing", "Your everyday shortcuts, all in one place.")
            VStack(spacing: 0) {
                ForEach(browserShortcuts, id: \.0) { title, keys in
                    HStack {
                        Text(title).font(.system(size: 12)); Spacer()
                        Text(keys).font(.system(size: 11, weight: .medium, design: .monospaced)).padding(.horizontal, 8).padding(.vertical, 5).background(model.wash, in: RoundedRectangle(cornerRadius: 6))
                    }.padding(.vertical, 8)
                    if title != browserShortcuts.last?.0 { Divider().opacity(0.15) }
                }
            }.padding(.horizontal, 12)
        }
    }
    private var downloads: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Your downloads", "A little home for the things you keep.")
            if model.downloads.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray").font(.system(size: 30, weight: .light)).foregroundStyle(model.accent).frame(width: 65, height: 65).background(model.wash, in: RoundedRectangle(cornerRadius: 20))
                    Text("Nothing here just yet").font(.system(size: 14, weight: .medium))
                    Text("Downloaded files will appear here.").font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 45)
            }
            ForEach(model.downloads) { download in
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc").foregroundStyle(model.accent).frame(width: 30)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(download.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(download.status == "progressing" ? "\(Int(download.received/1024)) KB of \(Int(download.total/1024)) KB" : download.status.capitalized).font(.system(size: 10)).foregroundStyle(.secondary)
                        if download.status == "progressing" { ProgressView(value: download.total > 0 ? download.received/download.total : nil).controlSize(.small) }
                    }
                    Spacer()
                    if download.status == "completed" {
                        Button { model.send("download.reveal", id: download.id) } label: { Image(systemName: "folder") }.help("Show in Finder").accessibilityLabel("Show "+download.name+" in Finder")
                        Button { model.send("download.open", id: download.id) } label: { Image(systemName: "arrow.up.right") }.help("Open download").accessibilityLabel("Open "+download.name)
                    } else if download.status == "progressing" { Button { model.send("download.cancel", id: download.id) } label: { Image(systemName: "xmark") }.help("Cancel download").accessibilityLabel("Cancel "+download.name) }
                }.padding(12).derivativeGlass(model, radius: 12, kind: .control)
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
