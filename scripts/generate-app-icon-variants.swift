#!/usr/bin/env swift
/*
 Brev - Mail Client for macOS and iOS
 Copyright (C) 2026 Brev contributors

 Regenerates the glass envelope icon family from SVG source artwork.
 Requires macOS, rsvg-convert (brew install librsvg), and iconutil.
 Compact artwork is selected by logical size before rasterizing each output.
 macOS keeps the authored transparency and canvas occupancy. iOS is flattened
 over a matching neutral background without an alpha channel. Preview PDFs
 retain vector paths, and all Dock icons retain the same ICNS resolutions.
 */

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct IconVariant {
    let assetName: String
    let finish: String
    let backgroundGray: CGFloat

    var sourceFilename: String { "brev-glass-\(finish).svg" }
    var compactFilename: String { "brev-glass-\(finish)-compact.svg" }
}

private struct AppIconEntry {
    let idiom: String
    let size: String
    let scale: String
    let filename: String
    let pixels: Int
}

private enum IconRenderMode {
    case sourceArtwork
    case opaqueIOS
}

// Stable asset names preserve saved preferences and settings backups.
private let variants: [IconVariant] = [
    IconVariant(assetName: "BrevIconEnvelopeLight", finish: "frost", backgroundGray: 0.82),
    IconVariant(assetName: "BrevIconEnvelopeDarkMetal", finish: "smoke", backgroundGray: 0.20),
    IconVariant(assetName: "BrevIconEnvelopeCarbon", finish: "obsidian", backgroundGray: 0.06)
]

private let defaultAppIconAssetName = "BrevIconEnvelopeDarkMetal"
// ADR-0080: keep the Nightly ring visually distinct from the stable icon.
private let nightlyAppIconAssetName = "BrevIconEnvelopeCarbon"

private let iosEntries = [
    AppIconEntry(idiom: "iphone", size: "20x20", scale: "2x", filename: "icon_20x20@2x.png", pixels: 40),
    AppIconEntry(idiom: "iphone", size: "20x20", scale: "3x", filename: "icon_20x20@3x.png", pixels: 60),
    AppIconEntry(idiom: "iphone", size: "29x29", scale: "2x", filename: "icon_29x29@2x.png", pixels: 58),
    AppIconEntry(idiom: "iphone", size: "29x29", scale: "3x", filename: "icon_29x29@3x.png", pixels: 87),
    AppIconEntry(idiom: "iphone", size: "40x40", scale: "2x", filename: "icon_40x40@2x.png", pixels: 80),
    AppIconEntry(idiom: "iphone", size: "40x40", scale: "3x", filename: "icon_40x40@3x.png", pixels: 120),
    AppIconEntry(idiom: "iphone", size: "60x60", scale: "2x", filename: "icon_60x60@2x.png", pixels: 120),
    AppIconEntry(idiom: "iphone", size: "60x60", scale: "3x", filename: "icon_60x60@3x.png", pixels: 180),
    AppIconEntry(idiom: "ipad", size: "20x20", scale: "1x", filename: "icon_20x20.png", pixels: 20),
    AppIconEntry(idiom: "ipad", size: "20x20", scale: "2x", filename: "icon_20x20@2x.png", pixels: 40),
    AppIconEntry(idiom: "ipad", size: "29x29", scale: "1x", filename: "icon_29x29.png", pixels: 29),
    AppIconEntry(idiom: "ipad", size: "29x29", scale: "2x", filename: "icon_29x29@2x.png", pixels: 58),
    AppIconEntry(idiom: "ipad", size: "40x40", scale: "1x", filename: "icon_40x40.png", pixels: 40),
    AppIconEntry(idiom: "ipad", size: "40x40", scale: "2x", filename: "icon_40x40@2x.png", pixels: 80),
    AppIconEntry(idiom: "ipad", size: "76x76", scale: "1x", filename: "icon_76x76.png", pixels: 76),
    AppIconEntry(idiom: "ipad", size: "76x76", scale: "2x", filename: "icon_76x76@2x.png", pixels: 152),
    AppIconEntry(idiom: "ipad", size: "83.5x83.5", scale: "2x", filename: "icon_83.5x83.5@2x.png", pixels: 167),
    AppIconEntry(idiom: "ios-marketing", size: "1024x1024", scale: "1x", filename: "icon_1024x1024.png", pixels: 1024)
]

private let macEntries = [
    AppIconEntry(idiom: "mac", size: "16x16", scale: "1x", filename: "icon_16x16.png", pixels: 16),
    AppIconEntry(idiom: "mac", size: "16x16", scale: "2x", filename: "icon_16x16@2x.png", pixels: 32),
    AppIconEntry(idiom: "mac", size: "32x32", scale: "1x", filename: "icon_32x32.png", pixels: 32),
    AppIconEntry(idiom: "mac", size: "32x32", scale: "2x", filename: "icon_32x32@2x.png", pixels: 64),
    AppIconEntry(idiom: "mac", size: "128x128", scale: "1x", filename: "icon_128x128.png", pixels: 128),
    AppIconEntry(idiom: "mac", size: "128x128", scale: "2x", filename: "icon_128x128@2x.png", pixels: 256),
    AppIconEntry(idiom: "mac", size: "256x256", scale: "1x", filename: "icon_256x256.png", pixels: 256),
    AppIconEntry(idiom: "mac", size: "256x256", scale: "2x", filename: "icon_256x256@2x.png", pixels: 512),
    AppIconEntry(idiom: "mac", size: "512x512", scale: "1x", filename: "icon_512x512.png", pixels: 512),
    AppIconEntry(idiom: "mac", size: "512x512", scale: "2x", filename: "icon_512x512@2x.png", pixels: 1024)
]

private let fileManager = FileManager.default
private let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
private let sourceDirectory = root.appending(path: "assets/app-icons/source")
private let macCatalog = root.appending(path: "apps/macOS/Resources/Assets.xcassets")
private let iosCatalog = root.appending(path: "apps/iOS/Resources/Assets.xcassets")
private let sourceColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

/// Asset names that are no longer part of the variant set and must be pruned
/// from both catalogs so stale `.appiconset`/`.imageset` folders don't linger.
private let retiredAssetNames = [
    "BrevIconPaper", "BrevIconOcean", "BrevIconInk",
    "BrevIconClassic", "BrevIconAurora", "BrevIconGradient",
    "BrevIconGraphite", "BrevIconCobalt", "BrevIconForest",
    "BrevIconPlum", "BrevIconEmber", "BrevIconCopper",
    "BrevIconTeal", "BrevIconAmber", "BrevIconRose", "BrevIconSlate"
]

try generateCatalogs()

private func generateCatalogs() throws {
    guard let defaultVariant = variants.first(where: { $0.assetName == defaultAppIconAssetName }) else {
        throw IconGenerationError.missingDefault(defaultAppIconAssetName)
    }

    try validateSourceArtwork()
    try pruneRetiredAssets()

    try writeAppIconSet(
        catalog: macCatalog,
        name: "AppIcon",
        entries: macEntries,
        variant: defaultVariant,
        mode: .sourceArtwork
    )
    guard let nightlyVariant = variants.first(where: { $0.assetName == nightlyAppIconAssetName }) else {
        throw IconGenerationError.missingDefault(nightlyAppIconAssetName)
    }
    try writeAppIconSet(
        catalog: macCatalog,
        name: "AppIcon-Nightly",
        entries: macEntries,
        variant: nightlyVariant,
        mode: .sourceArtwork
    )
    try writeAppIconSet(
        catalog: iosCatalog,
        name: "AppIcon",
        entries: iosEntries,
        variant: defaultVariant,
        mode: .opaqueIOS
    )
    try removeIfPresent(iosCatalog.appending(path: "\(defaultVariant.assetName).appiconset"))

    for variant in variants {
        try writeImageSet(catalog: macCatalog, variant: variant)
        try writeImageSet(catalog: iosCatalog, variant: variant)
        if variant.assetName == defaultAppIconAssetName {
            try writeImageSet(
                catalog: root.appending(path: "packages/BrevMail/Sources/BrevMail/Resources/BrevBrandAssets.xcassets"),
                variant: variant
            )
        }
        try writeDockIcon(variant)

        guard variant.assetName != defaultVariant.assetName else { continue }
        try writeAppIconSet(
            catalog: iosCatalog,
            name: variant.assetName,
            entries: iosEntries,
            variant: variant,
            mode: .opaqueIOS
        )
    }
}

private func validateSourceArtwork() throws {
    for variant in variants {
        for filename in [variant.sourceFilename, variant.compactFilename] {
            let source = sourceDirectory.appending(path: filename)
            guard fileManager.fileExists(atPath: source.path) else {
                throw IconGenerationError.missingSource(source.path)
            }
        }
    }
}

private func pruneRetiredAssets() throws {
    for catalog in [macCatalog, iosCatalog] {
        for assetName in retiredAssetNames {
            try removeIfPresent(catalog.appending(path: "\(assetName).appiconset"))
            try removeIfPresent(catalog.appending(path: "\(assetName).imageset"))
            try removeIfPresent(catalog.appending(path: "\(assetName)Preview.imageset"))
        }
    }
}

private func writeImageSet(catalog: URL, variant: IconVariant) throws {
    try removeIfPresent(catalog.appending(path: "\(variant.assetName).imageset"))

    let directory = catalog.appending(path: "\(variant.assetName)Preview.imageset")
    try replaceDirectory(directory)

    let filename = "icon.pdf"
    let data = try runTool("rsvg-convert", arguments: [
        "--format", "pdf", "--width", "1024", "--height", "1024",
        sourceDirectory.appending(path: variant.sourceFilename).path
    ])
    try data.write(to: directory.appending(path: filename), options: .atomic)

    let contents: [String: Any] = [
        "images": [
            [
                "filename": filename,
                "idiom": "universal"
            ]
        ],
        "properties": ["preserves-vector-representation": true],
        "info": [
            "author": "xcode",
            "version": 1
        ]
    ]
    try writeJSON(contents, to: directory.appending(path: "Contents.json"))
}

private func writeAppIconSet(
    catalog: URL,
    name: String,
    entries: [AppIconEntry],
    variant: IconVariant,
    mode: IconRenderMode
) throws {
    let directory = catalog.appending(path: "\(name).appiconset")
    try replaceDirectory(directory)

    for entry in entries {
        let data = try renderIconData(
            variant,
            pixels: entry.pixels,
            logicalSize: Double(entry.size.split(separator: "x")[0])!,
            mode: mode
        )
        try data.write(to: directory.appending(path: entry.filename), options: .atomic)
    }

    let images = entries.map { entry in
        [
            "filename": entry.filename,
            "idiom": entry.idiom,
            "scale": entry.scale,
            "size": entry.size
        ]
    }
    let contents: [String: Any] = [
        "images": images,
        "info": [
            "author": "xcode",
            "version": 1
        ]
    ]
    try writeJSON(contents, to: directory.appending(path: "Contents.json"))
}

private func writeDockIcon(_ variant: IconVariant) throws {
    let temporary = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fileManager.removeItem(at: temporary) }
    try writeAppIconSet(catalog: temporary, name: variant.assetName, entries: macEntries, variant: variant, mode: .sourceArtwork)
    let iconSet = temporary.appending(path: "\(variant.assetName).iconset")
    try fileManager.moveItem(at: temporary.appending(path: "\(variant.assetName).appiconset"), to: iconSet)
    try fileManager.removeItem(at: iconSet.appending(path: "Contents.json"))
    let directory = root.appending(path: "apps/macOS/Resources/AppIcons")
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    _ = try runTool("iconutil", arguments: [
        "--convert", "icns", "--output", directory.appending(path: "\(variant.assetName).icns").path, iconSet.path
    ])
}

private func renderIconData(
    _ variant: IconVariant,
    pixels: Int,
    logicalSize: Double,
    mode: IconRenderMode
) throws -> Data {
    // A 128 px macOS representation also serves 48–64 pt Retina Dock slots.
    var compact = logicalSize <= 64
    if case .sourceArtwork = mode, pixels <= 128 { compact = true }
    let filename = compact ? variant.compactFilename : variant.sourceFilename
    let png = try runTool("rsvg-convert", arguments: [
        "--width", String(pixels), "--height", String(pixels),
        sourceDirectory.appending(path: filename).path
    ])
    guard case .opaqueIOS = mode else { return png }
    guard
        let source = CGImageSourceCreateWithData(png as CFData, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
            bytesPerRow: 0, space: sourceColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
    else { throw IconGenerationError.renderFailed(filename) }
    context.setFillColor(CGColor(gray: variant.backgroundGray, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    guard let rendered = context.makeImage() else { throw IconGenerationError.renderFailed(filename) }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw IconGenerationError.renderFailed(filename)
    }
    CGImageDestinationAddImage(destination, rendered, nil)
    guard CGImageDestinationFinalize(destination) else { throw IconGenerationError.renderFailed(filename) }
    return data as Data
}

private func runTool(_ name: String, arguments: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [name] + arguments
    var environment = ProcessInfo.processInfo.environment
    environment["SOURCE_DATE_EPOCH"] = "0"
    process.environment = environment
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw IconGenerationError.renderFailed(name) }
    return data
}

private func replaceDirectory(_ directory: URL) throws {
    if fileManager.fileExists(atPath: directory.path) {
        try fileManager.removeItem(at: directory)
    }
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
}

private func removeIfPresent(_ url: URL) throws {
    if fileManager.fileExists(atPath: url.path) {
        try fileManager.removeItem(at: url)
    }
}

private func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    try data.write(to: url, options: .atomic)
}

private enum IconGenerationError: LocalizedError {
    case missingDefault(String)
    case missingSource(String)
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingDefault(let assetName):
            return "Unable to find default app icon variant \(assetName)."
        case .missingSource(let path):
            return "Missing app icon source artwork at \(path)."
        case .renderFailed(let filename):
            return "Failed to render app icon from \(filename)."
        }
    }
}
