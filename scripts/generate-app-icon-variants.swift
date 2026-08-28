#!/usr/bin/env swift
/*
 Brev - Mail Client for macOS and iOS
 Copyright (C) 2026 Brev contributors

 Regenerates Brev's primary and alternate app icon assets from the raster
 source artwork in assets/app-icons/source.

 The source pack is full-bleed rounded-tile PNG artwork (1254×1254, aurora,
 solid, gradient, and inverted paper-plane concepts). Two render modes turn
 each master into the platform assets:

 - .opaqueIOS: writes the artwork full-bleed without an alpha channel. iOS app
   icons must be opaque (App Store Connect rejects alpha); the system applies
   its own corner mask.
 - .sourceArtwork: masks the authored rounded tile, keeps transparency outside
   it, and insets the tile to `macTileRatio` so macOS Dock icons and in-app
   previews retain the standard rounded-tile margin.

 Rendering uses CoreGraphics directly, so the script has no external
 dependencies (the previous SVG pipeline shelled out to rsvg-convert).
 */

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct IconVariant {
    let assetName: String
    let sourceFilename: String
}

private struct AppIconEntry {
    let idiom: String
    let size: String
    let scale: String
    let filename: String
    let pixels: Int
}

private enum IconRenderMode {
    /// Masks and insets the authored tile for transparent macOS Dock icons and
    /// in-app previews.
    case sourceArtwork
    /// Composites the full-bleed tile over an opaque background, matching iOS
    /// app icon requirements (no alpha channel).
    case opaqueIOS
}

/// Fraction of the canvas the rounded tile occupies in `.sourceArtwork` mode.
/// Matches the previous SVG tile (x=96, width=832 in a 1024 canvas).
private let macTileRatio = 0.8125
private let sourceCornerRadiusRatio = 0.25

private let variants: [IconVariant] = [
    IconVariant(assetName: "BrevIconAuroraOriginal", sourceFilename: "01-aurora-original.png"),
    IconVariant(assetName: "BrevIconAuroraMinimalArc", sourceFilename: "02-aurora-minimal-arc.png"),
    IconVariant(assetName: "BrevIconAuroraThinLines", sourceFilename: "03-aurora-thin-lines.png"),
    IconVariant(assetName: "BrevIconAuroraSoftGlow", sourceFilename: "04-aurora-soft-glow.png"),
    IconVariant(assetName: "BrevIconAuroraDiagonal", sourceFilename: "05-aurora-diagonal.png"),
    IconVariant(assetName: "BrevIconAuroraCurtain", sourceFilename: "06-aurora-curtain.png"),
    IconVariant(assetName: "BrevIconAuroraGreenBlue", sourceFilename: "07-aurora-green-blue-bands.png"),
    IconVariant(assetName: "BrevIconAuroraHalo", sourceFilename: "08-aurora-halo.png"),
    IconVariant(assetName: "BrevIconSolidWhite", sourceFilename: "09-solid-white.png"),
    IconVariant(assetName: "BrevIconSolidLightGray", sourceFilename: "10-solid-light-gray.png"),
    IconVariant(assetName: "BrevIconSolidGraphite", sourceFilename: "11-solid-graphite-gray.png"),
    IconVariant(assetName: "BrevIconSolidNordicBlue", sourceFilename: "12-solid-nordic-blue.png"),
    IconVariant(assetName: "BrevIconGradientArctic", sourceFilename: "13-gradient-arctic-blue-navy.png"),
    IconVariant(assetName: "BrevIconGradientCyanViolet", sourceFilename: "14-gradient-cyan-violet.png"),
    IconVariant(assetName: "BrevIconInvertedDark", sourceFilename: "15-inverted-light-plane-dark.png"),
    IconVariant(assetName: "BrevIconInvertedBlack", sourceFilename: "16-inverted-light-plane-black.png"),
    IconVariant(assetName: "BrevIconInvertedGraphite", sourceFilename: "17-inverted-light-plane-dark-graphite.png"),
    IconVariant(assetName: "BrevIconInvertedBlackMetal", sourceFilename: "18-inverted-black-3d-metal-gradient.png"),
    IconVariant(assetName: "BrevIconInvertedGunmetal", sourceFilename: "19-inverted-gunmetal-3d-gradient.png"),
    IconVariant(assetName: "BrevIconInvertedCarbon", sourceFilename: "20-inverted-brushed-metal-carbon.png")
]

private let defaultAppIconAssetName = "BrevIconAuroraOriginal"

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
        let source = sourceDirectory.appending(path: variant.sourceFilename)
        guard fileManager.fileExists(atPath: source.path) else {
            throw IconGenerationError.missingSource(source.path)
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

    let filename = "icon_1024.png"
    let data = try renderIconData(variant, pixels: 1024, mode: .sourceArtwork)
    try data.write(to: directory.appending(path: filename), options: .atomic)

    let contents: [String: Any] = [
        "images": [
            [
                "filename": filename,
                "idiom": "universal",
                "scale": "1x"
            ]
        ],
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
        let data = try renderIconData(variant, pixels: entry.pixels, mode: mode)
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

private func renderIconData(
    _ variant: IconVariant,
    pixels: Int,
    mode: IconRenderMode
) throws -> Data {
    let source = sourceDirectory.appending(path: variant.sourceFilename)
    let image = try loadSourceImage(source)

    let context: CGContext
    switch mode {
    case .opaqueIOS:
        guard let ctx = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sourceColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw IconGenerationError.renderFailed(variant.sourceFilename)
        }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        context = ctx

    case .sourceArtwork:
        guard let ctx = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sourceColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw IconGenerationError.renderFailed(variant.sourceFilename)
        }
        ctx.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        ctx.interpolationQuality = .high
        let inset = (Double(pixels) * (1 - macTileRatio)) / 2
        let target = CGRect(
            x: inset,
            y: inset,
            width: Double(pixels) - inset * 2,
            height: Double(pixels) - inset * 2
        )
        ctx.addPath(
            CGPath(
                roundedRect: target,
                cornerWidth: target.width * sourceCornerRadiusRatio,
                cornerHeight: target.height * sourceCornerRadiusRatio,
                transform: nil
            )
        )
        ctx.clip()
        ctx.draw(image, in: target)
        context = ctx
    }

    guard let rendered = context.makeImage() else {
        throw IconGenerationError.renderFailed(variant.sourceFilename)
    }

    let data = NSMutableData()
    guard
        let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw IconGenerationError.renderFailed(variant.sourceFilename)
    }
    CGImageDestinationAddImage(destination, rendered, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw IconGenerationError.renderFailed(variant.sourceFilename)
    }
    return data as Data
}

private func loadSourceImage(_ url: URL) throws -> CGImage {
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw IconGenerationError.invalidSource(url.lastPathComponent)
    }
    return image
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
    case invalidSource(String)
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingDefault(let assetName):
            return "Unable to find default app icon variant \(assetName)."
        case .missingSource(let path):
            return "Missing app icon source artwork at \(path)."
        case .invalidSource(let filename):
            return "Unable to decode source artwork \(filename)."
        case .renderFailed(let filename):
            return "Failed to render app icon from \(filename)."
        }
    }
}
