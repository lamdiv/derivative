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
        VStack(alignment: .leading, spacing: 7) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { model.downloadsExpanded.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                    Text("Downloads").font(.system(size: 11, weight: .medium))
                    Spacer()
                    if !model.downloads.isEmpty { Text("\(model.downloads.count)").font(.system(size: 10)).foregroundStyle(.secondary) }
                }.padding(.horizontal, 8).padding(.vertical, 7).contentShape(Rectangle())
            }.accessibilityLabel(model.downloadsExpanded ? "Collapse downloads" : "Expand downloads")
            if model.downloadsExpanded {
                ScrollView {
                    VStack(spacing: 6) {
                        if model.downloads.isEmpty { Text("No downloads yet").font(.system(size: 11)).foregroundStyle(.secondary).padding(12).frame(maxWidth: .infinity) }
                        ForEach(model.downloads) { item in
                            HStack(spacing: 8) {
                                Image(systemName: "doc").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).font(.system(size: 11)).lineLimit(1)
                                    if item.status == "progressing" { ProgressView(value: item.total > 0 ? item.received/item.total : nil).controlSize(.mini) }
                                    else { Text(item.status.capitalized).font(.system(size: 9)).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength: 0)
                                if item.status == "completed" {
                                    Button { model.send("download.open", id: item.id) } label: { Image(systemName: "arrow.up.right") }.help("Open download")
                                    Button { model.send("download.reveal", id: item.id) } label: { Image(systemName: "folder") }.help("Show in Finder")
                                } else if item.status == "progressing" { Button { model.send("download.cancel", id: item.id) } label: { Image(systemName: "xmark") }.help("Cancel download") }
                            }.font(.system(size: 11)).padding(9).background(model.wash, in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }.frame(height: min(180, CGFloat(max(1, model.downloads.count))*52)).scrollIndicators(.hidden).transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}
