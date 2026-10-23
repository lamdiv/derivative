import SwiftUI

private typealias GlassEnvironment<Value> = SwiftUI.Environment<Value>

enum GlassSurfaceKind { case sidebar, panel, control }

/// A restrained glass treatment that keeps the macOS 14 deployment target.
/// The sidebar's backing blur comes from its AppKit visual-effect container;
/// small controls use only gradients, avoiding a blur layer for every tile.
private struct GlassSurface: ViewModifier {
    var dark: Bool
    var accent: Color
    var radius: CGFloat
    var kind: GlassSurfaceKind
    var elevated: Bool
    @GlassEnvironment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
    private var surface: Color { dark ? Color(red: 0.16, green: 0.14, blue: 0.21) : Color(red: 0.97, green: 0.95, blue: 0.99) }
    func body(content: Content) -> some View {
        content.background {
            ZStack {
                if reduceTransparency {
                    shape.fill(kind == .control ? (dark ? Color.white.opacity(0.09) : Color.black.opacity(0.04)) : surface)
                } else if kind == .panel {
                    shape.fill(.regularMaterial)
                    shape.fill(surface.opacity(dark ? 0.72 : 0.66))
                } else if kind == .sidebar {
                    shape.fill(surface.opacity(dark ? 0.62 : 0.72))
                } else {
                    shape.fill(LinearGradient(colors: [.white.opacity(dark ? 0.10 : 0.48), .white.opacity(dark ? 0.045 : 0.21)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                if kind != .control {
                    shape.fill(LinearGradient(colors: [accent.opacity(kind == .sidebar ? (dark ? 0.26 : 0.36) : 0.06), accent.opacity(kind == .sidebar ? 0.10 : 0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    if !reduceTransparency {
                        shape.fill(LinearGradient(colors: [.white.opacity(dark ? 0.045 : 0.16), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
            }.allowsHitTesting(false)
        }.overlay {
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.18 : 0.38), .white.opacity(dark ? 0.035 : 0.10), .white.opacity(dark ? 0.07 : 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: kind == .control ? 0.5 : 0.8)
                .opacity(kind == .control ? 0.6 : 1).allowsHitTesting(false)
        }.shadow(color: .black.opacity(elevated ? (dark ? 0.16 : 0.08) : 0), radius: 18, y: 8)
    }
}
extension View {
    @MainActor func derivativeGlass(_ model: BrowserModel, radius: CGFloat, kind: GlassSurfaceKind, elevated: Bool = false) -> some View {
        modifier(GlassSurface(dark: model.dark, accent: model.accent, radius: radius, kind: kind, elevated: elevated))
    }
}
