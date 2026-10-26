import AppKit
import SwiftUI

/// SwiftUI buttons inside the scrolling sidebar can consume the drag gesture
/// before an enclosing onDrag receives it. Track the selection area's native
/// mouse events, and receive drops here before the surrounding section does.
struct TabDragSurface: NSViewRepresentable {
    let model: BrowserModel
    let tabID: String
    func makeNSView(context: Context) -> TabDragView { TabDragView(model: model, tabID: tabID) }
    func updateNSView(_ view: TabDragView, context: Context) { view.model = model; view.tabID = tabID }
}

@MainActor final class TabDragView: NSView, NSDraggingSource {
    var model: BrowserModel
    var tabID: String
    private var start: NSPoint?
    private static let pasteboardType = NSPasteboard.PasteboardType(derivativeDragType.identifier)
    init(model: BrowserModel, tabID: String) {
        self.model = model; self.tabID = tabID
        super.init(frame: .zero)
        registerForDraggedTypes([Self.pasteboardType])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func isAccessibilityElement() -> Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { start = event.locationInWindow }
    override func mouseUp(with event: NSEvent) {
        defer { start = nil }
        if start != nil && bounds.contains(convert(event.locationInWindow, from: nil)) { model.selectTab(tabID) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start, hypot(event.locationInWindow.x-start.x, event.locationInWindow.y-start.y) >= 4 else { return }
        self.start = nil
        let token = "tab:"+tabID
        let item = NSPasteboardItem(); item.setString(token, forType: Self.pasteboardType)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        let preview = NSImage(size: bounds.size)
        if let content = window?.contentView {
            let rect = content.convert(bounds, from: self)
            if let bitmap = content.bitmapImageRepForCachingDisplay(in: rect) {
                content.cacheDisplay(in: rect, to: bitmap); preview.addRepresentation(bitmap)
            }
        }
        draggingItem.setDraggingFrame(bounds, contents: preview)
        model.dragging = token
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy] : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        model.dragging = nil; model.dropTarget = nil
    }
    private var drop: SidebarDrop { SidebarDrop(model: model, kind: "tab", id: tabID) }
    private func token(_ sender: NSDraggingInfo) -> String? {
        guard sender.draggingSource != nil else { return nil }
        if let data = sender.draggingPasteboard.data(forType: Self.pasteboardType), data.count <= 256,
           let value = String(data: data, encoding: .utf8) { return value }
        return model.dragging
    }
    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let token = token(sender) else { return [] }
        if model.dragging != token { model.dragging = token }
        guard drop.canDrop else { return [] }
        drop.updateTarget(y: convert(sender.draggingLocation, from: nil).y)
        return drop.operation == .copy ? .copy : .move
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        if model.dropTarget?.hasSuffix(":"+tabID) == true { model.dropTarget = nil }
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { update(sender) != [] }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let token = token(sender) else { return false }
        return drop.performTokenDrop(y: convert(sender.draggingLocation, from: nil).y, token: token)
    }
}
