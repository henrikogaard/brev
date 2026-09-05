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

@testable import BrevMail
import Testing

@Suite("Mail list load ownership")
@MainActor
struct MailListLoadOwnershipTests {
    @Test("search cancellation during debounce prevents backend work")
    func searchCancellationPreventsWork() async {
        let ownership = MailListLoadOwnership()
        let request = ownership.begin()
        let shouldLoad = await ownership.debounceSearch(request) { _ in throw CancellationError() }
        #expect(!shouldLoad)
    }

    @Test("a late page cannot publish after a newer profile reload")
    func latePageCannotPublish() {
        let ownership = MailListLoadOwnership()
        let first = ownership.begin()
        let second = ownership.begin()
        #expect(!ownership.accepts(first))
        #expect(ownership.accepts(second))
        ownership.invalidate()
        #expect(!ownership.accepts(second))
    }

    @Test("cancelled requests cannot publish even before the replacement starts")
    func cancelledRequestCannotPublish() async {
        let ownership = MailListLoadOwnership()
        let request = ownership.begin()
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return ownership.accepts(request)
        }
        #expect(await task.value == false)
    }
}
