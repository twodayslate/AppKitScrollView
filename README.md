# AppKitScrollView

`AppKitScrollView` is a macOS-first Swift package that wraps an `NSCollectionView` in a SwiftUI result-builder API.

It is meant for the cases where plain SwiftUI `ScrollView` or `List` are not enough:
- very large numbers of heterogeneous rows
- rows with dynamic height
- mixed content like text, disclosures, metrics, and custom controls
- AppKit-backed virtualization with SwiftUI-authored cells

The package keeps the row authoring model simple:

```swift
AppKitScrollView { context in
    Header()

    if messages.isEmpty {
        EmptyState()
    }

    ForEach(messages) { message in
        ChatBubble(message: message)
            .appKitScrollTarget(message.id)
    }

    Button("Jump to latest") {
        if let id = messages.last?.id {
            context.scrollTo(id, anchor: .bottom)
        }
    }
}
```

## What It Does

- Virtualizes arbitrary SwiftUI rows inside an `NSCollectionView`
- Flattens result-builder content, including `ForEach` and `if / else`, into collection rows
- Measures visible rows offscreen so dynamic-height content lays out correctly
- Preserves the viewport anchor during relayout so height changes do not throw the scroll position around
- Exposes a proxy-style context for scrolling and explicit relayout invalidation
- Provides a shared AppKit-backed text selection coordinator for selectable text across rows

## Requirements

- macOS 15+
- Xcode 16+ / Swift 6.0+

The package currently targets macOS 15 because the clean builder flattening API depends on `Group(subviews:)`.

## Installation

Until the first tagged release, add the package by branch:

```swift
dependencies: [
    .package(url: "https://github.com/twodayslate/AppKitScrollView", branch: "main")
]
```

Then add the product to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "AppKitScrollView", package: "AppKitScrollView")
    ]
)
```

## Usage

### Basic Builder

```swift
import AppKitScrollView
import SwiftUI

struct ContentView: View {
    let rows: [Row]

    var body: some View {
        AppKitScrollView { context in
            TitleRow()

            ForEach(rows) { row in
                RowView(row: row)
                    .appKitScrollTarget(row.id)
            }

            Button("Bottom") {
                context.scrollToBottom()
            }
        }
    }
}
```

### Height-Changing Rows

In normal SwiftUI usage you do not need to manually invalidate the layout. `AppKitScrollView` watches visible hosted rows for width-constrained height changes and automatically remeasures them when local state expands, collapses, or animates.

```swift
struct ExpandableRow: View {
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading) {
            Button(isExpanded ? "Collapse" : "Expand") {
                isExpanded.toggle()
            }

            if isExpanded {
                Text("More content")
            }
        }
    }
}
```

That covers common cases like:
- `DisclosureGroup`
- `if / else` branches
- animated show / hide sections
- wrapped text that reflows as the window resizes

Use:
- `scrollTo(_:anchor:)` for row-targeted scrolling
- `scrollToTop()` / `scrollToBottom()` for simple navigation
- `invalidateLayout()` only as an escape hatch for unusual cases where height changes come from something the host cannot observe directly
- `animateLayout(duration:)` only when you want to explicitly coordinate AppKit relayout timing with some custom animation behavior

### Text Selection

`AppKitScrollView` owns a shared Textual-style selection coordinator for every hosted row. Selection is opt in at the text-fragment level:

```swift
AppKitSelectableText(message.body)
    .appKitFont(.systemFont(ofSize: 15, weight: .medium))
    .foregroundStyle(.secondary)
    .appKitTextSelection(.enabled)
```

The modifier intentionally mirrors SwiftUI's `textSelection(_:)` shape, but it feeds the `AppKitScrollView` selection environment instead of SwiftUI's native per-view selection system. This matters for cross-card selection: the scroll view needs one shared selection owner, while individual text fragments only opt in and report their local text and layout information.

Use `.appKitTextSelection(.enabled)` on `AppKitSelectableText` fragments or other fragments that are built to cooperate with the `AppKitScrollView` selection model. Plain SwiftUI `Text` does not participate just because the modifier is present.

`AppKitScrollView` automatically installs the selection coordinator for its rows and assigns each top-level row an ordering base. When multiple selectable fragments live inside the same card, use `appKitTextSelectionOrder(_:)` to keep copy order deterministic within that card:

```swift
VStack(alignment: .leading) {
    AppKitSelectableText(summary)
        .appKitFont(.systemFont(ofSize: 15, weight: .medium))
        .foregroundStyle(.secondary)
        .appKitTextSelection(.enabled)

    AppKitSelectableText(details)
        .appKitFont(.systemFont(ofSize: 15, weight: .medium))
        .foregroundStyle(.secondary)
        .appKitTextSelection(.enabled)
        .appKitTextSelectionOrder(1)
}
```

Selectable fragments share one controller, so users can drag from text in one card into text in another card, copy the selected text with Command-C, and use Select All from the active selectable text view with Command-A or Control-A.

`AppKitSelectableText` supports SwiftUI-shaped call sites for selection, fixed sizing, and direct color styling through `.foregroundStyle(_:)` or `.foregroundColor(_:)`. It currently uses TextKit under the hood, so SwiftUI's opaque `Font` environment cannot be converted into `NSFont`; use `.appKitFont(_:)` when you need a specific AppKit font. A future implementation can move toward a `Text.Layout` collection model like Textual so more native SwiftUI text styling can participate directly.

If you need to use selectable fragments outside `AppKitScrollView`, install the same shared selection environment with `appKitSelectionContainer()`:

```swift
VStack(alignment: .leading) {
    AppKitSelectableText(title)
        .appKitTextSelection(.enabled)

    AppKitSelectableText(body)
        .appKitTextSelection(.enabled)
        .appKitTextSelectionOrder(1)
}
.appKitSelectionContainer()
```

## Example Project

The repository keeps the demo app in `Example/AppKitCollectionViewDemo.xcodeproj`. It exercises:

- 1000 heterogeneous rows
- `if / else` builder branches
- `ForEach` flattening
- dynamic disclosure and trend sections
- library-owned cross-card text selection
- aggressive resize and relayout behavior

Open the project and run the `AppKitCollectionViewDemo` scheme to inspect the behavior interactively.

The manual sign-off checklist lives in [`MANUAL_TEST_PLAN.md`](MANUAL_TEST_PLAN.md).

## CI

The GitHub Actions workflow at `.github/workflows/build.yml` runs:

- `swift build` for the package
- `xcodebuild` for `Example/AppKitCollectionViewDemo.xcodeproj`

That keeps the package surface and the example app from drifting apart.
