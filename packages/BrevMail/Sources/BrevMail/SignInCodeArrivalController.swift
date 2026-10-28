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
import Foundation

/// What a sign-in panel shows for one eligible message (ADR-0088 §7).
///
/// Memory-only by contract: no `Codable`, and every default description
/// is redacted so the value never reaches logs or diagnostics by accident.
public struct SignInCodePresentation: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    /// The extracted content.
    public enum Content: Equatable, Sendable {
        /// A one-time code, in its original spelling.
        case code(String)
        /// A sign-in link and the host the panel shows before opening.
        case link(destination: String, host: String)
    }

    /// The account the message arrived on.
    public let accountID: String
    /// The message the content was read from.
    public let messageID: String
    /// Sender display name (falls back to the address).
    public let sender: String
    public let content: Content
    /// How long the panel stays visible.
    public let timeout: TimeInterval

    public var description: String { "SignInCodePresentation(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: EmptyCollection<Mirror.Child>()) }
}

/// The surface that shows and hides sign-in presentations (the macOS panel).
@MainActor
public protocol SignInCodePresenting: AnyObject {
    /// Shows `presentation`; a newer one for the same account and sender
    /// replaces the older.
    func present(_ presentation: SignInCodePresentation)
    /// Hides anything shown for `accountID`.
    func dismiss(accountID: String)
}

/// Turns `.messagesAdded` into sign-in presentations under the ADR-0088
/// gates: per-account consent, the account's trusted-assessment
/// capability, an Inbox-class folder, the provider's trust and freshness
/// assessment, then one body read of the plain-text part only.
///
/// Consent is read before any work and again before the body read and
/// before display; disabling consent or removing the account cancels
/// in-flight work and dismisses the panel. Nothing is persisted or logged.
@MainActor
public final class SignInCodeArrivalController {
    /// Upper bound on messages inspected per event, so a burst cannot
    /// trigger many body reads.
    public static let maxMessagesPerEvent = 5

    private let settings: () -> SignInCodeSettings
    private let presenter: any SignInCodePresenting
    private var tasks: [String: [UUID: Task<Void, Never>]] = [:]

    var pendingInspectionCount: Int { tasks.values.reduce(0) { $0 + $1.count } }

    /// - Parameters:
    ///   - settings: Reads the current device-local consent on each check.
    ///   - presenter: The panel (or a test double).
    public init(
        settings: @escaping () -> SignInCodeSettings,
        presenter: any SignInCodePresenting
    ) {
        self.settings = settings
        self.presenter = presenter
    }

    /// Handles one backend event; anything other than `.messagesAdded`
    /// is ignored.
    public func handle(_ event: MailEvent, from backend: any MailBackend) {
        guard case .messagesAdded(let folderID, let messageIDs) = event else { return }
        let accountID = backend.account.id
        let consent = settings().accountOverride(for: accountID)
        guard consent.codesEnabled || consent.linksEnabled else { return }
        guard backend.extendedCapabilities.contains(.trustedSignInAssessment),
              let assessor = backend as? any SignInTrustAssessing
        else { return }
        for messageID in messageIDs.prefix(Self.maxMessagesPerEvent) {
            let taskID = UUID()
            let task = Task { [weak self] in
                guard let self else { return }
                defer {
                    tasks[accountID]?[taskID] = nil
                    if tasks[accountID]?.isEmpty == true { tasks[accountID] = nil }
                }
                await inspect(
                    messageID: messageID,
                    folderID: folderID,
                    backend: backend,
                    assessor: assessor
                )
            }
            tasks[accountID, default: [:]][taskID] = task
        }
    }

    /// Cancels pending work for the account and hides its panel. Call on
    /// consent changes and account removal.
    public func cancel(accountID: String) {
        tasks[accountID]?.values.forEach { $0.cancel() }
        tasks[accountID] = nil
        presenter.dismiss(accountID: accountID)
    }

    /// Waits for in-flight inspections to settle (tests).
    public func settle() async {
        for task in tasks.values.flatMap({ $0.values }) {
            await task.value
        }
    }

    private func inspect(
        messageID: String,
        folderID: String,
        backend: any MailBackend,
        assessor: any SignInTrustAssessing
    ) async {
        let accountID = backend.account.id
        guard !Task.isCancelled, isConsented(accountID) else { return }
        guard let folder = try? await backend.folders().first(where: { $0.id == folderID }),
              folder.role == .inbox
        else { return }
        guard case .pass = await assessor.signInTrustAssessment(for: messageID) else { return }
        // Recheck consent right before the body read: the toggle may have
        // flipped while the assessment ran.
        guard !Task.isCancelled, isConsented(accountID) else { return }
        guard let body = try? await backend.body(for: messageID),
              let text = body.plainText,
              let candidate = SignInCodeDetector.detect(in: text)
        else { return }
        let consent = settings().accountOverride(for: accountID)
        let content: SignInCodePresentation.Content
        switch candidate {
        case .code(let code):
            guard consent.codesEnabled else { return }
            content = .code(code)
        case .link(let destination, let host):
            guard consent.linksEnabled else { return }
            content = .link(destination: destination, host: host)
        }
        guard !Task.isCancelled else { return }
        let sender = await senderName(for: messageID, in: folder, backend: backend)
        guard !Task.isCancelled else { return }
        let latestConsent = settings().accountOverride(for: accountID)
        switch content {
        case .code: guard latestConsent.codesEnabled else { return }
        case .link: guard latestConsent.linksEnabled else { return }
        }
        presenter.present(
            SignInCodePresentation(
                accountID: accountID,
                messageID: messageID,
                sender: sender,
                content: content,
                timeout: SignInCodeSettings.panelTimeout
            )
        )
    }

    private func isConsented(_ accountID: String) -> Bool {
        let consent = settings().accountOverride(for: accountID)
        return consent.codesEnabled || consent.linksEnabled
    }

    /// The sender's display name from the folder's first page; the
    /// address when the header is not on that page.
    private func senderName(
        for messageID: String,
        in folder: Folder,
        backend: any MailBackend
    ) async -> String {
        let headers = await (try? backend.messages(in: folder, pageToken: nil).headers) ?? []
        guard let header = headers.first(where: { $0.id == messageID }) else { return "" }
        let name = header.from.name?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? header.from.email : name
    }
}
