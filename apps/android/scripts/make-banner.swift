import AppKit

// Renders the Android TV launcher banner (320x180): lens mark + "TapoCam" on a teal gradient.
let w: CGFloat = 320, h: CGFloat = 180
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGradient(colors: [NSColor(red: 0.13, green: 0.73, blue: 0.75, alpha: 1),
                    NSColor(red: 0.05, green: 0.38, blue: 0.55, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -30)
let cx: CGFloat = 70, cy: CGFloat = 90
func circle(_ r: CGFloat, _ c: NSColor, dx: CGFloat = 0, dy: CGFloat = 0) {
    c.setFill(); NSBezierPath(ovalIn: NSRect(x: cx + dx - r, y: cy + dy - r, width: r * 2, height: r * 2)).fill()
}
circle(44, .white)
circle(34, NSColor(white: 0.12, alpha: 1))
circle(20, NSColor(red: 0.2, green: 0.45, blue: 0.85, alpha: 1))
circle(5.5, NSColor(white: 1, alpha: 0.75), dx: 7, dy: 7)
let text = NSAttributedString(string: "TapoCam", attributes: [
    .font: NSFont.systemFont(ofSize: 38, weight: .bold), .foregroundColor: NSColor.white])
text.draw(at: NSPoint(x: 128, y: cy - text.size().height / 2))
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
