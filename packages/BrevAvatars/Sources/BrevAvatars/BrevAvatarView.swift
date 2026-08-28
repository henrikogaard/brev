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
import SwiftUI

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
    @AppStorage("avatar.useContacts") private var useContacts = true
    @AppStorage("avatar.useGravatar") private var useGravatar = false
    @AppStorage("avatar.useBIMI") private var useBIMI = false
    @AppStorage("avatar.useFavicon") private var useFavicon = false

    private let email: String
    private let displayName: String?
    private let size: CGFloat
    private let resolver: AvatarResolver

    @State private var avatar: ResolvedAvatar?
    @State private var decodedImage: CGImage?
    @State private var avatarImageRevision = 0

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
        ZStack {
            initialsLayer
            imageLayer
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(theme.border.color, lineWidth: 0.5)
        )
        .task(id: resolutionRequest) {
            await resolver.updatePreferences(resolutionRequest.preferences)
            avatar = await resolver.resolve(email: email, displayName: displayName)
            avatarImageRevision &+= 1
        }
        .task(id: avatarImageRequest) {
            decodedImage = await AvatarImageDecoder.shared.thumbnail(
                from: avatar?.imageData,
                maximumPixelDimension: AvatarImageDecodingPolicy.maximumPixelDimension(
                    displaySize: size,
                    displayScale: displayScale
                )
            )
        }
    }

    private var resolutionRequest: AvatarViewResolutionRequest {
        AvatarViewResolutionRequest(
            email: email,
            displayName: displayName,
            preferences: AvatarPreferences(
                useContacts: useContacts,
                useGravatar: useGravatar,
                useBIMI: useBIMI,
                useFavicon: useFavicon
            )
        )
    }

    private var avatarImageRequest: AvatarImageDecodeRequest {
        AvatarImageDecodeRequest(
            revision: avatarImageRevision,
            displaySize: size,
            displayScale: displayScale
        )
    }

    @ViewBuilder
    private var initialsLayer: some View {
        let initials = InitialsAvatar.initials(displayName: displayName, email: email)
        let palette = theme.avatarPalette
        let background = palette.isEmpty
            ? theme.accent.color
            : palette[InitialsAvatar.colorIndex(email: email, paletteCount: palette.count)].color
        let backgroundHex = palette.isEmpty
            ? theme.accent.hex
            : palette[InitialsAvatar.colorIndex(email: email, paletteCount: palette.count)].hex
        let foregroundStyle = InitialsAvatar.foregroundStyle(forBackgroundHex: backgroundHex)
        let foreground = switch (foregroundStyle, theme.mode) {
        case (.dark, .light), (.light, .dark):
            theme.textPrimary.color
        case (.dark, .dark), (.light, .light):
            theme.bgPrimary.color
        }
        Circle()
            .fill(background)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(foreground)
            )
    }

    @ViewBuilder
    private var imageLayer: some View {
        if let decodedImage {
            Image(decorative: decodedImage, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
    }
}

private struct AvatarImageDecodeRequest: Hashable {
    let revision: Int
    let displaySize: CGFloat
    let displayScale: CGFloat
}
