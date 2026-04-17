#!/usr/bin/env swift
// Generates the ProximityUnlock app icon and scales it to all required sizes.
// Usage: swift scripts/generate_icon.swift
import AppKit
import CoreGraphics

let size = 1024
let s = CGFloat(size)

// Create bitmap context
let bitmapRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep)!
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

// Flip coordinate system so y=0 is top-left
cg.translateBy(x: 0, y: s)
cg.scaleBy(x: 1, y: -1)

// --- Background gradient: blue (#4776E6) → purple (#8E54E9) ---
let colors = [
    CGColor(red: 0.278, green: 0.463, blue: 0.902, alpha: 1), // #4776E6
    CGColor(red: 0.557, green: 0.329, blue: 0.914, alpha: 1)  // #8E54E9
] as CFArray
let locs: [CGFloat] = [0, 1]
let colorSpace = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locs)!

cg.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: s, y: s),
    options: []
)

// Helper: draw a rounded rect path
func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// --- iPhone body ---
// Centered, ~55% of canvas width, tall aspect ratio
let phoneW: CGFloat = 380
let phoneH: CGFloat = 600
let phoneX: CGFloat = (s - phoneW) / 2 - 30   // shift slightly left to make room for lock
let phoneY: CGFloat = (s - phoneH) / 2 + 30
let phoneR: CGFloat = 52

cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

// Phone outer body
let phoneBody = roundedRect(CGRect(x: phoneX, y: phoneY, width: phoneW, height: phoneH), radius: phoneR)
cg.addPath(phoneBody)
cg.fillPath()

// Phone inner screen cutout (slightly inset, different radius)
let screenInset: CGFloat = 18
let screenR: CGFloat = 36
cg.setFillColor(CGColor(red: 0.278, green: 0.463, blue: 0.902, alpha: 0.85)) // blue tint
let screenRect = CGRect(x: phoneX + screenInset, y: phoneY + screenInset + 28,
                        width: phoneW - screenInset * 2, height: phoneH - screenInset * 2 - 56)
cg.addPath(roundedRect(screenRect, radius: screenR))
cg.fillPath()

// Home indicator bar at bottom of phone
cg.setFillColor(CGColor(red: 0.278, green: 0.463, blue: 0.902, alpha: 0.6))
let homeW: CGFloat = 100
let homeH: CGFloat = 8
let homeX = phoneX + (phoneW - homeW) / 2
let homeY = phoneY + phoneH - 28
cg.addPath(roundedRect(CGRect(x: homeX, y: homeY, width: homeW, height: homeH), radius: 4))
cg.fillPath()

// Dynamic island pill at top
cg.setFillColor(CGColor(red: 0.278, green: 0.463, blue: 0.902, alpha: 0.6))
let pillW: CGFloat = 80
let pillH: CGFloat = 18
let pillX = phoneX + (phoneW - pillW) / 2
let pillY = phoneY + 18
cg.addPath(roundedRect(CGRect(x: pillX, y: pillY, width: pillW, height: pillH), radius: 9))
cg.fillPath()

// --- Open padlock overlapping upper-right of phone ---
// Padlock body
cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
let lockBodyW: CGFloat = 200
let lockBodyH: CGFloat = 170
let lockBodyX = phoneX + phoneW - 60   // overlap phone's right edge
let lockBodyY: CGFloat = phoneY - 20   // sit above phone's top area
let lockBodyR: CGFloat = 28

cg.addPath(roundedRect(CGRect(x: lockBodyX, y: lockBodyY, width: lockBodyW, height: lockBodyH), radius: lockBodyR))
cg.fillPath()

// Keyhole in lock body
cg.setFillColor(CGColor(red: 0.557, green: 0.329, blue: 0.914, alpha: 1))
let khR: CGFloat = 24
let khX = lockBodyX + lockBodyW / 2
let khY = lockBodyY + lockBodyH / 2 + 10
cg.addEllipse(in: CGRect(x: khX - khR, y: khY - khR, width: khR * 2, height: khR * 2))
cg.fillPath()
// Keyhole stem
let stemW: CGFloat = 18
let stemH: CGFloat = 36
cg.addPath(roundedRect(CGRect(x: khX - stemW / 2, y: khY + khR - 8, width: stemW, height: stemH), radius: 4))
cg.fillPath()

// Open shackle (U shape, open on the right/top)
// The shackle is an arc of a thick white stroke
cg.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
cg.setLineWidth(36)
cg.setLineCap(.round)

let shackleCX = lockBodyX + lockBodyW * 0.36   // left-of-center so shackle arcs left
let shackleCY = lockBodyY                        // sits at top of lock body
let shackleR: CGFloat = 72

// Arc from bottom-left of shackle up and around to the right, open at right (not connecting)
cg.addArc(
    center: CGPoint(x: shackleCX, y: shackleCY),
    radius: shackleR,
    startAngle: CGFloat.pi,           // left side (9 o'clock)
    endAngle: 0,                       // right side (3 o'clock) — open, not reaching back down
    clockwise: false
)
cg.strokePath()

NSGraphicsContext.restoreGraphicsState()

// Save 1024px master
let iconDir = "ProximityUnlockMac/Assets.xcassets/AppIcon.appiconset"
let masterPath = "\(iconDir)/icon_1024_master.png"
let pngData = bitmapRep.representation(using: .png, properties: [:])!
try! pngData.write(to: URL(fileURLWithPath: masterPath))
print("Generated \(masterPath)")

// Scale to all required sizes using sips
let sizes: [(String, Int)] = [
    ("icon_512x512@2x.png", 1024),
    ("icon_512x512.png",    512),
    ("icon_256x256@2x.png", 512),
    ("icon_256x256.png",    256),
    ("icon_128x128@2x.png", 256),
    ("icon_128x128.png",    128),
    ("icon_32x32@2x.png",   64),
    ("icon_32x32.png",      32),
    ("icon_16x16@2x.png",   32),
    ("icon_16x16.png",      16),
]

for (filename, px) in sizes {
    let dest = "\(iconDir)/\(filename)"
    let result = Process()
    result.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    result.arguments = ["-z", "\(px)", "\(px)", masterPath, "--out", dest]
    try! result.run()
    result.waitUntilExit()
    print("  → \(filename) (\(px)px) exit=\(result.terminationStatus)")
}

// Remove master (not referenced by Contents.json)
try! FileManager.default.removeItem(atPath: masterPath)
print("Done. Icon PNGs updated in \(iconDir)/")
