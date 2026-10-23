import SwiftUI

// Explicit alias selects the property wrapper on SDKs that also export a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct SidebarAddressBar: View {
    @ObservedObject var model: BrowserModel
    @ViewState<String?> private var copiedURL = nil
    var body: some View {
        HStack(spacing: 1) {
            Button(action: model.search) {
                Text(model.displayAddress).font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .padding(.leading, 12).contentShape(Rectangle())
            }.accessibilityLabel("Edit address").help(model.address+" · ⌘L")
            AddressAction(icon: copiedURL == model.address ? "checkmark" : "link", title: copiedURL == model.address ? "Link copied" : "Copy link", wash: model.wash) {
                model.send("copy"); copiedURL = model.address
            }
            AddressAction(icon: "slider.horizontal.3", title: "Site controls", wash: model.wash, selected: model.siteControlsOpen) {
                model.send("site.controls")
            }.popover(isPresented: $model.siteControlsOpen, arrowEdge: .trailing) {
                SiteControlsPanel(model: model)
            }
        }.padding(.trailing, 5).background(model.wash, in: RoundedRectangle(cornerRadius: 11))
            .task(id: copiedURL) {
                guard copiedURL != nil else { return }
                do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
                copiedURL = nil
            }
    }
}
private struct AddressAction: View {
    let icon: String
    let title: String
    let wash: Color
    var selected = false
    let action: () -> Void
    @ViewState<Bool> private var hovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28).contentShape(RoundedRectangle(cornerRadius: 7))
                .background(hovered || selected ? wash : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityLabel(title).help(title)
            .onHover { hovered = $0 }.animation(.easeOut(duration: 0.12), value: hovered)
    }
}
private struct SiteControlsPanel: View {
    @ObservedObject var model: BrowserModel
    @ViewState<Int> private var zoom = 100
    @ViewState<Bool> private var muted = false
    private let zoomSteps = [25, 50, 67, 75, 80, 90, 100, 110, 125, 150, 175, 200, 250, 300]
    private func refresh() { zoom = Int(DerivativePageZoom()); muted = DerivativePageMuted() }
    private func setZoom(_ value: Int) { zoom = value; model.send("page.zoom", ["percent": String(value)]) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                SiteIcon(url: model.address, title: model.displayAddress, size: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayAddress).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Label(URL(string: model.address)?.scheme == "https" ? "Uses HTTPS" : "HTTP connection", systemImage: URL(string: model.address)?.scheme == "https" ? "lock" : "network")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { model.siteControlsOpen = false } label: {
                    Image(systemName: "xmark").font(.system(size: 10)).frame(width: 24, height: 24).background(model.wash, in: Circle())
                }.accessibilityLabel("Close site controls")
            }
            Divider().opacity(0.3)
            HStack {
                Text("Page zoom").font(.system(size: 12))
                Spacer()
                HStack(spacing: 0) {
                    Button { setZoom(zoomSteps.last(where: { $0 < zoom }) ?? 25) } label: { Image(systemName: "minus").frame(width: 28, height: 28) }
                        .disabled(zoom <= 25).accessibilityLabel("Zoom out")
                    Button { setZoom(100) } label: { Text("\(zoom)%").font(.system(size: 11, weight: .medium)).monospacedDigit().frame(width: 45, height: 28) }
                        .help("Reset zoom").accessibilityLabel("Reset zoom, currently \(zoom) percent")
                    Button { setZoom(zoomSteps.first(where: { $0 > zoom }) ?? 300) } label: { Image(systemName: "plus").frame(width: 28, height: 28) }
                        .disabled(zoom >= 300).accessibilityLabel("Zoom in")
                }.background(model.wash, in: RoundedRectangle(cornerRadius: 8))
            }
            Toggle(isOn: Binding(get: { muted }, set: { muted = $0; model.send("page.mute", ["muted": String($0)]) })) {
                Label("Mute tab", systemImage: muted ? "speaker.slash" : "speaker.wave.2").font(.system(size: 12))
            }.toggleStyle(.switch).controlSize(.mini).accessibilityLabel("Mute current tab")
        }.padding(16).frame(width: 260).foregroundStyle(model.ink).background(model.surface.opacity(0.96))
            .buttonStyle(.plain).preferredColorScheme(model.dark ? .dark : .light)
            .onAppear(perform: refresh).onChange(of: model.store.state.activeTabId) { _, _ in refresh() }
            .onChange(of: model.address) { _, _ in refresh() }
    }
}
