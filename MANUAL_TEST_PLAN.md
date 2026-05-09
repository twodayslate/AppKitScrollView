# AppKitScrollView Manual Test Plan

This document defines the manual sign-off required before `AppKitScrollView` can be called finished.

The goal is not just "looks okay once." The goal is:
- no overlaps
- no clipping
- no stale empty gaps after collapse
- no stale reused content
- no broken scroll anchoring
- no broken append behavior when infinite scrolling loads more rows
- no broken cross-card text selection behavior
- no incorrect intermediate animation frames when inspected frame-by-frame
- no obvious jank or beachballing during normal interaction

## Exit Criteria

All blocking checks below must pass in:
- the example app in `Debug`
- the example app after a fresh relaunch
- a normal interactive run with manual window resizing

Do not call the work complete if any of the following still happens:
- a collapsed row leaves a gap larger than the configured row spacing
- an expanded row pushes its content into the next row
- a row clips its own content during or after relayout
- scrolling past the giant long-text row causes visible layout corruption
- row content flashes, duplicates, or shows stale reused state
- text selection cannot drag across selectable fragments in different rows
- independent selected ranges remain highlighted in two different text fragments after starting a new selection
- any expand/collapse animation has a bad intermediate frame, including clipped rounded corners, overdraw from a neighboring row, detached content, or a snap between row height and visible content
- the app becomes briefly unresponsive during basic scroll, toggle, or resize interactions
- loading more rows at the bottom clips visible content, resets existing dynamic row heights, or jumps to an unrelated position

## Test Setup

Use this setup before every serious verification pass:

1. Quit the demo app.
2. Relaunch from a clean state.
3. Start with a medium window size, then repeat key checks at:
   - minimum practical width
   - medium width
   - wide width
4. Test with:
   - top of list
   - middle of list
   - near the giant long-text row
   - bottom of list

If saved application state can influence layout, clear it before the pass.

## Current Validation Status

Targeted automated validation was run on 2026-04-23 with:

```sh
swift build
xcodebuild -project 'Example/AppKitCollectionViewDemo.xcodeproj' -scheme 'AppKitCollectionViewDemo' -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
APPKIT_SCROLL_DEBUG_LAYOUT=1 APPKIT_SCROLL_AUTODEMO=1 AppKitCollectionViewDemo.app/Contents/MacOS/AppKitCollectionViewDemo
```

Validated from layout logs:

- Fixed `Animation Lab Trend` collapse returned to the configured `14` pt row gap.
- Fixed `Animation Lab Disclosure` collapse returned to the configured `14` pt row gap.
- Lower random trend row collapsed from expanded height to collapsed height with the following row visible at `nextGap=14`.
- Lower random disclosure row expanded and collapsed with neighboring rows visible at `nextGap=14`.

This is not a full manual sign-off. The remaining unchecked items below still need a human visual pass, especially continuous resize, full top-to-bottom scrolling, fast scrolling past the giant long-text row, and subjective animation/performance checks.

Targeted resize regression validation was run on 2026-04-24 with:

```sh
swift build
xcodebuild -project 'Example/AppKitCollectionViewDemo.xcodeproj' -scheme 'AppKitCollectionViewDemo' -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
APPKIT_SCROLL_DEBUG_LAYOUT=1 APPKIT_SCROLL_AUTODEMO=1 APPKIT_SCROLL_AUTODEMO_RESIZE=1 AppKitCollectionViewDemo.app/Contents/MacOS/AppKitCollectionViewDemo
```

Validated from layout logs:

- Automated window narrowing/widening ran while dynamic rows were being measured.
- Trend and disclosure toggles still settled with visible neighboring rows at `nextGap=14`.
- No visible row-frame log showed a gap different from the configured `14` pt spacing.

Targeted rapid-toggle validation was run on 2026-05-03 with:

```sh
swift build
xcodebuild -project 'Example/AppKitCollectionViewDemo.xcodeproj' -scheme 'AppKitCollectionViewDemo' -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
APPKIT_SCROLL_DEBUG_LAYOUT=1 APPKIT_SCROLL_AUTODEMO=1 AppKitCollectionViewDemo.app/Contents/MacOS/AppKitCollectionViewDemo
```

Validated from layout logs:

- The fixed `Animation Lab Trend` row was toggled rapidly five times near the top of the list.
- During every measured animation frame, the surrounding visible rows stayed at the configured `14` pt row gap.
- The debug run specifically covered the regression where a same-identity SwiftUI update could reload visible AppKit items and briefly let a neighboring row paint over the rounded border.

Targeted disclosure animation validation was run on 2026-05-04 with:

```sh
swift build
xcodebuild -project 'Example/AppKitCollectionViewDemo.xcodeproj' -scheme 'AppKitCollectionViewDemo' -configuration Debug build CODE_SIGNING_ALLOWED=NO
screencapture -x -v -V 3 -m /tmp/disclosure-collapse-driven.mov
ffmpeg -y -i /tmp/disclosure-collapse-driven.mov -vf fps=24 /tmp/disclosure_frames_driven/frame_%03d.png
```

Validated from frame-by-frame inspection:

- The fixed `Animation Lab Disclosure` collapse kept rounded bottom corners throughout the close animation.
- The card did not draw into the next row during collapse.
- Neighboring rows moved with the collapsing row instead of snapping after the content animation.

This is targeted validation only. It does not replace the full manual sign-off below.

## Blocking Scenarios

These are the cases most likely to hide real regressions.

### 1. Fresh Launch Layout

- [ ] Launch the app and inspect the first visible screen before any interaction.
  Expected: no clipped cards, no overlapped rows, no giant vertical holes.
- [ ] Relaunch the app a second time and compare the first screen.
  Expected: same stable layout, no launch-only corruption.
- [ ] Toggle the `if / else` branch control near the top.
  Expected: the spotlight row swaps cleanly without collapsing neighboring rows into each other.

### 2. Trend Row Expand / Collapse

Use both the fixed `Animation Lab Trend` row and random trend rows lower in the list.

- [ ] Expand a collapsed trend row with fully visible neighbors above and below.
  Expected: the row grows without clipping or overlap.
- [ ] Collapse that same trend row.
  Expected: the extra space closes back to the normal row gap.
- [ ] Repeat `Show Trend -> Hide Trend` 10 times on the same row.
  Expected: no cumulative spacing drift.
- [ ] Rapidly click `Show Trend` / `Hide Trend` on the fixed `Animation Lab Trend` row.
  Expected: the row settles to the correct final state, the border remains complete, and no stale partial trend section remains mounted.
- [ ] Watch the fixed `Animation Lab Trend` row during the transition, not just after it settles.
  Expected: the top edge keeps rounded corners throughout the animation and is never clipped flat by the collection cell.
- [ ] Inspect frame-by-frame during rapid `Animation Lab Trend` toggles when possible.
  Expected: the previous row never paints over the trend row's top-left or top-right rounded border, even between measured height commits.
- [ ] Toggle a trend row while it is near the bottom edge of the viewport.
  Expected: the scroll anchor remains stable and the row does not get clipped.
- [ ] Toggle a trend row while it is near the top edge of the viewport.
  Expected: no jump that hides the row header or creates stale space.
- [ ] Toggle two neighboring trend rows one after another.
  Expected: no stale gap remains between them.
- [ ] Toggle a trend row after narrowing the window enough to force text reflow.
  Expected: the collapsed gap is still correct after wrapping changes.
- [ ] Toggle a trend row after widening the window again.
  Expected: the relaid out height is still correct and there is no leftover empty band.
- [ ] Scroll away from a toggled trend row and back.
  Expected: no stale reused content and no old expanded height resurrects.

### 3. Disclosure Row Expand / Collapse

Use both the fixed `Animation Lab Disclosure` row and random disclosure rows lower in the list.

- [ ] Expand a disclosure row with several bullet rows.
  Expected: bullets appear fully, with no clipping.
- [ ] Collapse that disclosure row.
  Expected: the detail section disappears, the gap closes to the normal row spacing, and the card keeps rounded bottom corners for the entire collapse animation.
- [ ] Repeat disclosure expand/collapse 10 times.
  Expected: no extra dead space accumulates.
- [ ] Collapse a disclosure row when it is partially visible.
  Expected: no jump that hides unrelated content and no stale padding remains.
- [ ] Expand/collapse disclosure rows after a manual window resize.
  Expected: wrapped text and bullet layout remain correct.

### 4. Frame-by-Frame Animation Inspection

Record short videos and inspect extracted frames for the fixed animation lab rows and at least two random dynamic rows lower in the list.

Recommended capture flow:

```sh
screencapture -x -v -V 3 -m /tmp/appkit-scroll-animation.mov
ffmpeg -y -i /tmp/appkit-scroll-animation.mov -vf fps=24 /tmp/appkit-scroll-animation-frames/frame_%03d.png
```

- [ ] Inspect `Animation Lab Disclosure` collapse frame-by-frame.
  Expected: the bottom-left and bottom-right card corners remain rounded in every intermediate frame; no frame shows a flat rectangular bottom edge.
- [ ] Inspect `Animation Lab Disclosure` expansion frame-by-frame.
  Expected: detail content, card height, and neighboring row movement stay synchronized; no detached content, flash, or sudden final snap.
- [ ] Inspect `Animation Lab Trend` collapse frame-by-frame.
  Expected: the top and bottom card borders remain complete, rounded corners are preserved, and the previous row never paints over the trend row.
- [ ] Inspect `Animation Lab Trend` expansion frame-by-frame.
  Expected: the trend section reveals smoothly while row height grows with it; no clipped chart, stale shadow, or overdraw into adjacent rows.
- [ ] Inspect a random disclosure row lower in the list frame-by-frame.
  Expected: behavior matches the fixed lab row, including correct row spacing during every frame.
- [ ] Inspect a random trend row lower in the list frame-by-frame.
  Expected: behavior matches the fixed lab row, including complete borders and no transient overlap.
- [ ] Inspect rapid toggles frame-by-frame.
  Expected: cancellation and reversal do not leave a partial animation state, stale mounted detail content, flat corners, or incorrect final height.
- [ ] Inspect animation while the row is partially visible at the top and bottom viewport edges.
  Expected: viewport clipping is expected only at the viewport edge; the card itself must not be internally clipped flat or draw outside its own rounded shape.
- [ ] Inspect animation after narrowing the window enough to rewrap text.
  Expected: all intermediate frames use the reflowed text height; no estimated-height flash appears.
- [ ] Compare frame timestamps or visually step consecutive frames.
  Expected: row movement is monotonic toward the target state; no frame jumps backward, freezes for a visible beat, or snaps at the end.

### 5. Giant Long-Text Row

This row is intentionally much taller than the viewport.

- [ ] Scroll into the giant text row from above at normal speed.
  Expected: no hitch that corrupts surrounding layout.
- [ ] Scroll through the middle of the giant text row.
  Expected: text remains readable and untruncated.
- [ ] Scroll past the bottom edge of the giant text row into the next few rows.
  Expected: the rows after the giant cell appear at the correct heights immediately.
- [ ] Flick-scroll quickly past the giant text row.
  Expected: no overlaps, no clipped cards, no rows collapsing to partial heights.
- [ ] Resize the window while the giant text row is onscreen.
  Expected: the text reflows correctly and the row height updates without broken spacing.
- [ ] Toggle a trend row directly below or above the giant text row.
  Expected: no special-case gap remains because of the giant row.

### 6. Scroll Correctness

- [ ] Slow-scroll from top to bottom through the entire dataset.
  Expected: no row overlap, clipping, or stale reused content.
- [ ] Fast-scroll from top to bottom.
  Expected: no obvious layout corruption while virtualization catches up.
- [ ] Scroll from bottom back to top.
  Expected: the same rows still look correct when revisited.
- [ ] Pause mid-scroll on random rows.
  Expected: the settled layout is correct after motion stops.

### 7. Window Resize / Reflow

- [ ] Drag the window to the minimum supported width.
  Expected: content reflows, nothing overlaps, nothing clips.
- [ ] Drag back to a wide width.
  Expected: rows shrink appropriately and do not leave stale empty bands behind.
- [ ] Scroll near the bottom of the list, stop on rows around `900...999`, then resize the window narrower and wider.
  Expected: visible rows keep their full measured height during reflow; no row falls back to an estimated height and clips its top or bottom content.
- [ ] Expand or collapse a trend/disclosure row near the bottom of the list, then immediately resize the window.
  Expected: dynamic-height rows remain fully visible and neighboring rows keep the normal row spacing.
- [ ] Resize continuously while the viewport contains:
  - a trend row
  - a disclosure row
  - the giant long-text row
  Expected: all three remain valid throughout the resize.
- [ ] Resize immediately after collapsing a row.
  Expected: the stale collapse gap does not reappear.

### 8. Builder Semantics

- [ ] Toggle the top `if / else` branch repeatedly.
  Expected: the builder flattening still produces correct row spacing.
- [ ] Use the `Top`, `Midpoint`, and `Bottom` navigation buttons.
  Expected: scroll targeting lands correctly and does not break layout.
- [ ] Use `Regenerate 1000 Rows`.
  Expected: the new dataset displays correctly with no stale heights from the old dataset.
- [ ] After regeneration, repeat one trend toggle and one disclosure toggle.
  Expected: dynamic-height behavior still works on the new rows.

### 9. Reuse / Identity Regressions

- [ ] Expand a row, scroll it far offscreen, then return.
  Expected: the correct row is still expanded and its neighbors are correct.
- [ ] Collapse a row, scroll it far offscreen, then return.
  Expected: the old expanded gap does not return.
- [ ] Watch for any row showing another row's text, tags, or controls after aggressive scrolling.
  Expected: no stale reuse artifacts.

### 10. Infinite Bottom Loading

- [ ] Scroll to the bottom sentinel and stop for at least 2 seconds.
  Expected: the loading row appears, waits, then appends another batch of rows.
- [ ] After the first append completes, continue scrolling to the new bottom and wait again.
  Expected: another batch appends; there is no fixed maximum row count.
- [ ] Confirm the overview count increases by the batch size after each append.
  Expected: row count changes from `1000` to `1250`, then `1500`, and so on.
- [ ] Expand/collapse a dynamic row, then scroll to the bottom and trigger a load.
  Expected: existing measured rows keep correct heights; no stale expanded/collapsed gaps are reintroduced.
- [ ] Press `Regenerate Rows` while the bottom loader is visible or actively waiting.
  Expected: the pending load is ignored, the list resets to the initial row count, and no old batch appends afterward.
- [ ] Resize the window after at least one load-more batch has appended.
  Expected: newly appended rows reflow like the original rows without clipping or overlap.

### 11. Text Selection

Use the fixed long-text card, the fixed animation lab cards, and random bubble/disclosure/trend rows.

- [ ] Hover over selectable text in a bubble row, disclosure summary, disclosure detail, trend subtitle, and the long-text card.
  Expected: the cursor changes to an I-beam only over selectable text.
- [ ] Hover over selectable detail text inside an expanded disclosure row, including the fixed `Animation Lab Disclosure` row.
  Expected: the cursor stays as an I-beam over the selectable detail text even though the text is inside the disclosure content.
- [ ] Hover over nonselectable text such as card titles, metric values, buttons, tags, and navigation controls.
  Expected: those areas do not show the I-beam cursor and do not begin text selection.
- [ ] Drag within a single `AppKitSelectableText` fragment.
  Expected: partial text highlights exactly the dragged range, including partial-word selection.
- [ ] Start a selection inside one selectable fragment and drag into another selectable fragment in the same card.
  Expected: the first fragment, any intermediate selectable fragments, and the destination fragment show one continuous ordered selection.
- [ ] Start a selection inside one card and drag into selectable text in another card.
  Expected: selection continues across cards; both endpoints can be partial selections.
- [ ] Start in a lower card and drag upward into an earlier card.
  Expected: reverse-direction selection works and copy order is still top-to-bottom.
- [ ] Start a selection in one card, release, then start a new selection in another card.
  Expected: the old highlight clears; two independent selected ranges must not remain at the same time.
- [ ] Select text in a long-text paragraph, then select text in a bubble row.
  Expected: only the bubble selection remains highlighted.
- [ ] Select text in a collapsed/expanded disclosure detail, then select text in a trend row.
  Expected: only the trend selection remains highlighted.
- [ ] Copy a single-fragment partial selection with Command-C.
  Expected: the pasteboard contains only the highlighted substring.
- [ ] Copy a multi-fragment selection spanning several paragraphs/details/cards.
  Expected: copied text is ordered by visual row order, then fragment order within the row, with no unrelated titles/tags/buttons included.
- [ ] Copy after dragging upward from a later row to an earlier row.
  Expected: copied text is still in document order, not drag direction.
- [ ] Press Command-A while focus is in selectable text.
  Expected: all currently registered selectable fragments in the scroll view are selected.
- [ ] Press Control-A while focus is in selectable text.
  Expected: same behavior as Command-A.
- [ ] Press Command-C after Select All.
  Expected: pasteboard includes selectable body text only, in document order.
- [ ] Press Command-A while focus is on a nonselectable control such as a button.
  Expected: the text-selection system does not unexpectedly select all text.
- [ ] Begin selection in selectable text, drag outside the current text fragment but not over another fragment, and release.
  Expected: the selection endpoint clamps to the nearest selectable fragment without crashing or leaving a stale partial range.
- [ ] Begin selection in selectable text and drag across a row gap between cards.
  Expected: selection remains continuous and does not flicker into multiple independent ranges.
- [ ] Begin selection near the bottom of the viewport and drag downward enough to scroll.
  Expected: selection remains stable; if autoscroll is not implemented, it must at least not corrupt existing highlights or crash.
- [ ] Resize the window after making a multi-row selection.
  Expected: selected ranges remain attached to the same text and redraw at the new wrapped positions.
- [ ] Expand or collapse a disclosure row while text is selected inside it.
  Expected: no crash, no stale highlight floating in the old location, and subsequent selection still works.
- [ ] Trigger `Regenerate 1000 Rows` after making a selection.
  Expected: old selection clears and no stale text from the previous dataset remains selectable or copyable.
- [ ] Scroll selected rows offscreen and back.
  Expected: no stale highlight appears on unrelated reused rows.
- [ ] Trigger infinite loading after making a selection near the bottom.
  Expected: existing selection state does not attach to newly appended rows.
- [ ] Select across text that includes punctuation, emoji, or long wrapped lines if present in generated content.
  Expected: character offsets stay correct and copied text does not drop or duplicate characters.
- [ ] Select from the first selectable fragment in a row to the last selectable fragment in the same row.
  Expected: `appKitTextSelectionOrder(_:)` produces deterministic copy order within that row.
- [ ] Drag selection across a selectable fragment whose view is partially visible at the viewport edge.
  Expected: endpoint calculation clamps correctly and does not select unrelated offscreen text.
- [ ] Attempt to select plain SwiftUI `Text` that has not been replaced with `AppKitSelectableText`.
  Expected: it does not participate in AppKitScrollView cross-card selection.

## Known Historical Regression Checklist

These regressions have already happened and must be rechecked every time:

- [ ] `Hide Trend -> Show Trend` causes overlap.
- [ ] `Show Trend -> Hide Trend` leaves a gap larger than the row spacing.
- [ ] Rapid trend toggles leave the `Animation Lab Trend` border clipped or the row in a partial animation state.
- [ ] The `Animation Lab Trend` top border turns flat during animation because the hosted SwiftUI root is vertically centered inside a shorter AppKit item.
- [ ] A same-ID SwiftUI update reloads visible AppKit items and lets the preceding row cover the `Animation Lab Trend` rounded border mid-animation.
- [ ] Disclosure collapse leaves stale empty space.
- [ ] Selectable disclosure detail text does not show the I-beam cursor.
- [ ] Native disclosure expand/collapse animation flashes, jumps, or visually detaches from neighboring row movement.
- [ ] Disclosure collapse clips the card bottom into a flat rectangular edge before the animation settles.
- [ ] Disclosure expansion or collapse moves in uneven visible steps because SwiftUI reveal frames and AppKit row-frame updates are out of cadence.
- [ ] Expanding a row clips the next row.
- [ ] First launch shows clipped or partially measured rows near the top.
- [ ] Scrolling past the giant long-text row causes broken heights in the next rows.
- [ ] Resizing near the bottom of the list causes visible rows to clip after wrapping changes.
- [ ] The collection leaves a large dead area at the bottom after content shrinks.
- [ ] Visible rows flash or redraw stale content during relayout.
- [ ] Manual window resizing stops behaving like real width-driven reflow.
- [ ] Appending rows for infinite scrolling clears existing measured heights and causes clipping or stale gaps.
- [ ] Starting a second text selection leaves the first selection highlighted in another card.
- [ ] Dragging from one selectable card into another fails to extend the selection across both cards.
- [ ] Command-C copies stale text from a previous selection.
- [ ] Command-A selects titles, tags, buttons, or other nonselectable SwiftUI `Text`.

## Performance / UX Checks

These are subjective but still blocking if clearly bad.

- [ ] No beachball during ordinary scrolling.
- [ ] No beachball during single-row expand/collapse.
- [ ] No beachball during normal window resize.
- [ ] Trend animation does not visibly snap at the end.
- [ ] Disclosure expansion does not flash the whole row.
- [ ] Disclosure expansion and collapse animate smoothly enough that neighboring rows move with the row instead of snapping after the content animation.
- [ ] Neighboring rows move smoothly enough that the interaction feels intentional, not broken.

## Release Sign-Off Summary

Before marking this project complete, record:

- build used for testing
- macOS version
- window widths tested
- whether the giant text row was exercised
- whether both fixed lab rows were exercised
- whether any remaining issue was observed even once

If any blocking item fails once, the release is not done.
