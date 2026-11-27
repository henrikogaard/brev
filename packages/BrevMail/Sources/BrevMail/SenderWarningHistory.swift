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

import BrevBackend
import BrevCalendar
import BrevDesign
import BrevSettings
#if canImport(Contacts)
import Contacts
#endif
import SwiftUI

extension RecentRecipientStore {
    @MainActor
    func recordDelivery(of draft: Draft, result: SendResult, accountID: String) {
        let wasSent = result.scheduledFor == nil && !result.warnings.contains(.queuedForRetry)
        record((draft.to + draft.cc + draft.bcc).map { recipient in
            RecentRecipientObservation(accountID: accountID, displayName: recipient.name, email: recipient.email,
                                       date: .now, wasSentTo: wasSent)
        })
    }
}

/// Correspondence evidence for one reader. Retained only for the owning source.
struct SenderWarningHistory: Sendable, Equatable {
    /// Upper bound on Sent headers scanned on a cold cache load so opening a
    /// message never triggers an unbounded `limit: Int.max` SQLite scan.
    static let sentHeaderScanLimit = 500

    var written: Set<String> = []
    var knownDomains: Set<String> = []

    static func load(
        backend: any MailBackend,
        source: MailSourceID,
        sent: [Folder],
        ownAddresses: Set<String>,
        headerLimit: Int = sentHeaderScanLimit
    ) async -> Self {
        guard backend.account.id == source.accountID else { return Self() }
        var written = RecentRecipientStore().writtenAddresses(accountID: source.accountID)
        let boundedProvider = backend.extensionService(BoundedCachedHeaderProviding.self)
        for folder in sent where folder.role == .sent {
            guard !Task.isCancelled else { return Self() }
            let headers: [MessageHeader]
            if let boundedProvider {
                headers = await (try? boundedProvider.cachedMessageHeaders(
                    in: folder,
                    sourceID: source,
                    limit: headerLimit
                )) ?? []
            } else {
                headers = await (try? backend.cachedMessageHeaders(in: folder, sourceID: source)) ?? []
            }
            written.formUnion(recipients(of: headers, ownAddresses: ownAddresses))
        }
        let domains = Set(written.compactMap { address -> String? in
            guard let at = address.lastIndex(of: "@") else { return nil }
            return SenderDomainComparison.decodedHost(String(address[address.index(after: at)...]))
        })
        return Self(written: written, knownDomains: domains)
    }

    static func recipients(of sentHeaders: [MessageHeader], ownAddresses: Set<String>) -> Set<String> {
        var addresses = Set<String>()
        for header in sentHeaders where ownAddresses.contains(header.from.email.lowercased()) {
            for recipient in header.to + header.cc + header.bcc {
                addresses.insert(recipient.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            }
        }
        return addresses
    }
}

/// Bounded in-memory cache of correspondence history keyed by source, Sent
/// folder stamps (`id` + `totalCount`), own addresses, and written-recipient
/// revision. Prevents remounting `SenderWarningHistoryModifier` (for example on
/// iPhone message switches or macOS folder switches) from re-scanning SQLite on
/// every message open (ADR-0061).
@MainActor
final class SenderWarningHistoryCache {
    static let shared = SenderWarningHistoryCache()
    static let defaultCapacity = 16

    struct SentFolderStamp: Hashable, Sendable {
        let id: Folder.ID
        let totalCount: Int
    }

    struct Key: Hashable {
        let backendID: ObjectIdentifier
        let sourceID: MailSourceID
        let sentFolders: [SentFolderStamp]
        let ownAddresses: Set<String>
        let writtenRevision: Int
    }

    private let capacity: Int
    private var entries: [Key: SenderWarningHistory] = [:]
    private var recencyOrder: [Key] = []
    private var inFlightLoads: [Key: Task<SenderWarningHistory, Never>] = [:]
    private(set) var writtenRevision = 0
    private(set) var coldLoadCount = 0

    init(capacity: Int = SenderWarningHistoryCache.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    func value(for key: Key) -> SenderWarningHistory? {
        guard let cached = entries[key] else { return nil }
        touch(key)
        return cached
    }

    func load(
        key: Key,
        backend: any MailBackend,
        sent: [Folder],
        headerLimit: Int = SenderWarningHistory.sentHeaderScanLimit
    ) async -> SenderWarningHistory {
        if let cached = value(for: key) {
            return cached
        }
        if let existing = inFlightLoads[key] {
            return await existing.value
        }
        coldLoadCount += 1
        let task = Task { @MainActor in
            await SenderWarningHistory.load(
                backend: backend,
                source: key.sourceID,
                sent: sent,
                ownAddresses: key.ownAddresses,
                headerLimit: headerLimit
            )
        }
        inFlightLoads[key] = task
        let result = await task.value
        inFlightLoads[key] = nil
        if !Task.isCancelled {
            insert(result, for: key)
        }
        return result
    }

    func invalidateForWrittenAddressesChange() {
        writtenRevision &+= 1
        entries.removeAll()
        recencyOrder.removeAll()
        for task in inFlightLoads.values {
            task.cancel()
        }
        inFlightLoads.removeAll()
    }

    func removeAll() {
        entries.removeAll()
        recencyOrder.removeAll()
        for task in inFlightLoads.values {
            task.cancel()
        }
        inFlightLoads.removeAll()
        coldLoadCount = 0
    }

    private func insert(_ history: SenderWarningHistory, for key: Key) {
        if entries[key] == nil, entries.count >= capacity, let evicted = recencyOrder.first {
            recencyOrder.removeFirst()
            entries.removeValue(forKey: evicted)
        }
        entries[key] = history
        touch(key)
    }

    private func touch(_ key: Key) {
        recencyOrder.removeAll { $0 == key }
        recencyOrder.append(key)
    }
}

private struct SenderWarningHistoryKey: EnvironmentKey {
    static let defaultValue: SenderWarningHistory? = nil
}

private struct TrustedSenderEvaluatorKey: EnvironmentKey {
    static let defaultValue: TrustedSenderEvaluator = .empty
}

extension EnvironmentValues {
    var senderWarningHistory: SenderWarningHistory? {
        get { self[SenderWarningHistoryKey.self] }
        set { self[SenderWarningHistoryKey.self] = newValue }
    }

    var trustedSenderEvaluator: TrustedSenderEvaluator {
        get { self[TrustedSenderEvaluatorKey.self] }
        set { self[TrustedSenderEvaluatorKey.self] = newValue }
    }
}

/// Share a single cache read between all cards in the same reader.
struct SenderWarningHistoryModifier: ViewModifier {
    let backend: any MailBackend
    let sourceID: MailSourceID?
    let folders: [Folder]
    let mailboxEmail: String?
    let contactActions: MailSenderContactActions?
    private let cache: SenderWarningHistoryCache
    @AppStorage(MailboxViewPreferenceKey.allowRemoteContentForTrustedSenders)
    private var allowRemoteContentForTrustedSenders = false
    @State private var loaded: (Request, SenderWarningHistory)?
    @State private var systemContactEmails: Set<String> = []
    @State private var pimContactEmails: Set<String> = []
    @State private var revision = 0
    @State private var systemContactsRevision = 0
    @State private var pimContactsRevision = 0

    init(
        backend: any MailBackend,
        sourceID: MailSourceID?,
        folders: [Folder],
        mailboxEmail: String? = nil,
        contactActions: MailSenderContactActions? = nil,
        cache: SenderWarningHistoryCache = .shared
    ) {
        self.backend = backend
        self.sourceID = sourceID
        self.folders = folders
        self.mailboxEmail = mailboxEmail
        self.contactActions = contactActions
        self.cache = cache
    }

    private struct Request: Equatable {
        let backend: ObjectIdentifier
        let source: MailSourceID
        let sent: [Folder]
        let mine: Set<String>
        let revision: Int

        var cacheKey: SenderWarningHistoryCache.Key {
            SenderWarningHistoryCache.Key(
                backendID: backend,
                sourceID: source,
                sentFolders: sent.map {
                    SenderWarningHistoryCache.SentFolderStamp(id: $0.id, totalCount: $0.totalCount)
                },
                ownAddresses: mine,
                writtenRevision: revision
            )
        }
    }

    private struct SystemContactsRequest: Equatable {
        let isEnabled: Bool
        let revision: Int
    }

    private struct PIMContactsRequest: Equatable {
        let isEnabled: Bool
        let contactActionsID: ObjectIdentifier?
        let revision: Int
    }

    func body(content: Content) -> some View {
        let request = Request(
            backend: ObjectIdentifier(backend),
            source: sourceID ?? MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id),
            sent: folders.filter { $0.role == .sent },
            mine: Set([backend.account.emailAddress, mailboxEmail].compactMap { $0?.lowercased() }),
            revision: cache.writtenRevision &+ revision
        )
        let cacheKey = request.cacheKey
        let systemContactsRequest = SystemContactsRequest(
            isEnabled: allowRemoteContentForTrustedSenders,
            revision: systemContactsRevision
        )
        let pimContactsRequest = PIMContactsRequest(
            isEnabled: allowRemoteContentForTrustedSenders,
            contactActionsID: contactActions.map(ObjectIdentifier.init),
            revision: pimContactsRevision
        )
        let currentHistory = (loaded?.0 == request ? loaded?.1 : nil) ?? cache.value(for: cacheKey)
        let evaluator = TrustedSenderEvaluator(
            contactEmails: allowRemoteContentForTrustedSenders
                ? systemContactEmails.union(pimContactEmails)
                : [],
            repliedToEmails: currentHistory?.written ?? []
        )
        content
            .environment(\.senderWarningHistory, currentHistory)
            .environment(\.trustedSenderEvaluator, evaluator)
            .onReceive(NotificationCenter.default.publisher(for: RecentRecipientStore.writtenAddressesDidChange)
                .receive(on: DispatchQueue.main)) { _ in
                    cache.invalidateForWrittenAddressesChange()
                    revision += 1
            }
        #if canImport(Contacts)
            .onReceive(NotificationCenter.default.publisher(for: .CNContactStoreDidChange)
                .receive(on: DispatchQueue.main)) { _ in
                    guard allowRemoteContentForTrustedSenders else { return }
                    systemContactsRevision += 1
            }
        #endif
            .onReceive(NotificationCenter.default.publisher(for: .pimContactsCacheDidChange)
                .receive(on: DispatchQueue.main)) { _ in
                    guard allowRemoteContentForTrustedSenders else { return }
                    pimContactsRevision += 1
            }
            .task(id: request) {
                if let cached = cache.value(for: cacheKey) {
                    loaded = (request, cached)
                    return
                }
                let result = await cache.load(
                    key: cacheKey,
                    backend: backend,
                    sent: request.sent
                )
                guard !Task.isCancelled else { return }
                loaded = (request, result)
            }
            .task(id: systemContactsRequest) {
                guard systemContactsRequest.isEnabled else {
                    systemContactEmails = []
                    return
                }
                let emails = await SystemContactsRecipientLookup.shared.allContactEmails()
                guard !Task.isCancelled else { return }
                systemContactEmails = emails
            }
            .task(id: pimContactsRequest) {
                guard pimContactsRequest.isEnabled, let contactActions else {
                    pimContactEmails = []
                    return
                }
                let emails = await contactActions.allCachedContactEmails()
                guard !Task.isCancelled else { return }
                pimContactEmails = emails
            }
    }
}
