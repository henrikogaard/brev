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

@testable import BrevAvatars
import Foundation
import Testing

#if canImport(Contacts)
import Contacts
#endif

@Suite("AvatarResolver", .serialized)
struct AvatarResolverTests {
    @Test("default preferences do not make external avatar requests")
    func defaultPreferencesDoNotMakeExternalRequests() async {
        let recorder = AvatarRequestRecorder()
        let resolver = AvatarResolver(
            preferences: .default,
            urlSession: Self.urlSession(recorder: recorder),
            contactPhotoProvider: NoContactPhotoProvider()
        )

        let avatar = await resolver.resolve(
            email: "alex@example.test",
            displayName: "Alex"
        )

        #expect(avatar.source == .initials)
        #expect(recorder.urls.isEmpty)
    }

    @Test("enabling an avatar source re-resolves cached initials")
    func enablingAvatarSourceReResolvesCachedInitials() async {
        let favicon = Data([0x00, 0x00, 0x01, 0x00, 0x01])
        let recorder = AvatarRequestRecorder(routes: [
            "/apple-touch-icon.png": AvatarHTTPResponse(statusCode: 404),
            "/favicon.ico": AvatarHTTPResponse(
                data: favicon,
                statusCode: 200,
                contentType: "image/x-icon"
            )
        ])
        let resolver = AvatarResolver(
            preferences: .default,
            urlSession: Self.urlSession(recorder: recorder),
            contactPhotoProvider: NoContactPhotoProvider()
        )

        let initial = await resolver.resolve(
            email: "alex@example.test",
            displayName: "Alex"
        )
        await resolver.updatePreferences(AvatarPreferences(useFavicon: true))
        let resolvedAfterOptIn = await resolver.resolve(
            email: "alex@example.test",
            displayName: "Alex"
        )

        #expect(initial.source == .initials)
        #expect(resolvedAfterOptIn.source == .favicon)
        #expect(resolvedAfterOptIn.imageData == favicon)
        #expect(recorder.urls.map(\.absoluteString) == [
            "https://example.test/apple-touch-icon.png",
            "https://example.test/favicon.ico"
        ])
    }

    @Test("clearing cache discards in-flight avatar results")
    func clearingCacheDiscardsInFlightAvatarResults() async {
        let contactImage = Data([0x89, 0x50, 0x4E, 0x47])
        let provider = DelayedContactPhotoProvider(firstImageData: contactImage)
        let resolver = AvatarResolver(
            preferences: .default,
            urlSession: Self.urlSession(recorder: AvatarRequestRecorder()),
            contactPhotoProvider: provider
        )

        let firstResolve = Task {
            await resolver.resolve(email: "alex@example.test", displayName: "Alex")
        }
        await provider.waitUntilStarted()
        await resolver.clearCache()
        await provider.resume()

        let firstAvatar = await firstResolve.value
        let secondAvatar = await resolver.resolve(
            email: "alex@example.test",
            displayName: "Alex"
        )

        #expect(firstAvatar.source == .contacts)
        #expect(secondAvatar.source == .initials)
        #expect(await provider.requestCount == 2)
    }

    @Test("contacts are preferred before external avatar sources")
    func contactsArePreferredBeforeExternalAvatarSources() async {
        let contactImage = Data([0x89, 0x50, 0x4E, 0x47])
        let recorder = AvatarRequestRecorder(defaultResponse: AvatarHTTPResponse(
            data: Data([0x00, 0x00, 0x01, 0x00, 0x01]),
            statusCode: 200,
            contentType: "image/x-icon"
        ))
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(useGravatar: true, useFavicon: true),
            urlSession: Self.urlSession(recorder: recorder),
            contactPhotoProvider: StubContactPhotoProvider(imageData: contactImage)
        )

        let avatar = await resolver.resolve(
            email: "alex@example.test",
            displayName: "Alex"
        )

        #expect(avatar.source == .contacts)
        #expect(avatar.imageData == contactImage)
        #expect(recorder.urls.isEmpty)
    }

    @Test("contacts can be disabled independently")
    func contactsCanBeDisabledIndependently() async {
        let recorder = AvatarRequestRecorder()
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(useContacts: false),
            urlSession: Self.urlSession(recorder: recorder),
            contactPhotoProvider: StubContactPhotoProvider(imageData: Data([1, 2, 3]))
        )

        let avatar = await resolver.resolve(
            email: "alex@example.test",
            displayName: "Alex"
        )

        #expect(avatar.source == .initials)
        #expect(recorder.urls.isEmpty)
    }

    @Test("process policy prevents every Contacts read")
    func processPolicyPreventsEveryContactsRead() async {
        let original = AvatarPermissionPolicy.allowsSystemContactsAccess
        AvatarPermissionPolicy.allowsSystemContactsAccess = false
        defer { AvatarPermissionPolicy.allowsSystemContactsAccess = original }
        let provider = ConcurrencyTrackingContactPhotoProvider()
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(useContacts: true),
            urlSession: Self.urlSession(recorder: AvatarRequestRecorder()),
            contactPhotoProvider: provider
        )

        let avatar = await resolver.resolve(
            email: "alex@example.test",
            displayName: "Alex"
        )

        #expect(avatar.source == .initials)
        #expect(await provider.totalAccesses == 0)
    }

    #if canImport(Contacts)
    @Test("process policy prevents constructing the system Contacts store")
    func processPolicyPreventsConstructingSystemContactsStore() async {
        let original = AvatarPermissionPolicy.allowsSystemContactsAccess
        AvatarPermissionPolicy.allowsSystemContactsAccess = false
        defer { AvatarPermissionPolicy.allowsSystemContactsAccess = original }
        let recorder = ContactStoreFactoryRecorder()
        let provider = SystemContactPhotoProvider(storeFactory: {
            recorder.makeStore()
        })

        let data = await provider.photoData(for: "alex@example.test")

        #expect(data == nil)
        #expect(recorder.callCount == 0)
    }
    #endif

    @Test("favicon lookup is opt-in and follows the ADR probe order")
    func faviconLookupIsOptInAndFollowsProbeOrder() async {
        let favicon = Data([0x00, 0x00, 0x01, 0x00, 0x01])
        let recorder = AvatarRequestRecorder(routes: [
            "/apple-touch-icon.png": AvatarHTTPResponse(statusCode: 404),
            "/favicon.ico": AvatarHTTPResponse(
                data: favicon,
                statusCode: 200,
                contentType: "image/x-icon"
            )
        ])
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(useFavicon: true),
            urlSession: Self.urlSession(recorder: recorder),
            contactPhotoProvider: NoContactPhotoProvider()
        )

        let avatar = await resolver.resolve(
            email: "alex@example.test",
            displayName: "Alex"
        )

        #expect(avatar.source == .favicon)
        #expect(avatar.imageData == favicon)
        #expect(recorder.urls.map(\.absoluteString) == [
            "https://example.test/apple-touch-icon.png",
            "https://example.test/favicon.ico"
        ])
    }

    @Test("BIMI lookup is opt-in and fetches the linked SVG before favicon")
    func bimiLookupFetchesLinkedSVGBeforeFavicon() async {
        let svg = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
          <rect width="32" height="32"/>
        </svg>
        """.utf8)
        let logoURL = URL(string: "https://brand.example.test/logo.svg")!
        let recorder = AvatarRequestRecorder(routes: [
            "/logo.svg": AvatarHTTPResponse(
                data: svg,
                statusCode: 200,
                contentType: "image/svg+xml"
            ),
            "/apple-touch-icon.png": AvatarHTTPResponse(
                data: Data([0x00, 0x00, 0x01, 0x00, 0x01]),
                statusCode: 200,
                contentType: "image/x-icon"
            )
        ])
        let bimiResolver = StubBIMIRecordResolver(logoURL: logoURL)
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(useBIMI: true, useFavicon: true),
            urlSession: Self.urlSession(recorder: recorder),
            contactPhotoProvider: NoContactPhotoProvider(),
            bimiRecordResolver: bimiResolver,
            dmarcPolicyResolver: StubDMARCPolicyResolver(policy: .reject)
        )

        let avatar = await resolver.resolve(
            email: "alex@example.test",
            displayName: "Alex"
        )

        #expect(avatar.source == .bimi)
        #expect(avatar.imageData == svg)
        #expect(await bimiResolver.domains == ["example.test"])
        #expect(recorder.urls.map(\.absoluteString) == [
            "https://brand.example.test/logo.svg"
        ])
    }

    @Test("BIMI is preferred before Gravatar when both sources are enabled")
    func bimiIsPreferredBeforeGravatarWhenBothSourcesAreEnabled() async {
        let svg = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
          <rect width="32" height="32"/>
        </svg>
        """.utf8)
        let logoURL = URL(string: "https://brand.example.test/logo.svg")!
        let recorder = AvatarRequestRecorder(routes: [
            "/logo.svg": AvatarHTTPResponse(
                data: svg,
                statusCode: 200,
                contentType: "image/svg+xml"
            )
        ])
        let bimiResolver = StubBIMIRecordResolver(logoURL: logoURL)
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(useGravatar: true, useBIMI: true),
            urlSession: Self.urlSession(recorder: recorder),
            contactPhotoProvider: NoContactPhotoProvider(),
            bimiRecordResolver: bimiResolver,
            dmarcPolicyResolver: StubDMARCPolicyResolver(policy: .reject)
        )

        let avatar = await resolver.resolve(
            email: "alex@example.test",
            displayName: "Alex"
        )

        #expect(avatar.source == .bimi)
        #expect(avatar.imageData == svg)
        #expect(await bimiResolver.domains == ["example.test"])
        #expect(recorder.urls.map(\.absoluteString) == [
            "https://brand.example.test/logo.svg"
        ])
    }

    @Test("unsafe BIMI logo URLs fall through to favicon")
    func unsafeBIMILogoURLsFallThroughToFavicon() async {
        let favicon = Data([0x00, 0x00, 0x01, 0x00, 0x01])
        let recorder = AvatarRequestRecorder(routes: [
            "/apple-touch-icon.png": AvatarHTTPResponse(
                data: favicon,
                statusCode: 200,
                contentType: "image/x-icon"
            )
        ])
        let bimiResolver = StubBIMIRecordResolver(
            logoURL: URL(string: "http://brand.example.test/logo.svg")!
        )
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(useBIMI: true, useFavicon: true),
            urlSession: Self.urlSession(recorder: recorder),
            contactPhotoProvider: NoContactPhotoProvider(),
            bimiRecordResolver: bimiResolver,
            dmarcPolicyResolver: StubDMARCPolicyResolver(policy: .reject)
        )

        let avatar = await resolver.resolve(
            email: "alex@example.test",
            displayName: "Alex"
        )

        #expect(avatar.source == .favicon)
        #expect(avatar.imageData == favicon)
        #expect(await bimiResolver.domains == ["example.test"])
        #expect(recorder.urls.map(\.absoluteString) == [
            "https://example.test/apple-touch-icon.png"
        ])
    }

    @Test("BIMI SVG validation rejects remote references")
    func bimiSVGValidationRejectsRemoteReferences() {
        let inlineSVG = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
          <rect width="32" height="32"/>
        </svg>
        """.utf8)
        let remoteImageSVG = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
          <image href="https://tracker.example.test/pixel.png"/>
        </svg>
        """.utf8)
        let remoteStyleSVG = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
          <style>@import url("https://tracker.example.test/logo.css");</style>
        </svg>
        """.utf8)

        #expect(AvatarResolver.isSupportedBIMILogo(data: inlineSVG, contentType: "image/svg+xml"))
        #expect(!AvatarResolver.isSupportedBIMILogo(data: remoteImageSVG, contentType: "image/svg+xml"))
        #expect(!AvatarResolver.isSupportedBIMILogo(data: remoteStyleSVG, contentType: "image/svg+xml"))
    }

    @Test("BIMI SVG exceeding 32 KB is rejected")
    func bimiSVGExceeding32KBIsRejected() {
        let svgHeader = "<svg xmlns=\"http://www.w3.org/2000/svg\">"
        let svgFooter = "</svg>"
        let padding = String(repeating: "<!-- padding -->", count: 2200)
        let oversizedSVG = Data((svgHeader + padding + svgFooter).utf8)

        #expect(oversizedSVG.count > AvatarResolver.maximumSVGByteCount)
        #expect(!AvatarResolver.isSupportedBIMILogo(data: oversizedSVG, contentType: "image/svg+xml"))
    }

    @Test("BIMI SVG exactly at 32 KB is accepted")
    func bimiSVGAtSizeLimitIsAccepted() {
        // Build an SVG that fits within maximumSVGByteCount bytes.
        let svgHeader = "<svg xmlns=\"http://www.w3.org/2000/svg\">"
        let svgFooter = "</svg>"
        let available = AvatarResolver.maximumSVGByteCount - svgHeader.utf8.count - svgFooter.utf8.count
        let padding = String(repeating: "x", count: available)
        let justRightSVG = Data((svgHeader + padding + svgFooter).utf8)

        #expect(justRightSVG.count == AvatarResolver.maximumSVGByteCount)
        #expect(AvatarResolver.isSupportedBIMILogo(data: justRightSVG, contentType: "image/svg+xml"))
    }

    @Test("DMARC p=none causes BIMI fallback to initials")
    func dmarcNonePolicyFallsBackToInitials() async {
        let svg = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
          <rect width="32" height="32"/>
        </svg>
        """.utf8)
        let logoURL = URL(string: "https://example.test/logo.svg")!
        let recorder = AvatarRequestRecorder(routes: [
            "/logo.svg": AvatarHTTPResponse(
                data: svg,
                statusCode: 200,
                contentType: "image/svg+xml"
            )
        ])
        let bimiResolver = StubBIMIRecordResolver(logoURL: logoURL)
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(useBIMI: true),
            urlSession: Self.urlSession(recorder: recorder),
            contactPhotoProvider: NoContactPhotoProvider(),
            bimiRecordResolver: bimiResolver,
            dmarcPolicyResolver: StubDMARCPolicyResolver(policy: .none)
        )

        let avatar = await resolver.resolve(
            email: "alex@example.test",
            displayName: "Alex"
        )

        #expect(avatar.source == .initials)
        #expect(recorder.urls.isEmpty, "BIMI logo must not be fetched when DMARC policy is p=none")
    }

    @Test("DMARC unknown policy causes BIMI fallback to initials")
    func dmarcUnknownPolicyFallsBackToInitials() async {
        let svg = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
          <rect width="32" height="32"/>
        </svg>
        """.utf8)
        let logoURL = URL(string: "https://example.test/logo.svg")!
        let recorder = AvatarRequestRecorder(routes: [
            "/logo.svg": AvatarHTTPResponse(
                data: svg,
                statusCode: 200,
                contentType: "image/svg+xml"
            )
        ])
        let bimiResolver = StubBIMIRecordResolver(logoURL: logoURL)
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(useBIMI: true),
            urlSession: Self.urlSession(recorder: recorder),
            contactPhotoProvider: NoContactPhotoProvider(),
            bimiRecordResolver: bimiResolver,
            dmarcPolicyResolver: StubDMARCPolicyResolver(policy: .unknown)
        )

        let avatar = await resolver.resolve(
            email: "alex@example.test",
            displayName: "Alex"
        )

        #expect(avatar.source == .initials)
        #expect(recorder.urls.isEmpty)
    }

    @Test("BIMI SVG URL on a different domain is rejected")
    func bimiSVGURLOnDifferentDomainIsRejected() async {
        let svg = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
          <rect width="32" height="32"/>
        </svg>
        """.utf8)
        // Logo hosted on attacker.test, sender is example.test.
        let logoURL = URL(string: "https://attacker.test/logo.svg")!
        let recorder = AvatarRequestRecorder(routes: [
            "/logo.svg": AvatarHTTPResponse(
                data: svg,
                statusCode: 200,
                contentType: "image/svg+xml"
            )
        ])
        let bimiResolver = StubBIMIRecordResolver(logoURL: logoURL)
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(useBIMI: true),
            urlSession: Self.urlSession(recorder: recorder),
            contactPhotoProvider: NoContactPhotoProvider(),
            bimiRecordResolver: bimiResolver,
            dmarcPolicyResolver: StubDMARCPolicyResolver(policy: .reject)
        )

        let avatar = await resolver.resolve(
            email: "alex@example.test",
            displayName: "Alex"
        )

        #expect(avatar.source == .initials)
        #expect(recorder.urls.isEmpty, "Logo on a foreign domain must not be fetched")
    }

    @Test("BIMI SVG URL on a subdomain of the sender's domain is accepted")
    func bimiSVGURLOnSubdomainOfSenderDomainIsAccepted() async {
        let svg = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
          <rect width="32" height="32"/>
        </svg>
        """.utf8)
        // Logo hosted on brand.example.test; sender is example.test.
        let logoURL = URL(string: "https://brand.example.test/logo.svg")!
        let recorder = AvatarRequestRecorder(routes: [
            "/logo.svg": AvatarHTTPResponse(
                data: svg,
                statusCode: 200,
                contentType: "image/svg+xml"
            )
        ])
        let bimiResolver = StubBIMIRecordResolver(logoURL: logoURL)
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(useBIMI: true),
            urlSession: Self.urlSession(recorder: recorder),
            contactPhotoProvider: NoContactPhotoProvider(),
            bimiRecordResolver: bimiResolver,
            dmarcPolicyResolver: StubDMARCPolicyResolver(policy: .reject)
        )

        let avatar = await resolver.resolve(
            email: "alex@example.test",
            displayName: "Alex"
        )

        #expect(avatar.source == .bimi)
        #expect(avatar.imageData == svg)
        #expect(recorder.urls.map(\.absoluteString) == [
            "https://brand.example.test/logo.svg"
        ])
    }

    @Test("origin-domain cross-check helpers work correctly")
    func originDomainCrossCheckHelpersWorkCorrectly() {
        // Same domain.
        #expect(AvatarResolver.isBIMILogoURLOnSenderDomain(
            URL(string: "https://example.test/logo.svg")!,
            senderDomain: "example.test"
        ))
        // Subdomain of sender domain.
        #expect(AvatarResolver.isBIMILogoURLOnSenderDomain(
            URL(string: "https://brand.example.test/logo.svg")!,
            senderDomain: "example.test"
        ))
        // Deep subdomain.
        #expect(AvatarResolver.isBIMILogoURLOnSenderDomain(
            URL(string: "https://a.b.example.test/logo.svg")!,
            senderDomain: "example.test"
        ))
        // Unrelated domain — rejected.
        #expect(!AvatarResolver.isBIMILogoURLOnSenderDomain(
            URL(string: "https://attacker.test/logo.svg")!,
            senderDomain: "example.test"
        ))
        // Domain that shares a suffix but is not a subdomain — rejected.
        #expect(!AvatarResolver.isBIMILogoURLOnSenderDomain(
            URL(string: "https://notexample.test/logo.svg")!,
            senderDomain: "example.test"
        ))
    }

    @Test("invalid favicon responses fall through to initials")
    func invalidFaviconResponsesFallThroughToInitials() async {
        let recorder = AvatarRequestRecorder(routes: [
            "/apple-touch-icon.png": AvatarHTTPResponse(
                data: Data("<html></html>".utf8),
                statusCode: 200,
                contentType: "text/html"
            ),
            "/favicon.ico": AvatarHTTPResponse(statusCode: 404)
        ])
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(useFavicon: true),
            urlSession: Self.urlSession(recorder: recorder),
            contactPhotoProvider: NoContactPhotoProvider()
        )

        let avatar = await resolver.resolve(
            email: "alex@example.test",
            displayName: "Alex"
        )

        #expect(avatar.source == .initials)
        #expect(recorder.urls.map(\.absoluteString) == [
            "https://example.test/apple-touch-icon.png",
            "https://example.test/favicon.ico",
            "https://www.example.test/favicon.ico"
        ])
    }

    @Test("public mail provider domains are excluded from favicon fallback")
    func publicMailProviderDomainsAreExcludedFromFaviconFallback() async {
        let recorder = AvatarRequestRecorder(defaultResponse: AvatarHTTPResponse(
            data: Data([0x00, 0x00, 0x01, 0x00, 0x01]),
            statusCode: 200,
            contentType: "image/x-icon"
        ))
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(useFavicon: true),
            urlSession: Self.urlSession(recorder: recorder),
            contactPhotoProvider: NoContactPhotoProvider()
        )

        let avatar = await resolver.resolve(
            email: "alex@gmail.com",
            displayName: "Alex"
        )

        #expect(avatar.source == .initials)
        #expect(recorder.urls.isEmpty)
    }

    @Test("successful favicon results are reused from cache")
    func successfulFaviconResultsAreReusedFromCache() async {
        let favicon = Data([0x00, 0x00, 0x01, 0x00, 0x01])
        let recorder = AvatarRequestRecorder(routes: [
            "/apple-touch-icon.png": AvatarHTTPResponse(
                data: favicon,
                statusCode: 200,
                contentType: "image/x-icon"
            )
        ])
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(useFavicon: true),
            urlSession: Self.urlSession(recorder: recorder),
            contactPhotoProvider: NoContactPhotoProvider()
        )

        let first = await resolver.resolve(email: "alex@example.test", displayName: "Alex")
        let second = await resolver.resolve(email: "alex@example.test", displayName: "Alex")

        #expect(first.source == .favicon)
        #expect(second.source == .favicon)
        #expect(first.imageData == favicon)
        #expect(second.imageData == favicon)
        #expect(recorder.urls.map(\.absoluteString) == [
            "https://example.test/apple-touch-icon.png"
        ])
    }

    @Test("successful avatar results are reused from persistent cache")
    func successfulAvatarResultsAreReusedFromPersistentCache() async throws {
        let cacheURL = try Self.makeCacheURL()
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
        let favicon = Data([0x00, 0x00, 0x01, 0x00, 0x01])
        let firstRecorder = AvatarRequestRecorder(routes: [
            "/apple-touch-icon.png": AvatarHTTPResponse(
                data: favicon,
                statusCode: 200,
                contentType: "image/x-icon"
            )
        ])
        let firstResolver = try AvatarResolver(
            preferences: AvatarPreferences(useFavicon: true),
            urlSession: Self.urlSession(recorder: firstRecorder),
            contactPhotoProvider: NoContactPhotoProvider(),
            avatarCache: SQLiteAvatarCache(databaseURL: cacheURL)
        )

        let first = await firstResolver.resolve(email: "alex@example.test", displayName: "Alex")

        let secondRecorder = AvatarRequestRecorder()
        let secondResolver = try AvatarResolver(
            preferences: AvatarPreferences(useFavicon: true),
            urlSession: Self.urlSession(recorder: secondRecorder),
            contactPhotoProvider: NoContactPhotoProvider(),
            avatarCache: SQLiteAvatarCache(databaseURL: cacheURL)
        )
        let second = await secondResolver.resolve(email: "alex@example.test", displayName: "Alex")

        #expect(first.source == .favicon)
        #expect(second.source == .favicon)
        #expect(second.imageData == favicon)
        #expect(firstRecorder.urls.map(\.absoluteString) == [
            "https://example.test/apple-touch-icon.png"
        ])
        #expect(secondRecorder.urls.isEmpty)
    }

    @Test("failed avatar results are reused from persistent cache")
    func failedAvatarResultsAreReusedFromPersistentCache() async throws {
        let cacheURL = try Self.makeCacheURL()
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
        let firstRecorder = AvatarRequestRecorder()
        let firstResolver = try AvatarResolver(
            preferences: AvatarPreferences(useFavicon: true),
            urlSession: Self.urlSession(recorder: firstRecorder),
            contactPhotoProvider: NoContactPhotoProvider(),
            avatarCache: SQLiteAvatarCache(databaseURL: cacheURL)
        )

        let first = await firstResolver.resolve(email: "alex@example.test", displayName: "Alex")

        let secondRecorder = AvatarRequestRecorder()
        let secondResolver = try AvatarResolver(
            preferences: AvatarPreferences(useFavicon: true),
            urlSession: Self.urlSession(recorder: secondRecorder),
            contactPhotoProvider: NoContactPhotoProvider(),
            avatarCache: SQLiteAvatarCache(databaseURL: cacheURL)
        )
        let second = await secondResolver.resolve(email: "alex@example.test", displayName: "Alex")

        #expect(first.source == .initials)
        #expect(second.source == .initials)
        #expect(firstRecorder.urls.map(\.absoluteString) == [
            "https://example.test/apple-touch-icon.png",
            "https://example.test/favicon.ico",
            "https://www.example.test/favicon.ico"
        ])
        #expect(secondRecorder.urls.isEmpty)
    }

    @Test("clearing cache removes persistent avatar results")
    func clearingCacheRemovesPersistentAvatarResults() async throws {
        let cacheURL = try Self.makeCacheURL()
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
        let favicon = Data([0x00, 0x00, 0x01, 0x00, 0x01])
        let firstRecorder = AvatarRequestRecorder(routes: [
            "/apple-touch-icon.png": AvatarHTTPResponse(
                data: favicon,
                statusCode: 200,
                contentType: "image/x-icon"
            )
        ])
        let resolver = try AvatarResolver(
            preferences: AvatarPreferences(useFavicon: true),
            urlSession: Self.urlSession(recorder: firstRecorder),
            contactPhotoProvider: NoContactPhotoProvider(),
            avatarCache: SQLiteAvatarCache(databaseURL: cacheURL)
        )

        _ = await resolver.resolve(email: "alex@example.test", displayName: "Alex")
        await resolver.clearCache()

        let secondRecorder = AvatarRequestRecorder()
        let secondResolver = try AvatarResolver(
            preferences: AvatarPreferences(useFavicon: true),
            urlSession: Self.urlSession(recorder: secondRecorder),
            contactPhotoProvider: NoContactPhotoProvider(),
            avatarCache: SQLiteAvatarCache(databaseURL: cacheURL)
        )
        let second = await secondResolver.resolve(email: "alex@example.test", displayName: "Alex")

        #expect(second.source == .initials)
        #expect(secondRecorder.urls.map(\.absoluteString) == [
            "https://example.test/apple-touch-icon.png",
            "https://example.test/favicon.ico",
            "https://www.example.test/favicon.ico"
        ])
    }

    @Test("gravatar is attempted before favicon when both are enabled")
    func gravatarIsAttemptedBeforeFaviconWhenBothEnabled() async {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        let recorder = AvatarRequestRecorder(defaultResponse: AvatarHTTPResponse(
            data: png,
            statusCode: 200,
            contentType: "image/png"
        ))
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(useGravatar: true, useFavicon: true),
            urlSession: Self.urlSession(recorder: recorder),
            contactPhotoProvider: NoContactPhotoProvider()
        )

        let avatar = await resolver.resolve(
            email: "alex@example.test",
            displayName: "Alex"
        )

        #expect(avatar.source == .gravatar)
        #expect(recorder.urls.count == 1)
        #expect(recorder.urls.first?.host == "gravatar.com")
    }

    @Test("domain extraction rejects malformed email addresses")
    func domainExtractionRejectsMalformedEmailAddresses() {
        #expect(AvatarResolver.domain(from: "alex@example.test") == "example.test")
        #expect(AvatarResolver.domain(from: "alex@sub.example.test") == "sub.example.test")
        #expect(AvatarResolver.domain(from: "alex") == nil)
        #expect(AvatarResolver.domain(from: "alex@localhost") == nil)
        #expect(AvatarResolver.domain(from: "alex@example.test/path") == nil)
    }

    @Test("domain extraction rejects IP literals and internal hosts (SSRF)")
    func domainExtractionRejectsIPLiteralsAndInternalHosts() {
        // IP-literal From-domains would otherwise drive a favicon fetch at an
        // internal/metadata address.
        #expect(AvatarResolver.domain(from: "x@169.254.169.254") == nil) // cloud metadata
        #expect(AvatarResolver.domain(from: "x@127.0.0.1") == nil) // loopback
        #expect(AvatarResolver.domain(from: "x@10.0.0.1") == nil) // private
        #expect(AvatarResolver.domain(from: "x@192.168.1.5") == nil) // private
        #expect(AvatarResolver.domain(from: "x@db.internal") == nil) // internal TLD
        #expect(AvatarResolver.domain(from: "x@printer.local") == nil) // mDNS
        // Real public domains still pass.
        #expect(AvatarResolver.domain(from: "x@example.com") == "example.com")
    }

    private static func urlSession(recorder: AvatarRequestRecorder) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        AvatarURLProtocol.recorder = recorder
        configuration.protocolClasses = [AvatarURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func makeCacheURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevAvatarsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("avatars.sqlite")
    }

    @Test("concurrency limiter caps simultaneous avatar resolutions")
    func concurrencyLimiterCapsSimultaneousResolutions() async {
        // Fire 20 unique emails with a provider that tracks max concurrency.
        // With maxConcurrentResolutions=3, the max concurrent calls should
        // never exceed 3. All 20 should still resolve (no deadlock).
        let provider = ConcurrencyTrackingContactPhotoProvider()
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(
                useContacts: true,
                useGravatar: false,
                useBIMI: false,
                useFavicon: false
            ),
            urlSession: Self.urlSession(recorder: AvatarRequestRecorder()),
            contactPhotoProvider: provider,
            maxConcurrentResolutions: 3
        )

        let emails = (0 ..< 20).map { "user\($0)@example.test" }
        await withTaskGroup(of: ResolvedAvatar.self) { group in
            for email in emails {
                group.addTask {
                    await resolver.resolve(email: email, displayName: nil)
                }
            }
            var results: [ResolvedAvatar] = []
            for await avatar in group {
                results.append(avatar)
            }
            #expect(results.count == 20)
            #expect(results.allSatisfy { $0.source == .initials })
        }

        let maxConcurrent = await provider.maxConcurrentAccesses
        #expect(maxConcurrent <= 3)
        #expect(maxConcurrent >= 1)
    }

    @Test("concurrency limiter re-checks inFlight after acquiring a slot")
    func concurrencyLimiterDedupsSameEmailAfterSlotWait() async {
        // Many concurrent resolves for one email must share a single cascade
        // even when they all pass the initial inFlight miss and wait on the
        // limiter — the post-acquire re-check joins the first inFlight task.
        let provider = ConcurrencyTrackingContactPhotoProvider()
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(
                useContacts: true,
                useGravatar: false,
                useBIMI: false,
                useFavicon: false
            ),
            urlSession: Self.urlSession(recorder: AvatarRequestRecorder()),
            contactPhotoProvider: provider,
            maxConcurrentResolutions: 1
        )

        await withTaskGroup(of: ResolvedAvatar.self) { group in
            for _ in 0 ..< 20 {
                group.addTask {
                    await resolver.resolve(email: "same@example.test", displayName: nil)
                }
            }
            var results: [ResolvedAvatar] = []
            for await avatar in group {
                results.append(avatar)
            }
            #expect(results.count == 20)
            #expect(results.allSatisfy { $0.source == .initials })
        }

        let callCount = await provider.totalAccesses
        #expect(callCount == 1)
    }

    @Test("in-memory avatar cache evicts least recently used entries")
    func inMemoryCacheEvictsLeastRecentlyUsedEntries() async {
        let provider = ConcurrencyTrackingContactPhotoProvider()
        let resolver = AvatarResolver(
            preferences: AvatarPreferences(
                useContacts: true,
                useGravatar: false,
                useBIMI: false,
                useFavicon: false
            ),
            urlSession: Self.urlSession(recorder: AvatarRequestRecorder()),
            contactPhotoProvider: provider,
            maxInMemoryCacheEntries: 2
        )

        _ = await resolver.resolve(email: "one@example.test", displayName: nil)
        _ = await resolver.resolve(email: "two@example.test", displayName: nil)
        _ = await resolver.resolve(email: "three@example.test", displayName: nil)
        _ = await resolver.resolve(email: "one@example.test", displayName: nil)

        // The first entry was the least recently used when the third sender
        // arrived, so resolving it again must run the cascade again.
        #expect(await provider.totalAccesses == 4)
    }
}

#if canImport(Contacts)
private final class ContactStoreFactoryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.withLock { calls }
    }

    func makeStore() -> CNContactStore {
        lock.withLock { calls += 1 }
        return CNContactStore()
    }
}
#endif

private struct StubContactPhotoProvider: AvatarContactPhotoProviding {
    var imageData: Data?

    func photoData(for email: String) async -> Data? {
        imageData
    }
}

private actor StubBIMIRecordResolver: AvatarBIMIRecordResolving {
    let logoURL: URL?
    private(set) var domains: [String] = []

    init(logoURL: URL?) {
        self.logoURL = logoURL
    }

    func logoURL(for domain: String) async -> URL? {
        domains.append(domain)
        return logoURL
    }
}

private struct StubDMARCPolicyResolver: AvatarDMARCPolicyResolving {
    let policy: DMARCPolicy

    init(policy: DMARCPolicy = .reject) {
        self.policy = policy
    }

    func policy(for domain: String) async -> DMARCPolicy {
        policy
    }
}

private actor DelayedContactPhotoProvider: AvatarContactPhotoProviding {
    private let firstImageData: Data
    private var deliveredFirstImage = false
    private var isWaiting = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?
    private(set) var requestCount = 0

    init(firstImageData: Data) {
        self.firstImageData = firstImageData
    }

    func photoData(for email: String) async -> Data? {
        requestCount += 1
        guard !deliveredFirstImage else { return nil }

        deliveredFirstImage = true
        isWaiting = true
        startedContinuation?.resume()
        startedContinuation = nil
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
        isWaiting = false
        return firstImageData
    }

    func waitUntilStarted() async {
        guard !isWaiting else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

private final class AvatarRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let routes: [String: AvatarHTTPResponse]
    private let defaultResponse: AvatarHTTPResponse
    private var requests: [URL] = []

    init(
        routes: [String: AvatarHTTPResponse] = [:],
        defaultResponse: AvatarHTTPResponse = AvatarHTTPResponse(statusCode: 404)
    ) {
        self.routes = routes
        self.defaultResponse = defaultResponse
    }

    var urls: [URL] {
        lock.withLock { requests }
    }

    func response(for request: URLRequest) -> AvatarHTTPResponse {
        lock.withLock {
            if let url = request.url {
                requests.append(url)
                return routes[url.path] ?? defaultResponse
            }
            return defaultResponse
        }
    }
}

private struct AvatarHTTPResponse: Sendable {
    var data: Data
    var statusCode: Int
    var contentType: String

    init(
        data: Data = Data(),
        statusCode: Int,
        contentType: String = "application/octet-stream"
    ) {
        self.data = data
        self.statusCode = statusCode
        self.contentType = contentType
    }
}

private final class AvatarURLProtocol: URLProtocol {
    static var recorder: AvatarRequestRecorder?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let avatarResponse = Self.recorder?.response(for: request)
            ?? AvatarHTTPResponse(statusCode: 404)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: avatarResponse.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": avatarResponse.contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: avatarResponse.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Contact photo provider that tracks the maximum number of concurrent
/// `photoData` calls. Used to verify the `AvatarResolver` concurrency
/// limiter. Each call yields once so concurrent calls overlap and the
/// limiter's effect is observable.
private actor ConcurrencyTrackingContactPhotoProvider: AvatarContactPhotoProviding {
    private var active = 0
    private var maxActive = 0
    private var total = 0

    func photoData(for email: String) async -> Data? {
        active += 1
        total += 1
        if active > maxActive { maxActive = active }
        // Yield so other concurrent calls can overlap — this makes the
        // limiter's effect observable. Without this, each call would
        // complete before the next starts even without a limiter.
        await Task.yield()
        await Task.yield()
        active -= 1
        return nil
    }

    var maxConcurrentAccesses: Int { maxActive }
    var totalAccesses: Int { total }
}
