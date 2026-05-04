import AppKit
import SwiftUI

/// Embeds a tiny AppKit probe inside the SwiftUI row so height changes are measured from the live hosted subtree.
private struct HostedHeightReporter: NSViewRepresentable {
    let onMeasuredHeightChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> MeasuredHeightView {
        let view = MeasuredHeightView()
        view.onMeasuredHeightChange = onMeasuredHeightChange
        return view
    }

    func updateNSView(_ nsView: MeasuredHeightView, context: Context) {
        nsView.onMeasuredHeightChange = onMeasuredHeightChange
        nsView.scheduleReport()
    }

    /// Reports its laid-out background height without forcing a second SwiftUI tree to be rendered offscreen.
    final class MeasuredHeightView: NSView {
        var onMeasuredHeightChange: ((CGFloat) -> Void)?

        private var lastReportedHeight: CGFloat = 0
        private var reportScheduled = false

        override func layout() {
            super.layout()
            scheduleReport()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            scheduleReport()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            scheduleReport()
        }

        func scheduleReport() {
            guard !reportScheduled else {
                return
            }

            reportScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.reportHeightIfNeeded()
            }
        }

        private func reportHeightIfNeeded() {
            reportScheduled = false

            let measuredHeight = bounds.height
            guard measuredHeight > 0, abs(measuredHeight - lastReportedHeight) > 0.5 else {
                return
            }

            lastReportedHeight = measuredHeight
            onMeasuredHeightChange?(measuredHeight)
        }
    }
}

/// Keeps the hosted SwiftUI subtree identity stable while AppKit reuses collection items.
private struct IdentifiedHostedRootView: View {
    let id: AnyHashable
    let rootView: AnyView
    let onMeasuredHeightChange: (CGFloat) -> Void

    var body: some View {
        rootView
            .fixedSize(horizontal: false, vertical: true)
            .background(
                HostedHeightReporter(onMeasuredHeightChange: onMeasuredHeightChange)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id(id)
    }
}

/// Reusable AppKit item that embeds one arbitrary SwiftUI subtree inside the collection view.
final class HostedCollectionViewItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("HostedCollectionViewItem")

    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

    override func loadView() {
        view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        hostingView.frame = view.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.sizingOptions = []
        hostingView.clipsToBounds = true
        hostingView.wantsLayer = true
        hostingView.layer?.masksToBounds = true
        hostingView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.addSubview(hostingView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hostingView.rootView = AnyView(EmptyView())
    }

    /// Rebinds the hosted SwiftUI view and listens for live width-constrained height changes from inside the hosted subtree.
    func configure(
        id: AnyHashable,
        rootView: AnyView,
        onMeasuredHeightChange: @escaping (CGFloat) -> Void
    ) {
        hostingView.rootView = AnyView(
            IdentifiedHostedRootView(
                id: id,
                rootView: rootView,
                onMeasuredHeightChange: onMeasuredHeightChange
            )
        )
        hostingView.layoutSubtreeIfNeeded()
    }

    /// Forces the existing hosted subtree to reflow in-place so its embedded reporter emits a fresh height.
    func requestLiveHeightMeasurement() {
        hostingView.frame = view.bounds
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()
    }
}
