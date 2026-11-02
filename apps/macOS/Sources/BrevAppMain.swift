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

import BrevWidgets
import Foundation
import Security
import SwiftUI

@main
@MainActor
enum BrevAppMain {
    static func main() {
        if IsolatedMockConfiguration.isRequested() {
            #if DEBUG
            guard IsolatedMockConfiguration.permitsLaunch(
                info: Bundle.main.infoDictionary ?? [:],
                home: URL(fileURLWithPath: NSHomeDirectory()),
                isDebugBuild: true
            ), hasIsolatedSignature() else {
                exit(EX_CONFIG)
            }
            setenv("BREV_USE_MOCK", "1", 1)
            #else
            exit(EX_CONFIG)
            #endif
        }
        BrevApp.main()
    }

    private static func hasIsolatedSignature() -> Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, [], nil) == errSecSuccess else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information
        ) == errSecSuccess,
            let dictionary = information as? [String: Any],
            let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else {
            return false
        }
        return IsolatedMockConfiguration.hasOnlySandboxEntitlement(entitlements)
    }
}
