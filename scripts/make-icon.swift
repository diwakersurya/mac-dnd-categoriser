#!/usr/bin/env swift
// Turns a generated 1024px icon PNG (possibly with a fake checkerboard behind the squircle)
// into Resources/AppIcon.icns plus a 256px PNG for the README.
// Usage: swift scripts/make-icon.swift path/to/icon.png
import AppKit

let args = CommandLine.arguments
guard args.count == 2, let src = NSImage(contentsOfFile: args[1]),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <png>\n".utf8)); exit(1)
}

// 1. Read RGBA pixels.
let w = cg.width, h = cg.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx0 = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx0.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

// 2. Bounding box of "coloured" pixels. Checkerboard and drop shadow are neutral grey, the icon body is not.
var minX = w, minY = h, maxX = -1, maxY = -1
for y in 0..<h { for x in 0..<w {
    let i = (y * w + x) * 4
    let r = Int(px[i]), g = Int(px[i+1]), b = Int(px[i+2])
    if max(r, g, b) - min(r, g, b) > 30 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}}
guard maxX > minX, maxY > minY else { print("no coloured region found"); exit(1) }
let side = max(maxX - minX, maxY - minY) + 1
let srcRect = CGRect(x: (minX + maxX + 1) / 2 - side / 2, y: (minY + maxY + 1) / 2 - side / 2, width: side, height: side)
print("squircle found: \(Int(srcRect.minX)),\(Int(srcRect.minY)) side \(side)")

// 3. Compose on a transparent 1024 canvas: Apple layout is an 824px squircle centred with a soft shadow.
let canvas = 1024, iconSide = 824.0
let dest = CGRect(x: (Double(canvas) - iconSide) / 2, y: (Double(canvas) - iconSide) / 2 + 6, width: iconSide, height: iconSide)
let radius = iconSide * 0.225
let path = CGPath(roundedRect: dest.insetBy(dx: 1, dy: 1), cornerWidth: radius, cornerHeight: radius, transform: nil)
let ctx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(path); ctx.clip()
ctx.interpolationQuality = .high
if let cropped = ctx0.makeImage()?.cropping(to: srcRect) { ctx.draw(cropped, in: dest) }
let out = ctx.makeImage()!

// 4. Write iconset sizes, build icns, keep a 256px PNG.
func write(_ image: CGImage, size: Int, to url: URL) {
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}
let fm = FileManager.default
let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for s in [16, 32, 128, 256, 512] {
    write(out, size: s, to: iconset.appendingPathComponent("icon_\(s)x\(s).png"))
    write(out, size: s * 2, to: iconset.appendingPathComponent("icon_\(s)x\(s)@2x.png"))
}
write(out, size: 256, to: URL(fileURLWithPath: "Resources/AppIcon-256.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote Resources/AppIcon.icns and Resources/AppIcon-256.png" : "iconutil failed")
exit(p.terminationStatus)
