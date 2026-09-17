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

struct MailRootMailboxLoadRequest: Equatable, Sendable {
    let id: Int
    let sourceID: MailSourceID?

    init(id: Int, sourceID: MailSourceID? = nil) {
        self.id = id
        self.sourceID = sourceID
    }
}

enum MailRootMailboxLoadStartPolicy {
    static func canStartLoad(
        activeRequest: MailRootMailboxLoadRequest?,
        activeMailboxSwitchRequest: MailRootMailboxSwitchRequest?,
        supersedingActiveRequest: Bool = false
    ) -> Bool {
        (activeRequest == nil || supersedingActiveRequest)
            && activeMailboxSwitchRequest == nil
    }
}

enum MailRootMailboxLoadResponsePolicy {
    static func canApplyResponse(
        request: MailRootMailboxLoadRequest,
        activeRequest: MailRootMailboxLoadRequest?,
        currentSourceID: MailSourceID? = nil
    ) -> Bool {
        activeRequest == request && request.sourceID == currentSourceID
    }
}
