import SwiftUI

// Explicit alias selects the property wrapper on SDKs that also export a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct SidebarAddressBar: View {
    @ObservedObject var model: BrowserModel
    @ViewState<String?> private var copiedURL = nil
    @ViewState<Bool> private var addressHovered = false
    var body: some View {
        HStack(spacing: 1) {
            Button(action: model.search) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(model.displayAddress).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 11).frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .background(addressHovered ? model.wash : .clear, in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
            }.buttonStyle(SidebarImmediateButtonStyle()).onHover { addressHovered = $0 }
                .accessibilityLabel("Edit address").help(model.address+" · ⌘L")
            AddressAction(icon: copiedURL == model.address ? "checkmark" : "link", title: copiedURL == model.address ? "Link copied" : "Copy link", wash: model.wash) {
                model.send("copy"); copiedURL = model.address
            }
            AddressAction(icon: "slider.horizontal.3", title: "Site controls", wash: model.wash, selected: model.siteControlsOpen) {
                model.send("site.controls")
            }.popover(isPresented: $model.siteControlsOpen, arrowEdge: .trailing) {
                SiteControlsPanel(model: model)
            }
        }.padding(.trailing, 5).derivativeGlass(model, radius: 12, kind: .control)
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
    private var zoom: Int { model.pageZoom }
    @ViewState<Bool> private var muted = false
    private let zoomSteps = PageZoom.steps
    private func refresh() { model.pageZoom = Int(DerivativePageZoom()); muted = DerivativePageMuted() }
    private func setZoom(_ value: Int) { model.send("page.zoom", ["percent": String(value)]) }
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
        }.padding(16).frame(width: 260).foregroundStyle(model.ink).derivativeGlass(model, radius: 14, kind: .panel)
            .buttonStyle(.plain).preferredColorScheme(model.dark ? .dark : .light)
            .onAppear(perform: refresh).onChange(of: model.store.state.activeTabId) { _, _ in refresh() }
            .onChange(of: model.address) { _, _ in refresh() }
    }
}
