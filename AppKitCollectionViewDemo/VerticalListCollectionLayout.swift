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
            let height = max(delegate?.collectionViewLayout(self, heightForItemAt: item, width: itemWidth) ?? 80, 44)
            let frame = NSRect(x: itemOriginX(for: visibleWidth), y: yOffset, width: itemWidth, height: height)

            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            attributes.frame = frame

            cachedAttributes[indexPath] = attributes
            orderedAttributes.append(attributes)
            yOffset += height + itemSpacing
        }

        if itemCount > 0 {
            yOffset -= itemSpacing
        }

        preparedWidth = itemWidth
        preparedItemCount = itemCount
        contentSize = NSSize(
            width: max(visibleWidth, sectionInsets.left + sectionInsets.right + itemWidth),
            height: max(yOffset + sectionInsets.bottom, viewportHeight)
        )
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        orderedAttributes.filter { $0.frame.intersects(rect) }
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
