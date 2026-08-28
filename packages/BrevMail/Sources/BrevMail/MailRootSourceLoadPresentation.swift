/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 */

import BrevBackend
import Foundation

enum MailRootSourceLoadResult: Sendable {
    case sections([MailSourceSection])
    case failure(accountEmail: String, message: String)
}

struct MailRootSourceLoadFailure: Equatable, Sendable {
    let accountEmail: String
    let message: String
}

struct MailRootSourceLoadSummary: Equatable, Sendable {
    let sections: [MailSourceSection]
    let failures: [MailRootSourceLoadFailure]

    var hasPartialFailure: Bool {
        !sections.isEmpty && !failures.isEmpty
    }
}

enum MailRootSourceLoadPresentation {
    static func summary(for results: [MailRootSourceLoadResult]) -> MailRootSourceLoadSummary {
        var sections: [MailSourceSection] = []
        var failures: [MailRootSourceLoadFailure] = []

        for result in results {
            switch result {
            case .sections(let loadedSections):
                sections.append(contentsOf: loadedSections)
            case .failure(let accountEmail, let message):
                failures.append(MailRootSourceLoadFailure(accountEmail: accountEmail, message: message))
            }
        }

        return MailRootSourceLoadSummary(sections: sections, failures: failures)
    }

    static func partialFailureStatus(for summary: MailRootSourceLoadSummary) -> MailRootStatus? {
        guard summary.hasPartialFailure else { return nil }

        if summary.failures.count == 1, let failure = summary.failures.first {
            let account = failure.accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = failure.message.trimmingCharacters(in: .whitespacesAndNewlines)
            let message: String
            if account.isEmpty, detail.isEmpty {
                message = String(localized: "Couldn't load one mailbox account.", bundle: .module)
            } else if account.isEmpty {
                message = String(localized: "Couldn't load one mailbox account: \(detail)", bundle: .module)
            } else if detail.isEmpty {
                message = String(localized: "Couldn't load mailboxes for \(account).", bundle: .module)
            } else {
                message = String(localized: "Couldn't load mailboxes for \(account): \(detail)", bundle: .module)
            }
            return MailRootStatus(
                message: message,
                tone: .warning,
                actionTitle: String(localized: "Try Again", bundle: .module)
            )
        }

        return MailRootStatus(
            message: String(
                localized: "Couldn't load mailboxes for \(summary.failures.count) accounts.",
                bundle: .module
            ),
            tone: .warning,
            actionTitle: String(localized: "Try Again", bundle: .module)
        )
    }
}
