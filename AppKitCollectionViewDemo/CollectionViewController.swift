import AppKit

/// Root container that opts out of width-based fitting so the window can shrink freely.
private final class FlexibleRootView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var fittingSize: NSSize {
        var size = super.fittingSize
        size.width = 0
        return size
    }
}

/// Scroll view wrapper that avoids exporting a hard fitting width back to the window.
private final class FlexibleScrollView: NSScrollView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var fittingSize: NSSize {
        var size = super.fittingSize
        size.width = 0
        return size
    }
}

/// Collection view wrapper that participates in Auto Layout without pinning the window width.
private final class FlexibleCollectionView: NSCollectionView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var fittingSize: NSSize {
        var size = super.fittingSize
        size.width = 0
        return size
    }
}

/// Header background view that stays width-flexible even with hosted controls inside it.
private final class FlexibleVisualEffectView: NSVisualEffectView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var fittingSize: NSSize {
        var size = super.fittingSize
        size.width = 0
        return size
    }
}

/// Label field variant that can truncate instead of forcing its full text width into layout.
private final class FlexibleLabelField: NSTextField {
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width = NSView.noIntrinsicMetric
        return size
    }

    override var fittingSize: NSSize {
        var size = super.fittingSize
        size.width = 0
        return size
    }
}

/// Hosts the demo header and the collection view, and coordinates all size invalidation paths.
final class CollectionViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate, VerticalListCollectionLayoutDelegate {
    /// Captures the visible offset for one row so relayout can preserve the user's scroll position.
    private struct ViewportAnchor {
        let indexPath: IndexPath
        let topOffset: CGFloat
    }

    private static let headerHintText = "Scroll, resize the window or use the width slider, drag the height scale, randomize heights, and toggle sections inside the hosted SwiftUI cells."

    private let layout = VerticalListCollectionLayout()
    private let measurer = DemoCellMeasurer()
    private let scrollView = FlexibleScrollView()
    private let collectionView = FlexibleCollectionView()
    private let headerView = FlexibleVisualEffectView()
    private let statusLabel = FlexibleLabelField(labelWithString: "")
    private let windowWidthLabel = NSTextField(labelWithString: "Window Width")
    private let windowWidthValueLabel = FlexibleLabelField(labelWithString: "")
    private let scaleLabel = FlexibleLabelField(labelWithString: "")

    private lazy var windowWidthSlider: NSSlider = {
        let slider = NSSlider(value: 1180, minValue: 520, maxValue: 1400, target: self, action: #selector(windowWidthChanged(_:)))
        slider.isContinuous = true
        return slider
    }()

    private lazy var heightSlider: NSSlider = {
        let slider = NSSlider(value: heightScale, minValue: 0.75, maxValue: 1.9, target: self, action: #selector(heightScaleChanged(_:)))
        slider.isContinuous = true
        return slider
    }()

    private lazy var randomizeButton: NSButton = {
        let button = NSButton(title: "Randomize Heights", target: self, action: #selector(randomizeHeights))
        button.bezelStyle = .rounded
        return button
    }()

    private lazy var resetButton: NSButton = {
        let button = NSButton(title: "Reset", target: self, action: #selector(resetDemo))
        button.bezelStyle = .rounded
        return button
    }()

    private var items: [AnyDemoCell] = DemoCellFactory.makeCells(count: 1000)
    private var cachedHeights: [UUID: CGFloat] = [:]
    private var heightScale: Double = 1.05
    private var measurementWidth: CGFloat = 0
    private var pendingMetricsRefresh: DispatchWorkItem?
    private var pendingVisibleMeasurement: DispatchWorkItem?
    private var windowResizeObserver: NSObjectProtocol?
    private var scrollObserver: NSObjectProtocol?

    private var metrics: DemoLayoutMetrics {
        DemoLayoutMetrics(heightScale: CGFloat(heightScale))
    }

    override func loadView() {
        view = FlexibleRootView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        configureHeader()
        configureCollectionView()
        layoutViews()
        updateLabels()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        observeWindowIfNeeded()
        observeScrollIfNeeded()
        updateWindowWidthControls()
        collectionView.reloadData()
        syncCollectionViewGeometry()
        scheduleVisibleHeightMeasurement(delay: 0)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        removeScrollObserver()
        removeWindowObserver()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        syncCollectionViewGeometry()
    }

    deinit {
        removeScrollObserver()
        removeWindowObserver()
    }

    private func configureHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.material = .sidebar
        headerView.blendingMode = .withinWindow
        headerView.state = .active
        headerView.toolTip = Self.headerHintText
        headerView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        windowWidthLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        windowWidthLabel.textColor = .secondaryLabelColor
        windowWidthValueLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        windowWidthValueLabel.alignment = .right
        windowWidthValueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scaleLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        scaleLabel.alignment = .right
        scaleLabel.lineBreakMode = .byTruncatingHead
        scaleLabel.maximumNumberOfLines = 1
        scaleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scaleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let summaryRow = NSStackView()
        summaryRow.translatesAutoresizingMaskIntoConstraints = false
        summaryRow.orientation = .horizontal
        summaryRow.alignment = .centerY
        summaryRow.spacing = 12
        summaryRow.addArrangedSubview(statusLabel)
        summaryRow.addArrangedSubview(flexibleSpacer())
        summaryRow.addArrangedSubview(scaleLabel)

        let widthRow = NSStackView(views: [
            windowWidthLabel,
            windowWidthSlider,
            windowWidthValueLabel
        ])
        widthRow.translatesAutoresizingMaskIntoConstraints = false
        widthRow.orientation = .horizontal
        widthRow.alignment = .centerY
        widthRow.spacing = 12

        let controlsRow = NSStackView(views: [
            randomizeButton,
            resetButton,
            heightSlider
        ])
        controlsRow.translatesAutoresizingMaskIntoConstraints = false
        controlsRow.orientation = .horizontal
        controlsRow.alignment = .centerY
        controlsRow.spacing = 12

        heightSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        heightSlider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        windowWidthSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        windowWidthSlider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        headerView.addSubview(summaryRow)
        headerView.addSubview(widthRow)
        headerView.addSubview(controlsRow)
        view.addSubview(headerView)

        NSLayoutConstraint.activate([
            summaryRow.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 16),
            summaryRow.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            summaryRow.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),

            widthRow.topAnchor.constraint(equalTo: summaryRow.bottomAnchor, constant: 10),
            widthRow.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            widthRow.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),

            controlsRow.topAnchor.constraint(equalTo: widthRow.bottomAnchor, constant: 10),
            controlsRow.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            controlsRow.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),
            controlsRow.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -14),

            windowWidthSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            heightSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])
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

        view.addSubview(scrollView)
    }

    private func layoutViews() {
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func flexibleSpacer() -> NSView {
        let spacer = NSView(frame: .zero)
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    /// Keeps the document view width in sync with the viewport and refreshes height caches when wrapping changes.
    private func syncCollectionViewGeometry() {
        let availableViewportWidth = max(scrollView.contentSize.width, 320)
        guard availableViewportWidth > 0 else {
            return
        }

        if abs(collectionView.frame.width - availableViewportWidth) > 0.5 {
            collectionView.setFrameSize(NSSize(width: availableViewportWidth, height: max(collectionView.frame.height, scrollView.contentSize.height)))
        }

        layout.preferredItemWidth = nil

        let currentMeasurementWidth = layout.itemContentWidth(for: availableViewportWidth)
        if abs(currentMeasurementWidth - measurementWidth) > 1 {
            measurementWidth = currentMeasurementWidth
            cachedHeights.removeAll(keepingCapacity: true)
            updateLabels()
            invalidateLayout()
            scheduleVisibleHeightMeasurement()
        } else {
            updateLabels()
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

    private func applyMetricsRefresh() {
        pendingMetricsRefresh?.cancel()
        pendingMetricsRefresh = nil
        cachedHeights.removeAll(keepingCapacity: true)
        updateLabels()
        collectionView.reloadData()
        invalidateLayout()
    }

    private func currentWindowWidth() -> CGFloat {
        guard let window = view.window else {
            return view.bounds.width
        }

        return window.contentRect(forFrameRect: window.frame).width
    }

    private func observeWindowIfNeeded() {
        guard windowResizeObserver == nil, let window = view.window else {
            return
        }

        windowResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.updateWindowWidthControls()
            self?.syncCollectionViewGeometry()
        }
    }

    private func observeScrollIfNeeded() {
        guard scrollObserver == nil else {
            return
        }

        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleVisibleHeightMeasurement(delay: 0.12)
        }
    }

    private func removeWindowObserver() {
        guard let windowResizeObserver else {
            return
        }

        NotificationCenter.default.removeObserver(windowResizeObserver)
        self.windowResizeObserver = nil
    }

    private func removeScrollObserver() {
        pendingVisibleMeasurement?.cancel()
        pendingVisibleMeasurement = nil

        guard let scrollObserver else {
            return
        }

        NotificationCenter.default.removeObserver(scrollObserver)
        self.scrollObserver = nil
    }

    private func updateWindowWidthControls() {
        let availableWidth = max(currentWindowWidth(), 320)
        let maximumWidth = max(availableWidth, 1600)
        if abs(windowWidthSlider.maxValue - maximumWidth) > 0.5 {
            windowWidthSlider.maxValue = maximumWidth
        }
        if abs(windowWidthSlider.doubleValue - availableWidth) > 0.5 {
            windowWidthSlider.doubleValue = availableWidth
        }
        updateLabels()
    }

    func rebindWindowObservation() {
        removeWindowObserver()
        observeWindowIfNeeded()
        updateWindowWidthControls()
        syncCollectionViewGeometry()
    }

    private func updateLabels() {
        statusLabel.stringValue = "\(items.count) SwiftUI cells  •  custom height-aware layout"
        let contentWidth = measurementWidth > 0 ? measurementWidth : layout.itemContentWidth(for: max(scrollView.contentSize.width, 320))
        scaleLabel.stringValue = String(format: "content width %.0f pt  •  height scale %.2fx", contentWidth, heightScale)
        windowWidthValueLabel.stringValue = String(format: "%.0f pt", max(currentWindowWidth(), 320))
    }

    private func recordCachedHeight(_ height: CGFloat, for cell: AnyDemoCell) {
        let normalizedHeight = max(metrics.minimumHeight, ceil(height))
        let knownHeight = cachedHeights[cell.id]

        guard knownHeight == nil || abs((knownHeight ?? 0) - normalizedHeight) > 0.5 else {
            return
        }

        cachedHeights[cell.id] = normalizedHeight
    }

    private func indexPath(for cell: AnyDemoCell) -> IndexPath? {
        guard let itemIndex = items.firstIndex(where: { $0.id == cell.id }) else {
            return nil
        }

        return IndexPath(item: itemIndex, section: 0)
    }

    private func makeViewportAnchor(for cell: AnyDemoCell) -> ViewportAnchor? {
        guard
            let indexPath = indexPath(for: cell),
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
                .min(by: { $0.frame.minY < $1.frame.minY })
            ,
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

    /// Recomputes one row's exact height, reloads nearby items, and restores the viewport around the change.
    private func invalidateHeight(for cell: AnyDemoCell) {
        let viewportAnchor = makeViewportAnchor(for: cell)
        let contentWidth = layout.itemContentWidth(for: collectionView.bounds.width)
        let measuredHeight = measurer.measure(cell: cell, width: contentWidth, metrics: metrics)
        cachedHeights[cell.id] = measuredHeight

        if let indexPath = indexPath(for: cell) {
            var indexPaths = collectionView.indexPathsForVisibleItems()
            indexPaths.insert(indexPath)
            collectionView.reloadItems(at: indexPaths)
        }

        invalidateLayout()
        restoreViewportAnchor(viewportAnchor)
        collectionView.needsDisplay = true
        scrollView.contentView.needsDisplay = true
        collectionView.displayIfNeeded()
        scrollView.contentView.displayIfNeeded()
        scheduleVisibleHeightMeasurement(delay: 0.02)
    }

    /// Debounces exact visible-row measurement so scrolling and toggles do not trigger redundant relayout passes.
    private func scheduleVisibleHeightMeasurement(delay: TimeInterval = 0.08) {
        pendingVisibleMeasurement?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.applyVisibleHeightMeasurements()
        }
        pendingVisibleMeasurement = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Re-measures visible cells after layout-affecting changes and reapplies the scroll anchor if any heights moved.
    private func applyVisibleHeightMeasurements() {
        pendingVisibleMeasurement = nil

        let visibleIndexPaths = collectionView.indexPathsForVisibleItems().sorted()
        guard !visibleIndexPaths.isEmpty else {
            return
        }

        let anchor = makeTopVisibleViewportAnchor()
        let contentWidth = layout.itemContentWidth(for: collectionView.bounds.width)
        var updatedHeight = false

        for indexPath in visibleIndexPaths {
            let cell = items[indexPath.item]
            let measuredHeight = measurer.measure(cell: cell, width: contentWidth, metrics: metrics)
            let previousHeight = cachedHeights[cell.id]

            guard previousHeight == nil || abs((previousHeight ?? 0) - measuredHeight) > 0.5 else {
                continue
            }

            cachedHeights[cell.id] = measuredHeight
            updatedHeight = true
        }

        guard updatedHeight else {
            return
        }

        invalidateLayout()
        restoreViewportAnchor(anchor)
        collectionView.needsDisplay = true
        scrollView.contentView.needsDisplay = true
        collectionView.displayIfNeeded()
        scrollView.contentView.displayIfNeeded()
    }

    /// Resizes the actual NSWindow so the width slider and manual edge resizing exercise the same layout path.
    private func resizeWindow(toContentWidth width: CGFloat) {
        guard let window = view.window else {
            return
        }

        let currentContentRect = window.contentRect(forFrameRect: window.frame)
        let clampedWidth = max(window.contentMinSize.width, width)
        let targetContentRect = NSRect(origin: .zero, size: NSSize(width: clampedWidth, height: currentContentRect.height))
        let targetFrameSize = window.frameRect(forContentRect: targetContentRect).size

        guard abs(window.frame.width - targetFrameSize.width) > 0.5 else {
            return
        }

        var targetFrame = window.frame
        targetFrame.origin.y += targetFrame.height - targetFrameSize.height
        targetFrame.size = targetFrameSize
        window.setFrame(targetFrame, display: true)
    }

    @objc private func heightScaleChanged(_ sender: NSSlider) {
        heightScale = sender.doubleValue
        updateLabels()

        pendingMetricsRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.applyMetricsRefresh()
        }
        pendingMetricsRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    @objc private func randomizeHeights() {
        items.forEach { $0.randomizeHeightBias() }
        applyMetricsRefresh()
    }

    @objc private func resetDemo() {
        heightScale = 1.05
        heightSlider.doubleValue = heightScale
        items.forEach { $0.resetState() }
        applyMetricsRefresh()
    }

    @objc private func windowWidthChanged(_ sender: NSSlider) {
        resizeWindow(toContentWidth: CGFloat(sender.doubleValue))
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

        let cell = items[indexPath.item]
        let contentWidth = layout.itemContentWidth(for: collectionView.bounds.width)
        item.configure(
            with: cell,
            width: contentWidth,
            metrics: metrics,
            onLayoutInvalidationRequested: { [weak self] in
                self?.invalidateHeight(for: cell)
            }
        )
        return item
    }

    func collectionViewLayout(_ layout: VerticalListCollectionLayout, heightForItemAt index: Int, width: CGFloat) -> CGFloat {
        let cell = items[index]
        if let cachedHeight = cachedHeights[cell.id] {
            return cachedHeight
        }

        let estimatedHeight = cell.estimatedHeight(for: width, metrics: metrics)
        recordCachedHeight(estimatedHeight, for: cell)
        return max(estimatedHeight, metrics.minimumHeight)
    }
}
