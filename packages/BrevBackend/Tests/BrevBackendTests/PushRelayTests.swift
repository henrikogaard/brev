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
import CryptoKit
import Foundation
import Testing

@Suite("Closed-app push relay protocol & client (#11)")
struct PushRelayTests {
    @Test("endpoint validator enforces strict HTTPS, rejects credentials, and normalizes origins")
    func endpointValidatorStrictHTTPS() throws {
        let accepted = try PushRelayEndpointValidator.validate("  https://push.example.com/v1/register  ")
        #expect(accepted.absoluteString == "https://push.example.com/v1/register")
        #expect(PushRelayEndpointValidator.originKey(for: accepted) == "https://push.example.com")

        let acceptedDefaultPort = try PushRelayEndpointValidator.validate("https://PUSH.EXAMPLE.COM:443/other")
        #expect(PushRelayEndpointValidator.originKey(for: acceptedDefaultPort) == "https://push.example.com")

        let acceptedPort = try PushRelayEndpointValidator.validate("https://relay.example.org:8443/push?channel=ios")
        #expect(acceptedPort.host == "relay.example.org")
        #expect(acceptedPort.port == 8443)
        #expect(PushRelayEndpointValidator.originKey(for: acceptedPort) == "https://relay.example.org:8443")

        #expect(throws: PushRelayEndpointValidationError.empty) {
            _ = try PushRelayEndpointValidator.validate("   ")
        }
        #expect(throws: PushRelayEndpointValidationError.httpsRequired) {
            _ = try PushRelayEndpointValidator.validate("http://push.example.com/register")
        }
        #expect(throws: PushRelayEndpointValidationError.httpsRequired) {
            _ = try PushRelayEndpointValidator.validate("http://127.0.0.1:8080/register")
        }
        #expect(throws: PushRelayEndpointValidationError.httpsRequired) {
            _ = try PushRelayEndpointValidator.validate("ftp://push.example.com/register")
        }
        #expect(throws: PushRelayEndpointValidationError.embeddedCredentialsForbidden) {
            _ = try PushRelayEndpointValidator.validate("https://user:secret@push.example.com/register")
        }
        #expect(throws: PushRelayEndpointValidationError.embeddedCredentialsForbidden) {
            _ = try PushRelayEndpointValidator.validate("https://user@push.example.com/register")
        }
        #expect(throws: PushRelayEndpointValidationError.missingHost) {
            _ = try PushRelayEndpointValidator.validate("https:///register")
        }
        #expect(throws: PushRelayEndpointValidationError.malformedURL) {
            _ = try PushRelayEndpointValidator.validate("not a valid url with spaces")
        }

        // Destination comparison normalizes host case, default port, and empty-vs-root path,
        // while keeping trailing slashes on non-root paths distinct (/push != /push/).
        let apiLower = try PushRelayEndpointValidator.validate("https://jmap.example.com/api")
        let apiUpperPort = try PushRelayEndpointValidator.validate("https://JMAP.EXAMPLE.COM:443/api")
        let apiTrailingSlash = try PushRelayEndpointValidator.validate("https://jmap.example.com/api/")
        let rootBare = try PushRelayEndpointValidator.validate("https://example.com")
        let rootSlash = try PushRelayEndpointValidator.validate("https://example.com/")
        #expect(PushRelayEndpointValidator.representsSameDestination(apiLower, apiUpperPort))
        #expect(PushRelayEndpointValidator.representsSameDestination(rootBare, rootSlash))
        #expect(!PushRelayEndpointValidator.representsSameDestination(apiLower, apiTrailingSlash))
    }

    @Test("RFC 8291 P-256 key generation round-trips cleanly and never leaks private key in description")
    func rfc8291KeyGenerationRoundTrip() throws {
        let material = PushRelayEncryptionKeyMaterial.generate()
        let publicKeys = try material.publicKeys()

        #expect(!publicKeys.p256dh.contains("="))
        #expect(!publicKeys.p256dh.contains("+"))
        #expect(!publicKeys.p256dh.contains("/"))
        #expect(!publicKeys.auth.contains("="))
        #expect(!publicKeys.auth.contains("+"))
        #expect(!publicKeys.auth.contains("/"))

        let decodedPub = try #require(PushRelayBase64URL.decode(publicKeys.p256dh))
        let decodedAuth = try #require(PushRelayBase64URL.decode(publicKeys.auth))

        // RFC 8291 §3.1: uncompressed X9.63 P-256 point (65 bytes, 0x04 prefix) + 16-byte auth secret.
        #expect(decodedPub.count == 65)
        #expect(decodedPub.first == 0x04)
        #expect(decodedAuth.count == 16)

        let privateKey = try material.privateKey()
        #expect(privateKey.publicKey.x963Representation == decodedPub)

        let encoded = try JSONEncoder().encode(material)
        let decoded = try JSONDecoder().decode(PushRelayEncryptionKeyMaterial.self, from: encoded)
        #expect(decoded == material)
        #expect(try decoded.publicKeys() == publicKeys)

        let description = String(describing: material)
        #expect(!description.contains(material.privateKeyRawRepresentation.base64EncodedString()))
        #expect(!description.contains(material.authSecret.base64EncodedString()))
    }

    @Test("disabled mode, missing real push token, or same JMAP API/delivery URL performs zero network calls")
    func zeroNetworkCallsWhenInvalidOrUnprovisioned() async {
        let transport = RecordingPushRelayTransport(responses: [])
        let client = PushRelayClient(transport: transport)

        let disabledRequest = PushRelayRegistrationRequest(
            mode: .disabled,
            deviceClientID: "device-1",
            devicePushToken: "real-apns-token",
            accountIDs: ["acct-token-1"]
        )
        await #expect(throws: PushRelayClientError.disabled) {
            _ = try await client.register(
                endpointURLString: "https://relay.example.com/push",
                request: disabledRequest,
                bearerToken: nil
            )
        }

        // Reject missing token or fabricated deviceClientID reused as APNs token.
        let missingTokenRequest = PushRelayRegistrationRequest(
            mode: .userHostedRelay,
            deviceClientID: "brev-dev-123",
            devicePushToken: "",
            accountIDs: ["acct-token-1"]
        )
        await #expect(throws: PushRelayClientError.missingDevicePushToken) {
            _ = try await client.register(
                endpointURLString: "https://relay.example.com/push",
                request: missingTokenRequest,
                bearerToken: nil
            )
        }

        let fabricatedTokenRequest = PushRelayRegistrationRequest(
            mode: .userHostedRelay,
            deviceClientID: "brev-dev-123",
            devicePushToken: "brev-dev-123",
            accountIDs: ["acct-token-1"]
        )
        await #expect(throws: PushRelayClientError.missingDevicePushToken) {
            _ = try await client.register(
                endpointURLString: "https://relay.example.com/push",
                request: fabricatedTokenRequest,
                bearerToken: nil
            )
        }

        // JMAP mode rejects missing delivery URL and rejects delivery URL == JMAP API URL.
        let jmapMissingDelivery = PushRelayRegistrationRequest(
            mode: .jmapWebPush,
            deviceClientID: "brev-dev-123",
            webPushDeliveryURL: nil,
            accountIDs: ["acct-token-1"]
        )
        await #expect(throws: PushRelayClientError.missingWebPushDeliveryURL) {
            _ = try await client.register(
                endpointURLString: "https://jmap.example.com/api",
                request: jmapMissingDelivery,
                bearerToken: nil
            )
        }

        let jmapSameURL = PushRelayRegistrationRequest(
            mode: .jmapWebPush,
            deviceClientID: "brev-dev-123",
            webPushDeliveryURL: "https://JMAP.EXAMPLE.COM:443/api",
            accountIDs: ["acct-token-1"]
        )
        await #expect(throws: PushRelayClientError.webPushDeliveryURLMatchesAPIEndpoint) {
            _ = try await client.register(
                endpointURLString: "https://jmap.example.com/api",
                request: jmapSameURL,
                bearerToken: nil
            )
        }

        let emptyAccountsRequest = PushRelayRegistrationRequest(
            mode: .userHostedRelay,
            deviceClientID: "device-1",
            devicePushToken: "real-apns-token",
            accountIDs: []
        )
        await #expect(throws: PushRelayClientError.missingOptedInAccounts) {
            _ = try await client.register(
                endpointURLString: "https://relay.example.com/push",
                request: emptyAccountsRequest,
                bearerToken: nil
            )
        }

        let httpRequest = PushRelayRegistrationRequest(
            mode: .userHostedRelay,
            deviceClientID: "device-1",
            devicePushToken: "real-apns-token",
            accountIDs: ["acct-token-1"]
        )
        await #expect(throws: PushRelayClientError.invalidEndpoint(.httpsRequired)) {
            _ = try await client.register(
                endpointURLString: "http://relay.example.com/push",
                request: httpRequest,
                bearerToken: nil
            )
        }

        #expect(await transport.recordedRequests().isEmpty)
    }

    @Test("user-hosted relay register, refresh, and unregister send only opaque tokens, IDs, and RFC 8291 public keys")
    func userHostedRelayLifecycle() async throws {
        let expiresAt = Date(timeIntervalSince1970: 1_800_000_000)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let registerBody = try encoder.encode(
            PushRelayRegistrationResponse(subscriptionID: "sub-123", expiresAt: expiresAt, verificationCode: nil)
        )
        let refreshBody = try encoder.encode(
            PushRelayRegistrationResponse(
                subscriptionID: "sub-123",
                expiresAt: expiresAt.addingTimeInterval(86400),
                verificationCode: nil
            )
        )

        let transport = RecordingPushRelayTransport(responses: [
            (registerBody, 201),
            (refreshBody, 200),
            (Data(), 404)
        ])
        let client = PushRelayClient(transport: transport)
        let keys = try PushRelayEncryptionKeyMaterial.generate().publicKeys()

        let request = PushRelayRegistrationRequest(
            mode: .userHostedRelay,
            deviceClientID: "dev-client-uuid",
            devicePushToken: "deadbeef01234567",
            accountIDs: ["acct-b", "acct-a", "acct-a"],
            keys: keys,
            platform: "ios"
        )

        let registered = try await client.register(
            endpointURLString: "https://relay.example.com/v1/register",
            request: request,
            bearerToken: "my-relay-secret"
        )
        #expect(registered.subscriptionID == "sub-123")
        #expect(registered.state == .active)
        #expect(registered.expiresAt == expiresAt)

        let refreshed = try await client.refresh(
            endpointURLString: "https://relay.example.com/v1/register",
            subscriptionID: "sub-123",
            request: request,
            bearerToken: "my-relay-secret"
        )
        #expect(refreshed.subscriptionID == "sub-123")

        try await client.unregister(
            endpointURLString: "https://relay.example.com/v1/register",
            request: PushRelayUnregistrationRequest(
                deviceClientID: "dev-client-uuid",
                subscriptionID: "sub-123",
                accountIDs: ["acct-a", "acct-b"]
            ),
            mode: .userHostedRelay,
            bearerToken: "my-relay-secret"
        )

        let recorded = await transport.recordedRequests()
        #expect(recorded.count == 3)

        let postReq = recorded[0]
        #expect(postReq.httpMethod == "POST")
        #expect(postReq.url?.absoluteString == "https://relay.example.com/v1/register")
        #expect(postReq.value(forHTTPHeaderField: "Authorization") == "Bearer my-relay-secret")
        #expect(postReq.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let postBody = try #require(postReq.httpBody)
        let postBodyString = String(decoding: postBody, as: UTF8.self)
        #expect(postBodyString.contains("dev-client-uuid"))
        #expect(postBodyString.contains("deadbeef01234567"))
        #expect(postBodyString.contains(keys.p256dh))
        #expect(postBodyString.contains(keys.auth))
        #expect(!postBodyString.contains("password"))
        #expect(!postBodyString.contains("oauth"))
        #expect(!postBodyString.contains("privateKey"))
        let decodedPost = try JSONDecoder().decode(PushRelayRegistrationRequest.self, from: postBody)
        #expect(decodedPost.accountIDs == ["acct-a", "acct-b"])

        let putReq = recorded[1]
        #expect(putReq.httpMethod == "PUT")
        #expect(putReq.value(forHTTPHeaderField: "X-Brev-Subscription-ID") == "sub-123")

        let deleteReq = recorded[2]
        #expect(deleteReq.httpMethod == "DELETE")
        #expect(deleteReq.value(forHTTPHeaderField: "X-Brev-Subscription-ID") == "sub-123")
    }

    @Test("HTTP failure status codes surface typed httpFailure errors")
    func httpFailureSurfacesStatusCode() async {
        let transport = RecordingPushRelayTransport(responses: [(Data(), 401)])
        let client = PushRelayClient(transport: transport)
        let request = PushRelayRegistrationRequest(
            mode: .userHostedRelay,
            deviceClientID: "dev-1",
            devicePushToken: "tok-1",
            accountIDs: ["acct-1"]
        )
        await #expect(throws: PushRelayClientError.httpFailure(statusCode: 401)) {
            _ = try await client.register(
                endpointURLString: "https://relay.example.com/register",
                request: request,
                bearerToken: "bad-token"
            )
        }
    }

    @Test("JMAP RFC 8620 §7.2.2 distinguishes unverified creation from verified active subscription")
    func jmapVerificationContractAndDestroyParsing() async throws {
        let keys = try PushRelayEncryptionKeyMaterial.generate().publicKeys()
        let expires = Date(timeIntervalSince1970: 1_800_000_000)
        let spec = try JMAPWebPushSubscriptionSpec(
            deviceClientID: "brev-device-42",
            urlString: "https://webpush.example.com/push/token123",
            keys: keys,
            types: ["Email"],
            expires: expires
        )

        let payloadData = try spec.encodedSetCreateRequestData(clientCreationID: "sub-0")
        let json = try #require(try JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        let using = try #require(json["using"] as? [String])
        #expect(using == ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"])

        let jmapCreateResponse = """
        {
          "methodResponses": [
            [
              "PushSubscription/set",
              {
                "created": {
                  "brev-push-sub": {
                    "id": "jmap-sub-99",
                    "expires": "2027-01-15T08:00:00Z"
                  }
                }
              },
              "c0"
            ]
          ]
        }
        """
        let jmapVerifyResponse = """
        {
          "methodResponses": [
            [
              "PushSubscription/set",
              {
                "updated": {
                  "jmap-sub-99": null
                }
              },
              "c0"
            ]
          ]
        }
        """
        let jmapDestroyRejectedResponse = """
        {
          "methodResponses": [
            [
              "PushSubscription/set",
              {
                "notDestroyed": {
                  "jmap-sub-99": {
                    "type": "forbidden",
                    "description": "Not allowed to destroy subscription"
                  }
                }
              },
              "c0"
            ]
          ]
        }
        """
        let jmapDestroyNotFoundResponse = """
        {
          "methodResponses": [
            [
              "PushSubscription/set",
              {
                "notDestroyed": {
                  "jmap-sub-99": {
                    "type": "notFound"
                  }
                }
              },
              "c0"
            ]
          ]
        }
        """
        let jmapDestroyConfirmedResponse = """
        {
          "methodResponses": [
            [
              "PushSubscription/set",
              {
                "destroyed": ["jmap-sub-99"]
              },
              "c0"
            ]
          ]
        }
        """

        let transport = RecordingPushRelayTransport(responses: [
            (Data(jmapCreateResponse.utf8), 200),
            (Data(jmapVerifyResponse.utf8), 200),
            (Data(jmapDestroyRejectedResponse.utf8), 200),
            (Data(jmapDestroyNotFoundResponse.utf8), 200),
            (Data(jmapDestroyConfirmedResponse.utf8), 200)
        ])
        let client = PushRelayClient(transport: transport)
        let req = PushRelayRegistrationRequest(
            mode: .jmapWebPush,
            deviceClientID: "brev-device-42",
            webPushDeliveryURL: "https://webpush.example.com/push/token123",
            accountIDs: ["acct-jmap"],
            keys: keys
        )

        // 1. Creation MUST remain .pendingVerification until RFC 8620 §7.2.2 update succeeds.
        let created = try await client.register(
            endpointURLString: "https://jmap.example.com/api/",
            request: req,
            bearerToken: "jmap-token"
        )
        #expect(created.subscriptionID == "jmap-sub-99")
        #expect(created.state == .pendingVerification)

        // 2. Verification update transitions state to .active.
        let verified = try await client.verifyJMAPSubscription(
            endpointURLString: "https://jmap.example.com/api/",
            subscriptionID: "jmap-sub-99",
            verificationCode: "challenge-xyz",
            bearerToken: "jmap-token"
        )
        #expect(verified.subscriptionID == "jmap-sub-99")
        #expect(verified.state == .active)

        // 3. HTTP 200 with JMAP `notDestroyed` ("forbidden") MUST throw so local state is retained for retry.
        await #expect(
            throws: PushRelayClientError.jmapMethodRejected("Not allowed to destroy subscription")
        ) {
            try await client.unregister(
                endpointURLString: "https://jmap.example.com/api/",
                request: PushRelayUnregistrationRequest(
                    deviceClientID: "brev-device-42",
                    subscriptionID: "jmap-sub-99",
                    accountIDs: ["acct-jmap"]
                ),
                mode: .jmapWebPush,
                bearerToken: "jmap-token"
            )
        }

        // 4. HTTP 200 with JMAP `notDestroyed` ("notFound") succeeds (confirmed already absent).
        try await client.unregister(
            endpointURLString: "https://jmap.example.com/api/",
            request: PushRelayUnregistrationRequest(
                deviceClientID: "brev-device-42",
                subscriptionID: "jmap-sub-99",
                accountIDs: ["acct-jmap"]
            ),
            mode: .jmapWebPush,
            bearerToken: "jmap-token"
        )

        // 5. HTTP 200 with JMAP `destroyed: ["jmap-sub-99"]` succeeds.
        try await client.unregister(
            endpointURLString: "https://jmap.example.com/api/",
            request: PushRelayUnregistrationRequest(
                deviceClientID: "brev-device-42",
                subscriptionID: "jmap-sub-99",
                accountIDs: ["acct-jmap"]
            ),
            mode: .jmapWebPush,
            bearerToken: "jmap-token"
        )

        let recorded = await transport.recordedRequests()
        #expect(recorded.count == 5)
        let createBody = try String(decoding: #require(recorded[0].httpBody), as: UTF8.self)
        #expect(createBody.contains("https://webpush.example.com/push/token123"))
        #expect(!createBody.contains("https://jmap.example.com/api/"))

        let verifyBody = try String(decoding: #require(recorded[1].httpBody), as: UTF8.self)
        #expect(verifyBody.contains("PushSubscription/set"))
        #expect(verifyBody.contains("\"update\""))
        #expect(verifyBody.contains("challenge-xyz"))

        let destroyBody = try String(decoding: #require(recorded[4].httpBody), as: UTF8.self)
        #expect(destroyBody.contains("PushSubscription/set"))
        #expect(destroyBody.contains("\"destroy\""))
        #expect(destroyBody.contains("jmap-sub-99"))
    }

    @Test(
        "JMAP refresh sends future UTC expires, accepts null updated record, preserves active state, and falls back to create on notFound"
    )
    func jmapRefreshPreservesVerifiedStateAndFallsBackOnNotFound() async throws {
        let keys = try PushRelayEncryptionKeyMaterial.generate().publicKeys()
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15T08:00:00Z
        let expectedRequestedExpiry = fixedNow.addingTimeInterval(30 * 24 * 60 * 60) // 2027-02-14T08:00:00Z
        let updateNullRecordOK = """
        {
          "methodResponses": [
            [
              "PushSubscription/set",
              {
                "updated": {
                  "jmap-sub-1": null
                }
              },
              "c0"
            ]
          ]
        }
        """
        let updateNotFound = """
        {
          "methodResponses": [
            [
              "PushSubscription/set",
              {
                "notUpdated": {
                  "jmap-sub-1": {
                    "type": "notFound"
                  }
                }
              },
              "c0"
            ]
          ]
        }
        """
        let recreateResponse = """
        {
          "methodResponses": [
            [
              "PushSubscription/set",
              {
                "created": {
                  "brev-push-sub": {
                    "id": "jmap-sub-2"
                  }
                }
              },
              "c0"
            ]
          ]
        }
        """
        let transport = RecordingPushRelayTransport(responses: [
            (Data(updateNullRecordOK.utf8), 200),
            (Data(updateNotFound.utf8), 200),
            (Data(recreateResponse.utf8), 200)
        ])
        let client = PushRelayClient(transport: transport, now: { fixedNow })
        let req = PushRelayRegistrationRequest(
            mode: .jmapWebPush,
            deviceClientID: "brev-device-42",
            webPushDeliveryURL: "https://webpush.example.com/push/token123",
            accountIDs: ["acct-jmap"],
            keys: keys
        )

        // 1. Refresh on an already-verified subscription sends `update` with future UTC `expires`,
        // accepts RFC 8620 `updated[id]: null` as success, and preserves `.active`.
        let refreshed = try await client.refresh(
            endpointURLString: "https://jmap.example.com/api/",
            subscriptionID: "jmap-sub-1",
            request: req,
            currentState: .active,
            bearerToken: "jmap-token"
        )
        #expect(refreshed.subscriptionID == "jmap-sub-1")
        #expect(refreshed.state == .active)
        #expect(refreshed.expiresAt == expectedRequestedExpiry)

        // 2. If server returns `notFound` for the existing ID, refresh falls back to `create` (.pendingVerification).
        let recreated = try await client.refresh(
            endpointURLString: "https://jmap.example.com/api/",
            subscriptionID: "jmap-sub-1",
            request: req,
            currentState: .active,
            bearerToken: "jmap-token"
        )
        #expect(recreated.subscriptionID == "jmap-sub-2")
        #expect(recreated.state == .pendingVerification)

        let recorded = await transport.recordedRequests()
        #expect(recorded.count == 3)
        let firstBody = try String(decoding: #require(recorded[0].httpBody), as: UTF8.self)
        #expect(firstBody.contains("\"update\""))
        #expect(firstBody.contains("jmap-sub-1"))
        #expect(firstBody.contains("\"expires\":\"2027-02-14T08:00:00Z\""))
        #expect(!firstBody.contains("\"create\""))

        let secondBody = try String(decoding: #require(recorded[1].httpBody), as: UTF8.self)
        #expect(secondBody.contains("\"update\""))
        let thirdBody = try String(decoding: #require(recorded[2].httpBody), as: UTF8.self)
        #expect(thirdBody.contains("\"create\""))
    }

    @Test("URLSessionPushRelayTransport blocks HTTP redirects so payloads and tokens never leave the approved origin")
    func transportBlocksRedirects() async {
        RedirectBlockingURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RedirectBlockingURLProtocol.self]
        let transport = URLSessionPushRelayTransport(configuration: config)
        let client = PushRelayClient(transport: transport)

        let request = PushRelayRegistrationRequest(
            mode: .userHostedRelay,
            deviceClientID: "dev-1",
            devicePushToken: "real-apns-token",
            accountIDs: ["acct-token-1"]
        )

        await #expect(throws: PushRelayClientError.redirectBlocked(statusCode: 307)) {
            _ = try await client.register(
                endpointURLString: "https://relay.example.com/register",
                request: request,
                bearerToken: "origin-secret"
            )
        }

        let requestedHosts = RedirectBlockingURLProtocol.recordedHosts()
        #expect(requestedHosts == ["relay.example.com"])
        #expect(!requestedHosts.contains("attacker.example"))
    }

    @Test("PushWakePayload decodes opaque wakes and RFC 8620 §7.2.2 PushVerification challenges")
    func wakePayloadAndVerificationDecoding() throws {
        let validJSON = Data("""
        {
          "accountID": "acct-opaque-1",
          "stateToken": "state-42",
          "eventKind": "new_mail",
          "ignoredBody": "should never be read"
        }
        """.utf8)
        let decoded = try #require(PushWakePayload(jsonData: validJSON))
        #expect(decoded.accountID == "acct-opaque-1")
        #expect(decoded.stateToken == "state-42")
        #expect(decoded.eventKind == .newMail)
        #expect(!decoded.isJMAPVerificationChallenge)

        let jmapChallengeJSON = Data("""
        {
          "@type": "PushVerification",
          "pushSubscriptionId": "jmap-sub-77",
          "verificationCode": "verify-999"
        }
        """.utf8)
        let challenge = try #require(PushWakePayload(jsonData: jmapChallengeJSON))
        #expect(challenge.isJMAPVerificationChallenge)
        #expect(challenge == .jmapVerification(pushSubscriptionId: "jmap-sub-77", verificationCode: "verify-999"))

        let nestedAPNs: [AnyHashable: Any] = [
            "aps": ["content-available": 1],
            "brev": [
                "accountID": "acct-opaque-2",
                "eventKind": "mailbox_changed"
            ]
        ]
        let fromUserInfo = try #require(PushWakePayload(userInfo: nestedAPNs))
        #expect(fromUserInfo.accountID == "acct-opaque-2")
        #expect(fromUserInfo.stateToken == nil)
        #expect(fromUserInfo.eventKind == .mailboxChanged)

        #expect(PushWakePayload(userInfo: ["accountID": "   ", "eventKind": "new_mail"]) == nil)
        #expect(PushWakePayload(userInfo: ["accountID": "acct-1", "eventKind": "unknown_event"]) == nil)
        #expect(PushWakePayload(userInfo: ["@type": "PushVerification", "pushSubscriptionId": "s1"]) == nil)
        #expect(PushWakePayload(userInfo: ["aps": ["content-available": 1]]) == nil)
        #expect(PushWakePayload(jsonData: Data("{bad json".utf8)) == nil)
        #expect(PushWakePayload(userInfo: [
            "accountID": String(repeating: "a", count: 300),
            "eventKind": "new_mail"
        ]) == nil)

        // RFC 8620 §7.1 StateChange payloads with Email vs non-Email changes.
        let stateChangeEmailJSON = Data("""
        {
          "@type": "StateChange",
          "changed": {
            "acct-opaque-2": { "Mailbox": "m-9" },
            "acct-opaque-1": { "Email": "e-42", "Mailbox": "m-7" }
          }
        }
        """.utf8)
        let emailStateChange = try #require(PushWakePayload(jsonData: stateChangeEmailJSON))
        #expect(!emailStateChange.isJMAPVerificationChallenge)
        #expect(emailStateChange.eventKind == .newMail)
        #expect(emailStateChange.targetAccountTokens == ["acct-opaque-1", "acct-opaque-2"])
        #expect(emailStateChange.changedAccountStates["acct-opaque-1"] == "e-42")
        #expect(emailStateChange.changedAccountStates["acct-opaque-2"] == "m-9")

        let stateChangeMailboxOnlyJSON = Data("""
        {
          "@type": "StateChange",
          "changed": {
            "acct-opaque-2": { "Mailbox": "m-10" }
          }
        }
        """.utf8)
        let mailboxStateChange = try #require(PushWakePayload(jsonData: stateChangeMailboxOnlyJSON))
        #expect(mailboxStateChange.eventKind == .mailboxChanged)
        #expect(mailboxStateChange.targetAccountTokens == ["acct-opaque-2"])

        #expect(PushWakePayload(jsonData: Data("""
        {"@type":"StateChange","changed":{}}
        """.utf8)) == nil)
    }
}

private actor RecordingPushRelayTransport: PushRelayHTTPTransport {
    private var queued: [(Data, Int)]
    private var requests: [URLRequest] = []

    init(responses: [(Data, Int)]) {
        queued = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let next = queued.isEmpty ? (Data(), 200) : queued.removeFirst()
        let url = request.url ?? URL(string: "https://relay.example.com")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: next.1,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (next.0, response)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

private final class RedirectBlockingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var hosts: [String] = []

    static func reset() {
        lock.withLock { hosts.removeAll() }
    }

    static func recordedHosts() -> [String] {
        lock.withLock { hosts }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let host = request.url?.host {
            Self.lock.withLock { Self.hosts.append(host) }
        }
        let url = request.url ?? URL(string: "https://relay.example.com/register")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 307,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": "https://attacker.example/steal"]
        )!
        client?.urlProtocol(
            self,
            wasRedirectedTo: URLRequest(url: URL(string: "https://attacker.example/steal")!),
            redirectResponse: response
        )
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
