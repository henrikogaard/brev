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

import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Motion policy for Brev views: animations are dropped when the user has
/// turned on Reduce Motion (WCAG 2.3.3). Use `brevWithAnimation` in place of
/// `withAnimation` and `.brevAnimation(_:value:)` in place of
/// `.animation(_:value:)`.
public enum BrevMotion {
    /// Whether the system Reduce Motion setting is currently on.
    @MainActor
    public static var systemReduceMotion: Bool {
        #if os(macOS)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #elseif canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #else
        false
        #endif
    }

    /// Returns `animation`, or `nil` when Reduce Motion is on.
    /// - Parameters:
    ///   - animation: The animation the call site would normally run.
    ///   - reduceMotion: The Reduce Motion state to honour.
    public static func animation(_ animation: Animation?, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// `withAnimation` that is skipped when Reduce Motion is on. State still
/// changes; it just changes without motion.
/// - Parameters:
///   - animation: The animation to run when motion is allowed.
///   - reduceMotion: Overrides the system setting; `nil` reads the system
///     setting. Tests pass it explicitly.
///   - body: The state mutation to perform.
@MainActor
@discardableResult
public func brevWithAnimation<Result>(
    _ animation: Animation? = .default,
    reduceMotion: Bool? = nil,
    _ body: () throws -> Result
) rethrows -> Result {
    let resolved = reduceMotion ?? BrevMotion.systemReduceMotion
    return try withAnimation(BrevMotion.animation(animation, reduceMotion: resolved), body)
}

private struct BrevAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: Value

    func body(content: Content) -> some View {
        content.animation(BrevMotion.animation(animation, reduceMotion: reduceMotion), value: value)
    }
}

public extension View {
    /// `.animation(_:value:)` that is disabled when Reduce Motion is on.
    /// - Parameters:
    ///   - animation: The animation to apply when motion is allowed.
    ///   - value: The value whose changes trigger the animation.
    func brevAnimation<Value: Equatable>(_ animation: Animation? = .default, value: Value) -> some View {
        modifier(BrevAnimationModifier(animation: animation, value: value))
    }
}
