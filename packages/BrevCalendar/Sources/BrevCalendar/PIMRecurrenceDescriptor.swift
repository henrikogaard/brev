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

/// Lossless recurrence metadata captured at the adapter boundary
/// (ADR-0089).
///
/// `ICSParser.RecurrenceRule` is a descriptive summary — it drops
/// unknown RRULE parts and cannot drive occurrence generation. The
/// descriptor instead keeps every recurrence property verbatim plus
/// the DTSTART basis the projector needs, so the strict validator can
/// reject a series rather than silently expanding it wrong.
public struct PIMRecurrenceDescriptor: Sendable, Hashable, Codable {
    /// How the series' DTSTART value must be interpreted when
    /// generating wall-clock occurrences.
    public enum StartBasis: Sendable, Hashable, Codable {
        /// `VALUE=DATE`: whole days, stored as UTC-midnight instants.
        case dateOnly
        /// Date-time with a `Z` suffix — anchored to UTC.
        case utc
        /// Date-time with a `TZID` parameter (or a Google `timeZone`
        /// field); the payload is the verbatim zone identifier.
        case zoned(String)
        /// Date-time with no zone marker — floating local time.
        case floating
        /// No DTSTART / no basis information was captured.
        case unknown
    }

    /// Schema version of the descriptor payload.
    public static let currentVersion = 1

    /// Descriptor schema version; always `currentVersion` on write.
    public var version: Int
    /// Raw RRULE values in source order, verbatim, without the
    /// `RRULE:` prefix.
    public var rrules: [String]
    /// Whether the record carries any `RDATE` property (Google
    /// `RDATE:` recurrence entry).
    public var hasRDate: Bool
    /// Whether the record carries any `EXDATE` property (Google
    /// `EXDATE:` recurrence entry).
    public var hasExDate: Bool
    /// Raw EXDATE property bodies in source order, each as
    /// `<params>:<values>` without the `EXDATE` name (for example
    /// `TZID=Europe/Oslo:20261020T090000` or `:20261020T070000Z`).
    /// Empty on caches written before exclusions were captured; the
    /// validator then treats `hasExDate` as unsupported.
    public var exdates: [String]
    /// Google `recurrence[]` held entries other than RRULE/RDATE/EXDATE.
    /// Always false for ICS sources, where unknown properties stay in
    /// `rawPayload` only.
    public var hasUnrecognizedEntries: Bool
    /// The DTSTART basis captured at the boundary.
    public var startBasis: StartBasis

    public init(
        version: Int = Self.currentVersion,
        rrules: [String] = [],
        hasRDate: Bool = false,
        hasExDate: Bool = false,
        exdates: [String] = [],
        hasUnrecognizedEntries: Bool = false,
        startBasis: StartBasis = .unknown
    ) {
        self.version = version
        self.rrules = rrules
        self.hasRDate = hasRDate
        self.hasExDate = hasExDate
        self.exdates = exdates
        self.hasUnrecognizedEntries = hasUnrecognizedEntries
        self.startBasis = startBasis
    }

    /// Tolerant decoding: every field defaults so a descriptor written
    /// by an older schema still loads (ADR-0089 cache rule).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
            ?? Self.currentVersion
        rrules = try container.decodeIfPresent([String].self, forKey: .rrules)
            ?? []
        hasRDate = try container.decodeIfPresent(Bool.self, forKey: .hasRDate)
            ?? false
        hasExDate = try container.decodeIfPresent(Bool.self, forKey: .hasExDate)
            ?? false
        exdates = try container.decodeIfPresent([String].self, forKey: .exdates)
            ?? []
        hasUnrecognizedEntries = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasUnrecognizedEntries
        ) ?? false
        startBasis = try container.decodeIfPresent(
            StartBasis.self,
            forKey: .startBasis
        ) ?? .unknown
    }
}
