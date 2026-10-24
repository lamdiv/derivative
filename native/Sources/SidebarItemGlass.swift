import SwiftUI

private typealias ItemGlassEnvironment<Value> = SwiftUI.Environment<Value>

private struct SidebarItemGlass: ViewModifier {
    @ObservedObject var model: BrowserModel
    var radius: CGFloat
    var selected: Bool
    var hovered: Bool
    @ItemGlassEnvironment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    @ViewBuilder func body(content: Content) -> some View {
        Group {
            if #available(macOS 26, *), !reduceTransparency {
                content.glassEffect(.regular.tint(model.accent.opacity(selected ? 0.20 : hovered ? 0.08 : 0.01)), in: shape)
            } else {
                content.derivativeGlass(model, radius: radius, kind: .control)
                    .background(model.accent.opacity(selected ? 0.14 : hovered ? 0.07 : 0.02), in: shape)
            }
        }
        .overlay {
            shape.strokeBorder(model.accent.opacity(selected ? 0.30 : 0), lineWidth: 1).allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}


extension View {
    @MainActor func sidebarItemGlass(_ model: BrowserModel, radius: CGFloat, selected: Bool = false, hovered: Bool = false) -> some View {
        modifier(SidebarItemGlass(model: model, radius: radius, selected: selected, hovered: hovered))
    }
}
