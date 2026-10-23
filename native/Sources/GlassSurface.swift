import SwiftUI

private typealias GlassEnvironment<Value> = SwiftUI.Environment<Value>

enum GlassSurfaceKind { case sidebar, panel, control }

/// Use system Liquid Glass for navigation surfaces on macOS 26+.
/// Older systems retain a frosted treatment. Tiles share the enclosing material
/// instead of paying for a separate backdrop effect on every control.
private struct GlassSurface: ViewModifier {
    var dark: Bool
    var accent: Color
    var radius: CGFloat
    var kind: GlassSurfaceKind
    var elevated: Bool
    @GlassEnvironment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
    private var surface: Color { dark ? Color(red: 0.16, green: 0.14, blue: 0.21) : Color(red: 0.97, green: 0.95, blue: 0.99) }
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !reduceTransparency, kind != .control {
            content.glassEffect(.regular.tint(accent.opacity(kind == .sidebar ? 0.16 : 0.06)), in: shape)
        } else {
            fallback(content: content)
        }
    }
    private func fallback(content: Content) -> some View {
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
                    shape.fill(LinearGradient(colors: [.white.opacity(dark ? 0.075 : 0.5), .white.opacity(dark ? 0.025 : 0.23)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                if kind != .control {
                    shape.fill(LinearGradient(colors: [accent.opacity(kind == .sidebar ? (dark ? 0.18 : 0.23) : 0.06), accent.opacity(kind == .sidebar ? 0.07 : 0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    if !reduceTransparency {
                        shape.fill(LinearGradient(colors: [.white.opacity(dark ? 0.045 : 0.16), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
            }.allowsHitTesting(false)
        }.overlay {
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.14 : 0.38), .white.opacity(dark ? 0.025 : 0.10), .white.opacity(dark ? 0.055 : 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: kind == .control ? 0.5 : 0.8)
                .opacity(kind == .control ? 0.4 : 1).allowsHitTesting(false)
        }.shadow(color: .black.opacity(elevated ? (dark ? 0.16 : 0.08) : 0), radius: 18, y: 8)
    }
}
extension View {
    @MainActor func derivativeGlass(_ model: BrowserModel, radius: CGFloat, kind: GlassSurfaceKind, elevated: Bool = false) -> some View {
        modifier(GlassSurface(dark: model.dark, accent: model.accent, radius: radius, kind: kind, elevated: elevated))
    }
}
