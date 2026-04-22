import AppKit
import SwiftUI

/// Root container that opts out of width-based fitting so SwiftUI can shrink the window normally.
private final class FlexibleHostedRootView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var fittingSize: NSSize {
        var size = super.fittingSize
        size.width = 0
        return size
    }
}

/// Scroll view wrapper that avoids exporting a hard fitting width back to the hosting window.
private final class FlexibleHostedScrollView: NSScrollView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var fittingSize: NSSize {
        var size = super.fittingSize
        size.width = 0
        return size
    }
}

/// Collection view wrapper that participates in Auto Layout without pinning the SwiftUI host width.
private final class FlexibleHostedCollectionView: NSCollectionView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var fittingSize: NSSize {
        var size = super.fittingSize
        size.width = 0
        return size
    }
}

/// Lightweight configuration surface for the result-builder-backed AppKit collection view.
@available(macOS 15.0, *)
@MainActor
final class AppKitScrollViewContext: ObservableObject {
    /// Conservative starting height used before a visible row has been measured.
    private(set) var estimatedRowHeight: CGFloat = 132

    private var scrollToItemHandler: ((AnyHashable, UnitPoint?) -> Void)?
    private var scrollToTopHandler: ((UnitPoint?) -> Void)?
    private var scrollToBottomHandler: ((UnitPoint?) -> Void)?
    private var invalidateLayoutHandler: (() -> Void)?
    private var animateLayoutHandler: ((TimeInterval) -> Void)?

    /// Scrolls to the first hosted row whose identifier matches the supplied value.
    func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {
        scrollToItemHandler?(AnyHashable(id), anchor)
    }

    /// Scrolls to the top-most hosted row.
    func scrollToTop(anchor: UnitPoint? = .top) {
        scrollToTopHandler?(anchor)
    }

    /// Scrolls to the bottom-most hosted row.
    func scrollToBottom(anchor: UnitPoint? = .bottom) {
        scrollToBottomHandler?(anchor)
    }

    /// Requests a fresh visible-row measurement pass after local SwiftUI state changes row height.
    func invalidateLayout() {
        invalidateLayoutHandler?()
    }

    /// Coordinates a short burst of visible-row remeasurement alongside a SwiftUI animation.
    func animateLayout(duration: TimeInterval = 0.26) {
        animateLayoutHandler?(duration)
    }

    fileprivate func bind(
        estimatedRowHeight: CGFloat,
        scrollToItemHandler: @escaping (AnyHashable, UnitPoint?) -> Void,
        scrollToTopHandler: @escaping (UnitPoint?) -> Void,
        scrollToBottomHandler: @escaping (UnitPoint?) -> Void,
        invalidateLayoutHandler: @escaping () -> Void,
        animateLayoutHandler: @escaping (TimeInterval) -> Void
    ) {
        self.estimatedRowHeight = estimatedRowHeight
        self.scrollToItemHandler = scrollToItemHandler
        self.scrollToTopHandler = scrollToTopHandler
        self.scrollToBottomHandler = scrollToBottomHandler
        self.invalidateLayoutHandler = invalidateLayoutHandler
        self.animateLayoutHandler = animateLayoutHandler
    }
}

private struct AppKitScrollViewContextEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppKitScrollViewContext? = nil
}

@available(macOS 15.0, *)
extension EnvironmentValues {
    /// Exposes the current AppKit scroll proxy to child views that need to trigger relayout or scrolling.
    var appKitScrollViewContext: AppKitScrollViewContext? {
        get { self[AppKitScrollViewContextEnvironmentKey.self] }
        set { self[AppKitScrollViewContextEnvironmentKey.self] = newValue }
    }
}

private struct AppKitScrollTargetContainerKey: ContainerValueKey {
    static let defaultValue: AnyHashable? = nil
}

private extension ContainerValues {
    var appKitScrollTargetID: AnyHashable? {
        get { self[AppKitScrollTargetContainerKey.self] }
        set { self[AppKitScrollTargetContainerKey.self] = newValue }
    }
}

@available(macOS 15.0, *)
extension View {
    /// Marks a child view as a scroll target for `AppKitScrollViewContext.scrollTo`.
    func appKitScrollTarget<ID: Hashable>(_ id: ID) -> some View {
        containerValue(\.appKitScrollTargetID, AnyHashable(id))
    }
}

@available(macOS 15.0, *)
private struct AppKitScrollViewConfiguration: Equatable {
    var rowSpacing: CGFloat
    var contentInsets: EdgeInsets
    var minimumRowHeight: CGFloat
    var estimatedRowHeight: CGFloat

    var nsInsets: NSEdgeInsets {
        NSEdgeInsets(
            top: contentInsets.top,
            left: contentInsets.leading,
            bottom: contentInsets.bottom,
            right: contentInsets.trailing
        )
    }
}

@available(macOS 15.0, *)
private struct HostedSubviewDescriptor: Identifiable {
    let id: AnyHashable
    let estimatedHeight: CGFloat
    let rootView: AnyView
}

/// Result-builder-based SwiftUI wrapper that virtualizes arbitrary child views inside an AppKit-backed collection view.
@available(macOS 15.0, *)
struct AppKitScrollView<Content: View>: View {
    @StateObject private var context = AppKitScrollViewContext()

    private let configuration: AppKitScrollViewConfiguration
    private let content: (AppKitScrollViewContext) -> Content

    init(
        rowSpacing: CGFloat = 14,
        contentInsets: EdgeInsets = EdgeInsets(top: 18, leading: 24, bottom: 24, trailing: 24),
        minimumRowHeight: CGFloat = 44,
        estimatedRowHeight: CGFloat = 132,
        @ViewBuilder content: @escaping (AppKitScrollViewContext) -> Content
    ) {
        configuration = AppKitScrollViewConfiguration(
            rowSpacing: rowSpacing,
            contentInsets: contentInsets,
            minimumRowHeight: minimumRowHeight,
            estimatedRowHeight: estimatedRowHeight
        )
        self.content = content
    }

    init(
        rowSpacing: CGFloat = 14,
        contentInsets: EdgeInsets = EdgeInsets(top: 18, leading: 24, bottom: 24, trailing: 24),
        minimumRowHeight: CGFloat = 44,
        estimatedRowHeight: CGFloat = 132,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            rowSpacing: rowSpacing,
            contentInsets: contentInsets,
            minimumRowHeight: minimumRowHeight,
            estimatedRowHeight: estimatedRowHeight
        ) { _ in
            content()
        }
    }

    var body: some View {
        Group(subviews: content(context).environment(\.appKitScrollViewContext, context)) { subviews in
            AppKitScrollViewRepresentable(
                context: context,
                configuration: configuration,
                descriptors: subviews.map { subview in
                    HostedSubviewDescriptor(
                        id: subview.containerValues.appKitScrollTargetID ?? AnyHashable(subview.id),
                        estimatedHeight: configuration.estimatedRowHeight,
                        rootView: AnyView(subview)
                    )
                }
            )
        }
    }
}

@available(macOS 15.0, *)
private struct AppKitScrollViewRepresentable: NSViewControllerRepresentable {
    let context: AppKitScrollViewContext
    let configuration: AppKitScrollViewConfiguration
    let descriptors: [HostedSubviewDescriptor]

    func makeNSViewController(context: Context) -> AppKitScrollViewController {
        AppKitScrollViewController(configuration: configuration)
    }

    func updateNSViewController(_ controller: AppKitScrollViewController, context: Context) {
        controller.updateContext(self.context)
        controller.updateConfiguration(configuration)
        controller.updateItems(descriptors)
    }
}

/// AppKit controller that provides virtualization, measurement, and anchor-preserving relayout for the SwiftUI DSL.
@available(macOS 15.0, *)
private final class AppKitScrollViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate, VerticalListCollectionLayoutDelegate {
    private struct ViewportAnchor {
        let indexPath: IndexPath
        let topOffset: CGFloat
    }

    private let layout = VerticalListCollectionLayout()
    private let measurer = DemoCellMeasurer()
    private let scrollView = FlexibleHostedScrollView()
    private let collectionView = FlexibleHostedCollectionView()

    private var context: AppKitScrollViewContext?
    private var configuration: AppKitScrollViewConfiguration
    private var items: [HostedSubviewDescriptor] = []
    private var cachedHeights: [AnyHashable: CGFloat] = [:]
    private var boundsObserver: NSObjectProtocol?
    private var measurementWidth: CGFloat = 0
    private var pendingVisibleMeasurement: DispatchWorkItem?
    private var pendingAnimatedMeasurements: [DispatchWorkItem] = []

    init(configuration: AppKitScrollViewConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        pendingVisibleMeasurement?.cancel()
        cancelAnimatedMeasurements()
    }

    override func loadView() {
        view = FlexibleHostedRootView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        configureCollectionView()
        layoutViews()
        applyConfiguration()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        collectionView.reloadData()
        syncCollectionViewGeometry()
        remeasureVisibleItems(forceAll: true, extraScreens: 1)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        pendingVisibleMeasurement?.cancel()
        cancelAnimatedMeasurements()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        syncCollectionViewGeometry()
    }

    func updateContext(_ context: AppKitScrollViewContext) {
        self.context = context
        bindContext()
    }

    func updateConfiguration(_ configuration: AppKitScrollViewConfiguration) {
        guard self.configuration != configuration else {
            bindContext()
            return
        }

        self.configuration = configuration
        applyConfiguration()
        bindContext()
        cachedHeights.removeAll(keepingCapacity: true)
        invalidateLayout()
    }

    func updateItems(_ descriptors: [HostedSubviewDescriptor]) {
        let previousIDs = items.map(\.id)
        let nextIDs = descriptors.map(\.id)
        items = descriptors

        guard isViewLoaded else {
            return
        }

        if previousIDs != nextIDs {
            cachedHeights.removeAll(keepingCapacity: true)
            collectionView.reloadData()
            invalidateLayout()
            scheduleVisibleMeasurement(forceAll: true)
            return
        }

        let visibleIndexPaths = collectionView.indexPathsForVisibleItems()
        if visibleIndexPaths.isEmpty {
            collectionView.reloadData()
        } else {
            collectionView.reloadItems(at: visibleIndexPaths)
        }
    }

    private func configureCollectionView() {
        layout.delegate = self

        collectionView.translatesAutoresizingMaskIntoConstraints = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = false
        collectionView.collectionViewLayout = layout
        collectionView.register(HostedCollectionViewItem.self, forItemWithIdentifier: HostedCollectionViewItem.reuseIdentifier)
        collectionView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        collectionView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        collectionView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scrollView.documentView = collectionView
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: nil
        ) { [weak self] _ in
            self?.scheduleVisibleMeasurement()
        }

        view.addSubview(scrollView)
    }

    private func layoutViews() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func applyConfiguration() {
        layout.sectionInsets = configuration.nsInsets
        layout.itemSpacing = configuration.rowSpacing
        layout.preferredItemWidth = nil
    }

    private func bindContext() {
        context?.bind(
            estimatedRowHeight: configuration.estimatedRowHeight,
            scrollToItemHandler: { [weak self] id, anchor in
                self?.scrollToItem(with: id, anchor: anchor)
            },
            scrollToTopHandler: { [weak self] anchor in
                self?.scrollToTop(anchor: anchor)
            },
            scrollToBottomHandler: { [weak self] anchor in
                self?.scrollToBottom(anchor: anchor)
            },
            invalidateLayoutHandler: { [weak self] in
                self?.scheduleVisibleMeasurement(forceAll: true)
            },
            animateLayoutHandler: { [weak self] duration in
                self?.animateVisibleLayout(duration: duration)
            }
        )
    }

    /// Keeps the document view width in sync with the viewport and clears cached heights when wrapping changes.
    private func syncCollectionViewGeometry() {
        let availableViewportWidth = max(scrollView.contentSize.width, 320)
        guard availableViewportWidth > 0 else {
            return
        }

        if abs(collectionView.frame.width - availableViewportWidth) > 0.5 {
            collectionView.setFrameSize(NSSize(width: availableViewportWidth, height: max(collectionView.frame.height, scrollView.contentSize.height)))
        }

        let currentMeasurementWidth = layout.itemContentWidth(for: availableViewportWidth)
        if abs(currentMeasurementWidth - measurementWidth) > 1 {
            measurementWidth = currentMeasurementWidth
            cachedHeights.removeAll(keepingCapacity: true)
            invalidateLayout()
            scheduleVisibleMeasurement(forceAll: true)
        } else {
            updateCollectionViewHeight()
        }
    }

    /// Shrinks or grows the document view to match the layout's content height without leaving stale space below it.
    private func updateCollectionViewHeight() {
        let contentHeight = collectionView.collectionViewLayout?.collectionViewContentSize.height ?? collectionView.frame.height
        let targetHeight = max(contentHeight, scrollView.contentSize.height)

        if abs(collectionView.frame.height - targetHeight) > 0.5 {
            collectionView.setFrameSize(NSSize(width: collectionView.frame.width, height: targetHeight))
        }
    }

    private func invalidateLayout() {
        collectionView.collectionViewLayout?.invalidateLayout()
        collectionView.layoutSubtreeIfNeeded()
        updateCollectionViewHeight()
    }

    private func scheduleVisibleMeasurement(forceAll: Bool = false) {
        pendingVisibleMeasurement?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.remeasureVisibleItems(forceAll: forceAll, extraScreens: 0.75)
        }
        pendingVisibleMeasurement = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func cancelAnimatedMeasurements() {
        pendingAnimatedMeasurements.forEach { $0.cancel() }
        pendingAnimatedMeasurements.removeAll(keepingCapacity: false)
    }

    /// Re-measures visible rows at a few checkpoints so AppKit height updates track a short SwiftUI expansion animation.
    private func animateVisibleLayout(duration: TimeInterval) {
        cancelAnimatedMeasurements()
        remeasureVisibleItems(forceAll: true, extraScreens: 0.75)

        let checkpoints = [0.35, 0.8].map { duration * $0 }
        pendingAnimatedMeasurements = checkpoints.map { delay in
            let workItem = DispatchWorkItem { [weak self] in
                self?.remeasureVisibleItems(forceAll: true, extraScreens: 0.75)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            return workItem
        }
    }

    private func remeasureVisibleItems(forceAll: Bool, extraScreens: CGFloat) {
        guard !items.isEmpty else {
            return
        }

        let width = max(measurementWidth, layout.itemContentWidth(for: max(scrollView.contentSize.width, 320)))
        guard width > 0 else {
            return
        }

        let viewportHeight = max(scrollView.contentSize.height, 1)
        let visibleRect = collectionView.visibleRect
        let expandedRect = NSRect(
            x: visibleRect.origin.x,
            y: max(visibleRect.origin.y - (viewportHeight * extraScreens), 0),
            width: visibleRect.width,
            height: visibleRect.height + (viewportHeight * extraScreens * 2)
        )
        let indexPaths = (collectionView.collectionViewLayout?.layoutAttributesForElements(in: expandedRect) ?? [])
            .compactMap(\.indexPath)
            .sorted(by: { $0.item < $1.item })

        guard !indexPaths.isEmpty else {
            return
        }

        let viewportAnchor = makeTopVisibleViewportAnchor()
        var didChangeAnyHeight = false

        for indexPath in indexPaths {
            let descriptor = items[indexPath.item]
            if !forceAll, cachedHeights[descriptor.id] != nil {
                continue
            }

            let measuredHeight = max(
                configuration.minimumRowHeight,
                ceil(measurer.measure(
                    rootView: descriptor.rootView,
                    width: width,
                    minimumHeight: configuration.minimumRowHeight
                ))
            )
            let previousHeight = cachedHeights[descriptor.id]

            guard previousHeight == nil || abs((previousHeight ?? 0) - measuredHeight) > 0.5 else {
                continue
            }

            cachedHeights[descriptor.id] = measuredHeight
            didChangeAnyHeight = true
        }

        guard didChangeAnyHeight else {
            return
        }

        invalidateLayout()
        restoreViewportAnchor(viewportAnchor)
        collectionView.needsDisplay = true
        scrollView.contentView.needsDisplay = true
    }

    private func remeasureItem(with id: AnyHashable) {
        guard
            let itemIndex = items.firstIndex(where: { $0.id == id }),
            itemIndex < items.count
        else {
            return
        }

        let width = max(measurementWidth, layout.itemContentWidth(for: max(scrollView.contentSize.width, 320)))
        guard width > 0 else {
            return
        }

        let descriptor = items[itemIndex]
        let measuredHeight = max(
            configuration.minimumRowHeight,
            ceil(measurer.measure(
                rootView: descriptor.rootView,
                width: width,
                minimumHeight: configuration.minimumRowHeight
            ))
        )
        let previousHeight = cachedHeights[descriptor.id]

        guard previousHeight == nil || abs((previousHeight ?? 0) - measuredHeight) > 0.5 else {
            return
        }

        let viewportAnchor = makeViewportAnchor(for: id)
        cachedHeights[descriptor.id] = measuredHeight
        invalidateLayout()
        restoreViewportAnchor(viewportAnchor)
        collectionView.needsDisplay = true
        scrollView.contentView.needsDisplay = true
        scheduleVisibleMeasurement(forceAll: true)
    }

    private func indexPath(for id: AnyHashable) -> IndexPath? {
        guard let itemIndex = items.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return IndexPath(item: itemIndex, section: 0)
    }

    private func makeViewportAnchor(for id: AnyHashable) -> ViewportAnchor? {
        guard
            let indexPath = indexPath(for: id),
            let attributes = collectionView.collectionViewLayout?.layoutAttributesForItem(at: indexPath)
        else {
            return nil
        }

        let visibleRect = collectionView.visibleRect
        return ViewportAnchor(
            indexPath: indexPath,
            topOffset: attributes.frame.minY - visibleRect.minY
        )
    }

    private func makeTopVisibleViewportAnchor() -> ViewportAnchor? {
        let visibleRect = collectionView.visibleRect
        guard
            let attributes = collectionView.collectionViewLayout?
                .layoutAttributesForElements(in: visibleRect)
                .min(by: { $0.frame.minY < $1.frame.minY }),
            let indexPath = attributes.indexPath
        else {
            return nil
        }

        return ViewportAnchor(
            indexPath: indexPath,
            topOffset: attributes.frame.minY - visibleRect.minY
        )
    }

    private func restoreViewportAnchor(_ anchor: ViewportAnchor?) {
        guard
            let anchor,
            let attributes = collectionView.collectionViewLayout?.layoutAttributesForItem(at: anchor.indexPath)
        else {
            return
        }

        let clipView = scrollView.contentView
        let targetOriginY = attributes.frame.minY - anchor.topOffset
        let maxOriginY = max(collectionView.frame.height - clipView.bounds.height, 0)
        let clampedOriginY = min(max(targetOriginY, 0), maxOriginY)

        guard abs(clipView.bounds.origin.y - clampedOriginY) > 0.5 else {
            return
        }

        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: clampedOriginY))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func scrollToTop(anchor: UnitPoint?) {
        guard !items.isEmpty else {
            return
        }

        scrollToIndexPath(IndexPath(item: 0, section: 0), anchor: anchor)
    }

    private func scrollToBottom(anchor: UnitPoint?) {
        guard !items.isEmpty else {
            return
        }

        scrollToIndexPath(IndexPath(item: items.count - 1, section: 0), anchor: anchor)
    }

    private func scrollToItem(with id: AnyHashable, anchor: UnitPoint?) {
        guard let indexPath = indexPath(for: id) else {
            return
        }

        scrollToIndexPath(indexPath, anchor: anchor)
    }

    private func scrollToIndexPath(_ indexPath: IndexPath, anchor: UnitPoint?) {
        invalidateLayout()

        guard let attributes = collectionView.collectionViewLayout?.layoutAttributesForItem(at: indexPath) else {
            return
        }

        let clipView = scrollView.contentView
        let viewportHeight = clipView.bounds.height
        let currentOriginY = clipView.bounds.origin.y
        let targetOriginY: CGFloat

        if let anchor {
            let normalizedAnchorY = min(max(anchor.y, 0), 1)
            targetOriginY = attributes.frame.minY - ((viewportHeight - attributes.frame.height) * normalizedAnchorY)
        } else if attributes.frame.minY < clipView.bounds.minY {
            targetOriginY = attributes.frame.minY
        } else if attributes.frame.maxY > clipView.bounds.maxY {
            targetOriginY = attributes.frame.maxY - viewportHeight
        } else {
            targetOriginY = currentOriginY
        }

        let maxOriginY = max(collectionView.frame.height - viewportHeight, 0)
        let clampedOriginY = min(max(targetOriginY, 0), maxOriginY)

        guard abs(currentOriginY - clampedOriginY) > 0.5 else {
            return
        }

        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: clampedOriginY))
        scrollView.reflectScrolledClipView(clipView)
    }

    /// Treats a live hosted-row resize as a signal to rerun exact offscreen measurement for that row.
    private func recordMeasuredHeightChange(for itemID: AnyHashable) {
        remeasureItem(with: itemID)
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        guard let item = collectionView.makeItem(withIdentifier: HostedCollectionViewItem.reuseIdentifier, for: indexPath) as? HostedCollectionViewItem else {
            return NSCollectionViewItem()
        }

        let descriptor = items[indexPath.item]
        item.configure(
            id: descriptor.id,
            rootView: descriptor.rootView,
            onMeasuredHeightChange: { [weak self] _ in
                self?.recordMeasuredHeightChange(for: descriptor.id)
            }
        )
        return item
    }

    func collectionViewLayout(_ layout: VerticalListCollectionLayout, heightForItemAt index: Int, width: CGFloat) -> CGFloat {
        let descriptor = items[index]
        if let cachedHeight = cachedHeights[descriptor.id] {
            return cachedHeight
        }

        return max(descriptor.estimatedHeight, configuration.minimumRowHeight)
    }
}
