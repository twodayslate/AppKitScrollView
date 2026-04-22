import AppKit
import SwiftUI

/// Measures a SwiftUI-backed cell offscreen so AppKit can lay it out before the hosted view becomes visible.
@MainActor
final class DemoCellMeasurer {
    private let heightSafetyMargin: CGFloat = 6
    private let hostingController = NSHostingController(rootView: AnyView(EmptyView()))

    /// Returns a conservative height for the given cell at the requested width and layout metrics.
    func measure(cell: any DemoCellRenderable, width: CGFloat, metrics: DemoLayoutMetrics) -> CGFloat {
        let context = DemoCellRenderContext(
            width: width,
            metrics: metrics,
            invalidateLayout: {}
        )

        hostingController.rootView = cell.makeView(context: context)
        hostingController.view.layoutSubtreeIfNeeded()
        let size = hostingController.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return max(metrics.minimumHeight, ceil(size.height + heightSafetyMargin))
    }
}
