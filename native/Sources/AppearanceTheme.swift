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
        .init(id: "lavender", name: "Lilac", accent: tone(0xB39ADB), light: tone(0xFBF9FF), dark: tone(0x2B2735), lightSidebar: tone(0xEBE4F8), darkSidebar: tone(0x51465F)),
        .init(id: "mint", name: "Mint", accent: tone(0x82BCA5), light: tone(0xF6FCF8), dark: tone(0x242F2C), lightSidebar: tone(0xE0F2E8), darkSidebar: tone(0x435F54)),
        .init(id: "peach", name: "Peach", accent: tone(0xD9A07D), light: tone(0xFFFAF5), dark: tone(0x332B27), lightSidebar: tone(0xFBE8D9), darkSidebar: tone(0x6A5143)),
        .init(id: "blue", name: "Sky", accent: tone(0x8AADD9), light: tone(0xF7FAFF), dark: tone(0x252D39), lightSidebar: tone(0xE2EDFC), darkSidebar: tone(0x4A5D75)),
        .init(id: "blush", name: "Rose", accent: tone(0xD299B4), light: tone(0xFFF8FB), dark: tone(0x342932), lightSidebar: tone(0xF7E1EB), darkSidebar: tone(0x674C5E)),
        .init(id: "butter", name: "Butter", accent: tone(0xD4B76D), light: tone(0xFFFDF5), dark: tone(0x312E24), lightSidebar: tone(0xFBF0CE), darkSidebar: tone(0x655C42)),
        .init(id: "cloud", name: "Cloud", accent: tone(0xA2B0C3), light: tone(0xFBFCFE), dark: tone(0x292D35), lightSidebar: tone(0xEDF1F7), darkSidebar: tone(0x505968))
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
