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

#if os(macOS)
import AppKit

@MainActor
enum MessagePrintExportRenderer {
    typealias PrintableMessage = (header: MessageHeader, body: MessageBody?)

    static func presentPrintPanel(header: MessageHeader, body: MessageBody?) {
        presentPrintPanel(messages: [(header, body)])
    }

    static func presentPrintPanel(messages: [PrintableMessage]) {
        let view = printableView(messages: messages)
        let operation = NSPrintOperation(view: view)
        operation.printPanel.options.insert(.showsPaperSize)
        operation.printPanel.options.insert(.showsOrientation)
        operation.run()
    }

    static func exportPDF(header: MessageHeader, body: MessageBody?, to url: URL) throws {
        try exportPDF(messages: [(header, body)], to: url)
    }

    static func exportPDF(messages: [PrintableMessage], to url: URL) throws {
        let view = printableView(messages: messages)
        let data = view.dataWithPDF(inside: view.bounds)
        try data.write(to: url)
    }

    private static func printableView(messages: [PrintableMessage]) -> NSView {
        let pageWidth: CGFloat = 612
        let contentInset: CGFloat = 44
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: 200))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textStorage?.setAttributedString(printableContent(messages: messages))
        textView.textContainerInset = NSSize(width: contentInset, height: contentInset)
        textView.textContainer?.containerSize = NSSize(
            width: pageWidth - (contentInset * 2),
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? .zero
        textView.frame = NSRect(
            x: 0,
            y: 0,
            width: pageWidth,
            height: max(usedRect.height + (contentInset * 2), 792)
        )
        return textView
    }

    private static func printableContent(messages: [PrintableMessage]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, message) in messages.enumerated() {
            if index > 0 {
                result.append(line("", size: 12, weight: .regular))
                result.append(line(String(repeating: "-", count: 72), size: 12, weight: .regular))
                result.append(line("", size: 12, weight: .regular))
            }
            result.append(printableContent(header: message.header, body: message.body))
        }
        return result
    }

    private static func printableContent(header: MessageHeader, body: MessageBody?) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(line(header.subject.isEmpty ? "(No subject)" : header.subject, size: 22, weight: .semibold))
        result.append(line("From: \(correspondent(header.from))", size: 12, weight: .regular))
        if !header.to.isEmpty {
            result.append(line("To: \(header.to.map(correspondent).joined(separator: ", "))", size: 12, weight: .regular))
        }
        if !header.cc.isEmpty {
            result.append(line("Cc: \(header.cc.map(correspondent).joined(separator: ", "))", size: 12, weight: .regular))
        }
        result.append(line("Date: \(dateFormatter.string(from: header.date))", size: 12, weight: .regular))
        result.append(line("", size: 12, weight: .regular))
        result.append(line(bodyText(body), size: 13, weight: .regular))
        return result
    }

    private static func line(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSAttributedString {
        NSAttributedString(
            string: text + "\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    private static func bodyText(_ body: MessageBody?) -> String {
        // Delegate to the shared producer so macOS and iOS use identical
        // body-text reduction. The print/PDF security hardening (strip
        // <style>/<script>/comment blocks before tag removal so their source
        // never leaks into the output) now lives in MailPrintDocument.
        MailPrintDocument.bodyText(body)
    }

    private static func correspondent(_ correspondent: Correspondent) -> String {
        if let name = correspondent.name, !name.isEmpty {
            return "\(name) <\(correspondent.email)>"
        }
        return correspondent.email
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
#endif
