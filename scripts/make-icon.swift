import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift scripts/make-icon.swift OUTPUT.icns\n".utf8))
    exit(64)
}

func png(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "HARLens.Icon", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let background = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 196, yRadius: 196)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(srgbRed: 0.02, green: 0.15, blue: 0.27, alpha: 0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -16)
    shadow.shadowBlurRadius = 32
    shadow.set()
    NSGradient(colors: [
        NSColor(srgbRed: 0.04, green: 0.75, blue: 0.70, alpha: 1),
        NSColor(srgbRed: 0.08, green: 0.31, blue: 0.81, alpha: 1)
    ])!.draw(in: background, angle: -55)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.97).setFill()
    NSBezierPath(roundedRect: NSRect(x: 214, y: 240, width: 494, height: 558), xRadius: 48, yRadius: 48).fill()
    ("HAR" as NSString).draw(
        in: NSRect(x: 254, y: 622, width: 390, height: 118),
        withAttributes: [.font: NSFont.systemFont(ofSize: 108, weight: .bold),
                         .foregroundColor: NSColor(srgbRed: 0.08, green: 0.29, blue: 0.48, alpha: 1)]
    )
    for (index, width) in [330.0, 250.0, 305.0, 210.0].enumerated() {
        let y = 558 - Double(index) * 69
        NSColor(srgbRed: 0.20, green: 0.67, blue: 0.70, alpha: 0.27).setFill()
        NSBezierPath(roundedRect: NSRect(x: 258, y: y, width: width, height: 23), xRadius: 11.5, yRadius: 11.5).fill()
    }

    let handle = NSBezierPath()
    handle.move(to: NSPoint(x: 772, y: 294))
    handle.line(to: NSPoint(x: 866, y: 200))
    handle.lineWidth = 76
    handle.lineCapStyle = .round
    NSColor.white.setStroke()
    handle.stroke()
    let lens = NSBezierPath(ovalIn: NSRect(x: 518, y: 270, width: 320, height: 320))
    NSColor(srgbRed: 0.05, green: 0.22, blue: 0.40, alpha: 1).setFill()
    lens.fill()
    lens.lineWidth = 27
    NSColor.white.setStroke()
    lens.stroke()
    let trace = NSBezierPath()
    trace.move(to: NSPoint(x: 564, y: 417))
    for point in [NSPoint(x: 610, y: 417), NSPoint(x: 638, y: 476), NSPoint(x: 677, y: 371), NSPoint(x: 710, y: 440), NSPoint(x: 787, y: 440)] {
        trace.line(to: point)
    }
    trace.lineWidth = 18
    trace.lineCapStyle = .round
    trace.lineJoinStyle = .round
    NSColor(srgbRed: 0.22, green: 0.91, blue: 0.80, alpha: 1).setStroke()
    trace.stroke()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "HARLens.Icon", code: 2)
    }
    return data
}

func length(_ value: Int) -> Data {
    var bigEndian = UInt32(value).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}

var chunks = Data()
for (type, size) in [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024)] {
    let image = try png(size: size)
    chunks.append(Data(type.utf8))
    chunks.append(length(image.count + 8))
    chunks.append(image)
}
var icon = Data("icns".utf8)
icon.append(length(chunks.count + 8))
icon.append(chunks)
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try icon.write(to: output, options: .atomic)
guard NSImage(contentsOf: output)?.isValid == true else {
    throw NSError(domain: "HARLens.Icon", code: 3)
}
