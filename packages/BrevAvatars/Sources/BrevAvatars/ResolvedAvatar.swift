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

/// Which step of the resolution cascade produced this avatar
/// (ADR-0003 §Resolution cascade).
public enum AvatarSource: String, Sendable, Hashable, Codable {
    case contacts
    case gravatar
    case bimi
    case favicon
    case initials
    case none
}

/// A resolved avatar handed to the UI.
///
/// For non-initials sources `imageData` is the PNG/SVG bytes loaded
/// from the source or cache. For `.initials` and `.none`, callers
/// render a generated initials swatch using `InitialsAvatar`.
public struct ResolvedAvatar: Sendable, Hashable {
    public let email: String
    public let source: AvatarSource
    public let imageData: Data?

    public init(email: String, source: AvatarSource, imageData: Data? = nil) {
        self.email = email
        self.source = source
        self.imageData = imageData
    }
}
