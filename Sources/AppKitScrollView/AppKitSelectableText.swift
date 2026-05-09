import AppKit
import SwiftUI

@available(macOS 15.0, *)
private struct AppKitTextSelectionPosition {
    let fragmentID: UUID
    let offset: Int
}

@available(macOS 15.0, *)
private final class AppKitSelectableTextRegistration {
    let id: UUID
    var order: Int
    var text: String
    weak var view: AppKitSelectableTextView?

    init(id: UUID, order: Int, text: String, view: AppKitSelectableTextView) {
        self.id = id
        self.order = order
        self.text = text
        self.view = view
    }
}

/// Coordinates text selection across selectable text fragments in an AppKit-backed scroll surface.
@available(macOS 15.0, *)
@MainActor
public final class AppKitTextSelectionController: ObservableObject {
    private var registrations: [UUID: AppKitSelectableTextRegistration] = [:]
    private var anchor: AppKitTextSelectionPosition?
    private var focus: AppKitTextSelectionPosition?
    private var eventMonitor: Any?

    public init() {}

    deinit {
        MainActor.assumeIsolated {
            removeEventMonitor()
        }
    }

    func register(_ view: AppKitSelectableTextView, order: Int, text: String) {
        registrations[view.fragmentID] = AppKitSelectableTextRegistration(
            id: view.fragmentID,
            order: order,
            text: text,
            view: view
        )
    }

    func update(_ view: AppKitSelectableTextView, order: Int, text: String) {
        if let registration = registrations[view.fragmentID] {
            registration.order = order
            registration.text = text
            registration.view = view
        } else {
            register(view, order: order, text: text)
        }
    }

    func unregister(_ view: AppKitSelectableTextView) {
        registrations[view.fragmentID] = nil
        view.selectedCharacterRange = NSRange(location: 0, length: 0)
    }

    func beginSelection(in view: AppKitSelectableTextView, with event: NSEvent) {
        view.window?.makeFirstResponder(view)
        let localPoint = view.convert(event.locationInWindow, from: nil)
        let position = AppKitTextSelectionPosition(
            fragmentID: view.fragmentID,
            offset: view.characterOffset(for: localPoint)
        )

        anchor = position
        focus = position
        installEventMonitor(for: event.window)
        updateSelectionRanges()
    }

    func copySelectedTextToPasteboard() {
        let selectedText = orderedRegistrations()
            .compactMap { registration -> String? in
                guard
                    let view = registration.view,
                    view.selectedCharacterRange.length > 0,
                    let range = Range(view.selectedCharacterRange, in: registration.text)
                else {
                    return nil
                }

                return String(registration.text[range])
            }
            .joined(separator: "\n\n")

        guard !selectedText.isEmpty else {
            NSSound.beep()
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedText, forType: .string)
    }

    func selectAll() {
        anchor = orderedRegistrations().first.map {
            AppKitTextSelectionPosition(fragmentID: $0.id, offset: 0)
        }
        focus = orderedRegistrations().last.map {
            AppKitTextSelectionPosition(fragmentID: $0.id, offset: $0.text.utf16.count)
        }
        updateSelectionRanges()
    }

    private func installEventMonitor(for window: NSWindow?) {
        removeEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self, weak window] event in
            guard event.window === window else {
                return event
            }

            Task { @MainActor [weak self] in
                switch event.type {
                case .leftMouseDragged:
                    self?.moveFocus(to: event.locationInWindow, in: window)
                case .leftMouseUp:
                    self?.removeEventMonitor()
                default:
                    break
                }
            }

            return event
        }
    }

    private func removeEventMonitor() {
        guard let eventMonitor else {
            return
        }

        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func moveFocus(to windowPoint: NSPoint, in window: NSWindow?) {
        guard let position = selectionPosition(at: windowPoint, in: window) else {
            return
        }

        focus = position
        updateSelectionRanges()
    }

    private func selectionPosition(at windowPoint: NSPoint, in window: NSWindow?) -> AppKitTextSelectionPosition? {
        let liveRegistrations = orderedRegistrations().filter { registration in
            registration.view?.window === window
        }

        for registration in liveRegistrations {
            guard let view = registration.view else {
                continue
            }

            let rect = view.convert(view.bounds, to: nil)
            guard rect.contains(windowPoint) else {
                continue
            }

            return AppKitTextSelectionPosition(
                fragmentID: registration.id,
                offset: view.characterOffset(for: view.convert(windowPoint, from: nil))
            )
        }

        return liveRegistrations
            .compactMap { registration -> (registration: AppKitSelectableTextRegistration, distance: CGFloat, point: NSPoint)? in
                guard let view = registration.view else {
                    return nil
                }

                let localPoint = view.convert(windowPoint, from: nil)
                let clampedPoint = NSPoint(
                    x: min(max(localPoint.x, view.bounds.minX), view.bounds.maxX),
                    y: min(max(localPoint.y, view.bounds.minY), view.bounds.maxY)
                )
                let dx = localPoint.x - clampedPoint.x
                let dy = localPoint.y - clampedPoint.y
                return (registration, hypot(dx, dy), clampedPoint)
            }
            .min(by: { $0.distance < $1.distance })
            .map { registration, _, point in
                AppKitTextSelectionPosition(
                    fragmentID: registration.id,
                    offset: registration.view?.characterOffset(for: point) ?? registration.text.utf16.count
                )
            }
    }

    private func updateSelectionRanges() {
        guard
            let anchor,
            let focus,
            let start = orderedPosition(anchor, focus).start,
            let end = orderedPosition(anchor, focus).end
        else {
            clearSelection()
            return
        }

        for registration in registrations.values {
            let textLength = registration.text.utf16.count
            let selectedRange: NSRange

            if registration.id == start.fragmentID, registration.id == end.fragmentID {
                selectedRange = NSRange(
                    location: min(start.offset, end.offset),
                    length: abs(end.offset - start.offset)
                )
            } else if registration.id == start.fragmentID {
                selectedRange = NSRange(location: start.offset, length: max(textLength - start.offset, 0))
            } else if registration.id == end.fragmentID {
                selectedRange = NSRange(location: 0, length: end.offset)
            } else if isRegistration(registration, between: start, and: end) {
                selectedRange = NSRange(location: 0, length: textLength)
            } else {
                selectedRange = NSRange(location: 0, length: 0)
            }

            registration.view?.selectedCharacterRange = clamp(selectedRange, toLength: textLength)
        }
    }

    private func clearSelection() {
        for registration in registrations.values {
            registration.view?.selectedCharacterRange = NSRange(location: 0, length: 0)
        }
    }

    private func orderedPosition(
        _ first: AppKitTextSelectionPosition,
        _ second: AppKitTextSelectionPosition
    ) -> (start: AppKitTextSelectionPosition?, end: AppKitTextSelectionPosition?) {
        guard compare(first, second) != .orderedDescending else {
            return (second, first)
        }

        return (first, second)
    }

    private func isRegistration(
        _ registration: AppKitSelectableTextRegistration,
        between start: AppKitTextSelectionPosition,
        and end: AppKitTextSelectionPosition
    ) -> Bool {
        compare(AppKitTextSelectionPosition(fragmentID: registration.id, offset: 0), start) == .orderedDescending &&
            compare(AppKitTextSelectionPosition(fragmentID: registration.id, offset: registration.text.utf16.count), end) == .orderedAscending
    }

    private func compare(_ first: AppKitTextSelectionPosition, _ second: AppKitTextSelectionPosition) -> ComparisonResult {
        guard first.fragmentID != second.fragmentID else {
            if first.offset == second.offset {
                return .orderedSame
            }

            return first.offset < second.offset ? .orderedAscending : .orderedDescending
        }

        let firstOrder = registrations[first.fragmentID]?.order ?? 0
        let secondOrder = registrations[second.fragmentID]?.order ?? 0
        if firstOrder == secondOrder {
            return first.fragmentID.uuidString < second.fragmentID.uuidString ? .orderedAscending : .orderedDescending
        }

        return firstOrder < secondOrder ? .orderedAscending : .orderedDescending
    }

    private func orderedRegistrations() -> [AppKitSelectableTextRegistration] {
        registrations.values.sorted { first, second in
            if first.order == second.order {
                return first.id.uuidString < second.id.uuidString
            }

            return first.order < second.order
        }
    }

    private func clamp(_ range: NSRange, toLength length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        let upperBound = min(max(range.location + range.length, location), length)
        return NSRange(location: location, length: upperBound - location)
    }
}

@available(macOS 15.0, *)
public extension EnvironmentValues {
    @Entry var appKitTextSelectionController: AppKitTextSelectionController?
    @Entry var appKitTextSelectionBaseOrder = 0
    @Entry var appKitTextSelectionOrder = 0
}

@available(macOS 15.0, *)
private struct AppKitSelectionContainerModifier: ViewModifier {
    @StateObject private var selectionController = AppKitTextSelectionController()

    func body(content: Content) -> some View {
        content.environment(\.appKitTextSelectionController, selectionController)
    }
}

@available(macOS 15.0, *)
public extension View {
    /// Provides a shared text-selection owner to selectable text fragments below this view.
    func appKitSelectionContainer() -> some View {
        modifier(AppKitSelectionContainerModifier())
    }

    /// Orders a selectable text fragment relative to other fragments in the same scroll row.
    func appKitTextSelectionOrder(_ order: Int) -> some View {
        environment(\.appKitTextSelectionOrder, order)
    }
}

/// A TextKit-backed text fragment that participates in AppKitScrollView cross-card text selection.
@available(macOS 15.0, *)
public struct AppKitSelectableText: NSViewRepresentable {
    @Environment(\.appKitTextSelectionEnabled) private var isTextSelectionEnabled
    @Environment(\.appKitTextSelectionController) private var selectionController
    @Environment(\.appKitTextSelectionBaseOrder) private var selectionBaseOrder
    @Environment(\.appKitTextSelectionOrder) private var selectionOrder

    private let text: String
    private let font: NSFont?
    private let textColor: NSColor?

    public init(_ text: String) {
        self.text = text
        font = nil
        textColor = nil
    }

    private init(text: String, font: NSFont?, textColor: NSColor?) {
        self.text = text
        self.font = font
        self.textColor = textColor
    }

    public func appKitFont(_ font: NSFont) -> Self {
        AppKitSelectableText(text: text, font: font, textColor: textColor)
    }

    public func appKitTextColor(_ textColor: NSColor) -> Self {
        AppKitSelectableText(text: text, font: font, textColor: textColor)
    }

    public func foregroundColor(_ color: Color?) -> Self {
        AppKitSelectableText(text: text, font: font, textColor: color.map(NSColor.init))
    }

    public func foregroundStyle(_ color: Color) -> Self {
        AppKitSelectableText(text: text, font: font, textColor: NSColor(color))
    }

    public func makeNSView(context: Context) -> AppKitSelectableTextView {
        let view = AppKitSelectableTextView()
        update(view)
        return view
    }

    public func updateNSView(_ nsView: AppKitSelectableTextView, context: Context) {
        update(nsView)
    }

    public static func dismantleNSView(_ nsView: AppKitSelectableTextView, coordinator: ()) {
        nsView.selectionController?.unregister(nsView)
    }

    private func update(_ view: AppKitSelectableTextView) {
        let resolvedController = selectionController
        let resolvedFont = font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let resolvedColor = textColor ?? .labelColor
        let resolvedOrder = selectionBaseOrder + selectionOrder
        let activeController = isTextSelectionEnabled ? resolvedController : nil

        if view.selectionController !== activeController {
            view.selectionController?.unregister(view)
        }

        view.selectionController = activeController
        view.isSelectionEnabled = activeController != nil
        view.updateText(text, font: resolvedFont, textColor: resolvedColor)

        if let activeController {
            activeController.update(view, order: resolvedOrder, text: text)
        }
    }
}

@available(macOS 15.0, *)
public final class AppKitSelectableTextView: NSView {
    let fragmentID = UUID()
    weak var selectionController: AppKitTextSelectionController?

    var isSelectionEnabled = false {
        didSet {
            if !isSelectionEnabled {
                selectedCharacterRange = NSRange(location: 0, length: 0)
            }
            discardCursorRects()
        }
    }

    var selectedCharacterRange = NSRange(location: 0, length: 0) {
        didSet {
            needsDisplay = true
        }
    }

    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer(size: NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude))
    private var currentText = ""
    private var currentFont: NSFont?
    private var currentTextColor: NSColor?
    private var cursorTrackingArea: NSTrackingArea?

    public override var isFlipped: Bool {
        true
    }

    public override var acceptsFirstResponder: Bool {
        isSelectionEnabled
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    public override var intrinsicContentSize: NSSize {
        let width = max(bounds.width, 1)
        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(max(usedRect.height, 1)))
    }

    public override func layout() {
        super.layout()
        updateTextContainerWidth()
        discardCursorRects()
    }

    public override func updateTrackingAreas() {
        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }

        if isSelectionEnabled {
            let trackingArea = NSTrackingArea(
                rect: .zero,
                options: [.activeInKeyWindow, .cursorUpdate, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                owner: self
            )
            addTrackingArea(trackingArea)
            cursorTrackingArea = trackingArea
        } else {
            cursorTrackingArea = nil
        }

        super.updateTrackingAreas()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = bounds.width
        super.setFrameSize(newSize)
        if abs(oldWidth - newSize.width) > 0.5 {
            updateTextContainerWidth()
            invalidateIntrinsicContentSize()
            discardCursorRects()
        }
    }

    public override func resetCursorRects() {
        guard isSelectionEnabled else {
            return
        }

        addCursorRect(bounds, cursor: .iBeam)
    }

    public override func cursorUpdate(with event: NSEvent) {
        guard isSelectionEnabled else {
            super.cursorUpdate(with: event)
            return
        }

        NSCursor.iBeam.set()
    }

    public override func mouseEntered(with event: NSEvent) {
        guard isSelectionEnabled else {
            super.mouseEntered(with: event)
            return
        }

        NSCursor.iBeam.set()
    }

    public override func mouseMoved(with event: NSEvent) {
        guard isSelectionEnabled else {
            super.mouseMoved(with: event)
            return
        }

        NSCursor.iBeam.set()
    }

    func updateText(_ text: String, font: NSFont, textColor: NSColor) {
        if currentText == text,
           currentFont?.isEqual(font) == true,
           currentTextColor?.isEqual(textColor) == true {
            return
        }

        currentText = text
        currentFont = font
        currentTextColor = textColor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 0
        textStorage.setAttributedString(
            NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle
                ]
            )
        )
        selectedCharacterRange = clampedRange(selectedCharacterRange, toLength: text.utf16.count)
        updateTextContainerWidth()
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    func characterOffset(for point: NSPoint) -> Int {
        updateTextContainerWidth()
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)

        guard glyphRange.length > 0 else {
            return 0
        }

        let usedRect = layoutManager.usedRect(for: textContainer)
        if point.y <= usedRect.minY {
            return 0
        }
        if point.y >= usedRect.maxY {
            return currentText.utf16.count
        }

        var fraction: CGFloat = 0
        let characterIndex = layoutManager.characterIndex(
            for: point,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        let resolvedIndex = characterIndex + (fraction > 0.5 ? 1 : 0)
        return min(max(resolvedIndex, 0), currentText.utf16.count)
    }

    public override func mouseDown(with event: NSEvent) {
        guard isSelectionEnabled else {
            super.mouseDown(with: event)
            return
        }

        selectionController?.beginSelection(in: self, with: event)
    }

    public override func keyDown(with event: NSEvent) {
        guard isSelectionEnabled else {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch (modifiers, event.charactersIgnoringModifiers?.lowercased()) {
        case let (modifiers, "c") where modifiers.contains(.command):
            selectionController?.copySelectedTextToPasteboard()
            return
        case let (modifiers, "a") where modifiers.contains(.command) || modifiers.contains(.control):
            selectionController?.selectAll()
            return
        default:
            break
        }

        super.keyDown(with: event)
    }

    @objc func copy(_ sender: Any?) {
        guard isSelectionEnabled else {
            return
        }

        selectionController?.copySelectedTextToPasteboard()
    }

    public override func selectAll(_ sender: Any?) {
        guard isSelectionEnabled else {
            return
        }

        selectionController?.selectAll()
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        updateTextContainerWidth()
        layoutManager.ensureLayout(for: textContainer)

        if selectedCharacterRange.length > 0 {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: selectedCharacterRange,
                actualCharacterRange: nil
            )
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.78).setFill()
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: glyphRange,
                in: textContainer
            ) { rect, _ in
                NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: 3, yRadius: 3).fill()
            }
        }

        layoutManager.drawGlyphs(forGlyphRange: layoutManager.glyphRange(for: textContainer), at: .zero)
    }

    private func updateTextContainerWidth() {
        let width = max(bounds.width, 1)
        guard abs(textContainer.containerSize.width - width) > 0.5 else {
            return
        }

        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: textStorage.length), actualCharacterRange: nil)
    }

    private func clampedRange(_ range: NSRange, toLength length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        let upperBound = min(max(range.location + range.length, location), length)
        return NSRange(location: location, length: upperBound - location)
    }
}
