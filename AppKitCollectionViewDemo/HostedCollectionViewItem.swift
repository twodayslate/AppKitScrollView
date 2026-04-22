import AppKit
import SwiftUI

/// Keeps the hosted SwiftUI subtree identity stable while AppKit reuses collection items.
private struct IdentifiedHostedRootView: View {
    let id: AnyHashable
    let rootView: AnyView

    var body: some View {
        rootView
            .fixedSize(horizontal: false, vertical: true)
            .id(id)
    }
}

/// Reports live width-constrained fitting-height changes from the NSHostingView back to AppKit.
private final class ReportingHostingView: NSHostingView<AnyView> {
    var onMeasuredHeightChange: ((CGFloat) -> Void)?

    private var lastReportedWidth: CGFloat = 0
    private var lastReportedHeight: CGFloat = 0
    private var measurementScheduled = false

    override func layout() {
        super.layout()
        scheduleMeasurement()
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        scheduleMeasurement()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)

        if widthChanged {
            scheduleMeasurement()
        }
    }

    func resetMeasurementCache() {
        lastReportedWidth = 0
        lastReportedHeight = 0
        measurementScheduled = false
    }

    private func scheduleMeasurement() {
        guard !measurementScheduled else {
            return
        }

        measurementScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.reportMeasurementIfNeeded()
        }
    }

    private func reportMeasurementIfNeeded() {
        measurementScheduled = false

        let measuredWidth = bounds.width
        guard measuredWidth > 1 else {
            return
        }

        let measuredHeight = max(fittingSize.height, 1)
        guard
            abs(measuredWidth - lastReportedWidth) > 0.5 ||
            abs(measuredHeight - lastReportedHeight) > 0.5
        else {
            return
        }

        lastReportedWidth = measuredWidth
        lastReportedHeight = measuredHeight
        onMeasuredHeightChange?(measuredHeight)
    }
}

/// Reusable AppKit item that embeds one arbitrary SwiftUI subtree inside the collection view.
final class HostedCollectionViewItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("HostedCollectionViewItem")

    private let hostingView = ReportingHostingView(rootView: AnyView(EmptyView()))

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
        hostingView.onMeasuredHeightChange = nil
        hostingView.resetMeasurementCache()
        hostingView.rootView = AnyView(EmptyView())
    }

    /// Rebinds the hosted SwiftUI view and listens for live width-constrained height changes from inside the hosted subtree.
    func configure(
        id: AnyHashable,
        rootView: AnyView,
        onMeasuredHeightChange: @escaping (CGFloat) -> Void
    ) {
        hostingView.onMeasuredHeightChange = onMeasuredHeightChange
        hostingView.resetMeasurementCache()
        hostingView.rootView = AnyView(
            IdentifiedHostedRootView(
                id: id,
                rootView: rootView
            )
        )
        hostingView.layoutSubtreeIfNeeded()
    }

    /// Rebinds the demo cell abstraction into the generic SwiftUI hosting path used by the collection view.
    func configure(
        with cell: any DemoCellRenderable,
        width: CGFloat,
        metrics: DemoLayoutMetrics,
        onLayoutInvalidationRequested: @escaping () -> Void
    ) {
        configure(
            id: AnyHashable(cell.id),
            rootView: cell.makeView(
                context: DemoCellRenderContext(
                    width: width,
                    metrics: metrics,
                    invalidateLayout: onLayoutInvalidationRequested
                )
            ),
            onMeasuredHeightChange: { _ in }
        )
    }
}
