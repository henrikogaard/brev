/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the conditions in the LICENSE file.
 */

@testable import BrevAvatars
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

struct AvatarImageDecodingPolicyTests {
    @Test("decodes avatar assets at display resolution")
    func decodesAvatarAssetsAtDisplayResolution() {
        #expect(AvatarImageDecodingPolicy.maximumPixelDimension(displaySize: 28) == 56)
        #expect(AvatarImageDecodingPolicy.maximumPixelDimension(displaySize: 28, displayScale: 3) == 84)
        #expect(AvatarImageDecodingPolicy.maximumPixelDimension(displaySize: 0) == 1)
    }

    @Test("downsamples and reuses a decoded avatar image")
    func downsamplesAndCachesDecodedAvatarImage() async throws {
        let decoder = AvatarImageDecoder(cacheCountLimit: 2)
        let data = try Self.pngData(width: 400, height: 200)

        let first = try #require(await decoder.thumbnail(from: data, maximumPixelDimension: 80))
        let second = try #require(await decoder.thumbnail(from: data, maximumPixelDimension: 80))

        #expect(first.width == 80)
        #expect(first.height == 40)
        #expect(second.width == 80)
        #expect(await decoder.decodeCount == 1)
    }

    private static func pngData(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
