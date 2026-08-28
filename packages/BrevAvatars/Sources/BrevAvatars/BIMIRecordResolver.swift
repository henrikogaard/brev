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

import Dispatch
import Foundation

#if canImport(dnssd)
import dnssd
#endif

protocol AvatarBIMIRecordResolving: Sendable {
    func logoURL(for domain: String) async -> URL?
}

/// Maximum raw byte count accepted for a BIMI SVG logo. Many BIMI validators
/// cap at 32 KB; logos larger than this are rejected and fall back to initials.
let bimiMaximumSVGByteCount = 32768

struct SystemBIMIRecordResolver: AvatarBIMIRecordResolving {
    func logoURL(for domain: String) async -> URL? {
        let records = await DNSServiceTXTLookup.records(
            named: "default._bimi.\(domain)",
            timeout: 3
        )
        return records.lazy.compactMap(Self.logoURL(fromTXTRecord:)).first
    }

    static func logoURL(fromTXTRecord record: String) -> URL? {
        let fields = record.split(separator: ";", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let hasBIMIVersion = fields.contains { $0.caseInsensitiveCompare("v=BIMI1") == .orderedSame }
        guard hasBIMIVersion else { return nil }

        guard let logoField = fields.first(where: { field in
            field.lowercased().hasPrefix("l=")
        }) else {
            return nil
        }

        let rawURL = logoField.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawURL.isEmpty else { return nil }
        return URL(string: rawURL)
    }
}

// MARK: - DMARC policy

/// The DMARC `p=` policy tag values that make BIMI meaningful.
///
/// BIMI is only warranted for domains that publish a strong DMARC policy —
/// `quarantine` or `reject`. A `none` policy (or an absent DMARC record) does
/// not protect the domain from spoofing, so displaying the brand logo would
/// mislead recipients. See RFC 9091 §4.
enum DMARCPolicy: Sendable {
    case quarantine
    case reject
    case none
    case unknown

    /// Parse the `p=` value from a raw DMARC TXT record.
    ///
    /// Returns `.unknown` when the record is malformed or the tag is absent.
    init(fromTXTRecord record: String) {
        let fields = record.split(separator: ";", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        guard fields.contains(where: { $0 == "v=dmarc1" }) else {
            self = .unknown
            return
        }

        guard let pField = fields.first(where: { $0.hasPrefix("p=") }) else {
            self = .unknown
            return
        }

        switch pField.dropFirst(2) {
        case "quarantine": self = .quarantine
        case "reject": self = .reject
        case "none": self = .none
        default: self = .unknown
        }
    }

    /// Whether this policy is strong enough for BIMI display.
    var isBIMIPermitted: Bool {
        switch self {
        case .quarantine, .reject: return true
        case .none, .unknown: return false
        }
    }
}

protocol AvatarDMARCPolicyResolving: Sendable {
    func policy(for domain: String) async -> DMARCPolicy
}

struct SystemDMARCPolicyResolver: AvatarDMARCPolicyResolving {
    func policy(for domain: String) async -> DMARCPolicy {
        let records = await DNSServiceTXTLookup.records(
            named: "_dmarc.\(domain)",
            timeout: 3
        )
        return records.lazy.map(DMARCPolicy.init(fromTXTRecord:))
            .first { $0 != .unknown } ?? .unknown
    }
}

#if canImport(dnssd)
private enum DNSServiceTXTLookup {
    static func records(named name: String, timeout: TimeInterval) async -> [String] {
        await withCheckedContinuation { continuation in
            let context = DNSServiceTXTLookupContext(continuation: continuation)
            let retainedContext = context.retainContext()
            var serviceRef: DNSServiceRef?
            let queryError = name.withCString { cName in
                DNSServiceQueryRecord(
                    &serviceRef,
                    0,
                    0,
                    cName,
                    UInt16(kDNSServiceType_TXT),
                    UInt16(kDNSServiceClass_IN),
                    queryCallback,
                    retainedContext
                )
            }
            guard queryError == kDNSServiceErr_NoError,
                  let serviceRef else {
                context.finish([])
                return
            }

            context.setServiceRef(serviceRef)
            let queueError = DNSServiceSetDispatchQueue(
                serviceRef,
                DispatchQueue.global(qos: .utility)
            )
            guard queueError == kDNSServiceErr_NoError else {
                context.finish([])
                return
            }

            Task.detached {
                let nanoseconds = UInt64((timeout * 1_000_000_000).rounded())
                try? await Task.sleep(nanoseconds: nanoseconds)
                context.finish([])
            }
        }
    }

    private static let queryCallback: DNSServiceQueryRecordReply =
        { _, _, _, errorCode, _, rrtype, _, rdlen, rdata, _, rawContext in
            guard let rawContext else { return }
            let context = Unmanaged<DNSServiceTXTLookupContext>
                .fromOpaque(rawContext)
                .takeUnretainedValue()
            guard errorCode == kDNSServiceErr_NoError,
                  rrtype == UInt16(kDNSServiceType_TXT),
                  let rdata,
                  let record = decodeTXTRecord(Data(bytes: rdata, count: Int(rdlen)))
            else {
                context.finish([])
                return
            }

            context.finish([record])
        }

    private static func decodeTXTRecord(_ data: Data) -> String? {
        var strings: [String] = []
        var index = data.startIndex

        while index < data.endIndex {
            let length = Int(data[index])
            index = data.index(after: index)
            guard length <= data.distance(from: index, to: data.endIndex) else {
                return nil
            }
            let end = data.index(index, offsetBy: length)
            guard let string = String(data: data[index ..< end], encoding: .utf8) else {
                return nil
            }
            strings.append(string)
            index = end
        }

        return strings.isEmpty ? nil : strings.joined()
    }
}

private final class DNSServiceTXTLookupContext: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[String], Never>?
    private var retainedContext: UnsafeMutableRawPointer?
    private var serviceRef: DNSServiceRef?

    init(continuation: CheckedContinuation<[String], Never>) {
        self.continuation = continuation
    }

    func retainContext() -> UnsafeMutableRawPointer {
        lock.lock()
        defer { lock.unlock() }
        if let retainedContext {
            return retainedContext
        }
        let retainedContext = Unmanaged.passRetained(self).toOpaque()
        self.retainedContext = retainedContext
        return retainedContext
    }

    func setServiceRef(_ serviceRef: DNSServiceRef) {
        lock.withLock {
            self.serviceRef = serviceRef
        }
    }

    func finish(_ records: [String]) {
        let continuation: CheckedContinuation<[String], Never>?
        let serviceRef: DNSServiceRef?
        let retainedContext: UnsafeMutableRawPointer?

        lock.lock()
        guard self.continuation != nil else {
            lock.unlock()
            return
        }
        continuation = self.continuation
        self.continuation = nil
        serviceRef = self.serviceRef
        self.serviceRef = nil
        retainedContext = self.retainedContext
        self.retainedContext = nil
        lock.unlock()

        if let serviceRef {
            DNSServiceRefDeallocate(serviceRef)
        }
        continuation?.resume(returning: records)
        if let retainedContext {
            Unmanaged<DNSServiceTXTLookupContext>
                .fromOpaque(retainedContext)
                .release()
        }
    }
}
#else
private enum DNSServiceTXTLookup {
    static func records(named name: String, timeout: TimeInterval) async -> [String] {
        []
    }
}
#endif
