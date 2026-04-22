import AppKit
import SwiftUI

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

    /// Rebinds the hosted SwiftUI view for this item and wires height invalidation back to the controller.
    func configure(
        with cell: any DemoCellRenderable,
        width: CGFloat,
        metrics: DemoLayoutMetrics,
        onLayoutInvalidationRequested: @escaping () -> Void
    ) {
        hostingView.rootView = AnyView(
            cell.makeView(
                context: DemoCellRenderContext(
                    width: width,
                    metrics: metrics,
                    invalidateLayout: onLayoutInvalidationRequested
                )
            )
            .id(cell.id)
        )
    }
}
