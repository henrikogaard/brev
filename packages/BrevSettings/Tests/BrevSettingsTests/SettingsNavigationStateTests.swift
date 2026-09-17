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
@testable import BrevSettings
import Testing

@Suite("SettingsNavigationState")
@MainActor
struct SettingsNavigationStateTests {
    @Test("search results name the matching control and its scroll target")
    func searchDestinations() throws {
        let results = SettingsSearchResult.results(for: "font", sections: [.accounts, .mailboxView])
        let font = try #require(results.first { $0.title == "Message font" })
        #expect(font.section == .mailboxView)
        #expect(font.target == "Message font")
        #expect(SettingsSearchResult.results(for: "nonexistent-setting-xyz", sections: [.accounts, .mailboxView]).isEmpty)
    }

    @Test("search finds actual controls instead of only section titles")
    func searchFindsControls() {
        #expect(SettingsSection.mailboxView.matches(searchQuery: "font"))
        #expect(SettingsSection.mailboxView.matches(searchQuery: "text size"))
        #expect(SettingsSection.mailboxView.matches(searchQuery: "remote images"))
        #expect(SettingsSection.accounts.matches(searchQuery: "fetch schedule"))
    }

    @Test("Default section is Accounts")
    func defaultSection() {
        let nav = SettingsNavigationState()
        #expect(nav.selected == .accounts)
    }

    @Test("All sections have non-empty titles and symbols")
    func metadata() {
        for section in SettingsSection.allCases {
            #expect(!section.title.isEmpty)
            #expect(!section.symbolName.isEmpty)
        }
    }

    @Test("AI Writer section is available from settings navigation")
    func aiWriterSectionIsAvailable() {
        let section = SettingsSection(rawValue: "aiWriter")

        #expect(section?.title == "AI Writer")
        #expect(section?.symbolName == "wand.and.stars")
    }

    @Test("Default section availability hides capability-gated sections")
    func defaultSectionAvailabilityHidesCapabilityGatedSections() {
        let availability = SettingsSectionAvailability.v1Default

        #expect(SettingsSection.updates.availability == .capabilityGated)
        #expect(!SettingsSection.compose.isRoadmapOnly)
        #expect(!SettingsSection.notifications.isRoadmapOnly)
        #expect(availability.visibleSections.contains(.accounts))
        #expect(availability.visibleSections.contains(.appearance))
        #expect(availability.visibleSections.contains(.mailboxView))
        #expect(availability.visibleSections.contains(.signature))
        #expect(availability.visibleSections.contains(.compose))
        #expect(availability.visibleSections.contains(.security))
        #expect(availability.visibleSections.contains(.privacy))
        #expect(availability.visibleSections.contains(.notifications))
        #expect(availability.visibleSections.contains(.aiWriter))
        #expect(availability.visibleSections.contains(.about))
        #expect(!availability.visibleSections.contains(.updates))
        #expect(!availability.visibleSections.contains(.developer))
    }

    @Test("macOS direct-download availability exposes Updates")
    func macOSDirectDownloadAvailabilityExposesUpdates() {
        let availability = SettingsSectionAvailability.macOSDirectDownload

        #expect(SettingsSection.updates.availability == .capabilityGated)
        #expect(availability.visibleSections.contains(.updates))
        #expect(SettingsSectionAvailability.v1Default.visibleSections.contains(.updates) == false)
    }

    @Test("macOS developer direct-download availability exposes Developer")
    func macOSDeveloperDirectDownloadAvailabilityExposesDeveloper() {
        let availability = SettingsSectionAvailability.macOSDeveloperDirectDownload

        #expect(SettingsSection.developer.availability == .capabilityGated)
        #expect(availability.visibleSections.contains(.updates))
        #expect(availability.visibleSections.contains(.developer))
        #expect(!SettingsSectionAvailability.macOSDirectDownload.visibleSections.contains(.developer))
        #expect(!SettingsSectionAvailability.v1Default.visibleSections.contains(.developer))
    }

    @Test("Default section availability follows non-roadmap sections")
    func defaultSectionAvailabilityFollowsNonRoadmapSections() {
        let expected = SettingsSection.allCases.filter { $0.availability == .shipped }

        #expect(SettingsSectionAvailability.v1Default.visibleSections == expected)
    }

    @Test("Each section has explicit availability metadata")
    func eachSectionHasExplicitAvailabilityMetadata() {
        let metadata = SettingsSection.allCases.map(\.availability)

        #expect(metadata.contains(.shipped))
        #expect(metadata.contains(.capabilityGated))
        #expect(SettingsSection.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(SettingsSection.security.availability == .shipped)
    }

    @Test("Section availability removes duplicates and never stores an empty sidebar")
    func sectionAvailabilityRemovesDuplicatesAndNeverStoresEmptySidebar() {
        let duplicated = SettingsSectionAvailability(visibleSections: [
            .privacy,
            .privacy,
            .accounts,
            .accounts
        ])
        let empty = SettingsSectionAvailability(visibleSections: [])

        #expect(duplicated.visibleSections == [.privacy, .accounts])
        #expect(empty.visibleSections == [.accounts])
    }

    @Test("Navigation falls back when selected section is hidden")
    func navigationFallsBackWhenSelectedSectionIsHidden() {
        let nav = SettingsNavigationState(
            selected: .updates,
            availability: .v1Default
        )

        #expect(nav.selected == .accounts)
    }

    @Test("Navigation preserves selected section when it is available")
    func navigationPreservesAvailableSelection() {
        let nav = SettingsNavigationState(
            selected: .privacy,
            availability: .v1Default
        )

        #expect(nav.selected == .privacy)
    }

    @Test("Selecting an available section updates without recursive mutation")
    func selectingAvailableSectionUpdatesWithoutRecursiveMutation() {
        let nav = SettingsNavigationState()

        nav.select(.appearance)

        #expect(nav.selected == .appearance)
    }

    @Test("Selecting a hidden section falls back without recursive mutation")
    func selectingHiddenSectionFallsBackWithoutRecursiveMutation() {
        let nav = SettingsNavigationState()

        nav.select(.updates)

        #expect(nav.selected == .accounts)
    }

    @Test("Updating availability falls back when current section becomes hidden")
    func updatingAvailabilityFallsBackWhenCurrentSectionBecomesHidden() {
        let nav = SettingsNavigationState(
            selected: .updates,
            availability: .allVisible
        )

        nav.updateAvailability(.v1Default)

        #expect(nav.selected == .accounts)
    }

    @Test("Privacy section is available from settings navigation")
    func privacySectionIsAvailable() {
        let section = SettingsSection(rawValue: "privacy")

        #expect(section?.title == "Privacy")
        #expect(section?.symbolName == "hand.raised")
    }

    @Test("Calendar and Contacts section is available from settings navigation")
    func calendarContactsSectionIsAvailable() {
        let section = SettingsSection(rawValue: "calendarContacts")

        #expect(section?.title == "Calendar & Contacts")
        #expect(section?.symbolName == "calendar")
        #expect(section?.availability == .shipped)
        #expect(SettingsSectionAvailability.v1Default.visibleSections.contains(.calendarContacts))
    }

    @Test("Mailbox View section is available from settings navigation")
    func mailboxViewSectionIsAvailable() {
        let section = SettingsSection(rawValue: "mailboxView")

        #expect(section?.title == "Mailbox View")
        #expect(section?.symbolName == "list.bullet.rectangle")
    }

    @Test("Initial account selection falls back to first available account")
    func initialAccountSelectionFallsBackToFirstAvailableAccount() {
        let first = BrevAccount(id: "first", displayName: "First", emailAddress: "first@example.org")
        let second = BrevAccount(id: "second", displayName: "Second", emailAddress: "second@example.org")

        #expect(SettingsInitialAccountSelection.currentAccountID(
            from: nil,
            accounts: [first, second]
        ) == "first")
        #expect(SettingsInitialAccountSelection.currentAccountID(
            from: "missing",
            accounts: [first, second]
        ) == "first")
        #expect(SettingsInitialAccountSelection.currentAccountID(
            from: "second",
            accounts: [first, second]
        ) == "second")
        #expect(SettingsInitialAccountSelection.currentAccountID(from: "second", accounts: []) == nil)
    }

    // MARK: - Sidebar grouping

    @Test("Every declared group contains at least one section")
    func everyDeclaredGroupContainsASection() {
        #expect(Set(SettingsSection.allCases.map(\.group)) == Set(SettingsSectionGroup.allCases))
    }

    @Test("Group headers describe user tasks")
    func groupHeaderLabels() {
        #expect(SettingsSectionGroup.app.headerLabel == "App")
        #expect(SettingsSectionGroup.readingComposing.headerLabel == "Reading & Composing")
        #expect(SettingsSectionGroup.organization.headerLabel == "Organization")
        #expect(SettingsSectionGroup.syncStorage.headerLabel == "Sync & Storage")
        #expect(SettingsSectionGroup.privacySecurity.headerLabel == "Privacy & Security")
        #expect(SettingsSectionGroup.advanced.headerLabel == "Advanced")
    }

    @Test("Accounts shares the App group with Appearance")
    func accountsIsInAppGroup() {
        #expect(SettingsSection.accounts.group == .app)
    }

    @Test("Developer, Updates, About are in the advanced group")
    func advancedGroupOrder() {
        let advancedSections = SettingsSection.allCases.filter { $0.group == .advanced }
        #expect(advancedSections == [.developer, .updates, .about])
    }

    @Test("Reading and composing contains frequent mail presentation controls")
    func readingAndComposingGroupOrder() {
        let sections = SettingsSection.allCases.filter { $0.group == .readingComposing }
        #expect(sections == [
            .notifications, .mailboxView, .compose, .signature, .templates, .aiWriter,
        ])
    }

    @Test("Organization contains recurring mailbox workflow controls")
    func organizationGroupOrder() {
        let sections = SettingsSection.allCases.filter { $0.group == .organization }
        #expect(sections == [.vipAndReminders, .smartViews, .rules, .autoReply, .calendarContacts])
    }

    @Test("Sync & Storage group contains folder sync, mail storage, and import/export")
    func syncStorageGroupOrder() {
        let syncSections = SettingsSection.allCases.filter { $0.group == .syncStorage }
        #expect(syncSections == [.folderSync, .mailStorage, .importExport])
    }

    @Test("Privacy & Security group contains privacy and security")
    func privacySecurityGroupOrder() {
        let privacySections = SettingsSection.allCases.filter { $0.group == .privacySecurity }
        #expect(privacySections == [.privacy, .security])
    }

    @Test("App group contains Accounts and Appearance")
    func appGroupOrder() {
        let appSections = SettingsSection.allCases.filter { $0.group == .app }
        #expect(appSections == [.accounts, .appearance])
    }

    @Test("groupedVisibleSections groups v1Default sections in group order and omits empty groups")
    func groupedVisibleSectionsForV1Default() {
        let grouped = SettingsSectionAvailability.v1Default.groupedVisibleSections

        let groupNames = grouped.map(\.group)
        #expect(groupNames == [
            .app, .readingComposing, .organization,
            .syncStorage, .privacySecurity, .advanced,
        ])

        let app = grouped.first { $0.group == .app }?.sections
        #expect(app == [.accounts, .appearance])

        let reading = grouped.first { $0.group == .readingComposing }?.sections
        #expect(reading == [.notifications, .mailboxView, .compose, .signature, .templates, .aiWriter])

        let organization = grouped.first { $0.group == .organization }?.sections
        #expect(organization == [.vipAndReminders, .smartViews, .rules, .autoReply, .calendarContacts])

        let sync = grouped.first { $0.group == .syncStorage }?.sections
        #expect(sync == [.folderSync, .mailStorage, .importExport])

        let privacy = grouped.first { $0.group == .privacySecurity }?.sections
        #expect(privacy == [.privacy, .security])

        let advanced = grouped.first { $0.group == .advanced }?.sections
        #expect(advanced == [.about])
    }

    @Test("settings search matches section titles and user vocabulary")
    func settingsSearchMatchesTitlesAndKeywords() {
        let appearance = SettingsSectionAvailability.v1Default.groupedVisibleSections(matching: "dark mode")
        let gmail = SettingsSectionAvailability.v1Default.groupedVisibleSections(matching: "gmail")

        #expect(appearance.flatMap(\.sections) == [.appearance])
        #expect(gmail.flatMap(\.sections) == [.accounts])
    }

    @Test("settings search returns an empty result instead of unrelated sections")
    func settingsSearchCanReturnNoResults() {
        #expect(SettingsSectionAvailability.v1Default.groupedVisibleSections(matching: "zz-no-setting").isEmpty)
    }

    @Test("groupedVisibleSections omits groups with no visible sections")
    func groupedVisibleSectionsOmitsEmptyGroups() {
        // Custom availability with only accounts visible — only .app should appear
        let availability = SettingsSectionAvailability(visibleSections: [.accounts])
        let grouped = availability.groupedVisibleSections

        #expect(grouped.count == 1)
        #expect(grouped.first?.group == .app)
        #expect(grouped.first?.sections == [.accounts])
    }

    @Test("groupedVisibleSections preserves all visible sections across groups")
    func groupedVisibleSectionsPreservesAllVisible() {
        let grouped = SettingsSectionAvailability.allVisible.groupedVisibleSections
        let allGrouped = grouped.flatMap(\.sections)
        let expected = SettingsSection.allCases // allVisible includes every section in CaseIterable order

        #expect(allGrouped == expected)
    }
}
