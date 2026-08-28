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

import SwiftUI

/// Entry sheet for adding a mail account. Email-first configure only — no
/// provider catalog step (ADR-0028 standards-first discovery + skip shortcuts).
public struct MailAccountSetupSheet: View {
    @Bindable private var session: AppSession
    private let initialEmailAddress: String
    private let onClose: () -> Void

    public init(
        session: AppSession,
        initialEmailAddress: String = "",
        onClose: @escaping () -> Void
    ) {
        self.session = session
        self.initialEmailAddress = initialEmailAddress
        self.onClose = onClose
    }

    public var body: some View {
        IMAPAccountSetupSheet(
            session: session,
            initialEmailAddress: initialEmailAddress,
            onClose: onClose
        )
    }
}
