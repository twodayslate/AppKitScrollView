import AppKit
import SwiftUI

/// Sample screen that uses the result-builder-backed AppKit scroll view with a heterogeneous 1000-row dataset.
@available(macOS 15.0, *)
struct BuilderDemoView: View {
    @State private var rows = BuilderDemoFactory.makeRows(count: 1000)
    @State private var showsConditionalSpotlight = true

    var body: some View {
        AppKitScrollView(estimatedRowHeight: 156) { context in
            BuilderOverviewCard(
                rowCount: rows.count,
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

            BuilderLongTextCard(
                accent: .systemTeal,
                title: "Long Text Stress Test",
                message: BuilderDemoFactory.longFormMessage
            )

            BuilderTrendAnimationLabCard()

            ForEach(rows) { row in
                BuilderDemoRowView(row: row)
                    .appKitScrollTarget(row.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func regenerateRows() {
        rows = BuilderDemoFactory.makeRows(count: 1000)
    }
}

@available(macOS 15.0, *)
private struct BuilderOverviewCard: View {
    let rowCount: Int
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
                        Text("\(rowCount) result-builder rows hosted in an AppKit NSCollectionView. Resize the window, expand disclosures, toggle trends, and scroll hard.")
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
                        Button("Regenerate 1000 Rows", action: onRegenerate)
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

@available(macOS 15.0, *)
private struct BuilderLongTextCard: View {
    let accent: NSColor
    let title: String
    let message: String

    var body: some View {
        DemoSurface(accent: Color(nsColor: accent)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))

                Text(message)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
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
                    try? await Task.sleep(for: .milliseconds(800))
                    await MainActor.run {
                        model.showsTrend.toggle()
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
                    ForEach(model.tags, id: \.self) { tag in
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
    @Environment(\.appKitScrollViewContext) private var scrollContext

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

                HStack(spacing: 8) {
                    ForEach(model.tags, id: \.self) { tag in
                        DemoTag(title: tag, accent: accent)
                    }
                }
            }
        }
        .onChange(of: model.isExpanded) { _, _ in
            scrollContext?.invalidateLayout()
        }
    }
}

private struct TrendPanelRow: View {
    @ObservedObject var model: TrendRowModel
    @Environment(\.appKitScrollViewContext) private var scrollContext

    @State private var rendersTrendSection = false
    @State private var trendRevealProgress: CGFloat = 0
    @State private var trendContentHeight: CGFloat = 0
    @State private var pendingHideTask: Task<Void, Never>?

    private let trendAnimation = Animation.snappy(duration: 0.3, extraBounce: 0.02)
    private let trendAnimationDuration: TimeInterval = 0.3
    private var fallbackTrendContentHeight: CGFloat {
        max(CGFloat(model.bars.count) * 30 - 8, 44)
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
                    .clipped()
                    .frame(
                        height: max(trendContentHeight, fallbackTrendContentHeight) * trendRevealProgress,
                        alignment: .top
                    )
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
        .onAppear {
            rendersTrendSection = model.showsTrend
            trendRevealProgress = model.showsTrend ? 1 : 0
        }
        .onDisappear {
            pendingHideTask?.cancel()
            pendingHideTask = nil
        }
        .onChange(of: model.showsTrend) { _, showsTrend in
            applyTrendVisibility(showsTrend)
        }
    }

    private func applyTrendVisibility(_ showsTrend: Bool) {
        pendingHideTask?.cancel()
        pendingHideTask = nil

        if showsTrend {
            if !rendersTrendSection {
                rendersTrendSection = true
                trendRevealProgress = 0
                trendContentHeight = max(trendContentHeight, fallbackTrendContentHeight)
                scrollContext?.invalidateLayout()
            }

            withAnimation(trendAnimation) {
                trendRevealProgress = 1
            }
            scrollContext?.animateLayout(duration: trendAnimationDuration)
            return
        }

        withAnimation(trendAnimation) {
            trendRevealProgress = 0
        }
        scrollContext?.animateLayout(duration: trendAnimationDuration)

        pendingHideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(trendAnimationDuration * 1000)))
            guard !model.showsTrend else {
                return
            }

            rendersTrendSection = false
            scrollContext?.invalidateLayout()
            pendingHideTask = nil
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
    static let longFormMessage = [
        "This block is intentionally long so the AppKit-backed builder can prove that wrapped SwiftUI text is measured correctly and never truncated when the window narrows, widens, or the collection scrolls under pressure.",
        "It keeps going with enough density to force several paragraphs of reflow: signal lattice drift follows the anchor path while nested modules stream context through the viewport, and the host still needs to preserve every line instead of clipping after an estimated row height.",
        "If this row ever truncates, overlaps, or leaves a stale gap after resizing, the measurement or invalidation pipeline is wrong. That makes it a good fixed regression target alongside the disclosure and trend cards."
    ].joined(separator: " ")

    static func makeRows(count: Int) -> [BuilderDemoRow] {
        var generator = BuilderSeededGenerator(seed: 0xB017_D3110)

        return (0..<count).map { index in
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
