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

@testable import BrevBackend
import Testing

@Suite("OAuthClientConfiguration")
struct OAuthClientConfigurationTests {
    @Test("loads Google and Microsoft client values from environment keys")
    func loadsValuesFromEnvironment() {
        let configuration = OAuthClientConfiguration.load(
            environment: [
                "BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID": " mac-google-client-id ",
                "BREV_GOOGLE_OAUTH_IOS_CLIENT_ID": "123.apps.googleusercontent.com",
                "BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME": "com.googleusercontent.apps.123",
                "BREV_GOOGLE_OAUTH_CLIENT_SECRET": "\ngoogle-client-secret\n",
                "BREV_MICROSOFT_OAUTH_CLIENT_ID": "\tmicrosoft-client-id\t",
            ],
            infoDictionary: [
                "BREVGoogleOAuthMacOSClientID": "info-google-client-id",
                "BREVGoogleOAuthIOSClientID": "info-ios-client-id",
                "BREVGoogleOAuthClientSecret": "info-google-client-secret",
                "BREVMicrosoftOAuthClientID": "info-microsoft-client-id",
            ]
        )

        #expect(configuration.googleMacOSClientID == "mac-google-client-id")
        #expect(configuration.googleIOSClientID == "123.apps.googleusercontent.com")
        #expect(configuration.googleClientSecret == "google-client-secret")
        #expect(configuration.microsoftClientID == "microsoft-client-id")
        #expect(configuration.canStartGoogleOAuth)
        #expect(configuration.canStartMicrosoftOAuth)
    }

    @Test("Info.plist-style keys fill missing values")
    func infoDictionaryFillsMissingValues() {
        let configuration = OAuthClientConfiguration.load(
            environment: [
                "BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID": "env-google-client-id",
            ],
            infoDictionary: [
                "BREVGoogleOAuthMacOSClientID": "info-google-client-id",
                "BREVGoogleOAuthClientSecret": "info-google-client-secret",
                "BREVMicrosoftOAuthClientID": "info-microsoft-client-id",
            ]
        )

        #expect(configuration.googleMacOSClientID == "env-google-client-id")
        #expect(configuration.googleClientSecret == "info-google-client-secret")
        #expect(configuration.microsoftClientID == "info-microsoft-client-id")
    }

    @Test("blank and whitespace values are ignored")
    func blankValuesAreIgnored() {
        let configuration = OAuthClientConfiguration.load(
            environment: [
                "BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID": "   ",
                "BREV_GOOGLE_OAUTH_IOS_CLIENT_ID": "   ",
                "BREV_GOOGLE_OAUTH_CLIENT_SECRET": "\n\t",
                "BREV_MICROSOFT_OAUTH_CLIENT_ID": "",
            ],
            infoDictionary: [
                "BREVGoogleOAuthMacOSClientID": "\tinfo-google-client-id ",
                "BREVGoogleOAuthClientSecret": " info-google-client-secret\n",
                "BREVMicrosoftOAuthClientID": " info-microsoft-client-id ",
            ]
        )

        #expect(configuration.googleMacOSClientID == "info-google-client-id")
        #expect(configuration.googleClientSecret == "info-google-client-secret")
        #expect(configuration.microsoftClientID == "info-microsoft-client-id")
    }

    @Test("blank values without fallback produce disabled OAuth flags")
    func blankValuesWithoutFallbackDisableOAuth() {
        let configuration = OAuthClientConfiguration.load(
            environment: [
                "BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID": "\n",
                "BREV_GOOGLE_OAUTH_IOS_CLIENT_ID": "\n",
                "BREV_GOOGLE_OAUTH_CLIENT_SECRET": " ",
                "BREV_MICROSOFT_OAUTH_CLIENT_ID": "\t",
            ],
            infoDictionary: [
                "BREVGoogleOAuthMacOSClientID": "",
                "BREVGoogleOAuthClientSecret": "\n",
                "BREVMicrosoftOAuthClientID": "  ",
            ]
        )

        #expect(configuration.googleMacOSClientID == "")
        #expect(configuration.googleClientSecret == "")
        #expect(configuration.microsoftClientID == "")
        #expect(!configuration.canStartGoogleOAuth)
        #expect(!configuration.canStartMicrosoftOAuth)
    }

    @Test("legacy Google ID is only accepted for explicit local QA")
    func legacyIDRequiresLocalQA() {
        let disabled = OAuthClientConfiguration.load(
            environment: ["BREV_GOOGLE_OAUTH_CLIENT_ID": "legacy.apps.googleusercontent.com"],
            infoDictionary: nil
        )
        #expect(disabled.googleMacOSClientID == "")

        let enabled = OAuthClientConfiguration.load(
            environment: [
                "BREV_LOCAL_QA": "1",
                "BREV_GOOGLE_OAUTH_CLIENT_ID": "legacy.apps.googleusercontent.com",
            ],
            infoDictionary: nil
        )
        #expect(enabled.googleMacOSClientID == "legacy.apps.googleusercontent.com")
    }

    @Test("iOS callback defaults to Google's reversed client ID")
    func derivesIOSCallback() {
        let configuration = OAuthClientConfiguration(
            googleIOSClientID: "123.apps.googleusercontent.com"
        )
        #expect(configuration.googleIOSCallbackScheme == "com.googleusercontent.apps.123")
        #expect(configuration.googleIOSRedirectURI == "com.googleusercontent.apps.123:/oauth2redirect")
    }

    @Test("blank iOS redirect and callback values derive from the native client")
    func blankIOSRedirectAndCallbackDeriveDefaults() {
        let configuration = OAuthClientConfiguration(
            googleIOSClientID: "123.apps.googleusercontent.com",
            googleIOSRedirectURI: "",
            googleIOSCallbackScheme: ""
        )

        #expect(configuration.googleIOSCallbackScheme == "com.googleusercontent.apps.123")
        #expect(configuration.googleIOSRedirectURI == "com.googleusercontent.apps.123:/oauth2redirect")
    }
}
