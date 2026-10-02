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

import BrevBackend
import BrevDesign
import BrevThemes
import SwiftUI

struct MailboxViewSection: View {
    @Environment(\.brevTheme) private var theme
    @State private var mailboxSettings: MailboxViewSettings
    @State private var inboxClassificationSettings: InboxClassificationSettings
    @State private var folderPreferences: FolderPreferences

    private let settingsStore: SettingsPersistenceStore

    init(settingsStore: SettingsPersistenceStore = .standard) {
        self.settingsStore = settingsStore
        _mailboxSettings = State(initialValue: settingsStore.mailboxViewSettings())
        _inboxClassificationSettings = State(initialValue: settingsStore.inboxClassificationSettings())
        _folderPreferences = State(initialValue: settingsStore.folderPreferences())
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "Mailbox View", bundle: .module),
            subtitle: String(localized: "Reading, list layout, sidebar folders, and links.", bundle: .module),
            showsTitle: false
        ) {
            // One scroll instead of a segmented control nested inside a tabbed
            // pane: the four groups are short enough to read together, and
            // settings search scrolls straight to the group it names.
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                readingGroup
                SettingsMailPreview(settings: mailboxSettings)
                listGroup
                folderVisibilityGroup
                BrowserSettingsGroup(settingsStore: settingsStore)
            }
        }
    }

    private var folderVisibilityGroup: some View {
        SettingsGroup(
            title: String(localized: "Folders", bundle: .module),
            subtitle: String(localized: "Show or hide standard folders in the mailbox sidebar.", bundle: .module),
            symbolName: "folder"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsToggleRow(
                    symbolName: "star",
                    title: String(localized: "Starred", bundle: .module),
                    subtitle: String(localized: "Show the starred shortcut folder.", bundle: .module),
                    isOn: folderBinding(for: \.showStarred)
                )

                SettingsToggleRow(
                    symbolName: "clock",
                    title: String(localized: "Snoozed", bundle: .module),
                    subtitle: String(localized: "Show the snoozed messages folder.", bundle: .module),
                    isOn: folderBinding(for: \.showSnoozed)
                )

                SettingsToggleRow(
                    symbolName: "calendar.badge.clock",
                    title: String(localized: "Scheduled", bundle: .module),
                    subtitle: String(localized: "Show the scheduled send/recall folder.", bundle: .module),
                    isOn: folderBinding(for: \.showScheduled)
                )

                SettingsToggleRow(
                    symbolName: "tray.full",
                    title: String(localized: "All mail", bundle: .module),
                    subtitle: String(localized: "Show the all-mail aggregate folder.", bundle: .module),
                    isOn: folderBinding(for: \.showAllMail)
                )

                SettingsToggleRow(
                    symbolName: "exclamationmark.octagon",
                    title: String(localized: "Spam", bundle: .module),
                    subtitle: String(localized: "Show the spam folder.", bundle: .module),
                    isOn: folderBinding(for: \.showSpam)
                )

                SettingsToggleRow(
                    symbolName: "trash",
                    title: String(localized: "Trash", bundle: .module),
                    subtitle: String(localized: "Show the trash folder.", bundle: .module),
                    isOn: folderBinding(for: \.showTrash)
                )

                SettingsToggleRow(
                    symbolName: "archivebox",
                    title: String(localized: "Archive", bundle: .module),
                    subtitle: String(localized: "Show the archive folder.", bundle: .module),
                    isOn: folderBinding(for: \.showArchive)
                )

                SettingsToggleRow(
                    symbolName: "sidebar.left",
                    title: String(localized: "Sidebar icons", bundle: .module),
                    subtitle: String(
                        localized: "Show icons next to sidebar rows. Turn off for a denser, text-only rail.",
                        bundle: .module
                    ),
                    isOn: folderBinding(for: \.showIcons)
                )
            }
        }
    }

    private var readingGroup: some View {
        SettingsGroup(
            title: String(localized: "Reading", bundle: .module),
            subtitle: String(localized: "Rendering, conversation order, and type.", bundle: .module),
            symbolName: "text.alignleft"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsToggleRow(
                    symbolName: "doc.richtext",
                    title: String(localized: "Use rich HTML renderer", bundle: .module),
                    subtitle: String(
                        localized: "Show full message formatting inside Brev's sandboxed web view.",
                        bundle: .module
                    ),
                    isOn: mailboxBinding(for: \.useRichRenderer)
                )

                SettingsPickerRow(
                    symbolName: "arrow.up.arrow.down.square",
                    title: String(localized: "Conversation order", bundle: .module),
                    subtitle: mailboxSettings.threadMessageOrder.subtitle,
                    selection: mailboxBinding(for: \.threadMessageOrder)
                ) {
                    ForEach(MailboxThreadOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }

                SettingsPickerRow(
                    symbolName: "textformat",
                    title: String(localized: "Message font", bundle: .module),
                    subtitle: String(localized: "Applies to mailbox previews, readable bodies, and compose.", bundle: .module),
                    selection: mailboxBinding(for: \.fontFamily)
                ) {
                    ForEach(MailboxFontFamily.allCases) { fontFamily in
                        Text(fontFamily.title).tag(fontFamily)
                    }
                }

                #if os(iOS)
                SettingsSegmentedRow(
                    symbolName: "textformat.size",
                    title: String(localized: "Text size", bundle: .module),
                    subtitle: String(localized: "Applies to reading and composing message text.", bundle: .module),
                    selection: mailboxBinding(for: \.textSize)
                ) {
                    ForEach(MailboxTextSize.allCases) { textSize in
                        Text(textSize.title).tag(textSize)
                    }
                }
                #endif

                fontPreview

                SettingsInfoCallout(
                    symbolName: "shield",
                    message: String(
                        localized: "Remote images, web fonts, and tracking pixels stay blocked unless you opt in.",
                        bundle: .module
                    ),
                    tone: .info
                )
            }
        }
    }

    private var listGroup: some View {
        SettingsGroup(
            title: String(localized: "Mailbox list", bundle: .module),
            subtitle: String(localized: "Tune the overview columns for scanning and triage.", bundle: .module),
            symbolName: "list.bullet.rectangle"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsToggleRow(
                    symbolName: "rectangle.stack",
                    title: String(localized: "Group conversations", bundle: .module),
                    subtitle: String(localized: "Collect related messages into conversation threads.", bundle: .module),
                    isOn: mailboxBinding(for: \.groupByThread)
                )

                SettingsToggleRow(
                    symbolName: "calendar",
                    title: String(localized: "Group by received date", bundle: .module),
                    subtitle: String(localized: "Show Today, Yesterday, Last week, and older sections.", bundle: .module),
                    isOn: mailboxBinding(for: \.groupByDate)
                )

                SettingsToggleRow(
                    symbolName: "clock",
                    title: String(localized: "Show arrival time", bundle: .module),
                    subtitle: String(localized: "Use time for today's mail and date plus time for older mail.", bundle: .module),
                    isOn: mailboxBinding(for: \.showAbsoluteArrivalTime)
                )

                SettingsToggleRow(
                    symbolName: "person.crop.circle",
                    title: String(localized: "Show sender images", bundle: .module),
                    subtitle: String(
                        localized: "Display avatar, photo, or initials circles beside messages and headers.",
                        bundle: .module
                    ),
                    isOn: mailboxBinding(for: \.showSenderAvatars)
                )

                SettingsPickerRow(
                    symbolName: "arrow.up.arrow.down",
                    title: String(localized: "Sort order", bundle: .module),
                    subtitle: mailboxSettings.sortOrder.subtitle,
                    selection: mailboxBinding(for: \.sortOrder)
                ) {
                    ForEach(MailboxSortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }

                SettingsSegmentedRow(
                    symbolName: "text.justify.left",
                    title: String(localized: "Preview lines", bundle: .module),
                    subtitle: mailboxSettings.previewLineCount.subtitle,
                    selection: mailboxBinding(for: \.previewLineCount)
                ) {
                    ForEach(MailboxPreviewLineCount.allCases) { count in
                        Text(count.shortTitle).tag(count)
                    }
                }

                #if os(iOS)
                SettingsSegmentedRow(
                    symbolName: "rectangle.compress.vertical",
                    title: String(localized: "List density", bundle: .module),
                    subtitle: String(localized: "Adjust row spacing in the mailbox overview.", bundle: .module),
                    selection: mailboxBinding(for: \.listDensity)
                ) {
                    ForEach(MailboxListDensity.allCases) { density in
                        Text(density.title).tag(density)
                    }
                }
                #endif

                SettingsPickerRow(
                    symbolName: "rectangle.split.2x1",
                    title: String(localized: "Reading pane", bundle: .module),
                    subtitle: mailboxSettings.readingPanePlacement.subtitle,
                    selection: mailboxBinding(for: \.readingPanePlacement)
                ) {
                    ForEach(MailboxReadingPanePlacement.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }

                SettingsToggleRow(
                    symbolName: "chart.bar.doc.horizontal",
                    title: String(localized: "Show folder stats", bundle: .module),
                    subtitle: String(
                        localized: "Display current-folder counts at the bottom of the message list.",
                        bundle: .module
                    ),
                    isOn: mailboxBinding(for: \.showFolderStats)
                )

                SettingsSegmentedRow(
                    symbolName: "tray.2",
                    title: String(localized: "Inbox classification", bundle: .module),
                    subtitle: inboxClassificationSettings.mode.subtitle,
                    selection: inboxClassificationModeBinding
                ) {
                    ForEach(InboxClassificationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                SettingsSegmentedRow(
                    symbolName: "text.line.first.and.arrowtriangle.forward",
                    title: String(localized: "Stats detail", bundle: .module),
                    subtitle: mailboxSettings.folderStatsDetail.subtitle,
                    selection: mailboxBinding(for: \.folderStatsDetail),
                    isEnabled: mailboxSettings.showFolderStats
                ) {
                    ForEach(MailboxFolderStatsDetail.allCases) { detail in
                        Text(detail.title).tag(detail)
                    }
                }
            }
        }
    }

    private var inboxClassificationModeBinding: Binding<InboxClassificationMode> {
        Binding(
            get: { inboxClassificationSettings.mode },
            set: { newValue in
                inboxClassificationSettings.mode = newValue
                settingsStore.save(inboxClassificationSettings)
            }
        )
    }

    private var fontPreview: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
            Text("Preview", bundle: .module)
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
            Text("Brev keeps message text calm, readable, and easy to scan.", bundle: .module)
                .font(mailboxSettings.fontFamily.font(size: mailboxSettings.textSize.bodyPointSize))
                .foregroundStyle(theme.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BrevSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brevQuietSurface(cornerRadius: BrevRadius.sm)
    }

    private func mailboxBinding<Value>(
        for keyPath: WritableKeyPath<MailboxViewSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { mailboxSettings[keyPath: keyPath] },
            set: { newValue in
                mailboxSettings[keyPath: keyPath] = newValue
                settingsStore.save(mailboxSettings)
            }
        )
    }

    private func folderBinding(
        for keyPath: WritableKeyPath<FolderPreferences, Bool>
    ) -> Binding<Bool> {
        folderPreferenceBinding(for: keyPath)
    }

    private func folderPreferenceBinding<Value>(
        for keyPath: WritableKeyPath<FolderPreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { folderPreferences[keyPath: keyPath] },
            set: { newValue in
                folderPreferences[keyPath: keyPath] = newValue
                settingsStore.save(folderPreferences)
            }
        )
    }
}
