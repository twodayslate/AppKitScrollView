import AppKit
import QuartzCore
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
public final class AppKitScrollViewContext: ObservableObject {
    /// Conservative starting height used before a visible row has been measured.
    public private(set) var estimatedRowHeight: CGFloat = 132

    private var scrollToItemHandler: ((AnyHashable, UnitPoint?) -> Void)?
    private var scrollToTopHandler: ((UnitPoint?) -> Void)?
    private var scrollToBottomHandler: ((UnitPoint?) -> Void)?
    private var invalidateLayoutHandler: (() -> Void)?
    private var animateLayoutHandler: ((TimeInterval) -> Void)?

    /// Scrolls to the first hosted row whose identifier matches the supplied value.
    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {
        scrollToItemHandler?(AnyHashable(id), anchor)
    }

    /// Scrolls to the top-most hosted row.
    public func scrollToTop(anchor: UnitPoint? = .top) {
        scrollToTopHandler?(anchor)
    }

    /// Scrolls to the bottom-most hosted row.
    public func scrollToBottom(anchor: UnitPoint? = .bottom) {
        scrollToBottomHandler?(anchor)
    }

    /// Requests a fresh visible-row measurement pass after local SwiftUI state changes row height.
    public func invalidateLayout() {
        invalidateLayoutHandler?()
    }

    /// Coordinates a short burst of visible-row remeasurement alongside a SwiftUI animation.
    public func animateLayout(duration: TimeInterval = 0.26) {
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
public extension EnvironmentValues {
    /// Exposes the current AppKit scroll proxy to child views that need to trigger relayout or scrolling.
    var appKitScrollViewContext: AppKitScrollViewContext? {
        get { self[AppKitScrollViewContextEnvironmentKey.self] }
        set { self[AppKitScrollViewContextEnvironmentKey.self] = newValue }
    }

    /// Enables the AppKitScrollView text-selection system for cooperating text fragments.
    @Entry var appKitTextSelectionEnabled = false
}

private struct AppKitScrollTargetID: @unchecked Sendable {
    let rawValue: AnyHashable
}

private struct AppKitScrollTargetContainerKey: ContainerValueKey {
    static let defaultValue: AppKitScrollTargetID? = nil
}

private extension ContainerValues {
    var appKitScrollTargetID: AppKitScrollTargetID? {
        get { self[AppKitScrollTargetContainerKey.self] }
        set { self[AppKitScrollTargetContainerKey.self] = newValue }
    }
}

@available(macOS 15.0, *)
public extension View {
    /// Marks a child view as a scroll target for `AppKitScrollViewContext.scrollTo`.
    func appKitScrollTarget<ID: Hashable>(_ id: ID) -> some View {
        containerValue(\.appKitScrollTargetID, AppKitScrollTargetID(rawValue: AnyHashable(id)))
    }

    /// Opts cooperating text fragments into the AppKitScrollView text-selection system.
    func appKitTextSelection<S: TextSelectability>(_ selectability: S) -> some View {
        environment(\.appKitTextSelectionEnabled, type(of: selectability).allowsSelection)
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
public struct AppKitScrollView<Content: View>: View {
    @StateObject private var context = AppKitScrollViewContext()
    @StateObject private var textSelectionController = AppKitTextSelectionController()

    private let configuration: AppKitScrollViewConfiguration
    private let content: (AppKitScrollViewContext) -> Content

    public init(
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

    public init(
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

    public var body: some View {
        Group(
            subviews: content(context)
                .environment(\.appKitScrollViewContext, context)
                .environment(\.appKitTextSelectionController, textSelectionController)
        ) { subviews in
            AppKitScrollViewRepresentable(
                context: context,
                configuration: configuration,
                descriptors: subviews.indices.map { index in
                    let subview = subviews[index]
                    return HostedSubviewDescriptor(
                        id: subview.containerValues.appKitScrollTargetID?.rawValue ?? AnyHashable(subview.id),
                        estimatedHeight: configuration.estimatedRowHeight,
                        rootView: AnyView(subview.environment(\.appKitTextSelectionBaseOrder, index * 1_000))
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
@MainActor
private final class AppKitScrollViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate, VerticalListCollectionLayoutDelegate {
    private struct ViewportAnchor {
        let indexPath: IndexPath
        let topOffset: CGFloat
    }

    private let layout = VerticalListCollectionLayout()
    private let scrollView = FlexibleHostedScrollView()
    private let collectionView = FlexibleHostedCollectionView()
    private let debugLayoutLoggingEnabled = ProcessInfo.processInfo.environment["APPKIT_SCROLL_DEBUG_LAYOUT"] == "1"

    private var context: AppKitScrollViewContext?
    private var configuration: AppKitScrollViewConfiguration
    private var items: [HostedSubviewDescriptor] = []
    private var cachedHeights: [AnyHashable: CGFloat] = [:]
    private var animationDisplayLink: CADisplayLink?
    private var animatedMeasurementDeadline: CFTimeInterval?
    private var pendingLiveVisibleHeights: [AnyHashable: CGFloat] = [:]
    private var boundsObserver: NSObjectProtocol?
    private var measurementWidth: CGFloat = 0
    private var pendingVisibleMeasurement: DispatchWorkItem?
    private var hasAppliedInitialScrollPosition = false

    init(configuration: AppKitScrollViewConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        MainActor.assumeIsolated {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            animationDisplayLink?.invalidate()
        }
    }

    override func loadView() {
        view = FlexibleHostedRootView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        configureCollectionView()
        layoutViews()
        applyConfiguration()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        collectionView.reloadData()
        syncCollectionViewGeometry()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        requestVisibleHostedMeasurements()
        logVisibleLayoutIfNeeded(reason: "viewWillAppear")
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        pendingVisibleMeasurement?.cancel()
        pendingVisibleMeasurement = nil
        pendingLiveVisibleHeights.removeAll(keepingCapacity: true)
        cancelAnimatedMeasurements()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        syncCollectionViewGeometry()
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        guard !hasAppliedInitialScrollPosition else {
            return
        }

        hasAppliedInitialScrollPosition = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.scrollView.contentView.scroll(to: .zero)
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            self.scheduleVisibleMeasurement()
        }
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
        pendingVisibleMeasurement?.cancel()
        pendingVisibleMeasurement = nil
        applyConfiguration()
        bindContext()
        cachedHeights.removeAll(keepingCapacity: true)
        pendingLiveVisibleHeights.removeAll(keepingCapacity: true)
        cancelAnimatedMeasurements()
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
            removeMeasurementsForDeletedItems(remainingIDs: Set(nextIDs))
            collectionView.reloadData()
            invalidateLayout()
            scheduleVisibleMeasurement()
            return
        }

        let visibleIndexPaths = collectionView.indexPathsForVisibleItems()
        if visibleIndexPaths.isEmpty {
            return
        }

        reconfigureVisibleItems(at: visibleIndexPaths)
        requestVisibleHostedMeasurements()
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
            Task { @MainActor [weak self] in
                self?.scheduleVisibleMeasurement(delay: 0.12)
            }
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
                self?.scheduleVisibleMeasurement()
            },
            animateLayoutHandler: { [weak self] duration in
                self?.animateVisibleLayout(duration: duration)
            }
        )
    }

    /// Keeps the document view width in sync with the viewport while preserving measured heights during resize.
    private func syncCollectionViewGeometry() {
        let availableViewportWidth = max(scrollView.contentSize.width, 320)
        guard availableViewportWidth > 0 else {
            return
        }

        let didChangeDocumentWidth = abs(collectionView.frame.width - availableViewportWidth) > 0.5
        if abs(collectionView.frame.width - availableViewportWidth) > 0.5 {
            collectionView.setFrameSize(NSSize(width: availableViewportWidth, height: max(collectionView.frame.height, scrollView.contentSize.height)))
        }

        let currentMeasurementWidth = layout.itemContentWidth(for: availableViewportWidth)
        if abs(currentMeasurementWidth - measurementWidth) > 1 {
            measurementWidth = currentMeasurementWidth
            pendingLiveVisibleHeights.removeAll(keepingCapacity: true)
            invalidateLayout()
            requestVisibleHostedMeasurements()
            scheduleVisibleMeasurement(delay: 0.08)
        } else if didChangeDocumentWidth {
            invalidateLayout()
            requestVisibleHostedMeasurements()
            scheduleVisibleMeasurement(delay: 0.08)
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

    private var backingScaleFactor: CGFloat {
        max(view.window?.backingScaleFactor ?? scrollView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2, 1)
    }

    private func pixelRound(_ value: CGFloat) -> CGFloat {
        let scale = backingScaleFactor
        return (value * scale).rounded() / scale
    }

    private func pixelAlignedScrollOrigin(x: CGFloat, y: CGFloat, maxY: CGFloat) -> NSPoint {
        let clampedY = min(max(y, 0), maxY)
        return NSPoint(
            x: pixelRound(x),
            y: min(max(pixelRound(clampedY), 0), maxY)
        )
    }

    /// Keeps AppKit item frames in lock-step with SwiftUI's measured height frames instead of letting implicit layer
    /// animations briefly overlap neighboring collection items.
    private func performWithoutImplicitAppKitAnimation(_ updates: () -> Void) {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
        NSAnimationContext.endGrouping()
    }

    private func invalidateLayout() {
        performWithoutImplicitAppKitAnimation {
            collectionView.collectionViewLayout?.invalidateLayout()
            collectionView.layoutSubtreeIfNeeded()
            updateCollectionViewHeight()
        }
    }

    private var displayMatchedFrameInterval: TimeInterval {
        let screen = view.window?.screen ?? scrollView.window?.screen ?? NSScreen.main
        let reportedFPS = screen?.maximumFramesPerSecond ?? 60
        let fps = min(max(reportedFPS, 30), 240)
        return 1.0 / Double(fps)
    }

    private func startAnimationDisplayLinkIfNeeded() {
        guard animationDisplayLink == nil else {
            return
        }

        let displayLink = view.displayLink(target: self, selector: #selector(animationDisplayLinkDidFire(_:)))
        displayLink.add(to: .main, forMode: .common)
        animationDisplayLink = displayLink
    }

    private func stopAnimationDisplayLinkIfIdle() {
        guard pendingLiveVisibleHeights.isEmpty, animatedMeasurementDeadline == nil else {
            return
        }

        animationDisplayLink?.invalidate()
        animationDisplayLink = nil
    }

    @objc private func animationDisplayLinkDidFire(_ displayLink: CADisplayLink) {
        let timestamp = displayLink.timestamp > 0 ? displayLink.timestamp : CACurrentMediaTime()

        if let deadline = animatedMeasurementDeadline {
            requestVisibleHostedMeasurements()
            flushPendingLiveHeightChanges()

            if timestamp >= deadline {
                animatedMeasurementDeadline = nil
            }
        } else {
            flushPendingLiveHeightChanges()
        }

        stopAnimationDisplayLinkIfIdle()
    }

    /// Nudges existing visible hosts to lay out at the new width without reloading the SwiftUI subtree.
    private func requestVisibleHostedMeasurements() {
        for item in collectionView.visibleItems() {
            guard let hostedItem = item as? HostedCollectionViewItem else {
                continue
            }

            hostedItem.requestLiveHeightMeasurement()
        }
    }

    /// Updates visible hosting views in place so state-driven SwiftUI changes do not trigger AppKit item replacement.
    private func reconfigureVisibleItems(at indexPaths: Set<IndexPath>) {
        performWithoutImplicitAppKitAnimation {
            for indexPath in indexPaths where indexPath.item < items.count {
                guard let item = collectionView.item(at: indexPath) as? HostedCollectionViewItem else {
                    continue
                }

                let descriptor = items[indexPath.item]
                item.configure(
                    id: descriptor.id,
                    rootView: descriptor.rootView,
                    onMeasuredHeightChange: { [weak self] measuredHeight in
                        self?.recordMeasuredHeightChange(for: descriptor.id, measuredHeight: measuredHeight)
                    }
                )
            }
        }
    }

    private func scheduleVisibleMeasurement(delay: TimeInterval = 0) {
        pendingVisibleMeasurement?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.pendingVisibleMeasurement = nil
            self.requestVisibleHostedMeasurements()
            self.flushPendingLiveHeightChanges()
        }
        pendingVisibleMeasurement = workItem
        if delay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func cancelAnimatedMeasurements() {
        animatedMeasurementDeadline = nil
        stopAnimationDisplayLinkIfIdle()
    }

    /// Preserves measured heights for retained IDs while dropping stale state for removed builder children.
    private func removeMeasurementsForDeletedItems(remainingIDs: Set<AnyHashable>) {
        cachedHeights = cachedHeights.filter { remainingIDs.contains($0.key) }
        pendingLiveVisibleHeights = pendingLiveVisibleHeights.filter { remainingIDs.contains($0.key) }
        stopAnimationDisplayLinkIfIdle()
    }

    /// Keeps visible hosted rows measuring on the display cadence during explicit SwiftUI animations.
    private func animateVisibleLayout(duration: TimeInterval) {
        cancelAnimatedMeasurements()
        animatedMeasurementDeadline = CACurrentMediaTime() + max(duration, displayMatchedFrameInterval)
        requestVisibleHostedMeasurements()
        flushPendingLiveHeightChanges()
        startAnimationDisplayLinkIfNeeded()
    }

    private func indexPath(for id: AnyHashable) -> IndexPath? {
        guard let itemIndex = items.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return IndexPath(item: itemIndex, section: 0)
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
        let targetOrigin = pixelAlignedScrollOrigin(
            x: clipView.bounds.origin.x,
            y: targetOriginY,
            maxY: maxOriginY
        )

        guard abs(clipView.bounds.origin.y - targetOrigin.y) > 0.1 ||
            abs(clipView.bounds.origin.x - targetOrigin.x) > 0.1 else {
            return
        }

        clipView.scroll(to: targetOrigin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func restoreViewportOrigin(_ origin: NSPoint) {
        let clipView = scrollView.contentView
        let maxOriginY = max(collectionView.frame.height - clipView.bounds.height, 0)
        let targetOrigin = pixelAlignedScrollOrigin(
            x: origin.x,
            y: origin.y,
            maxY: maxOriginY
        )

        guard abs(clipView.bounds.origin.y - targetOrigin.y) > 0.1 ||
            abs(clipView.bounds.origin.x - targetOrigin.x) > 0.1 else {
            return
        }

        clipView.scroll(to: targetOrigin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func shouldPreserveViewportAnchor(for changedIndexPath: IndexPath?, anchor: ViewportAnchor?) -> Bool {
        guard
            let anchor,
            let changedIndexPath
        else {
            return false
        }

        return changedIndexPath.item <= anchor.indexPath.item
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
        let targetOrigin = pixelAlignedScrollOrigin(
            x: clipView.bounds.origin.x,
            y: targetOriginY,
            maxY: maxOriginY
        )

        guard abs(currentOriginY - targetOrigin.y) > 0.5 else {
            return
        }

        clipView.scroll(to: targetOrigin)
        scrollView.reflectScrolledClipView(clipView)
    }

    /// Uses the visible hosted-row height as the source of truth for rows that are currently onscreen.
    private func recordMeasuredHeightChange(for itemID: AnyHashable, measuredHeight: CGFloat) {
        let resolvedHeight = max(configuration.minimumRowHeight, measuredHeight)
        let previousPendingHeight = pendingLiveVisibleHeights[itemID]
        let previousExactHeight = cachedHeights[itemID]

        if debugLayoutLoggingEnabled {
            NSLog(
                "[AppKitScrollView] live-height item=\(String(describing: itemID)) measured=\(Int(resolvedHeight)) pending=\(Int(previousPendingHeight ?? -1)) cached=\(Int(previousExactHeight ?? -1))"
            )
        }

        let baselineHeight = previousPendingHeight ?? previousExactHeight ?? resolvedHeight
        let didChangeVisibleHeight = (previousPendingHeight == nil && previousExactHeight == nil) ||
            abs(baselineHeight - resolvedHeight) > 0.25

        guard didChangeVisibleHeight else {
            return
        }

        pendingLiveVisibleHeights[itemID] = resolvedHeight
        startAnimationDisplayLinkIfNeeded()
    }

    private func flushPendingLiveHeightChanges() {
        guard !pendingLiveVisibleHeights.isEmpty else {
            return
        }

        let pendingHeights = pendingLiveVisibleHeights
        pendingLiveVisibleHeights.removeAll(keepingCapacity: true)
        let viewportAnchor = makeTopVisibleViewportAnchor()
        let previousViewportOrigin = scrollView.contentView.bounds.origin
        var earliestChangedIndexPath: IndexPath?
        var didChangeAnyHeight = false

        for (itemID, resolvedHeight) in pendingHeights {
            let previousExactHeight = cachedHeights[itemID]
            let baselineHeight = previousExactHeight ?? resolvedHeight
            let didChangeVisibleHeight = previousExactHeight == nil ||
                abs(baselineHeight - resolvedHeight) > 0.25

            guard didChangeVisibleHeight else {
                continue
            }

            cachedHeights[itemID] = resolvedHeight
            didChangeAnyHeight = true

            if let changedIndexPath = indexPath(for: itemID),
               earliestChangedIndexPath == nil || changedIndexPath.item < earliestChangedIndexPath!.item {
                earliestChangedIndexPath = changedIndexPath
            }

        }

        guard didChangeAnyHeight else {
            return
        }

        invalidateLayout()
        if shouldPreserveViewportAnchor(for: earliestChangedIndexPath, anchor: viewportAnchor) {
            restoreViewportAnchor(viewportAnchor)
        } else {
            restoreViewportOrigin(previousViewportOrigin)
        }
        collectionView.needsDisplay = true
        scrollView.contentView.needsDisplay = true
    }

    private func logVisibleLayoutIfNeeded(reason: String) {
        guard debugLayoutLoggingEnabled else {
            return
        }

        let visibleRect = collectionView.visibleRect
        let attributes = (collectionView.collectionViewLayout?.layoutAttributesForElements(in: visibleRect) ?? [])
            .compactMap { attributes -> (IndexPath, NSRect)? in
                guard let indexPath = attributes.indexPath else {
                    return nil
                }

                return (indexPath, attributes.frame)
            }
            .sorted(by: { $0.0.item < $1.0.item })

        guard !attributes.isEmpty else {
            NSLog("[AppKitScrollView] \(reason): no visible attributes")
            return
        }

        NSLog("[AppKitScrollView] \(reason): visibleY=\(Int(visibleRect.minY))...\(Int(visibleRect.maxY)) width=\(Int(visibleRect.width))")

        for index in attributes.indices {
            let (indexPath, frame) = attributes[index]
            let itemID = items[indexPath.item].id
            let cachedHeight = Int(cachedHeights[itemID] ?? -1)
            let nextGap: Int

            if index + 1 < attributes.count {
                let nextFrame = attributes[index + 1].1
                nextGap = Int(round(nextFrame.minY - frame.maxY))
            } else {
                nextGap = Int.min
            }

            NSLog(
                "[AppKitScrollView] row \(indexPath.item) frameY=\(Int(frame.minY)) height=\(Int(frame.height)) cached=\(cachedHeight) nextGap=\(nextGap)"
            )
        }
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        guard indexPath.item < items.count else {
            return
        }

        let itemID = items[indexPath.item].id
        pendingLiveVisibleHeights.removeValue(forKey: itemID)
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        guard let item = collectionView.makeItem(withIdentifier: HostedCollectionViewItem.reuseIdentifier, for: indexPath) as? HostedCollectionViewItem else {
            return NSCollectionViewItem()
        }

        let descriptor = items[indexPath.item]
        item.configure(
            id: descriptor.id,
            rootView: descriptor.rootView,
            onMeasuredHeightChange: { [weak self] measuredHeight in
                self?.recordMeasuredHeightChange(for: descriptor.id, measuredHeight: measuredHeight)
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
