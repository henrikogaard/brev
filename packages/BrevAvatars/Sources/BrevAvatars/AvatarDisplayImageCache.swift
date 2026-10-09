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

/// Main-actor memory of the last decoded avatar per sender and size.
///
/// List rows are recreated while scrolling, which resets their `@State`.
/// Without this, every recreated row drew initials for a frame and swapped in
/// the photo after two actor hops (resolve, then decode). Reading this cache
/// synchronously in `body` lets the first frame show the photo.
@MainActor
final class AvatarDisplayImageCache {
    static let shared = AvatarDisplayImageCache(countLimit: 256)

    struct Key: Hashable {
        let resolverID: Int
        let email: String
        let preferences: AvatarPreferences
        let pixelDimension: Int

        init(resolverID: Int, email: String, preferences: AvatarPreferences, pixelDimension: Int) {
            self.resolverID = resolverID
            self.email = AvatarResolver.normalize(email)
            self.preferences = preferences
            self.pixelDimension = pixelDimension
        }

        fileprivate var cacheKey: NSString {
            let flags = [preferences.useContacts, preferences.useGravatar, preferences.useBIMI, preferences.useFavicon]
                .map { $0 ? "1" : "0" }.joined()
            return "\(resolverID)|\(flags)|\(pixelDimension)|\(email)" as NSString
        }
    }

    private final class Box {
        let image: CGImage

        init(_ image: CGImage) {
            self.image = image
        }
    }

    private let cache = NSCache<NSString, Box>()

    init(countLimit: Int) {
        cache.countLimit = countLimit
    }

    func image(for key: Key) -> CGImage? {
        cache.object(forKey: key.cacheKey)?.image
    }

    /// Stores the latest decode; `nil` forgets a photo the sender no longer has.
    func store(_ image: CGImage?, for key: Key) {
        if let image {
            cache.setObject(Box(image), forKey: key.cacheKey)
        } else {
            cache.removeObject(forKey: key.cacheKey)
        }
    }
}
