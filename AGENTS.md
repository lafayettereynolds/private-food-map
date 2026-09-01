# Taste Map repository instructions

These rules apply to this repository and every directory below it.

## Mandatory UI / UX preflight

Before starting any product, UI, UX, layout, visual, accessibility, or design-system task, read `docs/TASTEMAP_PRODUCT_DESIGN_RULES.md` in full. Do this before editing code, generating a mockup, changing a test expectation, or judging a page as complete.

For every affected page, first identify which parts belong to:

1. Core UI System
2. Food & Dining Visual System
3. Canonical Page Templates

SwiftUI is the rendering and interaction framework; its defaults are not the Taste Map design system. The current iOS layout is not automatically a source of truth.

Compose product UI in this direction only:

`Canonical Page Template → Core UI Components/TasteMapDesignTokens + Food & Dining Visual Components → SwiftUI rendering`

Stable typography, spacing, radius, border, control, icon, avatar, image-ratio, and touch-target values belong to `TasteMapDesignTokens`. Do not introduce a page-local replacement scale for a concept already owned by those tokens. A page-specific composition value is acceptable only when its canonical template genuinely requires it.

## Product semantics before presentation

For parity work, always perform these steps in order:

1. Confirm the original Web/product behavior, data source, entry point, states, permissions, and return path.
2. Correct any functional or semantic migration bug.
3. Restore the approved layout and interaction using the shared design system and canonical template.

Do not classify a migrated functional error as a cosmetic difference. A page is not accepted merely because it opens or contains a similarly named feature.

## Product-rule authority and historical evidence

Use the complete Source of Truth order in `docs/TASTEMAP_PRODUCT_DESIGN_RULES.md`. The current SwiftUI layout may prove that a capability exists, but it is never promoted to layout authority merely because it is already implemented. Historical task files and acceptance reports are evidence snapshots, not active rules; when they disagree with the canonical rules, the explicit supersession registry in that document controls.

For any Legacy/Web comparison or restoration task, also read `docs/TASTEMAP_LEGACY_FUSION_DECISIONS.md` in full. Classify each proposal as `RESTORE`, `KEEP CURRENT`, `FUSE`, `RETIRE`, or `NEEDS LAFAYETTE APPROVAL`. Legacy evidence cannot by itself authorize deleting or downgrading a current feature, data field, interaction, Premium capability, Social capability, sharing capability, Analytics capability, or current architecture. Any such removal requires `NEEDS LAFAYETTE APPROVAL` before implementation.

The current Map Marker and Restaurant-image contracts are not discretionary page details. Marker presentation must follow the deterministic overlap/layer rule recorded in the canonical design document; Restaurant-facing images must use the shared priority policy and converge on its canonical renderer. A page-local offset, spiderfy, image resolver, or fallback variant is not an acceptable substitute.

## Global correction and shared-component rule

When a task exposes a UI/UX problem, never assume it is isolated to the screenshot or page that revealed it.

Before implementing the fix:

1. Search the entire iOS app for every implementation of the same pattern.
2. Identify the newest approved standard in `docs/TASTEMAP_PRODUCT_DESIGN_RULES.md` and the applicable canonical template.
3. Reuse or extend an existing shared component/template whenever possible.
4. If duplicate or conflicting implementations exist, consolidate them into one shared component/template rather than adding another local variant.
5. Update every affected screen in the authorized scope so the same class of defect is fixed consistently.
6. Add focused regression coverage that prevents individual screens from drifting back to one-off implementations.

Examples include filters, tabs, top bars, icon action rows, Restaurant images, activity cards, rating references, empty states, and Restaurant Detail. A fix to one of these requires a global usage audit.

## Long-term design decisions

When Lafayette confirms a new durable product or visual rule, update `docs/TASTEMAP_PRODUCT_DESIGN_RULES.md` in the same task after the implementation is validated. Include the decision, shared-component/template impact, and a Do Not Regress note when appropriate.

Do not leave a lasting design decision only in chat, a temporary report, a screenshot, or a one-off test. If the new decision conflicts with the document, Lafayette's latest explicit instruction wins and the document must be brought up to date.

## Acceptance requirements

UI acceptance must verify information architecture, section order, control placement and weight, image placement, horizontal/vertical relationships, spacing, density, shared-component reuse, accessibility, state coverage, and the applicable Web/approved reference—not only titles, buttons, build success, or test success.

Final UI/UX reports must include a Design System Compliance section covering Core UI, Food & Dining visuals, Canonical Page Templates, remaining duplicate components, default-SwiftUI visual regressions, and remaining design-system gaps.
