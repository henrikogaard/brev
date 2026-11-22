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
import Foundation

/// Session-owned executor for Mark-as-read and Archive notification actions
/// (#307, ADR-0075).
///
/// Resolves the targeted account dynamically from connected session backends so
/// actions work both on iOS background wake and on macOS when the main window
/// is closed. Backend mutations route through each provider's offline mutation
/// queue (`PendingMutation`) when offline.
@MainActor
public final class NotificationActionExecutor {
    /// Posted on the default `NotificationCenter` after a notification action
    /// mutates mailbox state so any open mail view can refresh.
    public static let didMutateNotification = Notification.Name(
        "eu.brevmail.notifications.actionDidMutate"
    )

    public var backendsProvider: @MainActor () -> [any MailBackend]
    private let onMutated: (@MainActor (NotificationMailRoute) -> Void)?

    public init(
        backendsProvider: @escaping @MainActor () -> [any MailBackend] = { [] },
        onMutated: (@MainActor (NotificationMailRoute) -> Void)? = nil
    ) {
        self.backendsProvider = backendsProvider
        self.onMutated = onMutated
    }

    /// Marks the targeted message as read on the exact account named in `route`.
    /// Fails closed when that account is not currently connected.
    @discardableResult
    public func markRead(route: NotificationMailRoute) async -> Bool {
        guard let backend = backend(for: route.accountID) else { return false }
        do {
            if let sourceID = route.sourceID {
                try await backend.setRead(true, for: [route.messageID], sourceID: sourceID)
            } else {
                try await backend.setRead(true, for: [route.messageID])
            }
            notifyMutated(route)
            return true
        } catch {
            return false
        }
    }

    /// Moves the targeted message to the account's Archive folder.
    /// Fails closed when the account is disconnected or has no Archive folder.
    @discardableResult
    public func archive(route: NotificationMailRoute) async -> Bool {
        guard let backend = backend(for: route.accountID) else { return false }
        guard let archiveFolder = await resolveArchiveFolder(for: backend, sourceID: route.sourceID) else {
            return false
        }
        do {
            if let sourceID = route.sourceID {
                try await backend.move(messageIDs: [route.messageID], to: archiveFolder, sourceID: sourceID)
            } else {
                try await backend.move(messageIDs: [route.messageID], to: archiveFolder)
            }
            notifyMutated(route)
            return true
        } catch {
            return false
        }
    }

    private func backend(for accountID: String) -> (any MailBackend)? {
        backendsProvider().first { $0.account.id == accountID }
    }

    private func resolveArchiveFolder(
        for backend: any MailBackend,
        sourceID: MailSourceID?
    ) async -> Folder? {
        let folders: [Folder]
        do {
            if let sourceID {
                folders = try await backend.folders(in: sourceID)
            } else {
                folders = try await backend.folders()
            }
        } catch {
            return nil
        }
        return folders.first { $0.role == .archive }
    }

    private func notifyMutated(_ route: NotificationMailRoute) {
        onMutated?(route)
        NotificationCenter.default.post(name: Self.didMutateNotification, object: route)
    }
}
