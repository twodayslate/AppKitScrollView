import AppKit
import Combine
import SwiftUI

struct DemoLayoutMetrics {
    var heightScale: CGFloat

    var cardPadding: CGFloat { 14 + (heightScale * 8) }
    var cardSpacing: CGFloat { 8 + (heightScale * 4) }
    var titleSize: CGFloat { 13 + (heightScale * 4) }
    var bodySize: CGFloat { 12 + (heightScale * 2) }
    var captionSize: CGFloat { 11 + heightScale }
    var chipSize: CGFloat { 10 + heightScale }
    var lineSpacing: CGFloat { 2 + heightScale }
    var cornerRadius: CGFloat { 16 + (heightScale * 4) }
    var minimumHeight: CGFloat { 68 + (heightScale * 16) }

    var titleFont: Font { .system(size: titleSize, weight: .semibold, design: .rounded) }
    var bodyFont: Font { .system(size: bodySize, weight: .regular, design: .rounded) }
    var captionFont: Font { .system(size: captionSize, weight: .medium, design: .rounded) }
    var chipFont: Font { .system(size: chipSize, weight: .semibold, design: .rounded) }

    func lineHeight(for size: CGFloat, multiplier: CGFloat = 1.35) -> CGFloat {
        (size * multiplier) + lineSpacing
    }
}

struct DemoCellRenderContext {
    let width: CGFloat
    let metrics: DemoLayoutMetrics
    let invalidateLayout: () -> Void
}

protocol DemoCellRenderable: AnyObject {
    var id: UUID { get }
    func estimatedHeight(for width: CGFloat, metrics: DemoLayoutMetrics) -> CGFloat
    func makeView(context: DemoCellRenderContext) -> AnyView
    func randomizeHeightBias()
    func resetState()
}

final class AnyDemoCell: DemoCellRenderable {
    let id: UUID

    private let estimateHandler: (CGFloat, DemoLayoutMetrics) -> CGFloat
    private let viewHandler: (DemoCellRenderContext) -> AnyView
    private let randomizeHandler: () -> Void
    private let resetHandler: () -> Void

    init(
        id: UUID = UUID(),
        estimateHandler: @escaping (CGFloat, DemoLayoutMetrics) -> CGFloat,
        viewHandler: @escaping (DemoCellRenderContext) -> AnyView,
        randomizeHandler: @escaping () -> Void,
        resetHandler: @escaping () -> Void
    ) {
        self.id = id
        self.estimateHandler = estimateHandler
        self.viewHandler = viewHandler
        self.randomizeHandler = randomizeHandler
        self.resetHandler = resetHandler
    }

    func estimatedHeight(for width: CGFloat, metrics: DemoLayoutMetrics) -> CGFloat {
        estimateHandler(width, metrics)
    }

    func makeView(context: DemoCellRenderContext) -> AnyView {
        viewHandler(context)
    }

    func randomizeHeightBias() {
        randomizeHandler()
    }

    func resetState() {
        resetHandler()
    }
}

final class TextCardState {
    let accent: NSColor
    let label: String
    let title: String
    let body: String
    let tags: [String]
    let footer: String

    private(set) var heightBias: CGFloat
    private let baselineHeightBias: CGFloat

    init(
        accent: NSColor,
        label: String,
        title: String,
        body: String,
        tags: [String],
        footer: String,
        heightBias: CGFloat
    ) {
        self.accent = accent
        self.label = label
        self.title = title
        self.body = body
        self.tags = tags
        self.footer = footer
        self.heightBias = heightBias
        baselineHeightBias = heightBias
    }

    func bodyLineLimit(metrics: DemoLayoutMetrics) -> Int {
        max(3, Int(round(3 + Double(heightBias * 3.2) + Double(metrics.heightScale * 1.6))))
    }

    func randomizeHeightBias() {
        heightBias = CGFloat.random(in: 0.75...1.85)
    }

    func resetState() {
        heightBias = baselineHeightBias
    }
}

final class DisclosureCardState: ObservableObject {
    let accent: NSColor
    let title: String
    let summary: String
    let detailLines: [String]
    let footerChips: [String]

    @Published var isExpanded: Bool

    private(set) var heightBias: CGFloat
    private let baselineExpanded: Bool
    private let baselineHeightBias: CGFloat

    init(
        accent: NSColor,
        title: String,
        summary: String,
        detailLines: [String],
        footerChips: [String],
        isExpanded: Bool,
        heightBias: CGFloat
    ) {
        self.accent = accent
        self.title = title
        self.summary = summary
        self.detailLines = detailLines
        self.footerChips = footerChips
        self.isExpanded = isExpanded
        self.heightBias = heightBias
        baselineExpanded = isExpanded
        baselineHeightBias = heightBias
    }

    func visibleDetailCount() -> Int {
        min(detailLines.count, max(2, Int(round(2 + Double(heightBias * 2.4)))))
    }

    func randomizeHeightBias() {
        heightBias = CGFloat.random(in: 0.8...1.9)
    }

    func resetState() {
        isExpanded = baselineExpanded
        heightBias = baselineHeightBias
    }
}

struct MetricSnapshot: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

final class MetricsCardState: ObservableObject {
    let accent: NSColor
    let title: String
    let subtitle: String
    let metrics: [MetricSnapshot]
    let completion: Double
    let trendBars: [Double]

    @Published var showsTrend: Bool

    private(set) var heightBias: CGFloat
    private let baselineShowsTrend: Bool
    private let baselineHeightBias: CGFloat

    init(
        accent: NSColor,
        title: String,
        subtitle: String,
        metrics: [MetricSnapshot],
        completion: Double,
        trendBars: [Double],
        showsTrend: Bool,
        heightBias: CGFloat
    ) {
        self.accent = accent
        self.title = title
        self.subtitle = subtitle
        self.metrics = metrics
        self.completion = completion
        self.trendBars = trendBars
        self.showsTrend = showsTrend
        self.heightBias = heightBias
        baselineShowsTrend = showsTrend
        baselineHeightBias = heightBias
    }

    func visibleTrendCount() -> Int {
        min(trendBars.count, max(2, Int(round(2 + Double(heightBias * 3.1)))))
    }

    func randomizeHeightBias() {
        heightBias = CGFloat.random(in: 0.85...1.9)
    }

    func resetState() {
        showsTrend = baselineShowsTrend
        heightBias = baselineHeightBias
    }
}

final class ControlsCardState: ObservableObject {
    let accent: NSColor
    let title: String
    let blurb: String
    let notes: [String]

    @Published var showsAdvanced: Bool
    @Published var density: Double
    @Published var activeBlocks: Int

    private(set) var heightBias: CGFloat
    private let baselineShowsAdvanced: Bool
    private let baselineDensity: Double
    private let baselineActiveBlocks: Int
    private let baselineHeightBias: CGFloat

    init(
        accent: NSColor,
        title: String,
        blurb: String,
        notes: [String],
        showsAdvanced: Bool,
        density: Double,
        activeBlocks: Int,
        heightBias: CGFloat
    ) {
        self.accent = accent
        self.title = title
        self.blurb = blurb
        self.notes = notes
        self.showsAdvanced = showsAdvanced
        self.density = density
        self.activeBlocks = activeBlocks
        self.heightBias = heightBias
        baselineShowsAdvanced = showsAdvanced
        baselineDensity = density
        baselineActiveBlocks = activeBlocks
        baselineHeightBias = heightBias
    }

    func visibleNoteCount() -> Int {
        min(notes.count, max(2, Int(round(2 + Double(heightBias * 2.8)))))
    }

    func randomizeHeightBias() {
        heightBias = CGFloat.random(in: 0.75...1.95)
    }

    func resetState() {
        showsAdvanced = baselineShowsAdvanced
        density = baselineDensity
        activeBlocks = baselineActiveBlocks
        heightBias = baselineHeightBias
    }
}

enum DemoCellFactory {
    static func makeCells(count: Int) -> [AnyDemoCell] {
        var generator = SeededGenerator(seed: 0xD1CE_CAFE)
        return (0..<count).map { index in
            let kind = Int.random(in: 0..<4, using: &generator)

            switch kind {
            case 0:
                return makeTextCell(index: index, generator: &generator)
            case 1:
                return makeDisclosureCell(index: index, generator: &generator)
            case 2:
                return makeMetricsCell(index: index, generator: &generator)
            default:
                return makeControlsCell(index: index, generator: &generator)
            }
        }
    }

    private static func makeTextCell<G: RandomNumberGenerator>(index: Int, generator: inout G) -> AnyDemoCell {
        let accent = DemoPalette.colors.randomElement(using: &generator) ?? .systemBlue
        let title = "\(randomWord(using: &generator).capitalized) \(randomWord(using: &generator).capitalized) \(index + 1)"
        let body = randomParagraph(sentenceCount: Int.random(in: 3...6, using: &generator), generator: &generator)
        let label = "\(randomWord(using: &generator).uppercased()) / \(Int.random(in: 2...12, using: &generator))"
        let tags = (0..<3).map { _ in randomWord(using: &generator).capitalized }
        let footer = "\(Int.random(in: 2...14, using: &generator)) ms relayout budget"
        let state = TextCardState(
            accent: accent,
            label: label,
            title: title,
            body: body,
            tags: tags,
            footer: footer,
            heightBias: CGFloat.random(in: 0.85...1.75, using: &generator)
        )

        return AnyDemoCell(
            estimateHandler: { width, metrics in
                let usableWidth = max(width - (metrics.cardPadding * 2), 180)
                let titleHeight = estimatedTextHeight(
                    characters: state.title.count,
                    width: usableWidth,
                    fontSize: metrics.titleSize,
                    lineHeight: metrics.lineHeight(for: metrics.titleSize, multiplier: 1.22)
                )
                let bodyHeight = CGFloat(state.bodyLineLimit(metrics: metrics)) * metrics.lineHeight(for: metrics.bodySize)
                let total = (metrics.cardPadding * 2) + (metrics.cardSpacing * 3) + 24 + titleHeight + bodyHeight + 26
                return roundedHeight(total, metrics: metrics)
            },
            viewHandler: { context in
                AnyView(TextCardView(state: state, metrics: context.metrics))
            },
            randomizeHandler: {
                state.randomizeHeightBias()
            },
            resetHandler: {
                state.resetState()
            }
        )
    }

    private static func makeDisclosureCell<G: RandomNumberGenerator>(index: Int, generator: inout G) -> AnyDemoCell {
        let accent = DemoPalette.colors.randomElement(using: &generator) ?? .systemOrange
        let detailLines = (0..<Int.random(in: 4...8, using: &generator)).map { _ in
            randomSentence(wordCount: Int.random(in: 5...10, using: &generator), generator: &generator)
        }
        let footerChips = (0..<3).map { _ in randomWord(using: &generator).capitalized }
        let state = DisclosureCardState(
            accent: accent,
            title: "\(randomWord(using: &generator).capitalized) Disclosure \(index + 1)",
            summary: randomParagraph(sentenceCount: 2, generator: &generator),
            detailLines: detailLines,
            footerChips: footerChips,
            isExpanded: Bool.random(using: &generator),
            heightBias: CGFloat.random(in: 0.85...1.75, using: &generator)
        )

        return AnyDemoCell(
            estimateHandler: { width, metrics in
                let usableWidth = max(width - (metrics.cardPadding * 2), 180)
                let summaryHeight = estimatedTextHeight(
                    characters: state.summary.count,
                    width: usableWidth,
                    fontSize: metrics.bodySize,
                    lineHeight: metrics.lineHeight(for: metrics.bodySize)
                )
                let detailHeight = state.isExpanded
                    ? CGFloat(state.visibleDetailCount()) * (metrics.lineHeight(for: metrics.bodySize, multiplier: 1.25) + 6)
                    : 0
                let total = (metrics.cardPadding * 2) + (metrics.cardSpacing * 4) + 30 + summaryHeight + detailHeight + 30
                return roundedHeight(total, metrics: metrics)
            },
            viewHandler: { context in
                AnyView(DisclosureCardView(state: state, context: context))
            },
            randomizeHandler: {
                state.randomizeHeightBias()
            },
            resetHandler: {
                state.resetState()
            }
        )
    }

    private static func makeMetricsCell<G: RandomNumberGenerator>(index: Int, generator: inout G) -> AnyDemoCell {
        let accent = DemoPalette.colors.randomElement(using: &generator) ?? .systemGreen
        let metrics = [
            MetricSnapshot(label: "CPU", value: "\(Int.random(in: 14...92, using: &generator))%"),
            MetricSnapshot(label: "FPS", value: "\(Int.random(in: 38...120, using: &generator))"),
            MetricSnapshot(label: "MB", value: "\(Int.random(in: 120...980, using: &generator))")
        ]
        let trendBars = (0..<6).map { _ in Double.random(in: 0.25...0.95, using: &generator) }
        let state = MetricsCardState(
            accent: accent,
            title: "\(randomWord(using: &generator).capitalized) Cluster \(index + 1)",
            subtitle: randomSentence(wordCount: Int.random(in: 7...10, using: &generator), generator: &generator),
            metrics: metrics,
            completion: Double.random(in: 0.35...0.92, using: &generator),
            trendBars: trendBars,
            showsTrend: Bool.random(using: &generator),
            heightBias: CGFloat.random(in: 0.9...1.8, using: &generator)
        )

        return AnyDemoCell(
            estimateHandler: { _, metrics in
                let pillHeight = 58 + (metrics.heightScale * 14)
                let trendHeight = state.showsTrend
                    ? CGFloat(state.visibleTrendCount()) * (metrics.lineHeight(for: metrics.captionSize, multiplier: 1.15) + 8)
                    : 0
                let total = (metrics.cardPadding * 2) + (metrics.cardSpacing * 4) + 26 + pillHeight + trendHeight + 24
                return roundedHeight(total, metrics: metrics)
            },
            viewHandler: { context in
                AnyView(MetricsCardView(state: state, context: context))
            },
            randomizeHandler: {
                state.randomizeHeightBias()
            },
            resetHandler: {
                state.resetState()
            }
        )
    }

    private static func makeControlsCell<G: RandomNumberGenerator>(index: Int, generator: inout G) -> AnyDemoCell {
        let accent = DemoPalette.colors.randomElement(using: &generator) ?? .systemPink
        let notes = (0..<Int.random(in: 4...7, using: &generator)).map { _ in
            randomSentence(wordCount: Int.random(in: 4...9, using: &generator), generator: &generator)
        }
        let state = ControlsCardState(
            accent: accent,
            title: "\(randomWord(using: &generator).capitalized) Controls \(index + 1)",
            blurb: randomParagraph(sentenceCount: 2, generator: &generator),
            notes: notes,
            showsAdvanced: Bool.random(using: &generator),
            density: Double.random(in: 0.2...0.8, using: &generator),
            activeBlocks: Int.random(in: 2...8, using: &generator),
            heightBias: CGFloat.random(in: 0.8...1.9, using: &generator)
        )

        return AnyDemoCell(
            estimateHandler: { width, metrics in
                let usableWidth = max(width - (metrics.cardPadding * 2), 180)
                let blurbHeight = estimatedTextHeight(
                    characters: state.blurb.count,
                    width: usableWidth,
                    fontSize: metrics.bodySize,
                    lineHeight: metrics.lineHeight(for: metrics.bodySize)
                )
                let noteHeight = state.showsAdvanced
                    ? CGFloat(state.visibleNoteCount()) * (metrics.lineHeight(for: metrics.bodySize, multiplier: 1.2) + 4)
                    : 0
                let total = (metrics.cardPadding * 2) + (metrics.cardSpacing * 5) + 54 + blurbHeight + noteHeight + 28
                return roundedHeight(total, metrics: metrics)
            },
            viewHandler: { context in
                AnyView(ControlsCardView(state: state, context: context))
            },
            randomizeHandler: {
                state.randomizeHeightBias()
            },
            resetHandler: {
                state.resetState()
            }
        )
    }

    private static func randomParagraph<G: RandomNumberGenerator>(sentenceCount: Int, generator: inout G) -> String {
        (0..<sentenceCount)
            .map { _ in randomSentence(wordCount: Int.random(in: 8...14, using: &generator), generator: &generator) }
            .joined(separator: " ")
    }

    private static func randomSentence<G: RandomNumberGenerator>(wordCount: Int, generator: inout G) -> String {
        let words = (0..<wordCount).map { _ in randomWord(using: &generator) }
        return words.joined(separator: " ").capitalized + "."
    }

    private static func randomWord<G: RandomNumberGenerator>(using generator: inout G) -> String {
        DemoWordBank.words.randomElement(using: &generator) ?? "render"
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x1234_5678_9ABC_DEF0 : seed
    }

    mutating func next() -> UInt64 {
        state = 6364136223846793005 &* state &+ 1442695040888963407
        return state
    }
}

private enum DemoPalette {
    static let colors: [NSColor] = [
        .systemBlue,
        .systemGreen,
        .systemOrange,
        .systemPink,
        .systemPurple,
        .systemTeal,
        .systemIndigo
    ]
}

private enum DemoWordBank {
    static let words: [String] = [
        "adaptive", "anchor", "aperture", "artifact", "atlas", "baseline", "beacon", "buffer",
        "bundle", "cadence", "canvas", "cascade", "circuit", "cluster", "coast", "contour",
        "delta", "drift", "ember", "field", "finite", "fluent", "focus", "fuse",
        "glide", "harbor", "hinge", "index", "kernel", "latency", "ledger", "lumen",
        "matrix", "module", "nested", "offset", "orbit", "parcel", "path", "pivot",
        "plane", "prism", "pulse", "quartz", "raster", "region", "relay", "render",
        "ribbon", "signal", "spectrum", "stack", "stone", "stream", "tangent", "texture",
        "throttle", "vector", "viewport", "vivid", "wave", "window", "zenith"
    ]
}

private struct DemoCardSurface<Content: View>: View {
    let accent: Color
    let metrics: DemoLayoutMetrics
    @ViewBuilder let content: Content

    init(accent: Color, metrics: DemoLayoutMetrics, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.metrics = metrics
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            content
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .windowBackgroundColor),
                            accent.opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .stroke(accent.opacity(0.32), lineWidth: 1)
        )
    }
}

private struct CapsuleChip: View {
    let title: String
    let accent: Color
    let metrics: DemoLayoutMetrics

    var body: some View {
        Text(title)
            .font(metrics.chipFont)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(accent.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(accent.opacity(0.24), lineWidth: 1))
    }
}

private struct MetricPill: View {
    let snapshot: MetricSnapshot
    let accent: Color
    let metrics: DemoLayoutMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.label)
                .font(metrics.captionFont)
                .foregroundStyle(.secondary)
            Text(snapshot.value)
                .font(.system(size: metrics.titleSize + 2, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct BarRow: View {
    let label: String
    let value: Double
    let accent: Color
    let metrics: DemoLayoutMetrics

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(metrics.captionFont)
                .frame(width: 60, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(accent)
                        .frame(width: max(proxy.size.width * value, 10))
                }
            }
            .frame(height: 8)
            Text("\(Int(value * 100))")
                .font(metrics.captionFont)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .frame(height: metrics.lineHeight(for: metrics.captionSize, multiplier: 1.1) + 6)
    }
}

private struct TextCardView: View {
    let state: TextCardState
    let metrics: DemoLayoutMetrics

    var body: some View {
        let accent = Color(nsColor: state.accent)

        DemoCardSurface(accent: accent, metrics: metrics) {
            HStack(alignment: .top) {
                Label(state.label, systemImage: "text.alignleft")
                    .font(metrics.captionFont)
                    .foregroundStyle(accent)
                Spacer()
                Text(state.footer)
                    .font(metrics.captionFont)
                    .foregroundStyle(.secondary)
            }

            Text(state.title)
                .font(metrics.titleFont)
                .fixedSize(horizontal: false, vertical: true)

            Text(state.body)
                .font(metrics.bodyFont)
                .lineSpacing(metrics.lineSpacing)
                .foregroundStyle(.secondary)
                .lineLimit(state.bodyLineLimit(metrics: metrics))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(state.tags, id: \.self) { tag in
                    CapsuleChip(title: tag, accent: accent, metrics: metrics)
                }
            }
        }
    }
}

private struct DisclosureCardView: View {
    @ObservedObject var state: DisclosureCardState
    let context: DemoCellRenderContext

    var body: some View {
        let metrics = context.metrics
        let accent = Color(nsColor: state.accent)
        let expansionBinding = Binding(
            get: { state.isExpanded },
            set: { isExpanded in
                guard state.isExpanded != isExpanded else {
                    return
                }

                state.isExpanded = isExpanded
                context.invalidateLayout()
            }
        )

        DemoCardSurface(accent: accent, metrics: metrics) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title)
                        .font(metrics.titleFont)
                    Text("Expandable SwiftUI content hosted inside AppKit")
                        .font(metrics.captionFont)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Circle()
                    .fill(accent.opacity(0.18))
                    .overlay(Image(systemName: "chevron.down").foregroundStyle(accent))
                    .frame(width: 28, height: 28)
            }

            Text(state.summary)
                .font(metrics.bodyFont)
                .foregroundStyle(.secondary)
                .lineSpacing(metrics.lineSpacing)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup(isExpanded: expansionBinding) {
                VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                    ForEach(Array(state.detailLines.prefix(state.visibleDetailCount()).enumerated()), id: \.offset) { offset, line in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(accent)
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            Text(line)
                                .font(metrics.bodyFont)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, CGFloat(offset) * 2)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text(state.isExpanded ? "Collapse details" : "Expand details")
                    .font(metrics.captionFont)
                    .foregroundStyle(accent)
            }
            .accentColor(accent)

            HStack(spacing: 8) {
                ForEach(state.footerChips, id: \.self) { chip in
                    CapsuleChip(title: chip, accent: accent, metrics: metrics)
                }
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct MetricsCardView: View {
    @ObservedObject var state: MetricsCardState
    let context: DemoCellRenderContext

    var body: some View {
        let metrics = context.metrics
        let accent = Color(nsColor: state.accent)

        DemoCardSurface(accent: accent, metrics: metrics) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title)
                        .font(metrics.titleFont)
                    Text(state.subtitle)
                        .font(metrics.bodyFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(state.showsTrend ? "Hide Trend" : "Show Trend") {
                    state.showsTrend.toggle()
                    context.invalidateLayout()
                }
                .buttonStyle(.borderless)
                .font(metrics.captionFont)
                .foregroundStyle(accent)
            }

            HStack(spacing: 10) {
                ForEach(state.metrics) { snapshot in
                    MetricPill(snapshot: snapshot, accent: accent, metrics: metrics)
                }
            }

            ProgressView(value: state.completion)
                .tint(accent)

            if state.showsTrend {
                VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                    ForEach(Array(state.trendBars.prefix(state.visibleTrendCount()).enumerated()), id: \.offset) { index, value in
                        BarRow(
                            label: "Row \(index + 1)",
                            value: value,
                            accent: accent,
                            metrics: metrics
                        )
                    }
                }
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct ControlsCardView: View {
    @ObservedObject var state: ControlsCardState
    let context: DemoCellRenderContext

    var body: some View {
        let metrics = context.metrics
        let accent = Color(nsColor: state.accent)
        let advancedBinding = Binding(
            get: { state.showsAdvanced },
            set: { showsAdvanced in
                guard state.showsAdvanced != showsAdvanced else {
                    return
                }

                state.showsAdvanced = showsAdvanced
                context.invalidateLayout()
            }
        )

        DemoCardSurface(accent: accent, metrics: metrics) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title)
                        .font(metrics.titleFont)
                    Text(state.blurb)
                        .font(metrics.bodyFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(state.activeBlocks) blocks")
                        .font(metrics.captionFont)
                        .foregroundStyle(accent)
                    Stepper(value: $state.activeBlocks, in: 1...12) {
                        EmptyView()
                    }
                    .labelsHidden()
                }
            }

            Toggle("Show advanced controls", isOn: advancedBinding)
                .toggleStyle(.switch)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                Text("Density")
                    .font(metrics.captionFont)
                    .foregroundStyle(.secondary)
                Slider(value: $state.density, in: 0...1)
                    .accentColor(accent)
                Text("\(Int(state.density * 100))%")
                    .font(metrics.captionFont)
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .frame(width: 44, alignment: .trailing)
            }

            if state.showsAdvanced {
                VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                    ForEach(Array(state.notes.prefix(state.visibleNoteCount()).enumerated()), id: \.offset) { offset, note in
                        HStack(alignment: .top, spacing: 10) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(accent)
                                .frame(width: 10 + (CGFloat(offset) * 4), height: 10)
                                .padding(.top, 4)
                            Text(note)
                                .font(metrics.bodyFont)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private func estimatedTextHeight(characters: Int, width: CGFloat, fontSize: CGFloat, lineHeight: CGFloat) -> CGFloat {
    let estimatedCharactersPerLine = max(Int(width / max(fontSize * 0.57, 1)), 12)
    let lineCount = max(Int(ceil(Double(characters) / Double(estimatedCharactersPerLine))), 1)
    return CGFloat(lineCount) * lineHeight
}

private func roundedHeight(_ value: CGFloat, metrics: DemoLayoutMetrics) -> CGFloat {
    max(metrics.minimumHeight, ceil(value))
}
