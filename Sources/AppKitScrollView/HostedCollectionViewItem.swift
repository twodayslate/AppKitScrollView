import AppKit
import SwiftUI

/// Keeps the hosted SwiftUI subtree identity stable while AppKit reuses collection items.
private struct IdentifiedHostedRootView: View {
    @Environment(\.displayScale) private var displayScale

    let id: AnyHashable
    let rootView: AnyView
    let onMeasuredHeightChange: (CGFloat) -> Void

    var body: some View {
        rootView
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { measuredHeight in
                let measuredHeight = Self.pixelCeil(measuredHeight, scale: displayScale)
                guard measuredHeight > 0 else {
                    return
                }

                onMeasuredHeightChange(measuredHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id(id)
    }

    private nonisolated static func pixelCeil(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        let scale = max(scale, 1)
        return ceil(value * scale) / scale
    }
}

/// Reusable AppKit item that embeds one arbitrary SwiftUI subtree inside the collection view.
final class HostedCollectionViewItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("HostedCollectionViewItem")

    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

    override func loadView() {
        view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.masksToBounds = false
        hostingView.frame = view.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.sizingOptions = []
        hostingView.clipsToBounds = false
        hostingView.wantsLayer = true
        hostingView.layer?.masksToBounds = false
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
