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
import BrevSettings
import SwiftUI

/// Correspondence evidence for one reader. Retained only for the owning source.
struct SenderWarningHistory: Sendable {
    var written: Set<String> = []
    var knownDomains: Set<String> = []

    static func load(backend: any MailBackend, source: MailSourceID, sent: [Folder], ownAddresses: Set<String>) async -> Self {
        guard backend.account.id == source.accountID else { return Self() }
        var written = RecentRecipientStore().writtenAddresses(accountID: source.accountID)
        for folder in sent where folder.role == .sent {
            guard !Task.isCancelled else { return Self() }
            let headers = await (try? backend.cachedMessageHeaders(in: folder, sourceID: source)) ?? []
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

private struct SenderWarningHistoryKey: EnvironmentKey {
    static let defaultValue: SenderWarningHistory? = nil
}

extension EnvironmentValues {
    var senderWarningHistory: SenderWarningHistory? {
        get { self[SenderWarningHistoryKey.self] }
        set { self[SenderWarningHistoryKey.self] = newValue }
    }
}

/// Share a single cache read between all cards in the same reader.
struct SenderWarningHistoryModifier: ViewModifier {
    let backend: any MailBackend
    let sourceID: MailSourceID?
    let folders: [Folder]
    let mailboxEmail: String?
    @State private var loaded: (Request, SenderWarningHistory)?
    @State private var revision = 0

    init(backend: any MailBackend, sourceID: MailSourceID?, folders: [Folder], mailboxEmail: String? = nil) {
        self.backend = backend
        self.sourceID = sourceID
        self.folders = folders
        self.mailboxEmail = mailboxEmail
    }

    private struct Request: Equatable {
        let backend: ObjectIdentifier
        let source: MailSourceID
        let sent: [Folder]
        let mine: Set<String>
        let revision: Int
    }

    func body(content: Content) -> some View {
        let request = Request(
            backend: ObjectIdentifier(backend),
            source: sourceID ?? MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id),
            sent: folders.filter { $0.role == .sent },
            mine: Set([backend.account.emailAddress, mailboxEmail].compactMap { $0?.lowercased() }),
            revision: revision
        )
        content
            .environment(\.senderWarningHistory, loaded?.0 == request ? loaded?.1 : nil)
            .onReceive(NotificationCenter.default.publisher(for: RecentRecipientStore.writtenAddressesDidChange)
                .receive(on: DispatchQueue.main)) { _ in
                    revision += 1
            }
            .task(id: request) {
                let result = await SenderWarningHistory.load(
                    backend: backend,
                    source: request.source,
                    sent: request.sent,
                    ownAddresses: request.mine
                )
                guard !Task.isCancelled else { return }
                loaded = (request, result)
            }
    }
}
