import SwiftUI

struct FavoriteTile: View {
    @ObservedObject var model: BrowserModel
    let favorite: BrowserFavorite
    @SidebarRowState<Bool> private var hovered = false
    private var active: Bool { model.store.active?.favoriteId == favorite.id }
    var body: some View {
        Button { model.openFavorite(favorite.id) } label: {
            SiteIcon(url: favorite.url, title: favorite.name, size: 23)
                .frame(maxWidth: .infinity).frame(height: 43)
                .sidebarItemGlass(model, radius: 12, selected: active, hovered: hovered)
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .scaleEffect(model.dragging == "favorite:"+favorite.id ? 0.94 : hovered ? 1.025 : 1)
        }.buttonStyle(SidebarImmediateButtonStyle()).help(favorite.name).accessibilityLabel("Open favorite "+favorite.name)
            .onHover { hovered = $0 }.animation(.easeOut(duration: 0.12), value: hovered)
            .onDrag { hovered = false; return model.provider("favorite:"+favorite.id) }
            .onDrop(of: [derivativeDragType], delegate: SidebarDrop(model: model, kind: "favorite", id: favorite.id))
            .contextMenu {
                Button("Open") { model.openFavorite(favorite.id) }
                if model.store.currentTabs.contains(where: { $0.favoriteId == favorite.id }) {
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
}
