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
@testable import BrevMail
import Foundation
import Testing

@Suite("MailSearchFooterPolicy")
struct MailSearchFooterPolicyTests {
    private let source = MailSourceID(accountID: "work", mailboxID: "work")

    private func progress(
        coverage: MailSearchCoverage?,
        complete: Bool,
        failed: Bool = false
    ) -> MailSearchProgressState {
        var state = MailSearchProgressState()
        let request = state.begin(sources: [source])
        if let coverage {
            _ = state.apply(
                MailSearchUpdate(headers: [], coverage: coverage, replacesResults: true, isComplete: complete),
                source: source,
                request: request
            )
        }
        if failed { state.fail(source: source, request: request) }
        return state
    }

    @Test("a complete local search shows no status at all")
    func completeLocalSearchIsSilent() {
        let cached = progress(coverage: .cached, complete: true)
        #expect(!MailSearchFooterPolicy.shouldShow(progress: cached, execution: .cacheOnly, checksAttachments: false))
        // Adapters that do not report coverage give `.unverified` for an automatic search. That is not a failure.
        let unverified = progress(coverage: .unverified, complete: true)
        #expect(!MailSearchFooterPolicy.shouldShow(
            progress: unverified,
            execution: .cacheThenServer,
            checksAttachments: false
        ))
        #expect(!MailSearchFooterPolicy.shouldShow(
            progress: unverified,
            execution: .cacheOnly,
            checksAttachments: false
        ))
    }

    @Test("a failed server search says results are incomplete")
    func failedSearchShows() {
        let state = progress(coverage: .cached, complete: false, failed: true)
        #expect(MailSearchFooterPolicy.shouldShow(
            progress: state,
            execution: .cacheThenServer,
            checksAttachments: false
        ))
    }

    @Test("a server-only search that could not be verified shows the warning")
    func unverifiedServerOnlyShows() {
        let state = progress(coverage: .unverified, complete: true)
        #expect(MailSearchFooterPolicy.shouldShow(progress: state, execution: .serverOnly, checksAttachments: false))
    }

    @Test("cached matches shown while the server is still searching say so")
    func serverStageShows() {
        let state = progress(coverage: .cached, complete: false)
        #expect(MailSearchFooterPolicy.shouldShow(
            progress: state,
            execution: .cacheThenServer,
            checksAttachments: false
        ))
    }

    @Test("the attachment-content disclosure is kept while searching")
    func attachmentDisclosureShows() {
        let state = progress(coverage: nil, complete: false)
        #expect(MailSearchFooterPolicy.shouldShow(
            progress: state,
            execution: .cacheThenServer,
            checksAttachments: true
        ))
        #expect(!MailSearchFooterPolicy.shouldShow(
            progress: state,
            execution: .cacheThenServer,
            checksAttachments: false
        ))
    }

    @Test("no sources, no status")
    func noSources() {
        let state = MailSearchProgressState()
        #expect(!MailSearchFooterPolicy.shouldShow(progress: state, execution: .cacheOnly, checksAttachments: false))
    }
}
