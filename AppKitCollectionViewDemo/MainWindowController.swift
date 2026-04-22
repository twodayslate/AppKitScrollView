import AppKit
import SwiftUI

/// Creates the main demo window with a resizable content area large enough to stress the collection view.
final class MainWindowController: NSWindowController {
    /// Builds the main window using the result-builder AppKit scroll demo and a screen-aware initial size.
    init() {
        let contentViewController = NSHostingController(rootView: BuilderDemoView())
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 900)
        let initialContentSize = NSSize(
            width: max(520, min(1180, visibleFrame.width - 120)),
            height: max(520, min(840, visibleFrame.height - 120))
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = contentViewController
        window.title = "AppKitScrollView Result Builder Demo"
        window.setContentSize(initialContentSize)
        window.minSize = NSSize(width: 520, height: 520)
        window.contentMinSize = NSSize(width: 520, height: 520)
        window.resizeIncrements = NSSize(width: 1, height: 1)
        window.contentResizeIncrements = NSSize(width: 1, height: 1)
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
