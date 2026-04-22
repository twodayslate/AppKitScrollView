import AppKit

/// Creates the main demo window with a resizable content area large enough to stress the collection view.
final class MainWindowController: NSWindowController {
    /// Builds the main window using a screen-aware initial size while keeping the content width fully resizable.
    init() {
        let contentViewController = CollectionViewController()
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
        window.title = "Hosted SwiftUI NSCollectionView"
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
