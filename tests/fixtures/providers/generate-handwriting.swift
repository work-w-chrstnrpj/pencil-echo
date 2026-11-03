// Deterministic synthetic handwritten-style fixture; no personal handwriting.
// Run from repo root: swift tests/fixtures/providers/generate-handwriting.swift
import AppKit
let width = 800, height = 400
let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()
NSColor.white.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
NSColor.black.setStroke()
func stroke(_ points: [(Double, Double)]) {
    let path = NSBezierPath()
    path.lineWidth = 7
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: NSPoint(x: points[0].0, y: 400 - points[0].1))
    for point in points.dropFirst() { path.line(to: NSPoint(x: point.0, y: 400 - point.1)) }
    path.stroke()
}
// 2x + 3 = 11, deliberately imperfect hand-drawn strokes.
stroke([(75,155),(87,139),(111,139),(125,151),(122,170),(78,215),(127,214)])
stroke([(158,164),(197,215)])
stroke([(196,162),(157,217)])
stroke([(248,183),(301,182)])
stroke([(275,155),(274,211)])
stroke([(352,143),(386,142),(393,156),(378,176),(360,179),(383,181),(398,198),(390,215),(354,219)])
stroke([(447,173),(501,171)])
stroke([(448,199),(502,198)])
stroke([(552,155),(570,141),(568,218)])
stroke([(613,155),(631,141),(630,218)])
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: "application/App/Resources/handwritten-equation.png"))
