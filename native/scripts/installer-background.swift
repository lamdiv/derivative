import AppKit

// Finder's icon coordinates use a 640 × 420 point content area.
let canvas = NSSize(width: 640, height: 420)
let scale = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 1
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640 * scale, pixelsHigh: 420 * scale,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let transform = NSAffineTransform()
transform.scale(by: CGFloat(scale))
transform.concat()
let bounds = NSRect(origin: .zero, size: canvas)
NSGradient(starting: NSColor(red: 0.97, green: 0.95, blue: 1, alpha: 1),
           ending: NSColor(red: 1, green: 0.96, blue: 0.94, alpha: 1))!.draw(in: bounds, angle: -35)

func text(_ value: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    let measured = (value as NSString).size(withAttributes: attributes)
    (value as NSString).draw(at: NSPoint(x: (640 - measured.width) / 2, y: y), withAttributes: attributes)
}
let ink = NSColor(red: 0.24, green: 0.19, blue: 0.32, alpha: 1)
text("Make yourself at home.", y: 325, size: 29, weight: .semibold, color: ink)
text("Drag Derivative into Applications.", y: 293, size: 15, weight: .regular, color: ink.withAlphaComponent(0.7))

// Finder places the app and Applications icons at x=180 and x=460, y=210.
NSColor(red: 0.61, green: 0.49, blue: 0.76, alpha: 1).setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 286, y: 210)); arrow.line(to: NSPoint(x: 350, y: 210))
arrow.move(to: NSPoint(x: 338, y: 222)); arrow.line(to: NSPoint(x: 350, y: 210)); arrow.line(to: NSPoint(x: 338, y: 198))
arrow.stroke()
text("A little space for a curious internet.", y: 71, size: 13, weight: .medium, color: ink.withAlphaComponent(0.6))
text("Open from Applications, then eject this installer.", y: 43, size: 11, weight: .regular, color: ink.withAlphaComponent(0.5))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
