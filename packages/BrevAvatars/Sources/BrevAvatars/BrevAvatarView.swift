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

import BrevThemes
import CoreGraphics
import Foundation
import Observation
import SwiftUI

/// Shared main-actor observer for avatar preferences so scrolling cells do not
/// each register and tear down 4 `@AppStorage` KVO observers, and only sync
/// preferences to an `AvatarResolver` when they actually change.
@MainActor
@Observable
final class AvatarPreferencesObserver {
    static let shared = AvatarPreferencesObserver()

    private(set) var preferences: AvatarPreferences

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private var observer: NSObjectProtocol?

    private final class WeakResolverState {
        weak var resolver: AvatarResolver?
        var lastSyncedPreferences: AvatarPreferences

        init(resolver: AvatarResolver, preferences: AvatarPreferences) {
            self.resolver = resolver
            lastSyncedPreferences = preferences
        }
    }

    @ObservationIgnored
    private var syncedResolvers: [ObjectIdentifier: WeakResolverState] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = Self.readPreferences(from: defaults)
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refresh() {
        let latest = Self.readPreferences(from: defaults)
        if latest != preferences {
            preferences = latest
        }
    }

    func syncPreferencesIfNeeded(_ preferences: AvatarPreferences, to resolver: AvatarResolver) async {
        let id = ObjectIdentifier(resolver)
        if let existing = syncedResolvers[id],
           existing.resolver === resolver,
           existing.lastSyncedPreferences == preferences {
            return
        }
        await resolver.updatePreferences(preferences)
        if syncedResolvers.count >= 16 {
            syncedResolvers = syncedResolvers.filter { $0.value.resolver != nil }
        }
        syncedResolvers[id] = WeakResolverState(resolver: resolver, preferences: preferences)
    }

    private static func readPreferences(from defaults: UserDefaults) -> AvatarPreferences {
        let useContacts = defaults.object(forKey: "avatar.useContacts") as? Bool ?? true
        let useGravatar = defaults.bool(forKey: "avatar.useGravatar")
        let useBIMI = defaults.bool(forKey: "avatar.useBIMI")
        let useFavicon = defaults.bool(forKey: "avatar.useFavicon")
        return AvatarPreferences(
            useContacts: useContacts,
            useGravatar: useGravatar,
            useBIMI: useBIMI,
            useFavicon: useFavicon
        )
    }
}

/// SwiftUI avatar view. Renders an `AvatarResolver` result inside a
/// circular frame, falling back to deterministic colored initials
/// when no image is available.
///
/// Pulls the colored fallback from the current `BrevTheme`'s
/// `avatarPalette`. Image data is downsampled off the main actor and
/// rendered from a display-sized `CGImage`.
public struct BrevAvatarView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.displayScale) private var displayScale

    private let email: String
    private let displayName: String?
    private let size: CGFloat
    private let resolver: AvatarResolver
    private let preferencesObserver = AvatarPreferencesObserver.shared

    @State private var decodedEntry: (key: AvatarDisplayImageCache.Key, generation: Int, expiresAt: Date, image: CGImage)?

    public init(
        email: String,
        displayName: String? = nil,
        size: CGFloat = 28,
        resolver: AvatarResolver = .shared
    ) {
        self.email = email
        self.displayName = displayName
        self.size = size
        self.resolver = resolver
    }

    public var body: some View {
        let now = Date()
        let preferences = preferencesObserver.preferences
        let currentPixelDimension = pixelDimension
        let resolverID = ObjectIdentifier(resolver).hashValue
        let cacheGeneration = AvatarDisplayImageCache.shared.generation(forResolverID: resolverID)
        let cacheKey = AvatarDisplayImageCache.Key(
            resolverID: resolverID,
            email: email,
            preferences: preferences,
            pixelDimension: currentPixelDimension
        )
        let isLocalEntryExpired = if let decodedEntry,
                                     decodedEntry.key == cacheKey,
                                     decodedEntry.generation == cacheGeneration {
            decodedEntry.expiresAt <= now
        } else {
            false
        }
        let cachedImage: CGImage? = if let decodedEntry,
                                       decodedEntry.key == cacheKey,
                                       decodedEntry.generation == cacheGeneration,
                                       !isLocalEntryExpired {
            decodedEntry.image
        } else {
            AvatarDisplayImageCache.shared.image(for: cacheKey, now: now)
        }
        let taskRequest = AvatarImageLoadRequest(
            email: email,
            displayName: displayName,
            preferences: preferences,
            pixelDimension: currentPixelDimension,
            cacheGeneration: cacheGeneration,
            needsReloadAfterExpiry: isLocalEntryExpired && cachedImage == nil
        )

        Group {
            if let cachedImage {
                // Keep the themed circle swatch behind transparent sender logos
                // without running initials text extraction or rendering letters behind the logo.
                ZStack {
                    Circle()
                        .fill(avatarSwatch.color)
                    Image(decorative: cachedImage, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                }
            } else {
                initialsLayer
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(theme.border.color, lineWidth: 0.5)
        )
        .task(id: taskRequest) {
            if let existing = AvatarDisplayImageCache.shared.entry(for: cacheKey) {
                if decodedEntry?.key != cacheKey
                    || decodedEntry?.generation != cacheGeneration
                    || decodedEntry?.expiresAt != existing.expiresAt {
                    decodedEntry = (cacheKey, cacheGeneration, existing.expiresAt, existing.image)
                }
                return
            }
            await preferencesObserver.syncPreferencesIfNeeded(preferences, to: resolver)
            let resolution = await resolver.resolveWithExpiry(email: email, displayName: displayName)
            guard !Task.isCancelled else { return }
            let thumbnail = await AvatarImageDecoder.shared.thumbnail(
                from: resolution.avatar.imageData,
                maximumPixelDimension: currentPixelDimension
            )
            guard !Task.isCancelled else { return }
            let latestGeneration = AvatarDisplayImageCache.shared.generation(forResolverID: resolverID)
            guard latestGeneration == cacheGeneration else { return }
            AvatarDisplayImageCache.shared.store(
                thumbnail,
                for: cacheKey,
                expiresAt: resolution.expiresAt
            )
            if let thumbnail {
                decodedEntry = (cacheKey, cacheGeneration, resolution.expiresAt, thumbnail)
            } else if decodedEntry?.key == cacheKey {
                decodedEntry = nil
            }
        }
    }

    private var pixelDimension: Int {
        AvatarImageDecodingPolicy.maximumPixelDimension(displaySize: size, displayScale: displayScale)
    }

    private var avatarSwatch: BrevColor {
        let palette = theme.avatarPalette
        return palette.isEmpty
            ? theme.accent
            : palette[InitialsAvatar.colorIndex(email: email, paletteCount: palette.count)]
    }

    @ViewBuilder
    private var initialsLayer: some View {
        let initials = InitialsAvatar.initials(displayName: displayName, email: email)
        let swatch = avatarSwatch
        let foregroundStyle = InitialsAvatar.foregroundStyle(forBackgroundHex: swatch.hex)
        let foreground = switch (foregroundStyle, theme.mode) {
        case (.dark, .light), (.light, .dark):
            theme.textPrimary.color
        case (.dark, .dark), (.light, .light):
            theme.bgPrimary.color
        }
        Circle()
            .fill(swatch.color)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(foreground)
            )
    }
}

private struct AvatarImageLoadRequest: Hashable {
    let email: String
    let displayName: String?
    let preferences: AvatarPreferences
    let pixelDimension: Int
    let cacheGeneration: Int
    let needsReloadAfterExpiry: Bool
}
