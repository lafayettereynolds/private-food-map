# Global Shell and State Layout Contract

## Root shell

- Root tabs stay `地图 / 发现 / 我的` in one bottom system tab bar.
- A floating product CTA may sit above the tab bar only when it is the approved
  action for that surface; it must clear the home indicator, tab items, and
  scrolling content.
- Content extends behind neither an unreadable navigation bar nor an opaque
  duplicate custom bar.
- Sheets use native dismissal/keyboard behavior. A sheet may have a compact
  custom content header, but must not nest redundant title bars.

## Core geometry

- Page horizontal inset: `TasteMapDesignTokens.Layout.pageInset` unless a
  full-bleed map/image is explicitly part of the template.
- Interactive hit target: at least 44 pt.
- Compact filter visible height: 34 pt, inside a 44 pt hit target.
- Primary tabs: equal width at normal Dynamic Type; horizontal scrolling is the
  permitted accessibility-size adaptation.
- Cards use the shared radius/border/elevation tokens; page-local magic numbers
  are permitted only for genuine hero, map, wheel, or poster geometry.

## Shared states

All formal empty/auth/error/insufficient states use `TasteMapEmptyState` or a
specialized shared derivative. A state contains:

1. one honest semantic or decorative visual;
2. a concise state title;
3. a distinct explanation;
4. at most one primary recovery action in the state itself;
5. secondary recovery outside the state only when it is genuinely separate.

Authentication, permission, no data, filtered-to-zero, offline cache, network
error, and insufficient analytics sample are different states and must not
share misleading copy. Loading uses progress/skeleton behavior, never a fake
empty record. A decorative Food/Dining image never claims measured data.

## Icons

- Functional icons must describe an action/value and have VoiceOver labels.
- Sibling controls either all use semantic icons or all omit them.
- Static city means `building.2`, never GPS.
- Familiar icon-only actions may omit visible text only with a 44 pt hit target.
- Formal artwork does not render raw system emoji; legacy emoji strings may be
  mapped internally to `FoodDiningVisualLibrary` kinds.

## Images

All Restaurant-facing media uses the canonical image renderer and priority:
local user photo → lawful public/cached photo → lawful provider image → honest
Food/Dining fallback. Image ratios are controlled by the consuming template;
the renderer owns source/fallback/loading/error behavior.

## Permitted iOS adaptation

NavigationStack, keyboard, native share sheet, system permissions, contextual
menus, swipe actions, and PhotosPicker may remain platform-native. They may not
reorder the product's information architecture.
