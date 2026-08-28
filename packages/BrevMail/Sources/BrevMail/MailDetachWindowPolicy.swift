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

#if canImport(UIKit)
import SwiftUI
import UIKit
#endif

/// The device idiom relevant to window detachment. UIKit/SwiftUI types are
/// mapped into this neutral enum by the bridge below so the policy itself
/// stays unit-testable on any host (including the macOS test runner, where
/// UIKit is unavailable).
public enum MailWindowIdiom: Sendable { case phone, pad }

/// Decides whether an auxiliary surface opens as a detached window
/// (iPad at regular width, where multiple scenes are useful) or a sheet
/// (iPhone, and iPad in compact width). macOS uses its own NSWindow path
/// and does not consult this policy.
public enum MailDetachWindowPolicy {
    /// Returns `true` when the device and width combination warrants a
    /// detached window rather than a modal sheet.
    public static func shouldDetach(idiom: MailWindowIdiom, isRegularWidth: Bool) -> Bool {
        idiom == .pad && isRegularWidth
    }
}

#if canImport(UIKit)
public extension MailWindowIdiom {
    /// Maps a UIKit interface idiom into the neutral policy idiom. Everything
    /// that is not an iPad is treated as `.phone` — the policy only ever needs
    /// to single out iPad. Centralized here so call sites never re-implement
    /// the `userInterfaceIdiom == .pad` check (which would be prone to drift).
    init(_ idiom: UIUserInterfaceIdiom) {
        self = (idiom == .pad) ? .pad : .phone
    }
}

public extension MailDetachWindowPolicy {
    /// UIKit/SwiftUI-typed convenience that performs both the idiom and the
    /// width mapping in one place, so iOS call sites pass their environment
    /// values directly instead of re-deriving `.pad`/`.regular` inline.
    static func shouldDetach(
        idiom: UIUserInterfaceIdiom,
        horizontalSizeClass: UserInterfaceSizeClass?
    ) -> Bool {
        shouldDetach(idiom: MailWindowIdiom(idiom), isRegularWidth: horizontalSizeClass == .regular)
    }
}
#endif
