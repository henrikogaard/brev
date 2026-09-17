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

import BrevDesign
import SwiftUI

/// Consistent progress, retry, and success affordances for mail reversals.
struct MailUndoToast: View {
    let queue: UndoQueue
    let isBlocked: Bool
    let onUndo: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: BrevSpacing.sm) {
            if queue.isUndoing {
                BrevInlineStatus(message: String(localized: "Undoing change…", bundle: .module), tone: .info)
            } else {
                if let error = queue.errorMessage {
                    BrevToast(
                        message: String(localized: "Couldn’t undo the change: \(error)", bundle: .module),
                        tone: .danger,
                        actionTitle: isBlocked ? nil : String(localized: "Retry Undo", bundle: .module),
                        onAction: isBlocked ? nil : onRetry,
                        onDismiss: { queue.dismissFailure() }
                    )
                }
                if let mutation = queue.current {
                    BrevToast(
                        message: mutation.description,
                        tone: .info,
                        actionTitle: isBlocked ? nil : String(localized: "Undo", bundle: .module),
                        onAction: isBlocked ? nil : onUndo,
                        onDismiss: { queue.dismiss() }
                    )
                }
            }
        }
    }
}
