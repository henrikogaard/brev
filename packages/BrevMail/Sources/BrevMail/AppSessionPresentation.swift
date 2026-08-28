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

enum AppSessionPresentation {
    static func signInErrorMessage(for error: any Error) -> String {
        localizedMessage(
            for: error,
            fallback: String(localized: "Couldn't sign in.", bundle: .module)
        )
    }

    static func restoreErrorMessage(for error: any Error) -> String {
        if let mailError = error as? MailBackendError,
           case .authenticationRequired = mailError,
           KeychainMailCredentialStore.isSystemKeychainLocked {
            return String(
                localized: "Mac Keychain is locked. Unlock your Mac or disable automatic login, then restart Brev.",
                bundle: .module
            )
        }
        return localizedMessage(
            for: error,
            fallback: String(localized: "Couldn't restore your session.", bundle: .module)
        )
    }

    private static func localizedMessage(for error: any Error, fallback: String) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? fallback : message
    }
}
