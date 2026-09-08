# Discovery filter correction

## Later correction — persistent state control and action footer

The removable 未去过 tag implementation below is superseded. Record state is
now a permanent dimension selector beside City, with All/Unvisited/Visited/Wanted;
selecting All retains the entrance and users can reselect Unvisited immediately.
Browser interaction tests cover this round trip at 375/402 light/dark.
DiscoveryQueryPanel and the legacy shared filter sheet reuse sticky-action-form:
only fields scroll; Reset/Cancel/Apply remain outside that scroller. Geometry
checks passed at 874px and 480px viewport heights, at top and bottom, with 44px
actions. Short viewport simulation does not claim physical keyboard acceptance.
Grid rows retain intrinsic content height, avoiding compressed field overlap.
Final staged assets: index-C9XCNxDC.js / index-DzfBtv4G.css.

- Selected condition chips, including 未去过, are direct children of the shared
  horizontal FilterBar. No second row; existing clear callbacks preserved.
- Full Discovery panel now has Reset / Cancel / Apply. Reset clears conditions,
  preferences and period/sort drafts, preserving the opening city. Cancel
  discards drafts; Apply commits. Location-pending reset is disabled.
- Browser inline check passed at 375/402, light/dark: same row, horizontal
  overflow, 44px targets and clearing. Query-panel draft/reset/cancel/apply
  integration passed. Typechecks and formal QA build passed.
- 26 resources match dist/stage/built/installed QA bundle. JS index-ClJw2XlV.js.
  The installed affected screen has not been independently UI-inspected in this
  checkpoint; browser screenshots establish shared-layout evidence only.
- Global audit: legacy Community has no matching selected-condition second row;
  Native rollback Discovery has no 未去过 chip group. No new duplicate owner.
- Design systems: Core reuses FilterBar/ModalShell; Food visuals unchanged;
  canonical first-row placement corrected. No default SwiftUI regression.
- No real-device installation or production deployment.
