import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDirectory = root.appendingPathComponent("reports/hybrid-architecture/capacitor-poc", isDirectory: true)
let phaseOneDirectory = root.appendingPathComponent("reports/hybrid-architecture/phase-1/screenshots", isDirectory: true)
let panelSize = NSSize(width: 402, height: 874)
let headerHeight: CGFloat = 36
let gap: CGFloat = 16

func renderPair(name: String, leftLabel: String, rightLabel: String) throws {
    let leftURL = outputDirectory.appendingPathComponent("\(name)-browser.png")
    let rightURL = outputDirectory.appendingPathComponent("\(name)-capacitor.png")
    guard let left = NSImage(contentsOf: leftURL), let right = NSImage(contentsOf: rightURL) else {
        throw CocoaError(.fileReadCorruptFile)
    }

    let canvasSize = NSSize(width: panelSize.width * 2 + gap, height: panelSize.height + headerHeight)
    let canvas = NSImage(size: canvasSize)
    canvas.lockFocus()
    NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
    NSRect(origin: .zero, size: canvasSize).fill()

    let labelStyle: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.16, alpha: 1),
    ]
    leftLabel.draw(at: NSPoint(x: 12, y: panelSize.height + 9), withAttributes: labelStyle)
    rightLabel.draw(at: NSPoint(x: panelSize.width + gap + 12, y: panelSize.height + 9), withAttributes: labelStyle)
    left.draw(in: NSRect(x: 0, y: 0, width: panelSize.width, height: panelSize.height))
    right.draw(in: NSRect(x: panelSize.width + gap, y: 0, width: panelSize.width, height: panelSize.height))
    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: outputDirectory.appendingPathComponent("\(name)-side-by-side.png"))
}

try renderPair(name: "profile", leftLabel: "Browser · React", rightLabel: "Capacitor iOS · React + SwiftData")
try renderPair(name: "restaurant", leftLabel: "Browser · React", rightLabel: "Capacitor iOS · React + SwiftData")

func renderFoundationPair(name: String, foundationName: String) throws {
    let leftURL = outputDirectory.appendingPathComponent("\(name)-browser.png")
    let rightURL = phaseOneDirectory.appendingPathComponent(foundationName)
    guard let left = NSImage(contentsOf: leftURL), let right = NSImage(contentsOf: rightURL) else {
        throw CocoaError(.fileReadCorruptFile)
    }

    let canvasSize = NSSize(width: panelSize.width * 2 + gap, height: panelSize.height + headerHeight)
    let canvas = NSImage(size: canvasSize)
    canvas.lockFocus()
    NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
    NSRect(origin: .zero, size: canvasSize).fill()
    let style: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.16, alpha: 1),
    ]
    "Browser reference · shared React".draw(at: NSPoint(x: 12, y: panelSize.height + 9), withAttributes: style)
    "Phase 1 Capacitor · shared React + v1 Bridge".draw(at: NSPoint(x: panelSize.width + gap + 12, y: panelSize.height + 9), withAttributes: style)
    left.draw(in: NSRect(x: 0, y: 0, width: panelSize.width, height: panelSize.height))
    right.draw(in: NSRect(x: panelSize.width + gap, y: 0, width: panelSize.width, height: panelSize.height))
    canvas.unlockFocus()
    guard let tiff = canvas.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: phaseOneDirectory.appendingPathComponent("\(name)-browser-vs-phase-1.png"))
}

try renderFoundationPair(name: "profile", foundationName: "hybrid-foundation-profile.png")
try renderFoundationPair(name: "restaurant", foundationName: "hybrid-foundation-restaurant-detail.png")
