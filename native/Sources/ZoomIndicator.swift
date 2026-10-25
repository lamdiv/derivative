import AppKit
import SwiftUI

// The overlay must never intercept clicks intended for the Chromium webpage.
@MainActor final class ZoomIndicatorHost: NSHostingView<ZoomIndicatorView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct ZoomIndicatorView: View {
    @ObservedObject var model: BrowserModel
    var body: some View {
        ZStack {
            if model.zoomIndicatorVisible {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
                    Text("\(model.pageZoom)%").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(model.ink).derivativeGlass(model, radius: 13, kind: .panel)
                .accessibilityElement(children: .ignore).accessibilityLabel("Page zoom \(model.pageZoom) percent")
                .transition(.opacity)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14), value: model.zoomIndicatorVisible)
            .accessibilityHidden(!model.zoomIndicatorVisible).allowsHitTesting(false)
    }
}
