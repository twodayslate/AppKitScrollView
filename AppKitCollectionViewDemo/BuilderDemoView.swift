import AppKit
import SwiftUI

/// Sample screen that uses the result-builder-backed AppKit scroll view with a heterogeneous 1000-row dataset.
@available(macOS 15.0, *)
struct BuilderDemoView: View {
    private let initialRowCount = 1000
    private let loadMoreBatchSize = 250

    @State private var rows = BuilderDemoFactory.makeRows(count: 1000)
    @State private var showsConditionalSpotlight = true
    @State private var isLoadingMoreRows = false
    @State private var loadMoreGeneration = UUID()
    @State private var hasStartedAutoDemo = false

    var body: some View {
        AppKitScrollView(estimatedRowHeight: 156) { context in
            BuilderOverviewCard(
                rowCount: rows.count,
                batchSize: loadMoreBatchSize,
                estimatedRowHeight: context.estimatedRowHeight,
                showsConditionalSpotlight: showsConditionalSpotlight,
                onRegenerate: regenerateRows,
                onToggleConditionalSpotlight: {
                    showsConditionalSpotlight.toggle()
                },
                onScrollToTop: {
                    context.scrollToTop()
                },
                onScrollToMidpoint: {
                    guard let midpointID = rows[safe: rows.count / 2]?.id else {
                        return
                    }
                    context.scrollTo(midpointID, anchor: .center)
                },
                onScrollToBottom: {
                    context.scrollToBottom()
                }
            )
            .onAppear {
                startAutoDemoIfNeeded(context: context)
            }

            if showsConditionalSpotlight {
                BuilderConditionalSpotlightCard(
                    accent: .systemIndigo,
                    title: "If Branch",
                    summary: "This card comes from the `if` branch of the AppKitScrollView builder. Toggling it exercises conditional flattening before the collection diff runs."
                )
            } else {
                BuilderConditionalSpotlightCard(
                    accent: .orange,
                    title: "Else Branch",
                    summary: "This card comes from the `else` branch. The direct child list still flattens into separate collection rows, so the AppKit host can diff and relayout it normally."
                )
            }

            BuilderTrendAnimationLabCard()
            BuilderDisclosureAnimationLabCard()

            BuilderLongTextCard(
                accent: .systemTeal,
                title: "10x Viewport Text Torture Test",
                summary: "This fixed card is intentionally enormous. At a normal desktop window size it should be roughly ten times taller than the viewport, so text wrapping, measurement, and scrolling have to stay correct for one giant cell.",
                paragraphs: BuilderDemoFactory.longFormParagraphs
            )

            ForEach(rows) { row in
                BuilderDemoRowView(row: row)
                    .appKitScrollTarget(row.id)
            }

            BuilderLoadMoreCard(
                rowCount: rows.count,
                batchSize: loadMoreBatchSize,
                isLoading: isLoadingMoreRows
            )
            .appKitScrollTarget("load-more-sentinel")
            .onAppear {
                scheduleLoadMoreRows()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func regenerateRows() {
        loadMoreGeneration = UUID()
        isLoadingMoreRows = false
        rows = BuilderDemoFactory.makeRows(count: initialRowCount)
    }

    /// Starts a single delayed load when the bottom sentinel becomes visible.
    private func scheduleLoadMoreRows() {
        guard !isLoadingMoreRows else {
            return
        }

        isLoadingMoreRows = true
        let generation = loadMoreGeneration
        let shouldLogLoadMore = ProcessInfo.processInfo.environment["APPKIT_SCROLL_AUTODEMO_LOAD_MORE"] == "1"

        if shouldLogLoadMore {
            NSLog("[AppKitScrollViewDemo] scheduling load more from \(rows.count) rows")
        }

        Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                isLoadingMoreRows = false
                return
            }

            guard generation == loadMoreGeneration else {
                return
            }

            let startIndex = rows.count
            rows.append(contentsOf: BuilderDemoFactory.makeRows(count: loadMoreBatchSize, startIndex: startIndex))
            isLoadingMoreRows = false

            if shouldLogLoadMore {
                NSLog("[AppKitScrollViewDemo] appended \(loadMoreBatchSize) rows; total=\(rows.count)")
            }
        }
    }

    /// Starts a deterministic debug-only interaction pass so layout regressions can be checked from logs.
    @MainActor
    private func startAutoDemoIfNeeded(context: AppKitScrollViewContext) {
        guard ProcessInfo.processInfo.environment["APPKIT_SCROLL_AUTODEMO"] == "1", !hasStartedAutoDemo else {
            return
        }

        hasStartedAutoDemo = true
        Task { @MainActor in
            guard await sleepForAutoDemo(milliseconds: 1_200) else {
                return
            }

            await runAutoDemoTrendPass(context: context)
            await runAutoDemoDisclosurePass(context: context)
            await runAutoDemoLoadMorePassIfNeeded(context: context)
        }
    }

    @MainActor
    private func runAutoDemoTrendPass(context: AppKitScrollViewContext) async {
        guard let target = rows.dropFirst(12).first(where: { row in
            if case .trend = row.kind {
                return true
            }

            return false
        }) else {
            return
        }

        context.scrollTo(target.id, anchor: .center)
        guard await sleepForAutoDemo(milliseconds: 900) else {
            return
        }

        guard case let .trend(model) = target.kind else {
            return
        }

        NSLog("[AppKitScrollViewDemo] toggling random trend \(model.title) to \(!model.showsTrend)")
        model.showsTrend.toggle()
        guard await sleepForAutoDemo(milliseconds: 900) else {
            return
        }

        NSLog("[AppKitScrollViewDemo] toggling random trend \(model.title) to \(!model.showsTrend)")
        model.showsTrend.toggle()
        _ = await sleepForAutoDemo(milliseconds: 900)
    }

    @MainActor
    private func runAutoDemoDisclosurePass(context: AppKitScrollViewContext) async {
        guard let target = rows.dropFirst(12).first(where: { row in
            if case .disclosure = row.kind {
                return true
            }

            return false
        }) else {
            return
        }

        context.scrollTo(target.id, anchor: .center)
        guard await sleepForAutoDemo(milliseconds: 900) else {
            return
        }

        guard case let .disclosure(model) = target.kind else {
            return
        }

        NSLog("[AppKitScrollViewDemo] toggling random disclosure \(model.title) to \(!model.isExpanded)")
        model.isExpanded.toggle()
        guard await sleepForAutoDemo(milliseconds: 900) else {
            return
        }

        NSLog("[AppKitScrollViewDemo] toggling random disclosure \(model.title) to \(!model.isExpanded)")
        model.isExpanded.toggle()
        _ = await sleepForAutoDemo(milliseconds: 900)
    }

    @MainActor
    private func runAutoDemoLoadMorePassIfNeeded(context: AppKitScrollViewContext) async {
        guard ProcessInfo.processInfo.environment["APPKIT_SCROLL_AUTODEMO_LOAD_MORE"] == "1" else {
            return
        }

        let startingCount = rows.count
        NSLog("[AppKitScrollViewDemo] scrolling to bottom to trigger load more from \(startingCount) rows")
        context.scrollToBottom()

        guard await sleepForAutoDemo(milliseconds: 2_700) else {
            return
        }

        NSLog("[AppKitScrollViewDemo] load-more pass observed \(rows.count) rows")
    }

    private func sleepForAutoDemo(milliseconds: Int) async -> Bool {
        do {
            try await Task.sleep(for: .milliseconds(milliseconds))
            return true
        } catch {
            return false
        }
    }
}

@available(macOS 15.0, *)
private struct BuilderOverviewCard: View {
    let rowCount: Int
    let batchSize: Int
    let estimatedRowHeight: CGFloat
    let showsConditionalSpotlight: Bool
    let onRegenerate: () -> Void
    let onToggleConditionalSpotlight: () -> Void
    let onScrollToTop: () -> Void
    let onScrollToMidpoint: () -> Void
    let onScrollToBottom: () -> Void

    var body: some View {
        DemoSurface(accent: Color(nsColor: .systemBlue)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AppKitScrollView { context in ... }")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text("\(rowCount) result-builder rows hosted in an AppKit NSCollectionView. Resize the window, expand disclosures, toggle trends, scroll hard, and pause at the bottom to load \(batchSize) more rows.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 20)

                    HStack(spacing: 10) {
                        Button("Top", action: onScrollToTop)
                            .buttonStyle(.bordered)
                        Button("Midpoint", action: onScrollToMidpoint)
                            .buttonStyle(.bordered)
                        Button("Bottom", action: onScrollToBottom)
                            .buttonStyle(.bordered)
                        Button(showsConditionalSpotlight ? "Show Else Branch" : "Show If Branch", action: onToggleConditionalSpotlight)
                            .buttonStyle(.bordered)
                        Button("Regenerate Rows", action: onRegenerate)
                            .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.large)
                }

                Text("The builder receives a proxy-like context with programmatic scrolling, and the AppKit host uses visible-row measurement to keep the collection responsive while each row remains plain SwiftUI.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    DemoTag(title: "estimated \(Int(estimatedRowHeight)) pt", accent: .blue)
                    DemoTag(title: "Group(subviews:)", accent: .cyan)
                    DemoTag(title: "proxy scrollTo", accent: .pink)
                    DemoTag(title: "if / else branch", accent: .orange)
                    DemoTag(title: "manual window resize", accent: .indigo)
                    DemoTag(title: "infinite bottom load", accent: .green)
                }
            }
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct BuilderConditionalSpotlightCard: View {
    let accent: NSColor
    let title: String
    let summary: String

    var body: some View {
        DemoSurface(accent: Color(nsColor: accent)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(summary)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct BuilderLoadMoreCard: View {
    let rowCount: Int
    let batchSize: Int
    let isLoading: Bool

    var body: some View {
        let accent = Color(nsColor: .systemGreen)

        DemoSurface(accent: accent) {
            HStack(alignment: .center, spacing: 16) {
                ProgressView()
                    .controlSize(.small)
                    .opacity(isLoading ? 1 : 0)

                VStack(alignment: .leading, spacing: 6) {
                    Text(isLoading ? "Loading more rows..." : "Bottom reached")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))

                    Text(isLoading ? "Waiting 2 seconds, then appending \(batchSize) generated rows." : "\(rowCount) rows loaded. Pause here to append the next batch.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                DemoTag(title: "+\(batchSize)", accent: accent)
            }
        }
    }
}

@available(macOS 15.0, *)
private struct BuilderLongTextCard: View {
    let accent: NSColor
    let title: String
    let summary: String
    let paragraphs: [String]

    var body: some View {
        DemoSurface(accent: Color(nsColor: accent)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))

                Text(summary)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                        Text("\(index + 1). \(paragraph)")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@available(macOS 15.0, *)
private struct BuilderTrendAnimationLabCard: View {
    @StateObject private var model = BuilderDemoFactory.makeAnimationLabTrend()

    private let autoDemoEnabled = ProcessInfo.processInfo.environment["APPKIT_SCROLL_AUTODEMO"] == "1"

    var body: some View {
        TrendPanelRow(model: model)
            .task(id: autoDemoEnabled) {
                guard autoDemoEnabled else {
                    return
                }

                for _ in 0..<3 {
                    do {
                        try await Task.sleep(for: .milliseconds(800))
                    } catch {
                        return
                    }

                    await MainActor.run {
                        if autoDemoEnabled {
                            NSLog("[AppKitScrollViewDemo] toggling animation lab trend to \(!model.showsTrend)")
                        }
                        model.showsTrend.toggle()
                    }
                }
            }
    }
}

@available(macOS 15.0, *)
private struct BuilderDisclosureAnimationLabCard: View {
    @StateObject private var model = BuilderDemoFactory.makeAnimationLabDisclosure()

    private let autoDemoEnabled = ProcessInfo.processInfo.environment["APPKIT_SCROLL_AUTODEMO"] == "1"

    var body: some View {
        DisclosurePanelRow(model: model)
            .task(id: autoDemoEnabled) {
                guard autoDemoEnabled else {
                    return
                }

                do {
                    try await Task.sleep(for: .milliseconds(2600))
                } catch {
                    return
                }

                for _ in 0..<3 {
                    do {
                        try await Task.sleep(for: .milliseconds(800))
                    } catch {
                        return
                    }

                    await MainActor.run {
                        if autoDemoEnabled {
                            NSLog("[AppKitScrollViewDemo] toggling animation lab disclosure to \(!model.isExpanded)")
                        }
                        model.isExpanded.toggle()
                    }
                }
            }
    }
}

@available(macOS 15.0, *)
private struct BuilderDemoRowView: View {
    let row: BuilderDemoRow

    var body: some View {
        switch row.kind {
        case let .bubble(model):
            ChatBubbleRow(model: model)
        case let .disclosure(model):
            DisclosurePanelRow(model: model)
        case let .trend(model):
            TrendPanelRow(model: model)
        }
    }
}

private struct BuilderDemoRow: Identifiable {
    enum Kind {
        case bubble(BubbleRowModel)
        case disclosure(DisclosureRowModel)
        case trend(TrendRowModel)
    }

    let id: UUID
    let kind: Kind
}

private struct BubbleRowModel {
    let accent: NSColor
    let label: String
    let message: String
    let footer: String
    let tags: [String]
    let isOutgoing: Bool
}

private final class DisclosureRowModel: ObservableObject, Identifiable {
    let id = UUID()
    let accent: NSColor
    let title: String
    let summary: String
    let details: [String]
    let tags: [String]

    @Published var isExpanded: Bool

    init(accent: NSColor, title: String, summary: String, details: [String], tags: [String], isExpanded: Bool) {
        self.accent = accent
        self.title = title
        self.summary = summary
        self.details = details
        self.tags = tags
        self.isExpanded = isExpanded
    }
}

private struct MetricChip: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

private struct TrendSectionHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private final class TrendRowModel: ObservableObject, Identifiable {
    let id = UUID()
    let accent: NSColor
    let title: String
    let subtitle: String
    let metrics: [MetricChip]
    let bars: [Double]

    @Published var showsTrend: Bool

    init(accent: NSColor, title: String, subtitle: String, metrics: [MetricChip], bars: [Double], showsTrend: Bool) {
        self.accent = accent
        self.title = title
        self.subtitle = subtitle
        self.metrics = metrics
        self.bars = bars
        self.showsTrend = showsTrend
    }
}

private struct ChatBubbleRow: View {
    let model: BubbleRowModel

    var body: some View {
        let accent = Color(nsColor: model.accent)

        HStack {
            if model.isOutgoing {
                Spacer(minLength: 56)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                    Spacer(minLength: 12)
                    Text(model.footer)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Text(model.message)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    ForEach(Array(model.tags.enumerated()), id: \.offset) { _, tag in
                        DemoTag(title: tag, accent: accent)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: 760, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(accent.opacity(model.isOutgoing ? 0.16 : 0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(accent.opacity(0.35), lineWidth: 1)
            )

            if !model.isOutgoing {
                Spacer(minLength: 56)
            }
        }
    }
}

private struct DisclosurePanelRow: View {
    @ObservedObject var model: DisclosureRowModel

    var body: some View {
        let accent = Color(nsColor: model.accent)

        DemoSurface(accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.title)
                            .font(.system(size: 23, weight: .semibold, design: .rounded))
                        Text(model.summary)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 16)

                    Text(model.isExpanded ? "Hide Notes" : "Show Notes")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                }

                DisclosureGroup(isExpanded: $model.isExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(model.details.enumerated()), id: \.offset) { index, detail in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(accent)
                                    .frame(width: 7, height: 7)
                                    .padding(.top, 6)

                                Text(detail)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.leading, CGFloat(index % 2) * 8)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text(model.isExpanded ? "Collapse detail section" : "Expand detail section")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                }
                .accentColor(accent)
                .animation(.easeInOut(duration: 0.28), value: model.isExpanded)

                HStack(spacing: 8) {
                    ForEach(Array(model.tags.enumerated()), id: \.offset) { _, tag in
                        DemoTag(title: tag, accent: accent)
                    }
                }
            }
        }
    }
}

private struct TrendPanelRow: View {
    @ObservedObject var model: TrendRowModel

    @State private var rendersTrendSection: Bool
    @State private var trendRevealProgress: CGFloat
    @State private var trendContentHeight: CGFloat

    private let trendAnimation = Animation.easeInOut(duration: 0.34)
    private var fallbackTrendContentHeight: CGFloat {
        max(CGFloat(model.bars.count) * 30 - 8, 44)
    }

    init(model: TrendRowModel) {
        self._model = ObservedObject(wrappedValue: model)
        let startsExpanded = model.showsTrend
        _rendersTrendSection = State(initialValue: startsExpanded)
        _trendRevealProgress = State(initialValue: startsExpanded ? 1 : 0)
        _trendContentHeight = State(initialValue: 0)
    }

    var body: some View {
        let accent = Color(nsColor: model.accent)

        DemoSurface(accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.title)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                        Text(model.subtitle)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 16)

                    Button(model.showsTrend ? "Hide Trend" : "Show Trend") {
                        model.showsTrend.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        ForEach(model.metrics) { metric in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(metric.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text(metric.value)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(accent.opacity(0.12))
                            )
                        }
                    }

                    if rendersTrendSection {
                        let measuredTrendSection = VStack(spacing: 12) {
                            ForEach(Array(model.bars.enumerated()), id: \.offset) { index, value in
                                HStack(spacing: 14) {
                                    Text("Row \(index + 1)")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .frame(width: 52, alignment: .leading)

                                    GeometryReader { proxy in
                                        ZStack(alignment: .leading) {
                                            Capsule(style: .continuous)
                                                .fill(Color.white.opacity(0.08))
                                            Capsule(style: .continuous)
                                                .fill(accent)
                                                .frame(width: max(proxy.size.width * value * trendRevealProgress, 0))
                                        }
                                    }
                                    .frame(height: 12)

                                    Text("\(Int(value * 100))")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, alignment: .trailing)
                                }
                                .opacity(trendRevealProgress)
                                .offset(y: (1 - trendRevealProgress) * -8)
                            }
                        }
                        .padding(.top, 4)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: TrendSectionHeightPreferenceKey.self, value: proxy.size.height)
                            }
                        )

                        measuredTrendSection
                            .padding(.top, 14 * trendRevealProgress)
                            .frame(
                                height: (max(trendContentHeight, fallbackTrendContentHeight) * trendRevealProgress) + (14 * trendRevealProgress),
                                alignment: .top
                            )
                            .clipped()
                            .opacity(trendRevealProgress)
                            .scaleEffect(y: max(0.001, 0.985 + (0.015 * trendRevealProgress)), anchor: .top)
                            .onPreferenceChange(TrendSectionHeightPreferenceKey.self) { height in
                                guard abs(trendContentHeight - height) > 0.5 else {
                                    return
                                }

                                trendContentHeight = height
                            }
                    }
                }
            }
        }
        .onChange(of: model.showsTrend) { _, showsTrend in
            applyTrendVisibility(showsTrend)
        }
    }

    private func applyTrendVisibility(_ showsTrend: Bool) {
        if showsTrend {
            if !rendersTrendSection {
                rendersTrendSection = true
                trendRevealProgress = 0
                trendContentHeight = max(trendContentHeight, fallbackTrendContentHeight)
            }

            withAnimation(trendAnimation) {
                trendRevealProgress = 1
            }
            return
        }

        withAnimation(trendAnimation) {
            trendRevealProgress = 0
        }
    }
}

private struct DemoSurface<Content: View>: View {
    let accent: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.12),
                                Color(nsColor: .controlBackgroundColor)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(accent.opacity(0.35), lineWidth: 1)
            )
    }
}

private struct DemoTag: View {
    let title: String
    let accent: Color

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(accent.opacity(0.12))
            )
    }
}

private enum BuilderDemoFactory {
    static let longFormParagraphs: [String] = {
        let baseParagraphs = [
            "This block exists purely to stress measurement. It should stay readable when the window narrows, widens, jumps to a different scroll position, or gets remeasured after neighboring rows change height.",
            "The point is not pretty prose. The point is forcing one SwiftUI-authored cell to become absurdly tall so the AppKit host has to preserve line wrapping, avoid clipping, and keep scroll anchors coherent over a very large single item.",
            "If this card ever truncates, overlaps another block, or leaves stale whitespace after relayout, the package is still relying on an estimate somewhere it should be trusting live or exact measurement instead."
        ]

        return (0..<220).map { index in
            let paragraph = baseParagraphs[index % baseParagraphs.count]
            return "Section \(index + 1): \(paragraph)"
        }
    }()

    static func makeRows(count: Int, startIndex: Int = 0) -> [BuilderDemoRow] {
        let seedOffset = UInt64(truncatingIfNeeded: startIndex) &* 0x9E37_79B9_7F4A_7C15
        var generator = BuilderSeededGenerator(seed: 0xB017_D3110 ^ seedOffset)

        return (startIndex..<(startIndex + count)).map { index in
            let kind = Int.random(in: 0..<3, using: &generator)

            switch kind {
            case 0:
                return BuilderDemoRow(id: UUID(), kind: .bubble(makeBubble(index: index, generator: &generator)))
            case 1:
                return BuilderDemoRow(id: UUID(), kind: .disclosure(makeDisclosure(index: index, generator: &generator)))
            default:
                return BuilderDemoRow(id: UUID(), kind: .trend(makeTrend(index: index, generator: &generator)))
            }
        }
    }

    private static func makeBubble<G: RandomNumberGenerator>(index: Int, generator: inout G) -> BubbleRowModel {
        let accent = BuilderPalette.colors.randomElement(using: &generator) ?? .systemBlue
        let label = "\(randomWord(using: &generator).capitalized) \(index + 1)"
        let footer = "\(Int.random(in: 1...9, using: &generator)) min ago"
        let message = randomParagraph(sentenceCount: Int.random(in: 2...5, using: &generator), generator: &generator)
        let tags = (0..<3).map { _ in randomWord(using: &generator).capitalized }

        return BubbleRowModel(
            accent: accent,
            label: label,
            message: message,
            footer: footer,
            tags: tags,
            isOutgoing: Bool.random(using: &generator)
        )
    }

    private static func makeDisclosure<G: RandomNumberGenerator>(index: Int, generator: inout G) -> DisclosureRowModel {
        let details = (0..<Int.random(in: 3...7, using: &generator)).map { _ in
            randomSentence(wordCount: Int.random(in: 7...12, using: &generator), generator: &generator)
        }

        return DisclosureRowModel(
            accent: BuilderPalette.colors.randomElement(using: &generator) ?? .systemOrange,
            title: "\(randomWord(using: &generator).capitalized) Notes \(index + 1)",
            summary: randomSentence(wordCount: Int.random(in: 8...12, using: &generator), generator: &generator),
            details: details,
            tags: (0..<3).map { _ in randomWord(using: &generator).capitalized },
            isExpanded: Bool.random(using: &generator)
        )
    }

    private static func makeTrend<G: RandomNumberGenerator>(index: Int, generator: inout G) -> TrendRowModel {
        TrendRowModel(
            accent: BuilderPalette.colors.randomElement(using: &generator) ?? .systemPink,
            title: "\(randomWord(using: &generator).capitalized) Trend \(index + 1)",
            subtitle: randomSentence(wordCount: Int.random(in: 7...11, using: &generator), generator: &generator),
            metrics: [
                MetricChip(title: "CPU", value: "\(Int.random(in: 15...92, using: &generator))%"),
                MetricChip(title: "FPS", value: "\(Int.random(in: 30...120, using: &generator))"),
                MetricChip(title: "MB", value: "\(Int.random(in: 90...640, using: &generator))")
            ],
            bars: (0..<Int.random(in: 4...7, using: &generator)).map { _ in Double.random(in: 0.2...0.95, using: &generator) },
            showsTrend: Bool.random(using: &generator)
        )
    }

    static func makeAnimationLabTrend() -> TrendRowModel {
        TrendRowModel(
            accent: .systemMint,
            title: "Animation Lab Trend",
            subtitle: "This fixed row sits near the top so show and hide behavior can be tested without hunting through the random dataset.",
            metrics: [
                MetricChip(title: "CPU", value: "31%"),
                MetricChip(title: "FPS", value: "112"),
                MetricChip(title: "MB", value: "625")
            ],
            bars: [0.71, 0.34, 0.47, 0.84, 0.46],
            showsTrend: true
        )
    }

    static func makeAnimationLabDisclosure() -> DisclosureRowModel {
        DisclosureRowModel(
            accent: .systemOrange,
            title: "Animation Lab Disclosure",
            summary: "This fixed row sits near the top so disclosure expand and collapse behavior can be tested without depending on the random dataset.",
            details: [
                "The host should relayout surrounding rows smoothly while this disclosure expands.",
                "When the detail list collapses, the gap between neighboring blocks should close back to the normal row spacing.",
                "The row should not clip its bullets or leave stale empty space behind after the animation completes.",
                "This fixed lab row exists so regressions are easy to reproduce and re-check."
            ],
            tags: ["Disclosure", "Animation", "Relayout"],
            isExpanded: true
        )
    }

    private static func randomParagraph<G: RandomNumberGenerator>(sentenceCount: Int, generator: inout G) -> String {
        (0..<sentenceCount)
            .map { _ in randomSentence(wordCount: Int.random(in: 7...14, using: &generator), generator: &generator) }
            .joined(separator: " ")
    }

    private static func randomSentence<G: RandomNumberGenerator>(wordCount: Int, generator: inout G) -> String {
        let words = (0..<wordCount).map { _ in randomWord(using: &generator) }
        return words.joined(separator: " ").capitalized + "."
    }

    private static func randomWord<G: RandomNumberGenerator>(using generator: inout G) -> String {
        BuilderPalette.words.randomElement(using: &generator) ?? "signal"
    }
}

private struct BuilderSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

private enum BuilderPalette {
    static let colors: [NSColor] = [
        .systemBlue,
        .systemTeal,
        .systemIndigo,
        .systemGreen,
        .systemOrange,
        .systemPink,
        .systemRed
    ]

    static let words: [String] = [
        "anchor", "atlas", "beacon", "buffer", "circuit", "cluster", "coast", "drift", "ember",
        "field", "finite", "focus", "glide", "harbor", "hinge", "index", "kernel", "ledger",
        "lumen", "matrix", "module", "nested", "offset", "orbit", "parcel", "path", "phase",
        "pivot", "prism", "quartz", "ribbon", "signal", "spectrum", "stack", "stream", "vector",
        "wave", "window", "zenith"
    ]
}
