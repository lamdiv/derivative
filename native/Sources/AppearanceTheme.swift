import SwiftUI

private func tone(_ hex: UInt32) -> Color {
    Color(red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255)
}

struct SpacePalette: Identifiable {
    let id: String
    let name: String
    let accent: Color
    let light: Color
    let dark: Color
    let lightSidebar: Color
    let darkSidebar: Color
    func surface(dark: Bool) -> Color { dark ? self.dark : light }
    func sidebar(dark: Bool) -> Color { dark ? darkSidebar : lightSidebar }
    static let all: [SpacePalette] = [
        .init(id: "lavender", name: "Lilac", accent: tone(0xAA8FCB), light: tone(0xF4F1F8), dark: tone(0x19171F), lightSidebar: tone(0xDDD3ED), darkSidebar: tone(0x342D43)),
        .init(id: "mint", name: "Mint", accent: tone(0x79B49E), light: tone(0xF0F4F1), dark: tone(0x151C1B), lightSidebar: tone(0xD0E5DD), darkSidebar: tone(0x2B3E36)),
        .init(id: "peach", name: "Peach", accent: tone(0xCE9E82), light: tone(0xF8F3EF), dark: tone(0x201A18), lightSidebar: tone(0xEFD8C9), darkSidebar: tone(0x46362F)),
        .init(id: "blue", name: "Sky", accent: tone(0x85A9CF), light: tone(0xF0F3F8), dark: tone(0x171B23), lightSidebar: tone(0xD1DFEF), darkSidebar: tone(0x2C3B50)),
        .init(id: "blush", name: "Rose", accent: tone(0xC98FA9), light: tone(0xF7F0F3), dark: tone(0x21191E), lightSidebar: tone(0xE9CEDB), darkSidebar: tone(0x46313C))
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
            }.padding(7).frame(width: 48).background(palette.sidebar(dark: dark), in: RoundedRectangle(cornerRadius: 7))
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
