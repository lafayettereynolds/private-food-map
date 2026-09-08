# Premium return context — 2026-09-08

## Correction

The former filter-paywall handler closed the filter sheet and navigated to a
standalone Premium route. Back could restore the map route, but not its dismissed
filter sheet. This has been superseded by a shared PremiumReturnLayer: opening
Premium from an existing Hybrid page does not replace that page or alter Native
history. The caller remains mounted, including nested sheets, draft and scroll.
The top-layer modal blocks background input. Back dismisses only the Premium
layer. Escape is contained so a parent editor is not accidentally cancelled.
The Native map is temporarily deactivated without resetting its browse state.

## Consumer audit

- Hybrid event-driven locks: filters, dish/visit photos, same-taste rating,
  analytics, profile, roulette and custom-avatar actions use the common handler.
- Hybrid explicit Premium actions in Profile / Settings use the same navigate
  interception, so the current settings subsection survives.
- Browser PremiumPaywallHost already uses a modal above its mounted caller;
  removing the filter-dismiss listener preserves its filter context too.
- Native rollback ContentView uses the existing presentedSource sheet; no
  hard-coded root return was introduced.
- Standalone/deep-linked Premium route keeps its ordinary route history.

## Verification

Three focused suites / eight tests passed, including no route-history mutation,
no filter-dismiss listener, modal Escape containment and existing history tests.
Formal stage and built QA app each passed 26-file byte identity verification.
DebugQA build succeeded and was installed for account 553453737518 in free mode
on iPhone 17 Pro E4F3EED9-89D8-405C-B4CB-7CA816CE3405. Branch
feature/hybrid-final-integration, base 58bd556; unrelated shared changes preserved.
Runtime launch: com.lafayette.tastemap.qa --tastemap-hybrid-development
-AppleInterfaceStyle Light, TASTEMAP_VISUAL_QA_MODE=free, React Hybrid / MapKit.

Interactive checks: selected a visit-count filter, scrolled to companions, opened
Premium and returned to the same filter position with the reset state retained.
Profile analysis → Premium → Back returned to the unchanged profile. Browser and
Native rollback modal lifetimes were inspected in source, not separately fully
runtime-certified. No subscription was purchased and no restaurant data edited.

## Design System Compliance

Core controls, Premium content and shared persistent Back remain unchanged;
PremiumReturnLayer owns only modal lifetime and top-layer composition. Food and
dining visuals are unchanged. The canonical Premium template is reused, not
recreated. Browser and Native rollback remain legitimate existing consumers;
no default SwiftUI replacement or new page-specific visual system was added.
