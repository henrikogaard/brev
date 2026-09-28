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
import BrevWidgets
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Writes `WidgetSnapshot.json` into the shared App Group container so
/// Home Screen widgets can render the unified inbox without touching
/// Brev's stores, sync engine, or the network (ADR-0083).
///
/// Called from the same choke point as the app-icon badge update: the
/// unread total is derived through `MailBadgePresentation` so the
/// widget always shows exactly the number the badge shows. Message
/// previews are pulled from each backend's *cached* inbox headers —
/// publishing must never trigger network I/O — and are omitted entirely
/// when the user disables notification previews.
@MainActor
public final class WidgetSnapshotPublisher {
    /// Newest previews the widget keeps, per ADR-0083's narrow scope.
    public static let previewLimit = 3

    private let store: WidgetSnapshotStore
    /// The last payload written; identical snapshots skip the write and
    /// the `WidgetCenter` reload so badge refreshes stay cheap.
    private var lastPublished: WidgetSnapshot?

    public init(store: WidgetSnapshotStore = WidgetSnapshotStore()) {
        self.store = store
    }

    /// Chain of queued commits — each publish awaits the previous one
    /// before writing, so commits land strictly in call order and the
    /// newest snapshot always wins the shared file.
    private var commitTail: Task<Void, Never>?

    /// Derives and persists a snapshot if its content differs from the
    /// last one this session published.
    public func publish(
        folders: [Folder],
        sourceSections: [MailSourceSection],
        backends: [any MailBackend],
        settings: NotificationSettings
    ) async {
        let prior = commitTail
        let commit = Task { @MainActor in
            await prior?.value
            await self.commit(
                folders: folders,
                sourceSections: sourceSections,
                backends: backends,
                settings: settings
            )
        }
        commitTail = commit
        await commit.value
    }

    private func commit(
        folders: [Folder],
        sourceSections: [MailSourceSection],
        backends: [any MailBackend],
        settings: NotificationSettings
    ) async {
        let unread = MailBadgePresentation.unreadCount(
            folders: folders,
            sourceSections: sourceSections,
            settings: settings
        )
        let previews = settings.showPreviews
            ? await collectPreviews(sourceSections: sourceSections, backends: backends)
            : []
        let snapshot = WidgetSnapshot(totalUnread: unread, previews: previews)
        if lastPublished.map({ snapshot.sameContent(as: $0) }) == true { return }
        lastPublished = snapshot
        store.save(snapshot)
        #if canImport(WidgetKit) && (os(iOS) || os(macOS))
        WidgetCenter.shared.reloadTimelines(ofKind: "eu.brevmail.brev.widgets.mail-summary")
        #endif
    }

    /// Newest cached inbox headers across visible sources, newest first.
    /// Backends without a header cache contribute nothing; errors are
    /// ignored so a degraded source can't blank the widget.
    private func collectPreviews(
        sourceSections: [MailSourceSection],
        backends: [any MailBackend]
    ) async -> [WidgetMessagePreview] {
        let multiAccount = Set(sourceSections.map(\.account.id)).count > 1
        var headers: [(section: MailSourceSection, header: MessageHeader)] = []
        for section in sourceSections {
            guard let inbox = section.folders.first(where: { $0.role == .inbox }),
                  let backend = backends.first(where: { $0.account.id == section.account.id }),
                  let cached = try? await backend.cachedMessageHeaders(in: inbox, sourceID: section.id)
            else { continue }
            headers.append(contentsOf: cached.map { (section, $0) })
        }
        return headers
            .sorted { $0.header.date > $1.header.date }
            .prefix(Self.previewLimit)
            .map { pair in
                WidgetMessagePreview(
                    senderName: pair.header.from.displayName,
                    subject: pair.header.subject,
                    receivedAt: pair.header.date,
                    accountName: multiAccount ? pair.section.title : nil
                )
            }
    }
}
