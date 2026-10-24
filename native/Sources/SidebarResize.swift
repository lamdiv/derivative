import AppKit

@MainActor final class SidebarResizeHandle: NSView {
    weak var controller: BrowserController?
    private var origin: (x: CGFloat, width: CGFloat)?
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityLabel() -> String? { "Resize sidebar" }
    override func accessibilityRole() -> NSAccessibility.Role? { .splitter }
    override func mouseDown(with event: NSEvent) {
        guard let controller else { return }
        origin = (event.locationInWindow.x, controller.sidebar.bounds.width)
        controller.beginSidebarResize()
    }
    override func mouseDragged(with event: NSEvent) { resize(event, finished: false) }
    override func mouseUp(with event: NSEvent) { resize(event, finished: true); origin = nil }
    private func resize(_ event: NSEvent, finished: Bool) {
        guard let origin else { return }
        controller?.resizeSidebar(rawWidth: origin.width + event.locationInWindow.x-origin.x, finished: finished)
    }
}

@MainActor extension BrowserController {
    func beginSidebarResize() {
        sidebarResizing = true
        hideWork?.cancel(); hideWork = nil
        sidebarAnimation += 1; sidebar.layer?.removeAllAnimations()
        sidebarTransitioning = false; sidebarHiding = false
    }
    func resizeSidebar(rawWidth: CGFloat, finished: Bool) {
        guard rawWidth.isFinite else { return }
        if finished && rawWidth <= SidebarSizing.collapseThreshold {
            store.state.preferences.customSidebarWidth = nil
            store.state.preferences.sidebarSize = "comfortable"
            model.pinned = false; revealed = false
            if model.expanded { model.expandedSidebarMode = "hover" }
            else { normalPinned = false; store.state.preferences.sidebarMode = "hover" }
            sidebarResizing = false
            store.persist(); model.objectWillChange.send()
            transitionSidebar(visible: false, wasVisible: !sidebar.isHidden)
        } else {
            store.state.preferences.customSidebarWidth = Double(SidebarSizing.width(rawWidth, available: root.bounds.width))
            sidebarResizing = !finished
            if finished { store.persist(); model.objectWillChange.send() }
            layout()
        }
    }
}
