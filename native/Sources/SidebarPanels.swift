import SwiftUI

struct NativeSplitGroup: View {
    @ObservedObject var model: BrowserModel
    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.splitIDs, id: \.self) { id in
                if let tab = model.store.state.tabs.first(where: { $0.id == id }) {
                    Button { model.selectTab(id) } label: {
                        HStack(spacing: 6) { SiteIcon(url: tab.url, title: tab.title); Text(tab.title).font(.system(size: 11)).lineLimit(1); Spacer(minLength: 0) }
                            .padding(9).frame(maxWidth: .infinity).contentShape(Rectangle())
                            .background(model.wash.opacity(model.store.state.activeTabId == id ? 1 : 0), in: RoundedRectangle(cornerRadius: 8))
                    }.accessibilityLabel("Focus split tab \(tab.title)")
                }
            }
        }.background(model.wash, in: RoundedRectangle(cornerRadius: 10))
            .contextMenu {
                Button("Separate tabs") { model.send("split.close") }
                ForEach(model.splitIDs, id: \.self) { id in if let tab = model.store.state.tabs.first(where: { $0.id == id }) { Button("Close \(tab.title)") { model.closeTab(id) } } }
            }
    }
}
struct SidebarDownloads: View {
    @ObservedObject var model: BrowserModel
    var body: some View {
        Button { model.downloadsExpanded.toggle() } label: {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
                .background(model.downloadsExpanded ? model.wash : .clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if model.downloads.contains(where: { $0.status == "progressing" }) {
                        Circle().fill(model.accent).frame(width: 5, height: 5).padding(3)
                    }
                }
        }.help("Downloads")
            .accessibilityLabel(model.downloadsExpanded ? "Collapse downloads" : "Expand downloads")
            .popover(isPresented: $model.downloadsExpanded, arrowEdge: .bottom) {
                panel
            }
    }
    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Downloads").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { model.downloadsExpanded = false } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24)
                        .background(model.wash, in: Circle())
                }.accessibilityLabel("Close downloads")
            }
            if model.downloads.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray").font(.system(size: 25, weight: .light)).foregroundStyle(model.accent)
                    Text("No downloads yet").font(.system(size: 12, weight: .medium))
                    Text("Files you download will appear here.").font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 25)
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(model.downloads.reversed()) { item in
                            HStack(spacing: 10) {
                                Image(systemName: "doc").font(.system(size: 18)).foregroundStyle(model.accent)
                                    .frame(width: 30, height: 34)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    if item.status == "progressing" { ProgressView(value: item.total > 0 ? item.received/item.total : nil).controlSize(.mini) }
                                    else { Text(item.status.capitalized).font(.system(size: 10)).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength: 0)
                                if item.status == "completed" {
                                    Button { model.send("download.open", id: item.id) } label: { Image(systemName: "arrow.up.right") }.help("Open download").accessibilityLabel("Open download \(item.name)")
                                    Button { model.send("download.reveal", id: item.id) } label: { Image(systemName: "folder") }.help("Show in Finder").accessibilityLabel("Show \(item.name) in Finder")
                                } else if item.status == "progressing" { Button { model.send("download.cancel", id: item.id) } label: { Image(systemName: "xmark") }.help("Cancel download").accessibilityLabel("Cancel download \(item.name)") }
                            }.font(.system(size: 12)).padding(10).background(model.wash, in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                }.frame(height: min(330, CGFloat(model.downloads.count)*64)).scrollIndicators(.hidden)
            }
        }.padding(16).frame(width: 320)
            .foregroundStyle(model.ink).derivativeGlass(model, radius: 14, kind: .panel)
            .buttonStyle(.plain).preferredColorScheme(model.dark ? .dark : .light)
    }
}
