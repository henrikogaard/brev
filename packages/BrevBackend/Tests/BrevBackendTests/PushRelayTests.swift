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
    @Test("endpoint validator enforces strict HTTPS and rejects credentials or malformed URLs")
    func endpointValidatorStrictHTTPS() throws {
        let accepted = try PushRelayEndpointValidator.validate("  https://push.example.com/v1/register  ")
        #expect(accepted.absoluteString == "https://push.example.com/v1/register")

        let acceptedPort = try PushRelayEndpointValidator.validate("https://relay.example.org:8443/push?channel=ios")
        #expect(acceptedPort.host == "relay.example.org")
        #expect(acceptedPort.port == 8443)

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

        // Round-trip private key reconstruction derives identical public key.
        let privateKey = try material.privateKey()
        #expect(privateKey.publicKey.x963Representation == decodedPub)

        // Codable round-trip preserves exact key material.
        let encoded = try JSONEncoder().encode(material)
        let decoded = try JSONDecoder().decode(PushRelayEncryptionKeyMaterial.self, from: encoded)
        #expect(decoded == material)
        #expect(try decoded.publicKeys() == publicKeys)

        // Description must never include secret hex/base64 bytes.
        let description = String(describing: material)
        #expect(!description.contains(material.privateKeyRawRepresentation.base64EncodedString()))
        #expect(!description.contains(material.authSecret.base64EncodedString()))
    }

    @Test("disabled mode or missing opted-in accounts performs zero network calls")
    func zeroNetworkCallsWhenDisabledOrEmpty() async {
        let transport = RecordingPushRelayTransport(responses: [])
        let client = PushRelayClient(transport: transport)

        let disabledRequest = PushRelayRegistrationRequest(
            mode: .disabled,
            deviceClientID: "device-1",
            devicePushToken: "apns-token-hex",
            accountIDs: ["acct-1"]
        )
        await #expect(throws: PushRelayClientError.disabled) {
            _ = try await client.register(
                endpointURLString: "https://relay.example.com/push",
                request: disabledRequest,
                bearerToken: nil
            )
        }
        #expect(await transport.recordedRequests().isEmpty)

        let emptyAccountsRequest = PushRelayRegistrationRequest(
            mode: .userHostedRelay,
            deviceClientID: "device-1",
            devicePushToken: "apns-token-hex",
            accountIDs: []
        )
        await #expect(throws: PushRelayClientError.missingOptedInAccounts) {
            _ = try await client.register(
                endpointURLString: "https://relay.example.com/push",
                request: emptyAccountsRequest,
                bearerToken: nil
            )
        }
        #expect(await transport.recordedRequests().isEmpty)

        let httpRequest = PushRelayRegistrationRequest(
            mode: .userHostedRelay,
            deviceClientID: "device-1",
            devicePushToken: "apns-token-hex",
            accountIDs: ["acct-1"]
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
        let postBodyString = try String(decoding: #require(postReq.httpBody), as: UTF8.self)
        #expect(postBodyString.contains("dev-client-uuid"))
        #expect(postBodyString.contains("deadbeef01234567"))
        #expect(postBodyString.contains(keys.p256dh))
        #expect(postBodyString.contains(keys.auth))
        #expect(!postBodyString.contains("password"))
        #expect(!postBodyString.contains("oauth"))
        #expect(!postBodyString.contains("privateKey"))
        let decodedPost = try JSONDecoder().decode(PushRelayRegistrationRequest.self, from: #require(postReq.httpBody))
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

    @Test("JMAP RFC 8620 §7.2 PushSubscription/set spec formats valid JMAP create & destroy calls")
    func jmapWebPushSubscriptionSpecAndClient() async throws {
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

        let methodCalls = try #require(json["methodCalls"] as? [[Any]])
        #expect(methodCalls.count == 1)
        #expect(methodCalls[0][0] as? String == "PushSubscription/set")
        #expect(methodCalls[0][2] as? String == "c0")
        let args = try #require(methodCalls[0][1] as? [String: Any])
        let create = try #require(args["create"] as? [String: [String: Any]])
        let subObj = try #require(create["sub-0"])
        #expect(subObj["deviceClientId"] as? String == "brev-device-42")
        #expect(subObj["url"] as? String == "https://webpush.example.com/push/token123")
        #expect(subObj["types"] as? [String] == ["Email"])
        let jsonKeys = try #require(subObj["keys"] as? [String: String])
        #expect(jsonKeys["p256dh"] == keys.p256dh)
        #expect(jsonKeys["auth"] == keys.auth)

        // End-to-end JMAP registration & unregistration via PushRelayClient
        let jmapResponseJSON = """
        {
          "methodResponses": [
            [
              "PushSubscription/set",
              {
                "created": {
                  "brev-push-sub": {
                    "id": "jmap-sub-99",
                    "expires": "2027-01-15T08:00:00Z",
                    "verificationCode": "verify-abc"
                  }
                }
              },
              "c0"
            ]
          ]
        }
        """
        let destroyResponseJSON = """
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
            (Data(jmapResponseJSON.utf8), 200),
            (Data(destroyResponseJSON.utf8), 200)
        ])
        let client = PushRelayClient(transport: transport)
        let req = PushRelayRegistrationRequest(
            mode: .jmapWebPush,
            deviceClientID: "brev-device-42",
            devicePushToken: "https://webpush.example.com/push/token123",
            accountIDs: ["acct-jmap"],
            keys: keys
        )
        let response = try await client.register(
            endpointURLString: "https://jmap.example.com/api/",
            request: req,
            bearerToken: "jmap-token"
        )
        #expect(response.subscriptionID == "jmap-sub-99")
        #expect(response.verificationCode == "verify-abc")
        #expect(response.expiresAt != nil)

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
        #expect(recorded.count == 2)
        let destroyBody = try String(decoding: #require(recorded[1].httpBody), as: UTF8.self)
        #expect(destroyBody.contains("PushSubscription/set"))
        #expect(destroyBody.contains("\"destroy\""))
        #expect(destroyBody.contains("jmap-sub-99"))
    }

    @Test("PushWakePayload decodes opaque wakes and rejects malformed payloads")
    func wakePayloadValidation() throws {
        let validJSON = Data("""
        {
          "accountID": "acct-work",
          "stateToken": "state-42",
          "eventKind": "new_mail",
          "ignoredBody": "should never be read"
        }
        """.utf8)
        let decoded = try #require(PushWakePayload(jsonData: validJSON))
        #expect(decoded.accountID == "acct-work")
        #expect(decoded.stateToken == "state-42")
        #expect(decoded.eventKind == .newMail)

        let nestedAPNs: [AnyHashable: Any] = [
            "aps": ["content-available": 1],
            "brev": [
                "accountID": "acct-personal",
                "eventKind": "mailbox_changed"
            ]
        ]
        let fromUserInfo = try #require(PushWakePayload(userInfo: nestedAPNs))
        #expect(fromUserInfo.accountID == "acct-personal")
        #expect(fromUserInfo.stateToken == nil)
        #expect(fromUserInfo.eventKind == .mailboxChanged)

        // Reject missing/empty accountID, unknown eventKind, or oversized fields.
        #expect(PushWakePayload(userInfo: ["accountID": "   ", "eventKind": "new_mail"]) == nil)
        #expect(PushWakePayload(userInfo: ["accountID": "acct-1", "eventKind": "unknown_event"]) == nil)
        #expect(PushWakePayload(userInfo: ["aps": ["content-available": 1]]) == nil)
        #expect(PushWakePayload(jsonData: Data("{bad json".utf8)) == nil)
        #expect(PushWakePayload(userInfo: [
            "accountID": String(repeating: "a", count: 300),
            "eventKind": "new_mail"
        ]) == nil)
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
