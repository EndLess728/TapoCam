import AppKit

// Renders the app icon: a camera lens on a teal squircle.
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.13, green: 0.73, blue: 0.75, alpha: 1),
                    NSColor(red: 0.05, green: 0.38, blue: 0.55, alpha: 1)])!.draw(in: bg, angle: -90)
let ring = NSBezierPath(ovalIn: NSRect(x: 262, y: 262, width: 500, height: 500))
NSColor.white.setFill(); ring.fill()
NSColor(white: 0.12, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 322, y: 322, width: 380, height: 380)).fill()
NSColor(red: 0.2, green: 0.45, blue: 0.85, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 402, y: 402, width: 220, height: 220)).fill()
NSColor(white: 1, alpha: 0.75).setFill()
NSBezierPath(ovalIn: NSRect(x: 540, y: 540, width: 60, height: 60)).fill()
NSColor(red: 1, green: 0.3, blue: 0.3, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 740, y: 740, width: 70, height: 70)).fill()
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
