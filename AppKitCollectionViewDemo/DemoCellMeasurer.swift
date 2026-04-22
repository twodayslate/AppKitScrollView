import AppKit
import SwiftUI

/// Measures a SwiftUI-backed cell offscreen so AppKit can lay it out before the hosted view becomes visible.
@MainActor
final class DemoCellMeasurer {
    private let heightSafetyMargin: CGFloat = 6
    private let hostingController = NSHostingController(rootView: AnyView(EmptyView()))

    /// Returns a conservative height for an arbitrary hosted SwiftUI root view at the requested width.
    func measure(rootView: AnyView, width: CGFloat, minimumHeight: CGFloat) -> CGFloat {
        hostingController.rootView = rootView
        hostingController.view.layoutSubtreeIfNeeded()
        let size = hostingController.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return max(minimumHeight, ceil(size.height + heightSafetyMargin))
    }

    /// Returns a conservative height for the given cell at the requested width and layout metrics.
    func measure(cell: any DemoCellRenderable, width: CGFloat, metrics: DemoLayoutMetrics) -> CGFloat {
        let context = DemoCellRenderContext(
            width: width,
            metrics: metrics,
            invalidateLayout: {}
        )

        return measure(
            rootView: cell.makeView(context: context),
            width: width,
            minimumHeight: metrics.minimumHeight
        )
    }
}
