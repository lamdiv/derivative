import SwiftUI

struct SpacePalette: Identifiable {
    let id: String
    let name: String
    let accent: Color
    let light: Color
    let dark: Color
    func surface(dark: Bool) -> Color { dark ? self.dark : light }
    static let all: [SpacePalette] = [
        .init(id: "lavender", name: "Lilac", accent: Color(red: 0.70, green: 0.61, blue: 0.86), light: Color(red: 0.965, green: 0.952, blue: 0.985), dark: Color(red: 0.112, green: 0.106, blue: 0.145)),
        .init(id: "mint", name: "Mint", accent: Color(red: 0.50, green: 0.74, blue: 0.62), light: Color(red: 0.947, green: 0.974, blue: 0.957), dark: Color(red: 0.091, green: 0.127, blue: 0.119)),
        .init(id: "peach", name: "Peach", accent: Color(red: 0.85, green: 0.65, blue: 0.51), light: Color(red: 0.989, green: 0.963, blue: 0.945), dark: Color(red: 0.149, green: 0.115, blue: 0.106)),
        .init(id: "blue", name: "Sky", accent: Color(red: 0.53, green: 0.68, blue: 0.85), light: Color(red: 0.946, green: 0.965, blue: 0.989), dark: Color(red: 0.098, green: 0.119, blue: 0.153)),
        .init(id: "blush", name: "Rose", accent: Color(red: 0.83, green: 0.56, blue: 0.70), light: Color(red: 0.989, green: 0.951, blue: 0.967), dark: Color(red: 0.145, green: 0.104, blue: 0.127))
    ]
    static func named(_ id: String) -> SpacePalette { all.first { $0.id == id } ?? all[0] }
}

/// Code-drawn preview: no extra webviews, screenshot files, or blur layers.
struct AppearancePreview: View {
    let palette: SpacePalette
    let dark: Bool
    var body: some View {
        HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 3) { ForEach(0..<3) { _ in Circle().fill(.primary.opacity(0.22)).frame(width: 3, height: 3) } }
                HStack(spacing: 3) { ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.35)).frame(height: 11) } }
                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.45)).frame(height: 7)
                RoundedRectangle(cornerRadius: 3).fill(.primary.opacity(0.08)).frame(height: 5).padding(.trailing, 7)
                Spacer(minLength: 0)
            }.padding(7).frame(width: 48).background(palette.accent.opacity(dark ? 0.25 : 0.45), in: RoundedRectangle(cornerRadius: 7))
            VStack(spacing: 5) {
                Spacer(minLength: 0)
                Image(systemName: "sparkle").font(.system(size: 15, weight: .light)).foregroundStyle(palette.accent)
                Capsule().fill(.primary.opacity(0.09)).frame(width: 32, height: 4)
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity).background(dark ? .white.opacity(0.025) : .white.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
        }.padding(6).frame(height: 76).background(palette.surface(dark: dark), in: RoundedRectangle(cornerRadius: 11))
            .environment(\.colorScheme, dark ? .dark : .light).accessibilityHidden(true)
    }
}
