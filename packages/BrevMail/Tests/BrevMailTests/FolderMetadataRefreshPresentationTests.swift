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
import Testing

@Suite("FolderMetadataRefreshPresentation")
struct FolderMetadataRefreshPresentationTests {
    @Test("refresh errors include retry action and localized message")
    func refreshErrorsIncludeRetryActionAndLocalizedMessage() {
        #expect(FolderMetadataRefreshPresentation.refreshErrorStatus(
            for: MailBackendError.network(underlying: "offline")
        ) == MailRootStatus(
            message: "Network error: offline",
            actionTitle: "Try Again"
        ))
    }
}
