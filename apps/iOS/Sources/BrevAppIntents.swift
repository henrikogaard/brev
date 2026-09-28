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

import AppIntents
import BrevMail
import Foundation

/// "Check Mail" — foregrounds Brev and enqueues a refresh request the
/// mail root drains into its own `refreshVisibleMail` path, so this
/// intent adds no network call of its own (ADR-0006). Foregrounding
/// alone is not enough: `openAppWhenRun` produces no scene-phase
/// transition when the app is already active.
struct CheckMailIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Mail"
    static let description = IntentDescription(
        "Opens Brev and refreshes your mailboxes.",
        categoryName: "Mail"
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        BrevIntentHandoff.shared.requestRefresh()
        return .result()
    }
}

/// "New Message" — enqueues a compose request on the in-process handoff;
/// the app drains it into its normal compose-prefill presentation once
/// it is active.
struct ComposeMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "New Message"
    static let description = IntentDescription(
        "Starts a new message in Brev.",
        categoryName: "Mail"
    )
    static let openAppWhenRun = true

    @Parameter(title: "To")
    var to: String?

    @Parameter(title: "Subject")
    var subject: String?

    @Parameter(title: "Body")
    var body: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        BrevIntentHandoff.shared.requestCompose(
            prefill: ComposePrefill(
                to: to.map { [$0] } ?? [],
                subject: subject ?? "",
                bodyText: body ?? ""
            )
        )
        return .result()
    }
}

/// Shortcuts/Siri exposure for the app's intents.
struct BrevAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckMailIntent(),
            phrases: [
                "Check mail in \(.applicationName)",
                "Refresh \(.applicationName)"
            ],
            shortTitle: "Check Mail",
            systemImageName: "envelope.badge"
        )
        AppShortcut(
            intent: ComposeMessageIntent(),
            phrases: [
                "New message in \(.applicationName)",
                "Send a message with \(.applicationName)"
            ],
            shortTitle: "New Message",
            systemImageName: "square.and.pencil"
        )
    }
}
