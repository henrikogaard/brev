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

import BrevDesign
import Foundation

struct MailboxViewSettings: Equatable, Sendable {
    var useRichRenderer: Bool
    var allowRemoteContent: Bool
    var groupByThread: Bool
    var groupByDate: Bool
    var showAbsoluteArrivalTime: Bool
    var showSenderAvatars: Bool
    var previewLineCount: MailboxPreviewLineCount
    var fontFamily: MailboxFontFamily
    var textSize: MailboxTextSize
    var listDensity: MailboxListDensity
    var sortOrder: MailboxSortOrder
    var threadMessageOrder: MailboxThreadOrder
    var readingPanePlacement: MailboxReadingPanePlacement
    var showFolderStats: Bool
    var folderStatsDetail: MailboxFolderStatsDetail

    static let defaults = MailboxViewSettings(
        useRichRenderer: true,
        allowRemoteContent: false,
        groupByThread: true,
        groupByDate: true,
        showAbsoluteArrivalTime: false,
        showSenderAvatars: true,
        previewLineCount: .one,
        fontFamily: .system,
        textSize: .medium,
        listDensity: .comfortable,
        sortOrder: .newestFirst,
        threadMessageOrder: .oldestFirst,
        readingPanePlacement: .side,
        showFolderStats: true,
        folderStatsDetail: .compact
    )

    static func load(from defaults: UserDefaults = .standard) -> MailboxViewSettings {
        MailboxViewSettings(
            useRichRenderer: bool(
                for: MailboxViewPreferenceKey.useRichRenderer,
                defaultValue: Self.defaults.useRichRenderer,
                defaults: defaults
            ),
            allowRemoteContent: bool(
                for: MailboxViewPreferenceKey.allowRemoteContent,
                defaultValue: Self.defaults.allowRemoteContent,
                defaults: defaults
            ),
            groupByThread: bool(
                for: MailboxViewPreferenceKey.groupByThread,
                defaultValue: Self.defaults.groupByThread,
                defaults: defaults
            ),
            groupByDate: bool(
                for: MailboxViewPreferenceKey.groupByDate,
                defaultValue: Self.defaults.groupByDate,
                defaults: defaults
            ),
            showAbsoluteArrivalTime: bool(
                for: MailboxViewPreferenceKey.showAbsoluteArrivalTime,
                defaultValue: Self.defaults.showAbsoluteArrivalTime,
                defaults: defaults
            ),
            showSenderAvatars: bool(
                for: MailboxViewPreferenceKey.showSenderAvatars,
                defaultValue: Self.defaults.showSenderAvatars,
                defaults: defaults
            ),
            previewLineCount: intEnumValue(
                MailboxPreviewLineCount.self,
                for: MailboxViewPreferenceKey.previewLineCount,
                defaultValue: Self.defaults.previewLineCount,
                defaults: defaults
            ),
            fontFamily: enumValue(
                MailboxFontFamily.self,
                for: MailboxViewPreferenceKey.fontFamily,
                defaultValue: Self.defaults.fontFamily,
                defaults: defaults
            ),
            textSize: enumValue(
                MailboxTextSize.self,
                for: MailboxViewPreferenceKey.textSize,
                defaultValue: Self.defaults.textSize,
                defaults: defaults
            ),
            listDensity: enumValue(
                MailboxListDensity.self,
                for: MailboxViewPreferenceKey.listDensity,
                defaultValue: Self.defaults.listDensity,
                defaults: defaults
            ),
            sortOrder: enumValue(
                MailboxSortOrder.self,
                for: MailboxViewPreferenceKey.sortOrder,
                defaultValue: Self.defaults.sortOrder,
                defaults: defaults
            ),
            threadMessageOrder: enumValue(
                MailboxThreadOrder.self,
                for: MailboxViewPreferenceKey.threadMessageOrder,
                defaultValue: Self.defaults.threadMessageOrder,
                defaults: defaults
            ),
            readingPanePlacement: enumValue(
                MailboxReadingPanePlacement.self,
                for: MailboxViewPreferenceKey.readingPanePlacement,
                defaultValue: Self.defaults.readingPanePlacement,
                defaults: defaults
            ),
            showFolderStats: bool(
                for: MailboxViewPreferenceKey.showFolderStats,
                defaultValue: Self.defaults.showFolderStats,
                defaults: defaults
            ),
            folderStatsDetail: enumValue(
                MailboxFolderStatsDetail.self,
                for: MailboxViewPreferenceKey.folderStatsDetail,
                defaultValue: Self.defaults.folderStatsDetail,
                defaults: defaults
            )
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(useRichRenderer, forKey: MailboxViewPreferenceKey.useRichRenderer)
        defaults.set(allowRemoteContent, forKey: MailboxViewPreferenceKey.allowRemoteContent)
        defaults.set(groupByThread, forKey: MailboxViewPreferenceKey.groupByThread)
        defaults.set(groupByDate, forKey: MailboxViewPreferenceKey.groupByDate)
        defaults.set(showAbsoluteArrivalTime, forKey: MailboxViewPreferenceKey.showAbsoluteArrivalTime)
        defaults.set(showSenderAvatars, forKey: MailboxViewPreferenceKey.showSenderAvatars)
        defaults.set(previewLineCount.rawValue, forKey: MailboxViewPreferenceKey.previewLineCount)
        defaults.set(fontFamily.rawValue, forKey: MailboxViewPreferenceKey.fontFamily)
        defaults.set(textSize.rawValue, forKey: MailboxViewPreferenceKey.textSize)
        defaults.set(listDensity.rawValue, forKey: MailboxViewPreferenceKey.listDensity)
        defaults.set(sortOrder.rawValue, forKey: MailboxViewPreferenceKey.sortOrder)
        defaults.set(threadMessageOrder.rawValue, forKey: MailboxViewPreferenceKey.threadMessageOrder)
        defaults.set(readingPanePlacement.rawValue, forKey: MailboxViewPreferenceKey.readingPanePlacement)
        defaults.set(showFolderStats, forKey: MailboxViewPreferenceKey.showFolderStats)
        defaults.set(folderStatsDetail.rawValue, forKey: MailboxViewPreferenceKey.folderStatsDetail)
    }

    private static func bool(
        for key: String,
        defaultValue: Bool,
        defaults: UserDefaults
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private static func enumValue<Value>(
        _ type: Value.Type,
        for key: String,
        defaultValue: Value,
        defaults: UserDefaults
    ) -> Value where Value: RawRepresentable, Value.RawValue == String {
        guard let rawValue = defaults.string(forKey: key),
              let value = Value(rawValue: rawValue) else {
            return defaultValue
        }
        return value
    }

    private static func intEnumValue<Value>(
        _ type: Value.Type,
        for key: String,
        defaultValue: Value,
        defaults: UserDefaults
    ) -> Value where Value: RawRepresentable, Value.RawValue == Int {
        guard defaults.object(forKey: key) != nil,
              let value = Value(rawValue: defaults.integer(forKey: key)) else {
            return defaultValue
        }
        return value
    }
}
