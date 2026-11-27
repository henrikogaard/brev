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
import Observation

/// Main-actor memory of the last decoded avatar per sender and size.
///
/// List rows are recreated while scrolling, which resets their `@State`.
/// Without this, every recreated row drew initials for a frame and swapped in
/// the photo after two actor hops (resolve, then decode). Reading this cache
/// synchronously in `body` lets the first frame show the photo.
///
/// Entries carry the resolver's expiry timestamp and are invalidated whenever
/// `AvatarResolver.clearCache()` or preference changes run.
@MainActor
@Observable
final class AvatarDisplayImageCache {
    static let shared = AvatarDisplayImageCache(countLimit: 256)

    private(set) var invalidationGeneration = 0

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
        let expiresAt: Date
        let generation: Int

        init(_ image: CGImage, expiresAt: Date, generation: Int) {
            self.image = image
            self.expiresAt = expiresAt
            self.generation = generation
        }
    }

    @ObservationIgnored
    private let cache = NSCache<NSString, Box>()
    @ObservationIgnored
    private var generationByResolverID: [Int: Int] = [:]

    init(countLimit: Int) {
        cache.countLimit = countLimit
    }

    func generation(forResolverID resolverID: Int) -> Int {
        _ = invalidationGeneration
        return generationByResolverID[resolverID, default: 0]
    }

    func image(for key: Key, now: Date = Date()) -> CGImage? {
        entry(for: key, now: now)?.image
    }

    func entry(for key: Key, now: Date = Date()) -> (image: CGImage, expiresAt: Date)? {
        guard let box = cache.object(forKey: key.cacheKey) else { return nil }
        let currentGeneration = generationByResolverID[key.resolverID, default: 0]
        guard box.generation == currentGeneration, box.expiresAt > now else {
            cache.removeObject(forKey: key.cacheKey)
            return nil
        }
        return (box.image, box.expiresAt)
    }

    /// Stores the latest decode with its resolver expiry; `nil` forgets a photo
    /// the sender no longer has.
    func store(_ image: CGImage?, for key: Key, expiresAt: Date = .distantFuture) {
        if let image {
            let currentGeneration = generationByResolverID[key.resolverID, default: 0]
            cache.setObject(Box(image, expiresAt: expiresAt, generation: currentGeneration), forKey: key.cacheKey)
        } else {
            cache.removeObject(forKey: key.cacheKey)
        }
    }

    /// Invalidates all cached thumbnails for `resolverID` (e.g., on
    /// `AvatarResolver.clearCache()` or preference change).
    func invalidate(resolverID: Int) {
        generationByResolverID[resolverID, default: 0] &+= 1
        invalidationGeneration &+= 1
    }
}
