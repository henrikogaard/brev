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

#if os(macOS)
import AppKit
import BrevBackend
@testable import BrevMail
import BrevThemes
import Observation
import SwiftUI
import Testing

@Suite("Message list row gesture delivery", .serialized)
@MainActor
struct MessageListRowGestureTests {
    @Test("hover-only disclosure preserves child selection", arguments: [600.0, 340.0, 190.0])
    func hoverDelivery(width: Double) async throws {
        let fixture = HostedGestureRow(selected: false, width: width)
        defer { fixture.close() }
        try await fixture.settle()
        #expect(fixture.toggleFrame == .zero)
        fixture.hover(CGPoint(x: fixture.rowFrame.midX, y: fixture.rowFrame.midY))
        try await fixture.settle()
        let point = try fixture.chevronCenter()
        fixture.click(point)
        try await fixture.settle()
        #expect(fixture.toggles == 1)
        #expect(fixture.activations == 0)
        #expect(!fixture.state.expanded)
        #expect(fixture.state.selectedID == "child")
        try fixture.click(fixture.chevronCenter())
        try await fixture.settle()
        #expect(fixture.toggles == 2)
        #expect(fixture.activations == 0)
        #expect(fixture.state.expanded)
        #expect(fixture.state.selectedID == "child")
        fixture.hover(CGPoint(x: 2, y: 2), entered: false)
        try await fixture.settle()
        #expect(fixture.toggleFrame == .zero)
        fixture.click(point)
        try await fixture.settle()
        #expect(fixture.toggles == 2)
        #expect(fixture.activations == 1)
    }

    @Test("selected disclosure routes through wide, compact and stacked layouts",
          arguments: [600.0, 340.0, 190.0], [false, true])
    func chevronDelivery(width: Double, compact: Bool) async throws {
        let fixture = HostedGestureRow(width: width, compact: compact)
        defer { fixture.close() }
        try await fixture.settle()
        let point = try fixture.chevronCenter()
        let frame = try #require(fixture.toggleFrame)
        #expect(frame.size == CGSize(width: 18, height: 18))
        #expect(CGRect(origin: .zero, size: fixture.rowFrame.size).contains(frame))
        if width == 190 {
            #expect(frame.minY > 20)
        } else if width == 600 {
            #expect(frame.minY < 20)
        }
        fixture.click(point)
        try await fixture.settle()
        #expect(fixture.toggles == 1)
        #expect(fixture.activations == 0)
        fixture.click(CGPoint(x: fixture.rowFrame.minX + frame.minX - 3, y: point.y))
        try await fixture.settle()
        #expect(fixture.toggles == 2)
        #expect(fixture.activations == 0)
        fixture.click(CGPoint(x: fixture.rowFrame.minX + 25, y: fixture.rowFrame.midY))
        try await fixture.settle()
        #expect(fixture.activations == 1)
        #expect(fixture.toggles == 2)
    }

    @Test("List-hosted rows route their own coordinates", arguments: [600.0, 190.0])
    func listDelivery(width: Double) async throws {
        let fixture = HostedGestureRow(width: width, inList: true)
        defer { fixture.close() }
        try await fixture.settle()
        try fixture.click(fixture.chevronCenter())
        try await fixture.settle()
        #expect(fixture.toggles == 1)
        #expect(fixture.activations == 0)
        #expect(fixture.siblingToggles == 0)
        #expect(fixture.siblingActivations == 0)
    }

    @Test("layout changes update the frame and removing the glyph clears it")
    func changedLayoutAndMissingGlyph() async throws {
        let fixture = HostedGestureRow()
        defer { fixture.close() }
        try await fixture.settle()
        let oldFrame = try #require(fixture.toggleFrame)
        fixture.state.width = 190
        try await fixture.settle()
        let frame = try #require(fixture.toggleFrame)
        #expect(frame != oldFrame)
        #expect(frame.minY > oldFrame.minY)
        let point = try fixture.chevronCenter()
        fixture.click(point)
        try await fixture.settle()
        #expect(fixture.toggles == 1)
        fixture.state.threadCount = 1
        try await fixture.settle()
        #expect(fixture.toggleFrame == .zero)
        fixture.click(point)
        try await fixture.settle()
        #expect(fixture.toggles == 1)
        #expect(fixture.activations == 1)
    }
}

@MainActor
@Observable
private final class GestureRowState {
    var selectedID = "parent"
    var expanded = true
    var width: CGFloat = 340
    var threadCount = 4
}

@MainActor
private final class HostedGestureRow {
    let state = GestureRowState()
    let compact: Bool
    let inList: Bool
    var toggles = 0
    var activations = 0
    var siblingToggles = 0
    var siblingActivations = 0
    var toggleFrame: CGRect?
    var rowFrame = CGRect.zero
    var host: NSHostingView<AnyView>!
    let window: GestureTestWindow

    init(selected: Bool = true, width: CGFloat = 340, compact: Bool = false, inList: Bool = false) {
        self.compact = compact
        self.inList = inList
        state.width = width
        state.selectedID = selected ? "parent" : "child"
        window = GestureTestWindow(contentRect: CGRect(x: -10000, y: -10000, width: 800, height: 700),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        host = NSHostingView(rootView: AnyView(HostedRowContent(fixture: self)))
        host.frame = CGRect(x: 0, y: 0, width: 800, height: 700)
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
    }

    func makeRow(sibling: Bool = false) -> some View {
        MessageListRow(
            header: Self.header(sibling ? "sibling" : "parent"),
            threadCount: sibling ? 2 : state.threadCount,
            isSelected: sibling || state.selectedID == "parent" || !state.expanded, isChecked: false,
            isInSelectionMode: false, isPinned: false, isThreadExpanded: state.expanded,
            showAvatar: false, previewLineCount: 1, isCompactWidth: compact,
            fontFamily: .system, textSize: .medium,
            density: .compact, showsAbsoluteArrivalTime: false, sourceContext: nil,
            isBlockedSender: false, hasFollowUp: false,
            onActivate: { [weak self] in
                guard let self else { return }
                if sibling { siblingActivations += 1 } else {
                    activations += 1
                    state.selectedID = "parent"
                }
            }, onToggleCheck: {},
            onToggleThread: { [weak self] in
                guard let self else { return }
                if sibling { siblingToggles += 1 } else {
                    toggles += 1
                    state.expanded.toggle()
                }
            }
        )
        .frame(width: sibling ? 160 : state.width)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named("test.host"))
        } action: { [weak self] frame in
            if !sibling { self?.rowFrame = frame }
        }
        .onPreferenceChange(MessageListThreadTogglePreference.self) { [weak self] frame in
            if !sibling { self?.toggleFrame = frame }
        }
    }

    static func header(_ id: String) -> MessageHeader {
        MessageHeader(id: id, threadID: "thread", folderID: "inbox",
                      from: Correspondent(name: "Fixture Sender", email: "fixture@example.org"),
                      subject: "Fixture thread", snippet: "Fixture preview",
                      date: Date(timeIntervalSince1970: 1_700_000_000), isRead: true)
    }

    func settle() async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
    }

    func chevronCenter() throws -> CGPoint {
        let frame = try #require(toggleFrame)
        try #require(!frame.isEmpty)
        return CGPoint(x: rowFrame.minX + frame.midX, y: rowFrame.minY + frame.midY)
    }

    func close() {
        window.close()
        host.rootView = AnyView(EmptyView())
        window.contentView = nil
    }

    func click(_ point: CGPoint) {
        let location = host.convert(point, to: nil)
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil,
                                           eventNumber: 1, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
        }
    }

    func hover(_ point: CGPoint, entered: Bool = true) {
        host.updateTrackingAreas()
        let location = host.convert(point, to: nil)
        window.pointerLocation = location
        for area in host.trackingAreas {
            let event = HostingTrackingEvent(area: area, point: location, hostWindow: window, entered: entered)
            if entered {
                host.mouseEntered(with: event)
            } else {
                host.mouseExited(with: event)
            }
        }
    }
}

@MainActor
private struct HostedRowContent: View {
    let fixture: HostedGestureRow

    var body: some View {
        Group {
            if fixture.inList {
                List {
                    fixture.makeRow(sibling: true)
                    rows
                }
                .listStyle(.plain)
                .frame(width: fixture.state.width + 32, height: 400)
            } else {
                VStack(alignment: .leading, spacing: 0) { rows }
            }
        }
        .padding(.leading, 90)
        .padding(.top, 120)
        .frame(width: 800, height: 700, alignment: .topLeading)
        .coordinateSpace(name: "test.host")
        .brevTheme(.brevMonoLight)
        .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
    }

    @ViewBuilder
    private var rows: some View {
        fixture.makeRow()
        if fixture.state.expanded {
            ThreadInlineChildRow(header: HostedGestureRow.header("child"),
                                 isSelected: fixture.state.selectedID == "child", onSelect: {})
                .frame(width: fixture.state.width)
        }
    }
}

@MainActor
private final class GestureTestWindow: NSWindow {
    var pointerLocation = NSPoint(x: -1, y: -1)

    override var mouseLocationOutsideOfEventStream: NSPoint { pointerLocation }
}

// enterExitEvent has no trackingArea; SwiftUI ignores it for hover delivery.
private final class HostingTrackingEvent: NSEvent {
    let area: NSTrackingArea
    let point: CGPoint
    let hostWindow: NSWindow
    let entered: Bool

    init(area: NSTrackingArea, point: CGPoint, hostWindow: NSWindow, entered: Bool) {
        self.area = area
        self.point = point
        self.hostWindow = hostWindow
        self.entered = entered
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var type: NSEvent.EventType { entered ? .mouseEntered : .mouseExited }
    override var trackingArea: NSTrackingArea? { area }
    override var locationInWindow: NSPoint { point }
    override var window: NSWindow? { hostWindow }
    override var windowNumber: Int { hostWindow.windowNumber }
    override var timestamp: TimeInterval { ProcessInfo.processInfo.systemUptime }
}
#endif
