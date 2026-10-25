import SwiftUI

struct FavoriteTile: View {
    @ObservedObject var model: BrowserModel
    let favorite: BrowserFavorite
    @SidebarRowState<Bool> private var hovered = false
    private var active: Bool { model.store.active?.favoriteId == favorite.id }
    private var opened: Bool { model.store.currentTabs.contains { $0.favoriteId == favorite.id } }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button { model.openFavorite(favorite.id) } label: {
                SiteIcon(url: favorite.url, title: favorite.name, size: 23)
                    .frame(maxWidth: .infinity).frame(height: 43)
                    .sidebarItemGlass(model, radius: 12, selected: active, hovered: hovered)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(SidebarImmediateButtonStyle()).help(favorite.name).accessibilityLabel("Open favorite "+favorite.name)
                .accessibilityValue(active ? "Active tab" : opened ? "Tab open" : "Not open")
                .onDrag { hovered = false; return model.provider("favorite:"+favorite.id) }
            if opened {
                Menu { actions } label: {
                    Image(systemName: "ellipsis").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(model.ink.opacity(0.8))
                        .frame(width: 22, height: 20).contentShape(Rectangle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Favorite options").accessibilityLabel("Options for favorite "+favorite.name)
                    .padding(2)
            }
        }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(model.accent.opacity(active ? 0.95 : opened ? 0.55 : 0), lineWidth: active ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .scaleEffect(model.dragging == "favorite:"+favorite.id ? 0.94 : hovered ? 1.025 : 1)
            .onHover { hovered = $0 }.animation(.easeOut(duration: 0.12), value: hovered)
            .animation(.easeOut(duration: 0.12), value: active)
            .animation(.easeOut(duration: 0.12), value: opened)
            .onDrop(of: [derivativeDragType], delegate: SidebarDrop(model: model, kind: "favorite", id: favorite.id))
            .contextMenu { actions }
    }
    @ViewBuilder private var actions: some View {
        Button("Open") { model.openFavorite(favorite.id) }
        if opened {
            Button("Close Tab") { model.send("favorite.close", id: favorite.id) }
        }
        Button("Edit favorite") { model.send("favorite.edit", id: favorite.id) }
        Button("Copy address") { model.send("copy", id: favorite.url) }
        Menu("Move to Space") {
            ForEach(model.store.state.spaces.filter { $0.id != favorite.spaceId }) { space in
                Button(space.name) { model.send("favorite.move", id: favorite.id, ["spaceId": space.id]) }
                    .disabled(model.store.favorites(in: space.id).count >= 12)
            }
        }.disabled(model.store.state.spaces.count < 2)
        Divider()
        Button("Remove favorite") { model.store.deleteFavorite(favorite.id) }
    }
}
