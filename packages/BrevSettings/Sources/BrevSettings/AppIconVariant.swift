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

import Foundation

/// User-selectable app icon variants shared by both platform apps.
///
/// The app targets own the actual platform application of the icon:
/// macOS swaps the Dock image and iOS uses alternate app icon names.
public enum AppIconVariant: String, CaseIterable, Codable, Identifiable, Sendable, Hashable {
    case envelopeLight = "envelope-light"
    case envelopeDarkMetal = "envelope-dark-metal"
    case envelopeCarbon = "envelope-carbon"

    public var id: String { rawValue }

    public static let defaultVariant: AppIconVariant = .envelopeLight

    public var title: String {
        metadata.title
    }

    public var subtitle: String {
        metadata.subtitle
    }

    public var assetName: String {
        metadata.assetName
    }

    private var metadata: (title: String, subtitle: String, assetName: String) {
        switch self {
        case .envelopeLight: return (
                String(localized: "Light", bundle: .module),
                String(localized: "Recommended", bundle: .module),
                "BrevIconEnvelopeLight"
            )
        case .envelopeDarkMetal: return (
                String(localized: "Dark Metal", bundle: .module),
                String(localized: "Textured dark", bundle: .module),
                "BrevIconEnvelopeDarkMetal"
            )
        case .envelopeCarbon: return (
                String(localized: "Carbon", bundle: .module),
                String(localized: "Woven black", bundle: .module),
                "BrevIconEnvelopeCarbon"
            )
        }
    }

    public var alternateIconName: String? {
        self == Self.defaultVariant ? nil : assetName
    }

    public var previewAssetName: String {
        "\(assetName)Preview"
    }

    public static func matchingAlternateIconName(_ alternateIconName: String?) -> AppIconVariant {
        allCases.first { $0.alternateIconName == alternateIconName } ?? defaultVariant
    }

    fileprivate static func matchingPersistedRawValue(_ rawValue: String) -> AppIconVariant? {
        if let variant = AppIconVariant(rawValue: rawValue) {
            return variant
        }

        switch rawValue {
        // The retired 20-variant families map to the closest tone in the
        // envelope set so an existing selection keeps a related feel.
        case "solid-white", "solid-light-gray",
             "rose-blush", "light-minimal", "paper", "cream":
            return .envelopeLight
        case "aurora-original", "aurora-minimal-arc", "aurora-thin-lines",
             "aurora-soft-glow", "aurora-diagonal", "aurora-curtain",
             "aurora-green-blue-bands", "aurora-halo",
             "solid-nordic-blue", "gradient-arctic-blue-navy", "gradient-cyan-violet",
             "inverted-light-plane-dark", "inverted-black-3d-metal-gradient",
             "inverted-gunmetal-3d-gradient",
             "graphite-cyan", "cobalt-ice", "nordic-navy",
             "forest-mint", "forest-sage", "mint-ice",
             "plum-lavender", "plum-lilac",
             "ember-coral", "terracotta", "copper-peach", "teal-aqua",
             "classic", "blue", "teal", "gradient", "silver",
             "aurora", "iridescent", "ocean", "navy", "forest",
             "ember", "orange":
            return .envelopeDarkMetal
        case "solid-graphite-gray", "inverted-light-plane-black",
             "inverted-light-plane-graphite", "inverted-brushed-metal-carbon",
             "amber-honey", "sand-ink",
             "slate-silverblue", "fjord-blue", "graphite-mono",
             "slate", "graphite", "ink", "charcoal":
            return .envelopeCarbon
        default: return nil
        }
    }
}

public enum AppIconPreferences {
    public static let iconIDKey = "appearance.appIconVariant"

    public static func load(defaults: UserDefaults = .standard) -> AppIconVariant {
        guard
            let rawValue = defaults.string(forKey: iconIDKey),
            let variant = AppIconVariant.matchingPersistedRawValue(rawValue)
        else {
            return AppIconVariant.defaultVariant
        }

        return variant
    }

    public static func save(_ variant: AppIconVariant, defaults: UserDefaults = .standard) {
        defaults.set(variant.rawValue, forKey: iconIDKey)
    }
}
