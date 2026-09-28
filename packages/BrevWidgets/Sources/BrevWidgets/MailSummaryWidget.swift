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

#if canImport(WidgetKit)
import SwiftUI
import WidgetKit

/// Timeline entry for the mail summary widget: just the snapshot the
/// app last wrote, plus the entry date WidgetKit requires.
public struct MailSummaryEntry: TimelineEntry {
    public let date: Date
    public let snapshot: WidgetSnapshot?

    public init(date: Date = Date(), snapshot: WidgetSnapshot?) {
        self.date = date
        self.snapshot = snapshot
    }
}

/// Reloads on demand only — the app calls `WidgetCenter.reloadTimelines`
/// whenever it writes a fresh snapshot, so the provider never schedules
/// its own refresh cadence (ADR-0083; widgets do no sync work).
public struct MailSummaryProvider: TimelineProvider {
    private let store: WidgetSnapshotStore

    public init(store: WidgetSnapshotStore = WidgetSnapshotStore()) {
        self.store = store
    }

    public func placeholder(in context: Context) -> MailSummaryEntry {
        MailSummaryEntry(snapshot: WidgetSnapshot(
            generatedAt: .now,
            totalUnread: 3,
            previews: [
                WidgetMessagePreview(
                    senderName: String(localized: "Ina Berg", bundle: .module),
                    subject: String(localized: "Quarterly report", bundle: .module),
                    receivedAt: .now
                )
            ]
        ))
    }

    public func getSnapshot(in context: Context, completion: @escaping (MailSummaryEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        completion(MailSummaryEntry(snapshot: store.load()))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<MailSummaryEntry>) -> Void) {
        completion(Timeline(entries: [MailSummaryEntry(snapshot: store.load())], policy: .never))
    }
}

/// "Mail" widget: unified-inbox unread count plus the newest previews.
/// Small shows the count and the newest sender; medium adds up to
/// three preview rows (ADR-0083 narrow first scope).
public struct MailSummaryWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "eu.brevmail.brev.widgets.mail-summary",
            provider: MailSummaryProvider()
        ) { entry in
            MailSummaryWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Mail", bundle: .module))
        .description(String(localized: "Unread count and latest messages from your unified inbox.", bundle: .module))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
#endif
