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

/// One message preview row the widget can render without touching Brev's
/// stores. Carries only what a notification preview would show —
/// sender and subject, never body text (ADR-0083).
public struct WidgetMessagePreview: Codable, Sendable, Hashable, Identifiable {
    /// Stable identifier so SwiftUI lists diff cleanly across reloads.
    public var id: String { "\(accountName ?? "")|\(subject)|\(receivedAt.timeIntervalSince1970)" }
    public var senderName: String
    public var subject: String
    public var receivedAt: Date
    /// Display name of the owning account so a multi-account widget can
    /// disambiguate previews; nil for single-account installs.
    public var accountName: String?

    public init(senderName: String, subject: String, receivedAt: Date, accountName: String? = nil) {
        self.senderName = senderName
        self.subject = subject
        self.receivedAt = receivedAt
        self.accountName = accountName
    }
}

/// The whole payload a widget needs to render. Written atomically by the
/// app after each sync/materialization; read by the extension.
/// `version` lets a newer app write a shape an older widget still
/// decodes gracefully (unknown fields are ignored; a higher major
/// version falls back to the empty state).
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var generatedAt: Date
    /// Unified-inbox unread total after `badgePolicy` filtering —
    /// the same number the app badge shows.
    public var totalUnread: Int
    /// Newest inbox headers across accounts, newest first. Empty when
    /// the user has preview content hidden in Notification settings.
    public var previews: [WidgetMessagePreview]

    public init(
        version: Int = WidgetSnapshot.currentVersion,
        generatedAt: Date = Date(),
        totalUnread: Int,
        previews: [WidgetMessagePreview]
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.totalUnread = totalUnread
        self.previews = previews
    }

    /// Payload equality ignoring `generatedAt` — the timestamp refreshes
    /// on every publish, so comparing it directly would defeat the
    /// publisher's unchanged-content dedup.
    public func sameContent(as other: WidgetSnapshot) -> Bool {
        version == other.version
            && totalUnread == other.totalUnread
            && previews == other.previews
    }
}
