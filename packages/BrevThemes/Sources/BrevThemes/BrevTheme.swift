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
import SwiftUI

/// Light / dark intent declared by a theme. Mirrors `ColorScheme` but
/// is `Codable` so it survives JSON theme files.
public enum BrevThemeMode: String, Codable, Sendable, Hashable {
    case light
    case dark

    public var colorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// A complete theme: fifteen semantic tokens plus an avatar palette.
///
/// See ADR-0002 §Theme definition. The token set is deliberately
/// fixed; new UI roles get new tokens via a follow-up ADR rather than
/// per-view colors.
public struct BrevTheme: Identifiable, Codable, Sendable, Hashable {
    // Metadata
    public let id: String
    public let name: String
    public let mode: BrevThemeMode
    public let author: String
    public let license: String

    // Surfaces
    public let bgPrimary: BrevColor
    public let bgSecondary: BrevColor
    public let bgTertiary: BrevColor

    // Text
    public let textPrimary: BrevColor
    public let textSecondary: BrevColor
    public let textTertiary: BrevColor

    // Accents
    public let accent: BrevColor
    public let accentMuted: BrevColor
    public let success: BrevColor
    public let warning: BrevColor
    public let danger: BrevColor
    public let info: BrevColor

    // Structure
    public let border: BrevColor
    public let separator: BrevColor
    public let selection: BrevColor

    // Avatar fallback palette (ADR-0003)
    public let avatarPalette: [BrevColor]

    public init(
        id: String,
        name: String,
        mode: BrevThemeMode,
        author: String,
        license: String,
        bgPrimary: BrevColor,
        bgSecondary: BrevColor,
        bgTertiary: BrevColor,
        textPrimary: BrevColor,
        textSecondary: BrevColor,
        textTertiary: BrevColor,
        accent: BrevColor,
        accentMuted: BrevColor,
        success: BrevColor,
        warning: BrevColor,
        danger: BrevColor,
        info: BrevColor,
        border: BrevColor,
        separator: BrevColor,
        selection: BrevColor,
        avatarPalette: [BrevColor]
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.author = author
        self.license = license
        self.bgPrimary = bgPrimary
        self.bgSecondary = bgSecondary
        self.bgTertiary = bgTertiary
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.accent = accent
        self.accentMuted = accentMuted
        self.success = success
        self.warning = warning
        self.danger = danger
        self.info = info
        self.border = border
        self.separator = separator
        self.selection = selection
        self.avatarPalette = avatarPalette
    }

    /// Returns this theme with its semantic accent token replaced.
    ///
    /// All other palette roles remain unchanged so a user accent override
    /// does not silently alter surfaces, status colors, or avatar fallbacks.
    public func withAccent(_ accent: BrevColor) -> BrevTheme {
        BrevTheme(
            id: id,
            name: name,
            mode: mode,
            author: author,
            license: license,
            bgPrimary: bgPrimary,
            bgSecondary: bgSecondary,
            bgTertiary: bgTertiary,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textTertiary: textTertiary,
            accent: accent,
            accentMuted: accentMuted,
            success: success,
            warning: warning,
            danger: danger,
            info: info,
            border: border,
            separator: separator,
            selection: selection,
            avatarPalette: avatarPalette
        )
    }
}

public extension BrevTheme {
    /// Returns this theme with an accent that is readable on all three surfaces.
    func withReadableAccent(increasedContrast: Bool = false) -> BrevTheme {
        let surfaces = [bgPrimary, bgSecondary, bgTertiary]
        let target = increasedContrast ? 7.0 : 4.5
        if surfaces.allSatisfy({ accent.contrastRatio(against: $0) >= target }) {
            return self
        }
        let readable = Self.bestReadableAccent(
            requested: accent,
            surfaces: surfaces,
            target: target
        ) ?? (increasedContrast
            ? Self.bestReadableAccent(requested: accent, surfaces: surfaces, target: 4.5)
            : nil)
        let effective = readable?.color
            ?? Self.bestFallbackAccent(requested: accent, surfaces: surfaces)
        return withAccent(effective)
    }

    /// The effective accent color after applying the normal contrast target.
    var readableAccent: BrevColor {
        withReadableAccent().accent
    }

    /// Foreground color with the strongest contrast against the accent.
    var onAccent: BrevColor {
        let black = BrevColor("#000000")
        let white = BrevColor("#FFFFFF")
        return accent.contrastRatio(against: black) >= accent.contrastRatio(against: white)
            ? black
            : white
    }
}

private extension BrevTheme {
    static let readableAccentSearchSteps = 1024

    struct LuminanceInterval {
        let lower: Double
        let upper: Double
    }

    struct AccentCandidate {
        let color: BrevColor
        let contrast: Double
        let movement: Double
    }

    static func bestReadableAccent(
        requested: BrevColor,
        surfaces: [BrevColor],
        target: Double
    ) -> AccentCandidate? {
        let intervals = readableLuminanceIntervals(surfaces: surfaces, target: target)
        let candidates = [false, true].flatMap { towardWhite in
            intervals.compactMap {
                firstCandidate(
                    requested: requested,
                    surfaces: surfaces,
                    interval: $0,
                    towardWhite: towardWhite,
                    target: target
                )
            }
        }
        return candidates.min { lhs, rhs in
            if lhs.movement != rhs.movement {
                return lhs.movement < rhs.movement
            }
            return lhs.contrast > rhs.contrast
        }
    }

    static func readableLuminanceIntervals(
        surfaces: [BrevColor],
        target: Double
    ) -> [LuminanceInterval] {
        var intervals = [LuminanceInterval(lower: 0, upper: 1)]
        for surface in surfaces {
            let luminance = surface.relativeLuminance
            let lowerBranch = (luminance + 0.05) / target - 0.05
            let upperBranch = target * (luminance + 0.05) - 0.05
            let surfaceIntervals = [
                LuminanceInterval(lower: 0, upper: min(1, lowerBranch)),
                LuminanceInterval(lower: max(0, upperBranch), upper: 1)
            ]
            intervals = intervals.flatMap { current in
                surfaceIntervals.compactMap { allowed in
                    let lower = max(current.lower, allowed.lower)
                    let upper = min(current.upper, allowed.upper)
                    guard lower <= upper else { return nil }
                    return LuminanceInterval(lower: lower, upper: upper)
                }
            }
        }
        return intervals
    }

    static func firstCandidate(
        requested: BrevColor,
        surfaces: [BrevColor],
        interval: LuminanceInterval,
        towardWhite: Bool,
        target: Double
    ) -> AccentCandidate? {
        let first = candidate(
            requested: requested,
            towardWhite: towardWhite,
            step: 0
        )
        let last = candidate(
            requested: requested,
            towardWhite: towardWhite,
            step: readableAccentSearchSteps
        )
        let predicate: (Double) -> Bool = towardWhite
            ? { $0 >= interval.lower }
            : { $0 <= interval.upper }
        guard predicate(first.color.relativeLuminance) || predicate(last.color.relativeLuminance) else {
            return nil
        }

        var lower = 0
        var upper = readableAccentSearchSteps
        while lower < upper {
            let middle = (lower + upper) / 2
            let luminance = candidate(
                requested: requested,
                towardWhite: towardWhite,
                step: middle
            ).color.relativeLuminance
            if predicate(luminance) {
                upper = middle
            } else {
                lower = middle + 1
            }
        }

        let result = candidate(
            requested: requested,
            towardWhite: towardWhite,
            step: lower
        )
        guard result.color.relativeLuminance >= interval.lower,
              result.color.relativeLuminance <= interval.upper,
              result.color.contrastMinimum(on: surfaces) >= target else {
            return nil
        }
        return result
    }

    static func bestFallbackAccent(
        requested: BrevColor,
        surfaces: [BrevColor]
    ) -> BrevColor {
        let surfaceLuminances = surfaces
            .map(\.relativeLuminance)
            .sorted()
        var targetLuminances = [0.0, 1.0]
        if surfaceLuminances.count > 1 {
            for index in 0 ..< (surfaceLuminances.count - 1) {
                let first = log(surfaceLuminances[index] + 0.05)
                let second = log(surfaceLuminances[index + 1] + 0.05)
                targetLuminances.append(exp((first + second) / 2) - 0.05)
            }
        }

        var candidates = [AccentCandidate]()
        for towardWhite in [false, true] {
            candidates.append(candidate(
                requested: requested,
                surfaces: surfaces,
                towardWhite: towardWhite,
                step: 0
            ))
            candidates.append(candidate(
                requested: requested,
                surfaces: surfaces,
                towardWhite: towardWhite,
                step: readableAccentSearchSteps
            ))
            for targetLuminance in targetLuminances {
                let step = nearestStep(
                    requested: requested,
                    towardWhite: towardWhite,
                    targetLuminance: targetLuminance
                )
                for nearbyStep in max(0, step - 1) ... min(readableAccentSearchSteps, step + 1) {
                    candidates.append(candidate(
                        requested: requested,
                        surfaces: surfaces,
                        towardWhite: towardWhite,
                        step: nearbyStep
                    ))
                }
            }
        }

        return candidates.max { lhs, rhs in
            if lhs.contrast != rhs.contrast {
                return lhs.contrast < rhs.contrast
            }
            return lhs.movement > rhs.movement
        }?.color ?? requested
    }

    static func nearestStep(
        requested: BrevColor,
        towardWhite: Bool,
        targetLuminance: Double
    ) -> Int {
        let first = candidate(
            requested: requested,
            towardWhite: towardWhite,
            step: 0
        ).color.relativeLuminance
        let last = candidate(
            requested: requested,
            towardWhite: towardWhite,
            step: readableAccentSearchSteps
        ).color.relativeLuminance
        if towardWhite {
            if targetLuminance <= first { return 0 }
            if targetLuminance >= last { return readableAccentSearchSteps }
        } else {
            if targetLuminance >= first { return 0 }
            if targetLuminance <= last { return readableAccentSearchSteps }
        }

        var lower = 0
        var upper = readableAccentSearchSteps
        while lower < upper {
            let middle = (lower + upper) / 2
            let luminance = candidate(
                requested: requested,
                towardWhite: towardWhite,
                step: middle
            ).color.relativeLuminance
            if towardWhite ? luminance >= targetLuminance : luminance <= targetLuminance {
                upper = middle
            } else {
                lower = middle + 1
            }
        }
        return lower
    }

    static func candidate(
        requested: BrevColor,
        surfaces: [BrevColor] = [],
        towardWhite: Bool,
        step: Int
    ) -> AccentCandidate {
        let start = requested.sRGBComponents
        let progress = Double(step) / Double(readableAccentSearchSteps)
        let red = towardWhite
            ? start.red + (1 - start.red) * progress
            : start.red * (1 - progress)
        let green = towardWhite
            ? start.green + (1 - start.green) * progress
            : start.green * (1 - progress)
        let blue = towardWhite
            ? start.blue + (1 - start.blue) * progress
            : start.blue * (1 - progress)
        let color = BrevColor(
            String(
                format: "#%02X%02X%02X",
                Int((red * 255).rounded()),
                Int((green * 255).rounded()),
                Int((blue * 255).rounded())
            )
        )
        let contrast = color.contrastMinimum(on: surfaces)
        let movement = pow(color.sRGBComponents.red - start.red, 2)
            + pow(color.sRGBComponents.green - start.green, 2)
            + pow(color.sRGBComponents.blue - start.blue, 2)
        return AccentCandidate(color: color, contrast: contrast, movement: movement)
    }
}

private extension BrevColor {
    func contrastMinimum(on surfaces: [BrevColor]) -> Double {
        surfaces.map { contrastRatio(against: $0) }.min() ?? 0
    }
}
