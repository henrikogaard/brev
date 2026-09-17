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

enum ScheduledSendEditingError: Error, LocalizedError {
    case busy, notFound, stagingUnavailable, invalidDate, sessionChanged

    var errorDescription: String? {
        switch self {
        case .busy: String(
                localized: "A scheduled message is being updated or delivered. Try again when it finishes.",
                bundle: .module
            )
        case .notFound: String(localized: "This scheduled message is no longer available.", bundle: .module)
        case .stagingUnavailable: String(
                localized: "The draft could not be saved locally. Try again.",
                bundle: .module
            )
        case .invalidDate: String(localized: "Choose a valid scheduled send date.", bundle: .module)
        case .sessionChanged: String(localized: "The mailbox session changed. Start this operation again.", bundle: .module)
        }
    }
}
