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
#if os(macOS)
import Darwin
#endif

/// Thin stdio JSON-RPC 2.0 bridge (`brev-mcp`) forwarding MCP requests over Brev's
/// user-private Unix domain socket (ADR-0095 §1).
///
/// Fails closed with a structured JSON-RPC error if Brev is not running or Agent access
/// is turned off, and never opens Realm or SQLite stores directly.
enum BrevMCPHelperCLI {
    private static let appGroupIdentifier = "group.eu.brevmail.brev"
    private static let stableBundleIdentifier = "eu.brevmail.brev"
    private static let maxSocketPathUTF8Bytes = 100

    static func resolveSocketPath(arguments: [String] = CommandLine.arguments) -> String {
        if let index = arguments.firstIndex(of: "--socket"), index + 1 < arguments.count {
            return arguments[index + 1]
        }
        if let env = ProcessInfo.processInfo.environment["BREV_MCP_SOCKET"], !env.isEmpty {
            return env
        }
        let bundleID = hostAppBundleIdentifier(executablePath: arguments.first)
        let names = socketFileNames(forBundleIdentifier: bundleID)
        let groupContainer = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Group Containers", isDirectory: true)
            .appendingPathComponent(appGroupIdentifier, isDirectory: true)

        for name in [names.primary, names.compact] {
            let candidate = groupContainer.appendingPathComponent(name, isDirectory: false).path
            if candidate.utf8.count <= maxSocketPathUTF8Bytes {
                return candidate
            }
        }

        let tempCandidate = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("b-\(getuid())-\(names.shortTag).sock", isDirectory: false)
            .path
        if tempCandidate.utf8.count <= maxSocketPathUTF8Bytes {
            return tempCandidate
        }

        return URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("b-\(getuid())-\(names.shortTag).sock", isDirectory: false)
            .path
    }

    private static func hostAppBundleIdentifier(executablePath: String?) -> String? {
        guard let executablePath, !executablePath.isEmpty else { return nil }
        // Bundled helper lives at `<App>.app/Contents/Helpers/brev-mcp`.
        let contentsURL = URL(fileURLWithPath: executablePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String,
              !bundleID.isEmpty
        else { return nil }
        return bundleID
    }

    private static func socketFileNames(
        forBundleIdentifier bundleID: String?
    ) -> (primary: String, compact: String, shortTag: String) {
        let trimmed = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty || trimmed == stableBundleIdentifier {
            return ("mcp.sock", "m.sock", "s")
        }
        if trimmed.hasSuffix(".nightly") {
            return ("mcp-nightly.sock", "m-n.sock", "n")
        }
        let hash = fnv1a6Hex(trimmed)
        return ("mcp-\(hash).sock", "m-\(hash).sock", hash)
    }

    private static func fnv1a6Hex(_ input: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in input.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(format: "%06x", hash & 0x00FF_FFFF)
    }

    static func run() {
        #if os(macOS)
        let socketPath = resolveSocketPath()
        let stdinHandle = FileHandle.standardInput
        let stdoutHandle = FileHandle.standardOutput
        var persistentFD: Int32 = -1
        defer { if persistentFD >= 0 { close(persistentFD) } }

        var pending = Data()
        while true {
            let chunk = stdinHandle.availableData
            if chunk.isEmpty { break }
            pending.append(chunk)

            while let newlineIndex = pending.firstIndex(of: 0x0A) {
                let lineData = pending.subdata(in: 0 ..< newlineIndex)
                pending.removeSubrange(0 ... newlineIndex)
                guard !lineData.isEmpty else { continue }

                if let response = forwardLine(lineData, toSocketPath: socketPath, persistentFD: &persistentFD) {
                    stdoutHandle.write(response)
                    if response.last != 0x0A {
                        stdoutHandle.write(Data([0x0A]))
                    }
                }
            }
        }
        #endif
    }

    #if os(macOS)
    private static func forwardLine(
        _ lineData: Data,
        toSocketPath socketPath: String,
        persistentFD: inout Int32
    ) -> Data? {
        if persistentFD < 0 {
            guard let fd = connectUnixSocket(path: socketPath) else {
                return unavailableResponse(for: lineData)
            }
            persistentFD = fd
        }

        var payload = lineData
        payload.append(0x0A)
        var wroteAll = writeAll(payload, to: persistentFD)
        if !wroteAll {
            close(persistentFD)
            persistentFD = -1
            guard let retryFD = connectUnixSocket(path: socketPath) else {
                return unavailableResponse(for: lineData)
            }
            persistentFD = retryFD
            wroteAll = writeAll(payload, to: persistentFD)
        }
        guard wroteAll else {
            close(persistentFD)
            persistentFD = -1
            return unavailableResponse(for: lineData)
        }

        // Notifications (no `id`) expect no response.
        if !requestHasID(lineData) { return nil }

        var response = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(persistentFD, &chunk, chunk.count)
            if n <= 0 {
                close(persistentFD)
                persistentFD = -1
                break
            }
            response.append(contentsOf: chunk[0 ..< n])
            if response.contains(0x0A) { break }
        }
        return response.isEmpty ? unavailableResponse(for: lineData) : response
    }

    private static func writeAll(_ payload: Data, to fd: Int32) -> Bool {
        payload.withUnsafeBytes { rawPtr -> Bool in
            guard let base = rawPtr.baseAddress else { return false }
            var total = 0
            while total < payload.count {
                let written = write(fd, base.advanced(by: total), payload.count - total)
                if written <= 0 { return false }
                total += written
            }
            return true
        }
    }

    private static func connectUnixSocket(path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            return nil
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { rawBuffer in
            rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)
            for (index, byte) in bytes.enumerated() {
                rawBuffer[index] = byte
            }
        }
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, addrLen)
            }
        }
        guard result == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    private static func requestHasID(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return true
        }
        return object["id"] != nil
    }

    private static func unavailableResponse(for requestData: Data) -> Data? {
        let requestID: Any
        if let object = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any] {
            guard let id = object["id"] else { return nil }
            requestID = id
        } else {
            requestID = NSNull()
        }
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "error": [
                "code": -32001,
                "message": "Brev is not running or Agent access is turned off in Settings → Agent access."
            ]
        ]
        return try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
    #endif
}

BrevMCPHelperCLI.run()
