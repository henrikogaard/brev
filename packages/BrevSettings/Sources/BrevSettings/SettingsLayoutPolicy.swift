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

#if os(iOS)
typealias SettingsHorizontalSizeClass = UserInterfaceSizeClass
#else
enum SettingsHorizontalSizeClass: Equatable, Sendable {
    case compact
    case regular
}
#endif

enum SettingsLayoutKind: Equatable, Sendable {
    case split
    case stack
}

enum SettingsDeviceIdiom: Equatable, Sendable {
    case phone
    case pad
    case desktop
}

enum SettingsLayoutPolicy {
    static func layout(
        for horizontalSizeClass: SettingsHorizontalSizeClass?,
        device: SettingsDeviceIdiom
    ) -> SettingsLayoutKind {
        switch device {
        case .desktop:
            return .split
        case .phone, .pad:
            break
        }

        return horizontalSizeClass == .compact ? .stack : .split
    }
}

enum SettingsDismissButtonPolicy {
    static func showsDismissButton(device: SettingsDeviceIdiom) -> Bool {
        switch device {
        case .phone, .pad:
            true
        case .desktop:
            false
        }
    }
}
