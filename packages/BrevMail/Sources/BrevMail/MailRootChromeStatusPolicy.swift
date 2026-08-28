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

/// Single top-chrome choice for the mail workspace (priority rail).
enum MailRootTopChrome: Equatable, Sendable {
    case rootStatus(MailRootStatus)
    case offline
    case importProgress(ImportProgressBannerPresentation)
}

/// Picks at most one top status surface for `BrevMailRootView`.
enum MailRootChromeStatusPolicy {
    /// Priority: sign-in → offline → non-success root status → import progress/failure.
    static func resolve(
        rootStatus: MailRootStatus?,
        isOnline: Bool,
        importHealth: AccountSyncHealth?,
        folderSyncProgress: MailSyncProgress?
    ) -> MailRootTopChrome? {
        let importPresentation = ImportProgressPresentation.resolve(
            health: importHealth,
            folderSyncProgress: folderSyncProgress
        )

        if importHealth?.state == .authenticationRequired, let importPresentation {
            return .importProgress(importPresentation)
        }

        if !isOnline {
            return .offline
        }

        if let rootStatus, rootStatus.tone != .success {
            return .rootStatus(rootStatus)
        }

        if let importPresentation {
            return .importProgress(importPresentation)
        }

        return nil
    }
}
