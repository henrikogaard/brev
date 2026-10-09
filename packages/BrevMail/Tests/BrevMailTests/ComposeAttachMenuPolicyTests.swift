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
import Foundation
import Testing

@Suite("Compose attach menu policy")
struct ComposeAttachMenuPolicyTests {
    @Test("a device with a camera and scanner offers all four sources in order")
    func offersEverySource() {
        let items = ComposeAttachMenuPolicy.items(isCameraAvailable: true, isDocumentScanAvailable: true)
        #expect(items == [.photoLibrary, .camera, .files, .scanDocuments])
    }

    @Test("the camera item is left out when no camera is available")
    func hidesCameraWithoutCamera() {
        let items = ComposeAttachMenuPolicy.items(isCameraAvailable: false, isDocumentScanAvailable: true)
        #expect(items == [.photoLibrary, .files, .scanDocuments])
    }

    @Test("the scan item is left out when document scanning is unsupported")
    func hidesScanWhenUnsupported() {
        let items = ComposeAttachMenuPolicy.items(isCameraAvailable: true, isDocumentScanAvailable: false)
        #expect(items == [.photoLibrary, .camera, .files])
    }

    @Test("Photos and Files are always offered")
    func alwaysOffersPhotosAndFiles() {
        let items = ComposeAttachMenuPolicy.items(isCameraAvailable: false, isDocumentScanAvailable: false)
        #expect(items == [.photoLibrary, .files])
    }

    @Test("every item has a title and a symbol")
    func itemsArePresentable() {
        for item in [ComposeAttachMenuItem.photoLibrary, .camera, .files, .scanDocuments] {
            #expect(!item.title.isEmpty)
            #expect(!item.systemImage.isEmpty)
        }
    }

    @Test("scan filenames are stable, sortable and end in .pdf")
    func scanFilenameFormat() {
        let date = Date(timeIntervalSince1970: 1_779_960_600)
        let name = ComposeAttachMenuPolicy.scanFilename(
            date: date,
            timeZone: TimeZone(identifier: "UTC")!
        )
        #expect(name == "Scan 2026-05-28 09.30.pdf")
    }
}
