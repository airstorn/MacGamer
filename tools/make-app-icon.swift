import AppKit

guard let output = CommandLine.arguments.dropFirst().first else {
    fputs("usage: make-app-icon <png>\n", stderr)
    exit(1)
}

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let canvas = rect.insetBy(dx: 48, dy: 48)
    let background = NSBezierPath(roundedRect: canvas, xRadius: 230, yRadius: 230)
    NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.28, alpha: 1).setFill()
    background.fill()

    let glow = NSBezierPath(roundedRect: canvas, xRadius: 230, yRadius: 230)
    NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.86, alpha: 0.18).setStroke()
    glow.lineWidth = 28
    glow.stroke()

    let body = NSBezierPath(roundedRect: NSRect(x: 250, y: 340, width: 524, height: 300), xRadius: 120, yRadius: 120)
    NSColor(calibratedRed: 0.86, green: 0.93, blue: 0.98, alpha: 1).setFill()
    body.fill()

    let leftGrip = NSBezierPath(ovalIn: NSRect(x: 210, y: 250, width: 240, height: 280))
    leftGrip.fill()
    let rightGrip = NSBezierPath(ovalIn: NSRect(x: 574, y: 250, width: 240, height: 280))
    rightGrip.fill()

    NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.28, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 318, y: 448, width: 110, height: 36), xRadius: 8, yRadius: 8).fill()
    NSBezierPath(roundedRect: NSRect(x: 355, y: 411, width: 36, height: 110), xRadius: 8, yRadius: 8).fill()

    NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.86, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 620, y: 500, width: 48, height: 48)).fill()
    NSColor(calibratedRed: 0.38, green: 0.82, blue: 0.62, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 672, y: 448, width: 48, height: 48)).fill()
    NSColor(calibratedRed: 0.95, green: 0.62, blue: 0.28, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 568, y: 448, width: 48, height: 48)).fill()
    NSColor(calibratedRed: 0.86, green: 0.32, blue: 0.38, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 620, y: 396, width: 48, height: 48)).fill()
    return true
}

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to encode icon\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: output))
