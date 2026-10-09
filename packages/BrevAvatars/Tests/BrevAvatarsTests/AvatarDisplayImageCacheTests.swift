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
import Testing

@MainActor
struct AvatarDisplayImageCacheTests {
    @Test("a recreated row finds the image decoded for the same sender, size and preferences")
    func reusesImageForSameKey() throws {
        let cache = AvatarDisplayImageCache(countLimit: 4)
        let image = try Self.image()
        let key = AvatarDisplayImageCache.Key(
            resolverID: 1, email: " Ada@Example.com ", preferences: .default, pixelDimension: 56
        )
        cache.store(image, for: key)

        let sameSender = AvatarDisplayImageCache.Key(
            resolverID: 1, email: "ada@example.com", preferences: .default, pixelDimension: 56
        )
        #expect(cache.image(for: sameSender) === image)
    }

    @Test("size, preferences and resolver are part of the key")
    func keyIsolatesVariants() throws {
        let cache = AvatarDisplayImageCache(countLimit: 4)
        cache.store(try Self.image(), for: .init(resolverID: 1, email: "a@b.c", preferences: .default, pixelDimension: 56))
        var gravatar = AvatarPreferences.default
        gravatar.useGravatar = true

        #expect(cache.image(for: .init(resolverID: 1, email: "a@b.c", preferences: .default, pixelDimension: 84)) == nil)
        #expect(cache.image(for: .init(resolverID: 1, email: "a@b.c", preferences: gravatar, pixelDimension: 56)) == nil)
        #expect(cache.image(for: .init(resolverID: 2, email: "a@b.c", preferences: .default, pixelDimension: 56)) == nil)
    }

    @Test("storing nil forgets an image the sender no longer has")
    func storingNilRemoves() throws {
        let cache = AvatarDisplayImageCache(countLimit: 4)
        let key = AvatarDisplayImageCache.Key(resolverID: 1, email: "a@b.c", preferences: .default, pixelDimension: 56)
        cache.store(try Self.image(), for: key)
        cache.store(nil, for: key)
        #expect(cache.image(for: key) == nil)
    }

    private static func image() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try #require(context.makeImage())
    }
}
