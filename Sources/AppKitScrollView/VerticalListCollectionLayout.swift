import AppKit

/// Supplies per-row heights for the single-column collection layout.
@MainActor
protocol VerticalListCollectionLayoutDelegate: AnyObject {
    func collectionViewLayout(
        _ layout: VerticalListCollectionLayout,
        heightForItemAt index: Int,
        width: CGFloat
    ) -> CGFloat
}

/// Lightweight vertical list layout that caches row frames and reflows them when width or content changes.
final class VerticalListCollectionLayout: NSCollectionViewLayout {
    weak var delegate: VerticalListCollectionLayoutDelegate?

    var sectionInsets = NSEdgeInsets(top: 18, left: 24, bottom: 24, right: 24)
    var itemSpacing: CGFloat = 14
    var preferredItemWidth: CGFloat?

    private var cachedAttributes: [IndexPath: NSCollectionViewLayoutAttributes] = [:]
    private var orderedAttributes: [NSCollectionViewLayoutAttributes] = []
    private var preparedWidth: CGFloat = 0
    private var preparedItemCount: Int = 0
    private var contentSize: NSSize = .zero

    override var collectionViewContentSize: NSSize {
        contentSize
    }

    /// Computes the usable cell width after section insets and optional preferred-width clamping.
    func itemContentWidth(for collectionViewWidth: CGFloat) -> CGFloat {
        let availableWidth = max(collectionViewWidth - sectionInsets.left - sectionInsets.right, 280)
        guard let preferredItemWidth else {
            return availableWidth
        }

        return max(min(preferredItemWidth, availableWidth), 280)
    }

    private func itemOriginX(for collectionViewWidth: CGFloat) -> CGFloat {
        let availableWidth = max(collectionViewWidth - sectionInsets.left - sectionInsets.right, 280)
        let itemWidth = itemContentWidth(for: collectionViewWidth)
        let remainingWidth = max(availableWidth - itemWidth, 0)
        return sectionInsets.left + floor(remainingWidth / 2)
    }

    private func backingScale(for collectionView: NSCollectionView) -> CGFloat {
        collectionView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func pixelRound(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    private func pixelCeil(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        ceil(value * scale) / scale
    }

    /// Builds and caches item frames for the current width, keeping content at least as tall as the viewport.
    override func prepare() {
        guard let collectionView else {
            return
        }

        let sectionCount = collectionView.numberOfSections
        guard sectionCount > 0 else {
            cachedAttributes.removeAll()
            orderedAttributes.removeAll()
            contentSize = collectionView.bounds.size
            preparedWidth = 0
            preparedItemCount = 0
            return
        }

        let visibleWidth = max(collectionView.bounds.width, collectionView.enclosingScrollView?.contentSize.width ?? 0)
        let viewportHeight = max(collectionView.enclosingScrollView?.contentSize.height ?? 0, 0)
        let scale = backingScale(for: collectionView)
        let itemWidth = itemContentWidth(for: visibleWidth)
        let itemCount = collectionView.numberOfItems(inSection: 0)

        guard orderedAttributes.isEmpty || abs(preparedWidth - itemWidth) > 0.5 || preparedItemCount != itemCount else {
            return
        }

        cachedAttributes.removeAll(keepingCapacity: true)
        orderedAttributes.removeAll(keepingCapacity: true)

        var yOffset = sectionInsets.top

        for item in 0..<itemCount {
            let indexPath = IndexPath(item: item, section: 0)
            let measuredHeight = max(delegate?.collectionViewLayout(self, heightForItemAt: item, width: itemWidth) ?? 80, 44)
            let height = pixelCeil(measuredHeight, scale: scale)
            let frame = NSRect(
                x: pixelRound(itemOriginX(for: visibleWidth), scale: scale),
                y: pixelRound(yOffset, scale: scale),
                width: pixelRound(itemWidth, scale: scale),
                height: height
            )

            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            attributes.frame = frame

            cachedAttributes[indexPath] = attributes
            orderedAttributes.append(attributes)
            yOffset = frame.maxY + itemSpacing
        }

        if itemCount > 0 {
            yOffset -= itemSpacing
        }

        preparedWidth = itemWidth
        preparedItemCount = itemCount
        contentSize = NSSize(
            width: max(visibleWidth, sectionInsets.left + sectionInsets.right + itemWidth),
            height: max(pixelCeil(yOffset + sectionInsets.bottom, scale: scale), viewportHeight)
        )
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        guard !orderedAttributes.isEmpty else {
            return []
        }

        var lowerBound = 0
        var upperBound = orderedAttributes.count
        while lowerBound < upperBound {
            let midpoint = lowerBound + ((upperBound - lowerBound) / 2)
            if orderedAttributes[midpoint].frame.maxY < rect.minY {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        var visibleAttributes: [NSCollectionViewLayoutAttributes] = []
        var index = lowerBound
        while index < orderedAttributes.count {
            let attributes = orderedAttributes[index]
            if attributes.frame.minY > rect.maxY {
                break
            }

            if attributes.frame.intersects(rect) {
                visibleAttributes.append(attributes)
            }
            index += 1
        }

        return visibleAttributes
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        cachedAttributes[indexPath]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        guard let collectionView else {
            return false
        }

        return abs(newBounds.width - collectionView.bounds.width) > 0.5
    }

    override func invalidateLayout() {
        super.invalidateLayout()
        cachedAttributes.removeAll(keepingCapacity: true)
        orderedAttributes.removeAll(keepingCapacity: true)
        preparedWidth = 0
        preparedItemCount = 0
    }
}
