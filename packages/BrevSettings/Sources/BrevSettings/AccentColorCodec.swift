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
import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum AccentColorCodec {
    static func color(from hex: String) -> Color {
        BrevColor(hex).color
    }

    static func hex(from color: Color) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        #if os(macOS)
        guard let platformColor = NSColor(color).usingColorSpace(.sRGB) else {
            return "#000000"
        }
        platformColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #elseif os(iOS)
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#000000"
        }
        #endif

        return String(
            format: "#%02X%02X%02X",
            component(red),
            component(green),
            component(blue)
        )
    }

    private static func component(_ value: CGFloat) -> Int {
        Int((max(0, min(1, value)) * 255).rounded())
    }
}
