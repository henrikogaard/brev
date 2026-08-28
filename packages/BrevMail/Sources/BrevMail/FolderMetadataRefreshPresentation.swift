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

import Foundation

enum FolderMetadataRefreshPresentation {
    static func refreshErrorStatus(for error: any Error) -> MailRootStatus {
        MailRootStatus(
            message: localizedMessage(for: error),
            actionTitle: "Try Again"
        )
    }

    private static func localizedMessage(for error: any Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Couldn't refresh folders." : message
    }
}
