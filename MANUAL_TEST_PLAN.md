# AppKitScrollView Manual Test Plan

This document defines the manual sign-off required before `AppKitScrollView` can be called finished.

The goal is not just "looks okay once." The goal is:
- no overlaps
- no clipping
- no stale empty gaps after collapse
- no stale reused content
- no broken scroll anchoring
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
- the app becomes briefly unresponsive during basic scroll, toggle, or resize interactions

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
xcodebuild -project 'AppKitCollectionViewDemo.xcodeproj' -scheme 'AppKitCollectionViewDemo' -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
APPKIT_SCROLL_DEBUG_LAYOUT=1 APPKIT_SCROLL_AUTODEMO=1 AppKitCollectionViewDemo.app/Contents/MacOS/AppKitCollectionViewDemo
```

Validated from layout logs:

- Fixed `Animation Lab Trend` collapse returned to the configured `14` pt row gap.
- Fixed `Animation Lab Disclosure` collapse returned to the configured `14` pt row gap.
- Lower random trend row collapsed from expanded height to collapsed height with the following row visible at `nextGap=14`.
- Lower random disclosure row expanded and collapsed with neighboring rows visible at `nextGap=14`.

This is not a full manual sign-off. The remaining unchecked items below still need a human visual pass, especially continuous resize, full top-to-bottom scrolling, fast scrolling past the giant long-text row, and subjective animation/performance checks.

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
  Expected: the detail section disappears and the gap closes to the normal row spacing.
- [ ] Repeat disclosure expand/collapse 10 times.
  Expected: no extra dead space accumulates.
- [ ] Collapse a disclosure row when it is partially visible.
  Expected: no jump that hides unrelated content and no stale padding remains.
- [ ] Expand/collapse disclosure rows after a manual window resize.
  Expected: wrapped text and bullet layout remain correct.

### 4. Giant Long-Text Row

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

### 5. Scroll Correctness

- [ ] Slow-scroll from top to bottom through the entire dataset.
  Expected: no row overlap, clipping, or stale reused content.
- [ ] Fast-scroll from top to bottom.
  Expected: no obvious layout corruption while virtualization catches up.
- [ ] Scroll from bottom back to top.
  Expected: the same rows still look correct when revisited.
- [ ] Pause mid-scroll on random rows.
  Expected: the settled layout is correct after motion stops.

### 6. Window Resize / Reflow

- [ ] Drag the window to the minimum supported width.
  Expected: content reflows, nothing overlaps, nothing clips.
- [ ] Drag back to a wide width.
  Expected: rows shrink appropriately and do not leave stale empty bands behind.
- [ ] Resize continuously while the viewport contains:
  - a trend row
  - a disclosure row
  - the giant long-text row
  Expected: all three remain valid throughout the resize.
- [ ] Resize immediately after collapsing a row.
  Expected: the stale collapse gap does not reappear.

### 7. Builder Semantics

- [ ] Toggle the top `if / else` branch repeatedly.
  Expected: the builder flattening still produces correct row spacing.
- [ ] Use the `Top`, `Midpoint`, and `Bottom` navigation buttons.
  Expected: scroll targeting lands correctly and does not break layout.
- [ ] Use `Regenerate 1000 Rows`.
  Expected: the new dataset displays correctly with no stale heights from the old dataset.
- [ ] After regeneration, repeat one trend toggle and one disclosure toggle.
  Expected: dynamic-height behavior still works on the new rows.

### 8. Reuse / Identity Regressions

- [ ] Expand a row, scroll it far offscreen, then return.
  Expected: the correct row is still expanded and its neighbors are correct.
- [ ] Collapse a row, scroll it far offscreen, then return.
  Expected: the old expanded gap does not return.
- [ ] Watch for any row showing another row's text, tags, or controls after aggressive scrolling.
  Expected: no stale reuse artifacts.

## Known Historical Regression Checklist

These regressions have already happened and must be rechecked every time:

- [ ] `Hide Trend -> Show Trend` causes overlap.
- [ ] `Show Trend -> Hide Trend` leaves a gap larger than the row spacing.
- [ ] Disclosure collapse leaves stale empty space.
- [ ] Expanding a row clips the next row.
- [ ] First launch shows clipped or partially measured rows near the top.
- [ ] Scrolling past the giant long-text row causes broken heights in the next rows.
- [ ] The collection leaves a large dead area at the bottom after content shrinks.
- [ ] Visible rows flash or redraw stale content during relayout.
- [ ] Manual window resizing stops behaving like real width-driven reflow.

## Performance / UX Checks

These are subjective but still blocking if clearly bad.

- [ ] No beachball during ordinary scrolling.
- [ ] No beachball during single-row expand/collapse.
- [ ] No beachball during normal window resize.
- [ ] Trend animation does not visibly snap at the end.
- [ ] Disclosure expansion does not flash the whole row.
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
