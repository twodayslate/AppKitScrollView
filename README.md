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

## Requirements

- macOS 15+
- Xcode 16+ / Swift 5.10+

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

## Example Project

The repository keeps the demo app in `AppKitCollectionViewDemo.xcodeproj`. It exercises:

- 1000 heterogeneous rows
- `if / else` builder branches
- `ForEach` flattening
- dynamic disclosure and trend sections
- aggressive resize and relayout behavior

Open the project and run the `AppKitCollectionViewDemo` scheme to inspect the behavior interactively.

The manual sign-off checklist lives in [`MANUAL_TEST_PLAN.md`](MANUAL_TEST_PLAN.md).

## Repository Layout

- `Package.swift`: Swift package definition
- `AppKitCollectionViewDemo/AppKitScrollView.swift`: public SwiftUI surface and AppKit host
- `AppKitCollectionViewDemo/HostedCollectionViewItem.swift`: reusable hosting item
- `AppKitCollectionViewDemo/VerticalListCollectionLayout.swift`: single-column collection layout
- `AppKitCollectionViewDemo/DemoCellMeasurer.swift`: offscreen SwiftUI measurement

The package and the demo app intentionally share the core implementation files so the example stays representative of the published package.

## CI

The GitHub Actions workflow at `.github/workflows/build.yml` runs:

- `swift build` for the package
- `xcodebuild` for the example project

That keeps the package surface and the example app from drifting apart.
