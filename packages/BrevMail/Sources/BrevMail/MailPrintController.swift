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
import Foundation
#if canImport(UIKit)
import UIKit

/// iOS print/PDF driver. Renders `MailPrintDocument` HTML through a
/// `UIMarkupTextPrintFormatter` so on-paper and PDF output match the
/// shared producer (and the macOS renderer).
@MainActor
enum MailPrintController {
    typealias PrintableMessage = MailPrintDocument.PrintableMessage

    /// Presents the system print sheet for the given messages.
    static func presentPrint(messages: [PrintableMessage], jobName: String) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = jobName.isEmpty ? "Message" : jobName
        controller.printInfo = info
        controller.printFormatter = UIMarkupTextPrintFormatter(
            markupText: MailPrintDocument.html(messages: messages)
        )
        controller.present(animated: true, completionHandler: nil)
    }

    /// Renders the messages to a PDF file in the temporary directory and
    /// returns its URL (caller presents a share sheet / document export).
    static func exportPDF(messages: [PrintableMessage], fileName: String) throws -> URL {
        let formatter = UIMarkupTextPrintFormatter(markupText: MailPrintDocument.html(messages: messages))
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

        // US Letter at 72 dpi; printable rect inset by 44pt to match macOS.
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let printable = page.insetBy(dx: 44, dy: 44)
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(printable, forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, nil)
        let pageCount = max(renderer.numberOfPages, 1)
        for i in 0 ..< pageCount {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()

        let safeName = (fileName.isEmpty ? "Message" : fileName).replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName)
            .appendingPathExtension("pdf")
        try data.write(to: url)
        return url
    }
}
#endif
