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

/// Decides which Appearance-settings controls are shown per platform.
/// Window translucency and transparent-title-bar are macOS chrome with
/// no effect on iOS, so they are hidden there rather than shown inert.
public struct AppearanceControlsPolicy: Equatable, Sendable {
    /// OS-capability granularity, coarser than layout idiom: these flags
    /// gate macOS-only window chrome, not iPad-vs-iPhone layout choices.
    public enum Platform: Sendable { case macOS, iOS }

    public let showsThemePicker: Bool
    public let showsAppIconPicker: Bool
    public let showsWindowTranslucencyControls: Bool
    public let showsTransparentTitleBarToggle: Bool

    /// The control set appropriate for the given platform.
    public static func forPlatform(_ platform: Platform) -> AppearanceControlsPolicy {
        switch platform {
        case .macOS:
            return AppearanceControlsPolicy(
                showsThemePicker: true,
                showsAppIconPicker: true,
                showsWindowTranslucencyControls: true,
                showsTransparentTitleBarToggle: true
            )
        case .iOS:
            return AppearanceControlsPolicy(
                showsThemePicker: true,
                showsAppIconPicker: true,
                showsWindowTranslucencyControls: false,
                showsTransparentTitleBarToggle: false
            )
        }
    }

    /// The policy for the platform this binary is running on.
    public static var current: AppearanceControlsPolicy {
        #if os(macOS)
        forPlatform(.macOS)
        #else
        forPlatform(.iOS)
        #endif
    }
}
