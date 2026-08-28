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

/// Per-user toggles that decide which external avatar sources Brev
/// is allowed to contact. Every external source defaults **off** —
/// see ADR-0003 §Privacy controls and ADR-0006.
///
/// `Sendable` + `Hashable` so the resolver can key its in-memory
/// cache by `(email, preferences)` and re-resolve when the user flips
/// a toggle.
public struct AvatarPreferences: Sendable, Hashable, Codable {
    /// Look up senders in the user's system Contacts. On by default
    /// because system Contacts data never leaves the device.
    public var useContacts: Bool

    /// Query Gravatar with the SHA-256 of the sender's email.
    /// Off by default — leaks the contact graph to Automattic.
    public var useGravatar: Bool

    /// Query BIMI TXT records on the sender's domain and fetch the
    /// referenced SVG logo. Off by default.
    public var useBIMI: Bool

    /// Fetch the sender domain's favicon. Off by default — favicon
    /// fetches reveal the user's IP to the sender's webserver.
    public var useFavicon: Bool

    public init(
        useContacts: Bool = true,
        useGravatar: Bool = false,
        useBIMI: Bool = false,
        useFavicon: Bool = false
    ) {
        self.useContacts = useContacts
        self.useGravatar = useGravatar
        self.useBIMI = useBIMI
        self.useFavicon = useFavicon
    }

    /// Privacy-strict defaults — initials only, zero external lookups.
    public static let initialsOnly = AvatarPreferences(
        useContacts: false,
        useGravatar: false,
        useBIMI: false,
        useFavicon: false
    )

    /// Out-of-the-box Brev defaults — Contacts only, no network.
    public static let `default` = AvatarPreferences()
}
