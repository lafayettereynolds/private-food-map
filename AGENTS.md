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

The current Map Marker and Restaurant-visual contracts are not discretionary page details. Marker presentation must follow the deterministic overlap/layer rule recorded in the canonical design document; Restaurant-facing visuals must use the shared, surface-aware `RestaurantUGCImagePool` / `RestaurantVisualResolution` policy and converge on the canonical renderer. A page-local offset, spiderfy, image resolver, provider-photo dependency, or fallback variant is not an acceptable substitute.

The formal Restaurant Visual Strategy is:

- Personal Map: current-owner marker/Restaurant/Visit photo, otherwise deterministic `FoodCategoryVisualID`; never another user's UGC.
- Add Search / Nearby / Restaurant Detail: current-owner photo, eligible public Taste Map UGC, otherwise the category visual.
- Following / Same Taste / Latest: the viewer-visible activity photo, then eligible public Restaurant UGC, then the category visual.
- For You / Trending: current-owner photo when present, then eligible public Restaurant UGC as visual material, then the category visual. The uploader is neither the recommendation author nor the trend source.

Other-user public UGC is in-app display material only unless a separate explicit export grant exists. It must not silently enter posters, downloads, backups, or external shares. Private/friends-only content never enters the public pool; deletion, visibility downgrade, account deletion, moderation disablement, unreadable resources, and viewer blocks must remove eligibility. Browser and Capacitor use the same React renderer and typed descriptor semantics; the iOS map remains a Native MapKit surface using the same source semantics.

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

This is an iron rule, not a best-effort suggestion. The screenshot that exposed a defect is only the first known consumer. Maintain an explicit inventory of every same-semantic consumer in React Browser UI, Capacitor UI, Native/SwiftUI rollback UI, extensions, previews, and accessibility labels that are inside the authorized scope. A task is incomplete if even one matching shipping surface still uses the superseded behavior. Fix the owning shared component or semantic primitive first, update every remaining legitimate consumer, and add both positive and forbidden-pattern coverage so the old variant cannot silently return.

## Runtime artifact truth gate (iron rule)

Never report a UI correction as complete from source diffs, unit tests, `dist`, or a successful compile alone. The artifact installed for Lafayette must be proven to contain the same implementation that was reviewed.

For formal Hybrid Taste Map builds:

1. Build and stage the formal bundle with `pnpm run hybrid:stage:formal`; `hybrid:sync:*` updates the internal Capacitor shell and is not a substitute for staging the formal `TasteMap.xcodeproj` resources.
2. Verify that `dist` and `ios/TasteMap/HybridRuntimeResources/public` are byte-for-byte current by running `pnpm run hybrid:verify:formal-stage` (the formal stage command must run this automatically).
3. After Xcode builds, verify the built `TasteMap.app/public` against the staged formal resources with `pnpm run hybrid:verify:formal-stage -- /absolute/path/to/TasteMap.app`.
4. Install that exact `.app` on the fixed Simulator or requested real device, launch it, and inspect the affected runtime surfaces. For a global semantic correction, inspect every representative surface named in the consumer inventory—not only the original screenshot.
5. If source, staged resources, built artifact, or installed runtime disagree, the task is `FAIL / STALE ARTIFACT`; do not claim that the user-visible issue is fixed.

Hashed asset-name changes are expected and must be staged in the formal resources. Never leave the repository with a new source implementation while the tracked formal bundle still points to an older asset hash.

### Preview renderer identity gate (iron rule)

Before showing Lafayette any Simulator screenshot or leaving a UI build open for manual review, prove that the installed app is rendering the intended product surface and runtime mode. A Hybrid review must launch the Hybrid root with the intended fixture/session; a Native rollback, fallback, UI-test fixture, or candidate renderer must never be presented as the current Hybrid result.

For every visual checkpoint:

1. Record the source branch/commit, built `.app`, launch arguments, environment, runtime mode, route, and renderer (`React Hybrid`, `Native MapKit surface`, or `Native rollback`).
2. Verify the page identity and the continued presence of unaffected contract-critical regions before asking Lafayette to review. For Restaurant Detail this includes, when data is present, ratings, photos, visit overview/history, business information, and downstream content—not only the modified action.
3. A narrowly scoped UI request may not change the page renderer, route ownership, runtime mode, canonical template, or unrelated regions unless Lafayette explicitly authorizes that expansion.
4. If the wrong renderer or fixture is installed, immediately classify the screenshot as invalid, restore the intended runtime, and do not use the mistaken screenshot as acceptance evidence.

This gate exists because changing only a launch mode can make correct data and sections appear to have been removed even when source data is intact. Build success and visual resemblance do not waive renderer-identity verification.

## Long-term design decisions

When Lafayette confirms a new durable product or visual rule, update `docs/TASTEMAP_PRODUCT_DESIGN_RULES.md` in the same task after the implementation is validated. Include the decision, shared-component/template impact, and a Do Not Regress note when appropriate.

Do not leave a lasting design decision only in chat, a temporary report, a screenshot, or a one-off test. If the new decision conflicts with the document, Lafayette's latest explicit instruction wins and the document must be brought up to date.

## Acceptance requirements

UI acceptance must verify information architecture, section order, control placement and weight, image placement, horizontal/vertical relationships, spacing, density, shared-component reuse, accessibility, state coverage, and the applicable Web/approved reference—not only titles, buttons, build success, or test success.

Visual quality is a product requirement, not optional polish. A functionally correct control still fails acceptance when its alignment, proportion, whitespace, grouping, hierarchy, or relationship to surrounding content visibly degrades the approved composition. For a narrow visual correction, preserve every unaffected region, compare before/after at the real target viewport, and verify both the local geometry and the full-page balance before presenting the result.

Final UI/UX reports must include a Design System Compliance section covering Core UI, Food & Dining visuals, Canonical Page Templates, remaining duplicate components, default-SwiftUI visual regressions, and remaining design-system gaps.

## Hybrid UI architecture (mandatory)

Taste Map's approved migration direction is one React product UI rendered in both the Browser and the iOS Capacitor shell, with native capabilities retained behind a typed platform boundary. Before changing a Hybrid route, read `docs/TASTEMAP_HYBRID_ARCHITECTURE.md` and `docs/TASTEMAP_HYBRID_MIGRATION_STATUS.md` in full in addition to the product design rules above.

The following rules are project-level constraints:

1. Product UI may depend only on `TasteMapPlatform`; it must not call Capacitor, Swift, Keychain, SwiftData, URLSession, StoreKit, Photos, Location, or iOS APIs directly.
2. Browser and Capacitor must render the same React component and page-template implementation. Do not create separate "Browser UI" and "iOS Web UI" forks.
3. Native calls use the versioned `TasteMapNative.v1` request/response envelope and capability registry. Never expose Apple tokens, refresh tokens, credentials, Keychain values, raw local file paths, SwiftData model objects, or unrestricted native method invocation to JavaScript.
4. The Browser adapter and Native adapter must preserve the same DTO semantics, UI states, image-priority policy, errors, and route contracts. Add contract tests whenever a method or DTO changes.
5. iOS Release UI assets must be signed local bundle resources. A production Capacitor `server.url`, remote UI dependency, development URL, test user header, fixture identity, debug route, or Premium/test bypass is forbidden.
6. Debug fixtures and preview routes must be both build-time gated and excluded from Release artifacts. A runtime-only flag is insufficient. Re-run the Release App binary/resource purity scan after changing build inputs.
7. `HYBRID_READY` does not mean `HYBRID_PRIMARY`. The current SwiftUI implementation remains the default production route and rollback path until Lafayette explicitly approves a route switch. Do not delete or retire it automatically.
8. Update `docs/TASTEMAP_HYBRID_MIGRATION_STATUS.md` in the same change whenever route ownership or readiness changes. Valid states are `NATIVE_PRIMARY`, `HYBRID_POC`, `HYBRID_READY`, `HYBRID_PRIMARY`, `NATIVE_ROLLBACK`, and `RETIRED_AFTER_MIGRATION`.
9. Profile and Restaurant Detail are the Phase 1 reference routes. All other routes remain native-primary until a separately authorized migration phase.
10. Native service queries must be current-user scoped. Bridge DTOs are lean, explicit, deterministic, and backward-compatible within their major version. Do not pass a database or network client through the bridge.

### Mandatory Hybrid Product Contract gate

`Browser == Capacitor` proves only cross-platform parity; it never proves that the shared UI is the correct product. Every Hybrid surface and every shared App Shell change must pass these gates independently:

1. `PRODUCT CONTRACT PASS`: the route, App Shell, navigation, global CTA, page hierarchy, labels, section order and data semantics match Lafayette's current approved product rules.
2. `ONE REACT UI PASS`: Browser and Capacitor consume the same formal React page/shared component; a platform adapter may not redraw the page hierarchy.
3. `CURRENT CAPABILITY PRESERVATION PASS`: a capability that remains Native stays visible through a typed handoff. Migration state is never permission to silently remove a formal capability.
4. `BROWSER ↔ CAPACITOR PARITY PASS`: both hosts render the same React component/CSS and equivalent state.
5. `VISUAL REFERENCE PASS`: every applicable Legacy, Lafayette or canonical reference is satisfied. Mark `NOT APPLICABLE` only when no controlling reference exists.
6. `FUNCTION / SEMANTIC PASS`: actions, data sources, states, return paths and error handling work; Native DTO capability fields remain the authority for ownership-sensitive UI.
7. `NEGATIVE CONTRACT PASS`: prohibited UI, semantic substitutions, duplicate routes/pages and no-op actions are absent.

Native data/security verification is mandatory inside the Function/Semantic gate and never becomes optional merely because the page is read-oriented.

Only when every applicable gate passes may a route be reported as `HYBRID_INTEGRATED / PASS`. Automated presence tests are insufficient: stable product topology must also have exact count/order assertions and negative/forbidden-pattern assertions.

Before declaring a Hybrid batch complete, scan the entire authorized route set for duplicate `HybridXXXPage`/`IOSXXXPage`/Capacitor-only layouts, `readOnly`/`disabled`/`unavailable`/no-op migration losses, route-to-tab coupling and Browser/Capacitor shared errors. Fix each repeated root cause in the shared component or typed adapter and add a regression contract; do not wait for Lafayette to rediscover each surface visually.

The route registry is not a bottom-navigation registry. The route registry may contain Map, Discovery, Add, Restaurant, Profile, Visit, Lists, Roulette, Analytics, Premium, Settings and deep-link surfaces. The exact primary bottom navigation is `地图 → 发现 → 我的`; Add Restaurant remains a route entered by the single Map-owned floating `添加餐厅` primary CTA and must never become a fourth bottom tab.

Any change to `HybridAppShell`, bottom navigation, root routes, global CTA or root tab composition must run the global Hybrid Product Contract suite in addition to route and bridge tests.

When a durable Hybrid architecture decision changes, update both Hybrid documents and add focused TypeScript/Swift contract coverage. Build success alone is not acceptance: verify Browser behavior, fixed-Simulator Capacitor behavior, back navigation, safe areas, offline local boot, structured error states, performance, and Release purity.

## Mandatory embedded-extension identity gate before device install / Final RC

Before installing any Taste Map build with extensions, run `scripts/verify-ios-embedded-identity.py` against the final signed `.app`, with the expected `--build`, `--bundle-id`, and (for a development device install) `--device-udid`. It must PASS for the main app and every embedded `.appex`; a main-app-only codesign check is insufficient. The gate checks plist identity/executable/versions, NSExtension, embedding, signing team, provisioning and entitlements/App Group compatibility. Unknown extension identifiers require an explicit audit before adding them to the allowlist.

Never pass `INFOPLIST_FILE` as a global xcodebuild override: it overrides extension targets too. Assign a custom identity plist only in the intended app target configuration. Never patch a signed artifact's plist after building. This extension gate supplements (does not replace) source/artifact fingerprint, renderer, resource parity and secret/purity gates. Device identity and actual renderer must be verified again after installation before smoke.
