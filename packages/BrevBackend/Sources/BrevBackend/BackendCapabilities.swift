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

/// Capability flags advertised by a `MailBackend`.
///
/// View code branches on these — never on the concrete backend type.
/// See ADR-0001 §Capability matrix and ADR-0028 invariant 2.
public struct BackendCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// The backend resolves search queries server-side (vs. scanning a
    /// local cache).
    public static let serverSideSearch = BackendCapabilities(rawValue: 1 << 0)

    /// The backend returns pre-threaded message lists.
    public static let serverSideThreading = BackendCapabilities(rawValue: 1 << 1)

    // Bit 2 was the retired provider-native remote-push capability (ADR-0037).
    // Keep the hole so the remaining capability raw values stay stable.

    /// The backend has first-class label support distinct from folders.
    public static let labels = BackendCapabilities(rawValue: 1 << 3)

    /// The backend can snooze messages server-side.
    public static let snooze = BackendCapabilities(rawValue: 1 << 4)

    /// The backend exposes a server-side endpoint for replying to a
    /// calendar invite (vs. emitting an iMIP REPLY client-side).
    public static let serverSideCalendarReply = BackendCapabilities(rawValue: 1 << 5)

    /// The backend renders ICS attachments into structured calendar
    /// events server-side (vs. parsing them locally).
    public static let serverSideIcsRender = BackendCapabilities(rawValue: 1 << 6)

    /// The backend can request AI compose assistance.
    public static let aiWriter = BackendCapabilities(rawValue: 1 << 7)

    /// The backend requires OAuth authentication; password / app-password
    /// flows are never offered (ADR-0028).
    public static let oauthAuth = BackendCapabilities(rawValue: 1 << 8)

    /// The backend exposes provider-specific REST/Graph/JMAP-style APIs
    /// beyond generic mail transport.
    public static let providerAPI = BackendCapabilities(rawValue: 1 << 9)

    /// The backend can authenticate IMAP through OAuth/XOAUTH2.
    public static let imapOAuth = BackendCapabilities(rawValue: 1 << 10)

    /// The backend can send through SMTP submission. Older provider-roadmap
    /// docs introduced this as SMTP OAuth/XOAUTH2, but standards IMAP/SMTP
    /// accounts also use it for password/app-password SMTP sends.
    public static let smtpOAuth = BackendCapabilities(rawValue: 1 << 11)

    /// The backend exposes JMAP mail primitives.
    public static let jmapMail = BackendCapabilities(rawValue: 1 << 12)

    /// The account can expose more than one mailbox source.
    public static let multipleMailboxes = BackendCapabilities(rawValue: 1 << 13)

    /// The backend can expose delegated or shared mailboxes.
    public static let sharedMailboxes = BackendCapabilities(rawValue: 1 << 14)

    /// The backend can manage server-side rules or filters.
    public static let serverRules = BackendCapabilities(rawValue: 1 << 15)

    /// The backend can manage a server-side vacation/auto-reply.
    public static let autoReply = BackendCapabilities(rawValue: 1 << 16)

    /// The backend can manage server-side aliases.
    public static let aliases = BackendCapabilities(rawValue: 1 << 17)

    /// The backend can manage server-side signatures or templates.
    public static let serverSignatures = BackendCapabilities(rawValue: 1 << 18)

    /// The backend discovered ManageSieve for the mailbox.
    public static let manageSieve = BackendCapabilities(rawValue: 1 << 19)

    /// The backend discovered Sieve vacation support.
    public static let sieveVacation = BackendCapabilities(rawValue: 1 << 20)

    /// The backend can expose raw unsubscribe headers to the domain
    /// parser. The parser itself remains local-only.
    public static let listUnsubscribeHeaders = BackendCapabilities(rawValue: 1 << 21)

    /// The backend exposes provider sync/operation health in addition
    /// to Brev's local diagnostics.
    public static let providerSyncHealth = BackendCapabilities(rawValue: 1 << 22)

    /// The backend supports IMAP IDLE or equivalent live sync.
    public static let idleSync = BackendCapabilities(rawValue: 1 << 23)

    /// The backend supports delta/history sync.
    public static let historyDeltaSync = BackendCapabilities(rawValue: 1 << 24)

    /// The backend can create custom folders.
    public static let folderCreate = BackendCapabilities(rawValue: 1 << 25)

    /// The backend can rename existing folders.
    public static let folderRename = BackendCapabilities(rawValue: 1 << 26)

    /// The backend can delete folders.
    public static let folderDelete = BackendCapabilities(rawValue: 1 << 27)

    /// The backend can purge all messages from a folder server-side
    /// (for example empty Trash or Spam).
    public static let folderFlush = BackendCapabilities(rawValue: 1 << 28)

    /// The backend can persist a per-message flag *color* (vs. only the
    /// boolean flag). Backends without it fall back to a local color
    /// store; see ADR-0019.
    public static let flagColors = BackendCapabilities(rawValue: 1 << 29)

    /// The backend can move messages to the spam/junk folder via a
    /// dedicated API call (vs. a plain folder move). Backends without
    /// this capability fall back to a folder-move to the spam folder.
    public static let junkAPI = BackendCapabilities(rawValue: 1 << 30)

    /// The backend exposes a server-side block-sender action that
    /// prevents future delivery from the blocked address.
    /// Requires the `.junkAPI` capability as a prerequisite.
    public static let blockSender = BackendCapabilities(rawValue: 1 << 31)
}

// Note: BackendCapabilities uses a UInt32 OptionSet (32 bits).
// Additional capability flags must be added to a separate OptionSet
// if more than 32 are needed. See ADR-0001 §Capability matrix.

/// Extended capability flags for v2 provider features.
/// Separate from `BackendCapabilities` to avoid exhausting the 32-bit space.
public struct BackendExtendedCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// The backend can list server-side sender aliases (additional From addresses).
    public static let serverAliases = BackendExtendedCapabilities(rawValue: 1 << 0)

    /// The backend can list and manage server-side signatures.
    public static let serverSignatures = BackendExtendedCapabilities(rawValue: 1 << 1)

    /// The backend exposes server-side signature templates.
    public static let serverSignatureTemplates = BackendExtendedCapabilities(rawValue: 1 << 2)

    /// The backend can manage shared or delegated mailbox membership.
    public static let sharedMailboxManagement = BackendExtendedCapabilities(rawValue: 1 << 3)

    /// The backend can send as another mailbox identity when permission exists.
    public static let sendAs = BackendExtendedCapabilities(rawValue: 1 << 4)

    /// The backend can send on behalf of another mailbox identity when permission exists.
    public static let sendOnBehalf = BackendExtendedCapabilities(rawValue: 1 << 5)

    /// The backend can show provider/admin retention policy metadata.
    public static let retentionPolicyVisibility = BackendExtendedCapabilities(rawValue: 1 << 6)

    /// The backend can manage provider/admin retention policies where allowed.
    public static let retentionPolicyManagement = BackendExtendedCapabilities(rawValue: 1 << 7)

    /// The backend can show or apply sensitivity labels / information protection metadata.
    public static let sensitivityLabels = BackendExtendedCapabilities(rawValue: 1 << 8)

    /// The backend can copy messages into a folder, leaving the originals in
    /// place (distinct from `move`). See ADR-0045.
    public static let messageCopy = BackendExtendedCapabilities(rawValue: 1 << 9)

    /// The backend can return a message's raw RFC822 source, gating View
    /// Source, Save As (.eml), and Show Headers. See ADR-0045.
    public static let rawMessageSource = BackendExtendedCapabilities(rawValue: 1 << 10)

    /// The backend groups messages into conversations itself, from RFC 5322
    /// reply links rather than a server-side thread id. Threading UI treats it
    /// exactly like `.serverSideThreading`; see ADR-0052.
    public static let clientSideThreading = BackendExtendedCapabilities(rawValue: 1 << 11)

    /// The backend can resolve complete message headers from its local cache.
    /// Callers gate `CachedMessageHeaderProviding` on this flag before asking
    /// for the extension service (ADR-0028 invariant 2).
    public static let cachedMessageHeaders = BackendExtendedCapabilities(rawValue: 1 << 12)
}

/// Admin policy restrictions discovered for an account or tenant.
///
/// These are intentionally separate from capabilities: a backend may know how
/// to perform an operation while the tenant policy makes the control read-only
/// or disabled for the current user.
public struct BackendPolicyRestrictions: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let sharedMailboxManagement = BackendPolicyRestrictions(rawValue: 1 << 0)
    public static let sendAs = BackendPolicyRestrictions(rawValue: 1 << 1)
    public static let sendOnBehalf = BackendPolicyRestrictions(rawValue: 1 << 2)
    public static let retentionPolicies = BackendPolicyRestrictions(rawValue: 1 << 3)
    public static let sensitivityLabels = BackendPolicyRestrictions(rawValue: 1 << 4)
}
