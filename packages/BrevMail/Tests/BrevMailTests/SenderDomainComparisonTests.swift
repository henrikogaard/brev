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
import Testing

@Suite("Local sender-domain comparisons")
struct SenderDomainComparisonTests {
    @Test("brand impersonation and near spellings are distinct from ordinary senders")
    func brands() {
        #expect(SenderDomainComparison
            .claimedDomain(name: "PayPal", domain: "paypa1-support.com", knownDomains: []) == "paypal.com")
        #expect(SenderDomainComparison.claimedDomain(name: nil, domain: "xn--pypal-4ve.com", knownDomains: []) == "paypal.com")
        #expect(SenderDomainComparison.claimedDomain(name: nil, domain: "pаypal.com", knownDomains: []) == "paypal.com")
        #expect(SenderDomainComparison.claimedDomain(name: "PayPal", domain: "mail.paypal.com", knownDomains: []) == nil)
        #expect(SenderDomainComparison
            .claimedDomain(name: "PayPal study group", domain: "university.example", knownDomains: []) == nil)
        #expect(SenderDomainComparison.claimedDomain(name: nil, domain: "münchen.example", knownDomains: []) == nil)
    }

    @Test("one edit from a familiar domain is compared on a label boundary")
    func correspondence() {
        let known: Set<String> = ["northwind.example"]
        for domain in ["northwimd.example", "northwiind.example", "nortwind.example", "mail.northwimd.example"] {
            #expect(SenderDomainComparison.claimedDomain(name: nil, domain: domain, knownDomains: known) == "northwind.example")
        }
        for domain in [
            "mail.northwind.example",
            "northwind.invalid",
            "notnorthwind.example",
            "another.example",
            "northwimd.example.org"
        ] {
            #expect(SenderDomainComparison.claimedDomain(name: nil, domain: domain, knownDomains: known) == nil)
        }
    }
}
