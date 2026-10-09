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

/// Touch-target floor shared by the Brev controls (Apple HIG: 44 pt).
///
/// Controls scale their metrics with `@ScaledMetric` so hit areas grow with
/// Dynamic Type, but never fall below this floor on iOS.
public enum BrevHitTarget {
    /// Minimum hit-target edge on touch platforms; `0` (no floor) on macOS.
    public static let minimum: CGFloat = {
        #if os(iOS)
        44
        #else
        0
        #endif
    }()

    /// The larger of the platform floor and a Dynamic Type scaled value.
    /// - Parameter scaled: The `@ScaledMetric` value for the current size category.
    public static func resolved(scaled: CGFloat) -> CGFloat {
        max(minimum, scaled)
    }
}
