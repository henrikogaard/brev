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

@testable import BrevMail
import BrevSettings
import Testing

@Suite("TemplatePickerPresentation")
struct TemplatePickerPresentationTests {
    @Test("visible templates include global and active account scoped templates")
    func visibleTemplatesIncludeGlobalAndActiveAccountScopedTemplates() {
        var settings = MessageTemplateSettings.defaults
        settings.add(MessageTemplate(name: "Global", body: "Hello"))
        settings.add(MessageTemplate(name: "Work", body: "Work reply", accountID: "acct-1"))
        settings.add(MessageTemplate(name: "Personal", body: "Personal reply", accountID: "acct-2"))

        let visible = TemplatePickerPresentation.visibleTemplates(
            settings: settings,
            accountID: "acct-1",
            searchText: ""
        )

        #expect(visible.map(\.name) == ["Global", "Work"])
    }

    @Test("search only matches templates visible for the active account")
    func searchOnlyMatchesVisibleTemplates() {
        var settings = MessageTemplateSettings.defaults
        settings.add(MessageTemplate(name: "Invoice", body: "Paid", accountID: "acct-1"))
        settings.add(MessageTemplate(name: "Invoice personal", body: "Hidden", accountID: "acct-2"))
        settings.add(MessageTemplate(name: "Receipt", body: "Invoice attached"))

        let visible = TemplatePickerPresentation.visibleTemplates(
            settings: settings,
            accountID: "acct-1",
            searchText: "invoice"
        )

        #expect(visible.map(\.name) == ["Invoice", "Receipt"])
    }
}
