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

import CoreGraphics
import Foundation
import ImageIO

enum AvatarImageDecodingPolicy {
    static func maximumPixelDimension(
        displaySize: CGFloat,
        displayScale: CGFloat = 2
    ) -> Int {
        max(1, Int((displaySize * displayScale).rounded(.up)))
    }
}

actor AvatarImageDecoder {
    static let shared = AvatarImageDecoder()
    private let cache = NSCache<AvatarImageCacheKey, DecodedAvatarImage>()
    private var decodeCountStorage = 0

    init(cacheCountLimit: Int = 128) {
        cache.countLimit = cacheCountLimit
    }

    var decodeCount: Int {
        decodeCountStorage
    }

    func thumbnail(
        from data: Data?,
        maximumPixelDimension: Int
    ) -> CGImage? {
        guard let data, !data.isEmpty else {
            return nil
        }
        let normalizedMaximumPixelDimension = max(1, maximumPixelDimension)
        let key = AvatarImageCacheKey(data: data, maximumPixelDimension: normalizedMaximumPixelDimension)
        if let cached = cache.object(forKey: key) {
            return cached.image
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil)
        else {
            return nil
        }

        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: normalizedMaximumPixelDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        decodeCountStorage += 1
        cache.setObject(DecodedAvatarImage(image: image), forKey: key)
        return image
    }
}

private final class AvatarImageCacheKey: NSObject {
    private let data: Data
    private let maximumPixelDimension: Int

    init(data: Data, maximumPixelDimension: Int) {
        self.data = data
        self.maximumPixelDimension = maximumPixelDimension
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(data)
        hasher.combine(maximumPixelDimension)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? AvatarImageCacheKey else { return false }
        return data == other.data && maximumPixelDimension == other.maximumPixelDimension
    }
}

private final class DecodedAvatarImage {
    let image: CGImage

    init(image: CGImage) {
        self.image = image
    }
}
