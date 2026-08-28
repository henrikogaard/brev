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

#if os(macOS)
import Foundation
import Network

enum GoogleOAuthLoopbackReceiverError: Error, Equatable {
    case alreadyStarted
    case cancelled
    case listenerFailed
}

/// Receives one Google OAuth callback on an ephemeral IPv4 loopback port.
@MainActor
final class GoogleOAuthLoopbackReceiver {
    private static let callbackPath = "/oauth2redirect"
    private nonisolated static let maximumRequestBytes = 16 * 1024

    private let queue = DispatchQueue(label: "eu.brevmail.brev.google-oauth-loopback")
    private var listener: NWListener?
    private var startContinuation: CheckedContinuation<String, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var bufferedCallback: URL?
    private var redirectURI: String?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var terminalError: GoogleOAuthLoopbackReceiverError?
    private var hasStarted = false
    private var hasAcceptedCallback = false

    /// Starts a listener bound only to `127.0.0.1` and returns its exact redirect URI.
    func start() async throws -> String {
        guard !hasStarted else { throw GoogleOAuthLoopbackReceiverError.alreadyStarted }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: .any)
        } catch {
            throw GoogleOAuthLoopbackReceiverError.listenerFailed
        }
        self.listener = listener
        hasStarted = true

        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = listener?.port else {
                        self.finish(with: GoogleOAuthLoopbackReceiverError.listenerFailed)
                        return
                    }
                    let redirectURI = "http://127.0.0.1:\(port.rawValue)\(Self.callbackPath)"
                    self.redirectURI = redirectURI
                    self.startContinuation?.resume(returning: redirectURI)
                    self.startContinuation = nil
                case .failed:
                    self.cancelConnections()
                    self.finish(with: GoogleOAuthLoopbackReceiverError.listenerFailed)
                case .cancelled:
                    self.finish(with: GoogleOAuthLoopbackReceiverError.cancelled)
                default:
                    break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.accept(connection)
            }
        }
        listener.start(queue: queue)

        return try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
        }
    }

    /// Waits for the first valid callback request received on the listener.
    func waitForCallback() async throws -> URL {
        if let bufferedCallback {
            self.bufferedCallback = nil
            return bufferedCallback
        }
        if let terminalError {
            throw terminalError
        }
        return try await withCheckedThrowingContinuation { continuation in
            callbackContinuation = continuation
        }
    }

    /// Stops the listener and fails any pending waiters.
    func cancel() {
        listener?.cancel()
        listener = nil
        cancelConnections()
        finish(with: GoogleOAuthLoopbackReceiverError.cancelled)
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil else {
            connection.cancel()
            return
        }
        connections[ObjectIdentifier(connection)] = connection
        receiveRequest(on: connection, accumulated: Data())
    }

    private nonisolated func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4 * 1024) { [weak self] data, _, complete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var request = accumulated
            if let data {
                request.append(data)
            }
            if request.count > Self.maximumRequestBytes {
                sendResponse(status: "413 Payload Too Large", body: "", on: connection)
                return
            }
            if request.range(of: Data("\r\n\r\n".utf8)) != nil || complete || error != nil {
                handle(request: request, on: connection)
            } else {
                receiveRequest(on: connection, accumulated: request)
            }
        }
    }

    private nonisolated func handle(request: Data, on connection: NWConnection) {
        guard let requestText = String(data: request, encoding: .utf8),
              let requestLine = requestText.components(separatedBy: "\r\n").first
        else {
            sendResponse(status: "400 Bad Request", body: "", on: connection)
            return
        }
        let fields = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 2, fields[0] == "GET" else {
            sendResponse(status: "405 Method Not Allowed", body: "", on: connection)
            return
        }

        Task { @MainActor in
            guard self.listener != nil,
                  self.terminalError == nil,
                  !self.hasAcceptedCallback,
                  let redirectURI,
                  let redirect = URL(string: redirectURI),
                  let callback = URL(string: String(fields[1]), relativeTo: redirect),
                  callback.scheme == redirect.scheme,
                  callback.host == redirect.host,
                  callback.port == redirect.port,
                  callback.path == Self.callbackPath
            else {
                self.sendResponse(status: "404 Not Found", body: "", on: connection)
                return
            }
            self.hasAcceptedCallback = true

            let message = String(
                localized: "Google sign-in is complete. You can close this window and return to Brev.",
                bundle: .module
            )
            let body = "<!doctype html><meta charset=\"utf-8\"><title>Brev</title><p>\(message)</p>"
            self.sendResponse(status: "200 OK", body: body, on: connection)
            self.listener?.cancel()
            self.listener = nil
            self.cancelConnections(except: connection)
            if let callbackContinuation {
                self.callbackContinuation = nil
                callbackContinuation.resume(returning: callback.absoluteURL)
            } else {
                self.bufferedCallback = callback.absoluteURL
            }
        }
    }

    private nonisolated func sendResponse(status: String, body: String, on connection: NWConnection) {
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            Task { @MainActor in
                self?.connections.removeValue(forKey: ObjectIdentifier(connection))
            }
        })
    }

    private func cancelConnections(except preservedConnection: NWConnection? = nil) {
        let preservedID = preservedConnection.map(ObjectIdentifier.init)
        for (identifier, connection) in connections where identifier != preservedID {
            connection.cancel()
        }
        if let preservedConnection, let preservedID {
            connections = [preservedID: preservedConnection]
        } else {
            connections.removeAll()
        }
    }

    private func finish(with error: GoogleOAuthLoopbackReceiverError) {
        terminalError = error
        startContinuation?.resume(throwing: error)
        startContinuation = nil
        callbackContinuation?.resume(throwing: error)
        callbackContinuation = nil
    }
}
#endif
