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

/// The PIM domain a source serves (ADR-0072).
public enum PIMSourceKind: String, Sendable, Hashable, Codable, CaseIterable {
    case calendar
    case contacts
}

/// The protocol family that owns a source. A Google account can own both a
/// Calendar and a Contacts source; DAV providers map one-to-one to kinds.
public enum PIMSourceProvider: String, Sendable, Hashable, Codable {
    case google
    case calDAV
    case cardDAV

    /// The PIM domain this provider serves.
    public var kind: PIMSourceKind {
        switch self {
        case .google, .calDAV:
            return .calendar
        case .cardDAV:
            return .contacts
        }
    }
}

/// Feature-level capability the user enabled on a source. Operation-level
/// limits (per-collection permission, item constraints) are resolved by the
/// services that consume the source (ADR-0072 capability model).
public enum PIMSourceCapability: String, Sendable, Hashable, Codable {
    case read
    case write
}

/// Lifecycle states reported by the shared settings presentation model.
/// Ordering is not meaningful; every state is entered through a serial
/// transition owned by PIMSourceCoordinator.
public enum PIMSourceStatus: String, Sendable, Hashable, Codable, CaseIterable {
    /// Source exists but is not connected; cached content may remain
    /// readable with freshness warnings.
    case disconnected
    /// A connect or reconnect attempt is in flight.
    case connecting
    /// Connected and validated; sync has not necessarily run.
    case ready
    /// A sync generation is in flight.
    case syncing
    /// Connected but the granted scopes or permissions cover only part of
    /// the requested feature set.
    case permissionLimited
    /// The stored credential was rejected or expired; reconnect required.
    case authenticationRequired
    /// The last lifecycle operation failed; statusDetail carries the cause.
    case failed
}

/// Provider-neutral PIM source record (ADR-0072).
///
/// A source is an independently enabled Calendar or Contacts connection. It
/// may link to a mail account (linkedAccountID) or stand alone for DAV
/// providers. Secrets never live on the record: credentialAccount is a
/// Keychain reference resolved by the credential store.
public struct PIMSource: Sendable, Hashable, Codable, Identifiable {
    public typealias ID = String

    public let id: ID
    public var kind: PIMSourceKind
    public var provider: PIMSourceProvider
    /// Mail account this source is attached to, if any. Standalone DAV
    /// sources leave this nil so account removal cannot orphan them.
    public var linkedAccountID: String?
    public var displayName: String
    /// The endpoint the source was validated against (manual or discovered).
    public var endpointURL: URL?
    /// The authenticated principal reported by the provider, when known.
    public var principalURL: URL?
    /// Keychain account key for the stored credential. Never the secret.
    public var credentialAccount: String?
    public var enabledCapabilities: Set<PIMSourceCapability>
    /// Background-sync opt-in. Stays false until the user explicitly enables
    /// the source's sync; connecting alone never schedules work.
    public var syncEnabled: Bool
    public var status: PIMSourceStatus
    /// Short diagnostic for .failed / .permissionLimited; not localized.
    public var statusDetail: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: ID,
        kind: PIMSourceKind,
        provider: PIMSourceProvider,
        linkedAccountID: String? = nil,
        displayName: String,
        endpointURL: URL? = nil,
        principalURL: URL? = nil,
        credentialAccount: String? = nil,
        enabledCapabilities: Set<PIMSourceCapability> = [.read],
        syncEnabled: Bool = false,
        status: PIMSourceStatus = .disconnected,
        statusDetail: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.provider = provider
        self.linkedAccountID = linkedAccountID
        self.displayName = displayName
        self.endpointURL = endpointURL
        self.principalURL = principalURL
        self.credentialAccount = credentialAccount
        self.enabledCapabilities = enabledCapabilities
        self.syncEnabled = syncEnabled
        self.status = status
        self.statusDetail = statusDetail
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Google API scopes requested when a PIM feature is enabled on a Google
/// mail account (ADR-0072 feature-triggered authorization).
///
/// Enablement starts read-only: browsing slices (#6/#8) need only these
/// grants. Authoring slices (#7/#9) re-ask with wider scopes when the user
/// enables editing — consent always follows the feature, never ahead of it.
public enum GooglePIMScopes {
    /// Read-only Calendar scope for browsing connected calendars.
    public static let calendarReadOnly =
        "https://www.googleapis.com/auth/calendar.readonly"
    /// Read-only Contacts scope for browsing connected contacts.
    public static let contactsReadOnly =
        "https://www.googleapis.com/auth/contacts.readonly"

    /// The scopes a source kind needs for initial read-only enablement.
    public static func scopes(for kind: PIMSourceKind) -> Set<String> {
        switch kind {
        case .calendar: return [calendarReadOnly]
        case .contacts: return [contactsReadOnly]
        }
    }
}
