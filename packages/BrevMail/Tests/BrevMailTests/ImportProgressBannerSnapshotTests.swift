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

#if canImport(UIKit)
import BrevDesign
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@Suite("ImportProgressBanner snapshots")
struct ImportProgressBannerSnapshotTests {
    @Test("import progress banner renders in-progress and failure states")
    @MainActor
    func importProgressBannerRendersStates() throws {
        let theme = BrevTheme.brevBuiltIns.first { $0.id == "brev-light" } ?? BrevTheme.brevBuiltIns[0]

        let inProgress = ImportProgressBanner(
            presentation: ImportProgressBannerPresentation(
                phase: .backfillContinuing,
                title: "Downloading mail",
                message: "You can read available messages while Brev downloads the rest.",
                style: .info,
                showsDeterminateProgress: true,
                progressCompleted: 2,
                progressTotal: 5,
                progressFraction: 0.4,
                showsRetryAction: false,
                accessibilityLabel: "Downloading mail. 2 of 5 folders complete."
            ),
            onRetry: nil
        )
        .frame(width: 360)
        .brevTheme(theme)

        let failure = ImportProgressBanner(
            presentation: ImportProgressBannerPresentation(
                phase: .recoverableFailure,
                title: "Sync interrupted",
                message: "Cached mail stays available. Retry when you're back online.",
                style: .warning,
                showsDeterminateProgress: false,
                progressCompleted: nil,
                progressTotal: nil,
                progressFraction: nil,
                showsRetryAction: true,
                accessibilityLabel: "Sync interrupted."
            ),
            onRetry: {}
        )
        .frame(width: 360)
        .brevTheme(theme)

        let inProgressHost = UIHostingController(rootView: inProgress)
        inProgressHost.view.backgroundColor = .clear
        assertSnapshot(
            of: inProgressHost,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: "in-progress"
        )

        let failureHost = UIHostingController(rootView: failure)
        failureHost.view.backgroundColor = .clear
        assertSnapshot(
            of: failureHost,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: "failure"
        )
    }
}
#endif
