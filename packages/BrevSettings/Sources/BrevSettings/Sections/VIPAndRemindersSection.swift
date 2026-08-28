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
import BrevThemes
import SwiftUI

struct VIPAndRemindersSection: View {
    @Environment(\.brevTheme) private var theme
    private let settingsStore: SettingsPersistenceStore
    @State private var vipSettings: VIPSenderSettings
    @State private var followUpSettings: FollowUpSettings
    @State private var blockedSendersSettings: BlockedSendersSettings
    @State private var newVIPEmail = ""
    @State private var isAddingVIP = false
    @State private var vipErrorMessage: String?

    init(settingsStore: SettingsPersistenceStore = .standard) {
        self.settingsStore = settingsStore
        _vipSettings = State(initialValue: settingsStore.vipSenderSettings())
        _followUpSettings = State(initialValue: settingsStore.followUpSettings())
        _blockedSendersSettings = State(initialValue: BlockedSendersSettings.load())
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "VIP & Reminders", bundle: .module),
            subtitle: String(
                localized: "Mark senders as VIP to find their messages quickly. Set follow-up reminders on individual messages.",
                bundle: .module
            )
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                vipSendersGroup
                blockedSendersGroup
                followUpGroup
            }
        }
    }

    // MARK: - VIP senders

    private var vipSendersGroup: some View {
        SettingsGroup(
            title: String(localized: "VIP senders", bundle: .module),
            subtitle: String(localized: "Messages from VIP senders appear in the VIP smart view.", bundle: .module),
            symbolName: "star"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                if vipSettings.senders.isEmpty {
                    Text("No VIP senders yet.", bundle: .module)
                        .brevFont(.body)
                        .foregroundStyle(theme.textSecondary.color)
                } else {
                    VStack(spacing: BrevSpacing.xs) {
                        ForEach(vipSettings.senders) { sender in
                            VIPSenderRow(sender: sender) {
                                removeVIP(email: sender.email)
                            }
                        }
                    }
                }

                HStack(spacing: BrevSpacing.sm) {
                    if isAddingVIP {
                        TextField("email@example.com", text: $newVIPEmail)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { confirmAddVIP() }
                        BrevButton(String(localized: "Add", bundle: .module), style: .secondary) { confirmAddVIP() }
                        BrevButton(String(localized: "Cancel", bundle: .module), style: .tertiary) {
                            isAddingVIP = false
                            newVIPEmail = ""
                            vipErrorMessage = nil
                        }
                    } else {
                        BrevButton(String(localized: "Add VIP sender", bundle: .module), style: .secondary) {
                            isAddingVIP = true
                        }
                        Spacer(minLength: 0)
                    }
                }

                if let vipErrorMessage {
                    Text(vipErrorMessage)
                        .brevFont(.caption)
                        .foregroundStyle(theme.danger.color)
                }

                SettingsInfoCallout(
                    symbolName: "info.circle",
                    message: String(
                        localized: "VIP status is local to this device. You can also mark a sender as VIP from the message header.",
                        bundle: .module
                    ),
                    tone: .info
                )
            }
        }
    }

    // MARK: - Blocked senders

    /// Blocking is offered from the message header, but the list it writes
    /// to had no reader anywhere in the app — the row view and the unblock
    /// call below both existed and were never reachable, so blocking a
    /// sender was a one-way door.
    private var blockedSendersGroup: some View {
        SettingsGroup(
            title: String(localized: "Blocked senders", bundle: .module),
            subtitle: String(localized: "Messages from these senders are filtered out of your mailbox.", bundle: .module),
            symbolName: "nosign"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                if blockedSendersSettings.blockedEmails.isEmpty {
                    Text("No blocked senders.", bundle: .module)
                        .brevFont(.body)
                        .foregroundStyle(theme.textSecondary.color)
                } else {
                    VStack(spacing: BrevSpacing.xs) {
                        ForEach(blockedSendersSettings.blockedEmails, id: \.self) { email in
                            BlockedSenderRow(email: email) {
                                unblockSender(email: email)
                            }
                        }
                    }
                }

                SettingsInfoCallout(
                    symbolName: "info.circle",
                    message: String(
                        localized: "Block a sender from the message header. Blocking is local to this device.",
                        bundle: .module
                    ),
                    tone: .info
                )
            }
        }
    }

    // MARK: - Follow-up reminders

    private var followUpGroup: some View {
        SettingsGroup(
            title: String(localized: "Follow-up reminders", bundle: .module),
            subtitle: String(localized: "Set reminders directly from the message reading pane or context menu.", bundle: .module),
            symbolName: "clock.badge.exclamationmark"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                let active = followUpSettings.activeReminders
                if active.isEmpty {
                    Text("No active follow-up reminders.", bundle: .module)
                        .brevFont(.body)
                        .foregroundStyle(theme.textSecondary.color)
                } else {
                    VStack(spacing: BrevSpacing.xs) {
                        ForEach(active) { reminder in
                            FollowUpReminderRow(reminder: reminder) {
                                completeReminder(id: reminder.id)
                            } onDismiss: {
                                dismissReminder(id: reminder.id)
                            }
                        }
                    }
                }

                SettingsInfoCallout(
                    symbolName: "info.circle",
                    message: String(
                        localized: "Follow-up reminders are local to this device. They are not synced to the server.",
                        bundle: .module
                    ),
                    tone: .info
                )
            }
        }
    }

    // MARK: - Actions

    private func confirmAddVIP() {
        let trimmed = newVIPEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            vipErrorMessage = String(localized: "Email address cannot be empty.", bundle: .module)
            return
        }
        guard trimmed.contains("@") else {
            vipErrorMessage = String(localized: "Enter a valid email address.", bundle: .module)
            return
        }
        vipSettings.add(VIPSender(email: trimmed))
        settingsStore.save(vipSettings)
        newVIPEmail = ""
        isAddingVIP = false
        vipErrorMessage = nil
    }

    private func removeVIP(email: String) {
        vipSettings.remove(email: email)
        settingsStore.save(vipSettings)
    }

    private func completeReminder(id: FollowUpReminder.ID) {
        followUpSettings.complete(id: id)
        settingsStore.save(followUpSettings)
        NotificationCenter.default.post(name: .brevFollowUpDidChange, object: nil)
    }

    private func dismissReminder(id: FollowUpReminder.ID) {
        followUpSettings.dismiss(id: id)
        settingsStore.save(followUpSettings)
        NotificationCenter.default.post(name: .brevFollowUpDidChange, object: nil)
    }

    private func unblockSender(email: String) {
        blockedSendersSettings.unblock(email)
        blockedSendersSettings.save(to: .standard)
    }
}

// MARK: - Row components

private struct BlockedSenderRow: View {
    @Environment(\.brevTheme) private var theme
    let email: String
    let onUnblock: () -> Void

    var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "nosign")
                .foregroundStyle(theme.danger.color)
                .font(.system(size: 12))
            Text(email)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
            Spacer()
            BrevButton(String(localized: "Unblock", bundle: .module), style: .tertiary) { onUnblock() }
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(theme.bgSecondary.color)
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
    }
}

private struct VIPSenderRow: View {
    @Environment(\.brevTheme) private var theme
    let sender: VIPSender
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "star.fill")
                .foregroundStyle(theme.warning.color)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 2) {
                if let displayName = sender.displayName, !displayName.isEmpty {
                    Text(displayName)
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.textPrimary.color)
                    Text(sender.email)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textTertiary.color)
                } else {
                    Text(sender.email)
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.textPrimary.color)
                }
            }

            Spacer()

            BrevButton(String(localized: "Remove", bundle: .module), style: .tertiary) { onRemove() }
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(theme.bgSecondary.color)
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
    }
}

private struct FollowUpReminderRow: View {
    @Environment(\.brevTheme) private var theme
    let reminder: FollowUpReminder
    let onComplete: () -> Void
    let onDismiss: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: reminder.isDue() ? "clock.badge.exclamationmark" : "clock")
                .foregroundStyle(reminder.isDue() ? theme.warning.color : theme.textTertiary.color)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text("Message \(String(reminder.messageID.prefix(8)))…", bundle: .module)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textPrimary.color)
                Text("Due: \(Self.dateFormatter.string(from: reminder.dueAt))", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(reminder.isDue() ? theme.warning.color : theme.textSecondary.color)
            }

            Spacer()

            BrevButton(String(localized: "Done", bundle: .module), style: .secondary) { onComplete() }
            BrevButton(String(localized: "Dismiss", bundle: .module), style: .tertiary) { onDismiss() }
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(theme.bgSecondary.color)
        .clipShape(RoundedRectangle(cornerRadius: BrevRadius.sm))
    }
}
