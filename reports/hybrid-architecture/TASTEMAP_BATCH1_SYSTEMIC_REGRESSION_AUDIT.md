# Taste Map｜Batch 1 Systemic Hybrid Regression Audit

Date: 2026-09-03
Branch: `feature/hybrid-remaining-ui-batch`
Audit baseline: `277c5838b0fefa0403efbee074ac214ed77f09f3`
Scope: Batch 1 Product UI and read/presentation integration only. Batch 2 write migration, Production, StoreKit production configuration and App Store operations were not started.

## Executive result

Thirteen product surfaces were scanned as one system rather than as isolated screenshots:

1. My Map / My List
2. Profile
3. Restaurant Detail
4. Discovery
5. Community
6. Add Restaurant
7. Nearby
8. Lists
9. Roulette
10. Analytics
11. Posters
12. Premium
13. Settings

All objectively resolvable regressions found in the authorized Batch 1 scope were closed. No P0 cross-user leak, ownership bypass, destructive migration or data-loss path was found.

| Root-cause category | Findings | Surfaces affected | Fixed | Remaining |
| --- | ---: | --- | ---: | ---: |
| Duplicate Hybrid UI / page-fork risk | 7 renderer families | Discovery + Community; Add + Nearby; Lists; Roulette; Analytics + Posters; Premium; Settings | 7 | 0 |
| Capability hidden by migration state | 11 capability families | Profile, Restaurant Detail, Add, Lists, Premium, Settings | 11 | 0 |
| Missing exact Product Contract | 10 contract families | App Shell, Map, Discovery, Add, Restaurant Detail, Visit history, Profile, Lists, Analytics, Settings | 10 | 0 |
| Missing negative/forbidden contract | 13 forbidden-pattern families | Global | 13 | 0 |
| Browser/Capacitor joint Product regression | 3 shared-flow families | Discovery/Community, Add/Nearby, Settings handoff | 3 | 0 |
| Current-only capability loss risk | 12 capability families | Social, Premium, Same Taste, Sharing, Profile, Restaurant, Visit, Lists, Analytics, Account, WantToGo, Sync/Backup/Import | 12 | 0 |
| Shared component / shell root cause | 7 shared roots | App Shell, navigation, Discovery, acquisition, Restaurant Detail, Profile, Settings | 7 | 0 |

The counts above are root-cause/contract-family counts, not repeated DOM occurrences. One shared fix may close multiple surfaces; this is intentional.

## A. Duplicate Hybrid UI

### Findings

| Family | Evidence before closure | Root cause | Fix | Regression proof |
| --- | --- | --- | --- | --- |
| Discovery / Community | `HybridDiscoveryPage` and `CommunityPage` owned parallel page anatomy and card geometry | platform route was treated as permission to redraw the page | both consume `TasteMapDiscoveryScaffold`, `TasteMapFilterBar`, and `TasteMapActivityCardFrame`; Hybrid remains a thin DTO/action adapter | `HybridGlobalProductContract.test.ts`; `HybridRemainingUIContract.test.tsx`; Browser and Capacitor screenshots |
| Add Restaurant / Nearby | Browser modal and Hybrid page expressed acquisition hierarchy independently | Native provider boundary leaked into product layout | both consume `TasteMapRestaurantAcquisitionScaffold`; Search, Nearby, Share and Manual are one formal UI contract | exact acquisition contract and candidate-destination test |
| Lists | Hybrid shell previously handed off/placeholdered rather than owning the formal shared read UI | route status substituted for product implementation | Browser and Hybrid consume `TasteMapListsPage` | shared-renderer ownership test |
| Roulette | separate Native handoff prevented Browser/Capacitor Product parity | capability location was confused with page ownership | Browser and Hybrid consume the existing `RestaurantRoulette` renderer and preserve state | render contract + primary route UI E2E |
| Analytics / Posters | Hybrid placeholder/handoff did not expose the approved analysis family | page migration was treated as optional capability | Browser and Hybrid consume `TasteMapAnalyticsPage`; all five poster modes use `renderAnalysisPosterBlob` | analytics/poster tests and five screenshot families |
| Premium | Hybrid placeholder could not express active/free/unavailable states | StoreKit ownership was confused with paywall UI ownership | shared `TasteMapPremiumPage`; price/purchase remains typed Native handoff | entitlement-state render contract and Release fail-closed tests |
| Settings | Hybrid placeholder and legacy Browser modal diverged | tools remained Native, so UI hierarchy was omitted | shared `TasteMapSettingsPage`, typed Native handoff, and retired Drive controls removed from legacy modal | exact settings sections + no-Google-Drive negative contract |

Two files still use the `Hybrid…Page` name: `HybridDiscoveryPage.tsx` and `HybridAddRestaurantPage.tsx`. Source inspection and exact tests confirm that they contain only platform data/capability adapters; they do not define a second page skeleton, card system, FilterBar or acquisition layout. Retired duplicate page filenames are asserted absent.

## B. Capability hidden by migration state

Eleven capability families were missing, no-op or at risk of being hidden because their final writer/system provider remains Native:

| Capability | Formal Batch 1 behavior | Authority |
| --- | --- | --- |
| Edit Profile | visible entry → `profileEdit` typed handoff | Native session/profile service |
| Social connections | visible entry → `socialNative` typed handoff | Native auth/social service |
| Add provider search / Nearby / Share / Manual | visible shared acquisition UI → Native provider capability where required | Native location/provider adapter |
| Record Visit | visible Restaurant action → existing Native Visit editor | owner-scoped capability DTO |
| Edit Visit | exactly one entry for each editable Visit → `visitEdit` | `editableVisitIDs` from Native owner scope |
| Edit Restaurant | visible only when `canEditRestaurant` | Native capability DTO |
| Delete Restaurant | visible only when `canDeleteRestaurant` | Native capability DTO |
| Add to List | visible only when `canAddToList` | Native capability DTO and existing list service |
| WantToGo | visible only when `canAddToWantToGo` and viewer state allows it | Native capability DTO |
| Premium purchase / restore | visible UI → `premiumStore`; no fake price or fake success | StoreKit/server entitlement |
| Settings tools | Account, Backup/Import, Sync, permissions and storage remain visible → `settingsNative` | existing Native services |

React does not compare a Visit or Restaurant `userId` to infer authority. Public/cached Restaurant projections use an explicit public-readable capability set and cannot acquire edit/delete rights from provider identity.

## C. Exact Product Contracts

The following stable structures are now executable policy rather than presence-only assertions:

1. Bottom navigation is exactly `地图 / 发现 / 我的` and has length 3.
2. Add Restaurant has exactly one root primary entry: the Map floating `添加餐厅` CTA.
3. Map scopes are exactly `去过 / 想吃 / 推荐`.
4. Map/List switch is only the centered title + icon control; no segmented duplicate exists.
5. Discovery first-level tabs are exactly `关注 / 为你推荐 / 同味之选 / 最新 / 趋势`.
6. Activity rating is Visit/activity rating, never Restaurant aggregate rating.
7. Restaurant Detail owns one canonical body and locked section order.
8. Editable current-user Visit has exactly one edit entry; non-editable Visit has zero.
9. Add acquisition capabilities are exactly Search, Nearby, Share, Manual; candidate destination is canonical Restaurant Detail.
10. Profile, Lists, Analytics and Settings preserve their formal module/section topology.

Contract source: `src/hybrid/app/HybridProductContracts.ts`.
Long-term enforcement: `hybrid/tests/HybridGlobalProductContract.test.ts`, `hybrid/tests/HybridMapProductContract.test.ts`, route tests, platform tests, Swift capability/owner tests and UI E2E.

## D. Negative / forbidden contracts

Automated tests now reject:

- Add as a fourth bottom tab;
- multiple root Add Restaurant entries;
- the retired label `适合你`;
- numeric or food-count Restaurant clusters;
- default marker offset/spiderfy/dispersion;
- raw emoji formal markers;
- an extra Map/List segmented row;
- paste-link as the primary acquisition flow;
- aggregate Restaurant rating used as Activity rating;
- a second Restaurant Detail renderer;
- production no-op callbacks hiding formal actions;
- JavaScript ownership inference by user-ID comparison;
- route-registry-to-bottom-tab generation;
- retired Google Drive controls reappearing through either formal Settings surface.

## E. Browser and Capacitor jointly incorrect

Three shared-flow regressions required Product correction before platform equality could count as parity:

1. **Discovery / Community:** the page hierarchy and activity semantics were not the approved five-tab, Visit-rating contract. The formal Web page and Hybrid adapter were both moved onto one corrected scaffold.
2. **Add Restaurant / Nearby:** page density and capability hierarchy did not express Search/Nearby/Share/Manual as one compact flow. The corrected acquisition scaffold is now shared by Browser and Capacitor.
3. **Settings handoff:** the new shared Settings topology was correct, but Browser could still enter a legacy modal exposing the explicitly retired Google Drive UI. The control implementation was removed while provider-neutral photo abstractions and real Backup/Import/cache behavior were preserved.

`Browser == Capacitor` is now only the cross-platform gate; the Product Contract, reference, semantics and negative gates remain independent.

## F. Current-only capability protection

The audit explicitly retained all twelve protected capability families:

- Social and public profile routes;
- Premium status, paywall, purchase and restore entry;
- Same Taste content;
- system/public sharing;
- current Profile follower/following and visit/want/spend statistics;
- current Restaurant multi-provider identity and viewer state;
- complete optional Visit semantics;
- private/public/ranked List visibility;
- five current Analytics modes and five 9:16 posters;
- Account/security boundaries;
- WantToGo actions;
- Sync status, Backup Export and Import/Restore native flows.

No capability was removed because Legacy lacked it. Google Drive is excluded because Lafayette explicitly classified it as `RETIRE`; the provider abstractions and historical decoder compatibility were not deleted.

## G. Shared roots corrected

1. `HybridAppShell`: exact bottom navigation, route/UI separation, no no-op callbacks, shared page routing and detail refetch.
2. `TasteMapBottomNavigation` / `HYBRID_BOTTOM_NAVIGATION`: exactly three primary destinations.
3. `TasteMapDiscoveryScaffold` + `TasteMapFilterBar` + `TasteMapActivityCardFrame`: one formal Discovery/Community hierarchy and Visit-rating semantics.
4. `TasteMapRestaurantAcquisitionScaffold`: one Search/Nearby/Share/Manual hierarchy.
5. `RestaurantPreviewCard`: canonical Detail body plus owner-capability-driven Visit edit/action rows.
6. `ProfilePage`: real Hybrid callbacks for Edit, Social, Lists, Roulette, Analytics and Settings.
7. `TasteMapSettingsPage` + `SettingsModal`: formal sections, typed handoff and retired Drive UI prevention.

## Discovery regression inventory

| Current regression | Expected | Evidence | Root cause | Classification | Auto-fix |
| --- | --- | --- | --- | --- | --- |
| parallel Browser/Hybrid page anatomy | one shared formal five-tab page | formal Web, Product Rules, Browser/Capacitor comparison | route-specific redraw | One React UI | shared scaffold/card/filter components |
| hierarchy not locked to five tabs | exact approved order | Product Rules and Historical/Lafayette reference | presence-only tests | Product Contract | exact tuple and order test |
| activity score could drift toward Restaurant summary score | Visit/activity rating | Community DTO and design contract | semantic shortcut | Function/Semantic | explicit `activityRating`/`visitRating`; negative aggregate-rating test |
| current actions at risk during read migration | Like, Comment, More/Share, Restaurant actions remain visible | current Web behavior | migration-state capability loss | Current-only protection | shared Activity Card and typed action adapter |

## Add Restaurant regression inventory

| Current regression | Expected | Evidence | Root cause | Classification | Auto-fix |
| --- | --- | --- | --- | --- | --- |
| parallel Hybrid acquisition layout | one shared compact React flow | formal Web, Product Rules | Native provider boundary leaked into layout | One React UI | shared acquisition scaffold |
| primary hierarchy incomplete/oversized | Search, Nearby, Share, Manual all visible with high information density | latest Product Contract | capability migration treated as UI omission | Product Contract | exact four-capability contract |
| share could regress to paste-link primary | Share ingestion is a formal secondary path, not a primary paste field | Product Rules | old Web implementation residue | Forbidden pattern | no primary paste input test |
| Manual Add duplication risk | exactly one Manual entry | Product Rules | independent card/CTA implementations | Exact contract | one `manual` capability marker |
| Search/Nearby candidate could enter a minimal confirm fork | canonical Restaurant Detail | global Detail rule | provider result owned its own flow | Cross-entry consistency | Native candidate cache/projection → canonical Hybrid Detail |
| GPS/provider not fully available in Browser preview | honest unavailable/error state while UI remains complete | platform capability boundary | capability availability conflated with page topology | Function/Semantic | typed adapter and compact location state; no Product omission |

## Visit history edit contract

- Native returns `editableVisitIDs` from current-user owner scope.
- `RestaurantPreviewCard` renders exactly one edit control for each allowed Visit and none otherwise.
- the action opens the existing `VisitEditorView`; React does not write SwiftData.
- save dismisses the actual Native route, returns to the same canonical Hybrid Restaurant Detail, increments detail revision and refetches the official DTO.
- UI E2E proved the edited note appears without manual refresh and other-user Visits do not gain the action.

## Verification evidence

- TypeScript/Worker: 56 test files, 386 tests passed.
- Exact Hybrid Product Contract subset: 4 files, 32 tests passed.
- Hybrid platform/route package: 12 TypeScript + 6 Swift bridge tests passed.
- iOS full unit/integration: 65 suites, 638 tests passed.
- Key UI E2E passed:
  - shared Discovery Product/visual contract;
  - global Product navigation contract;
  - rich primary route interaction path (Discovery → Add → Profile → Lists → Roulette → Analytics → Settings);
  - owner-scoped Visit edit → Native editor → automatic Restaurant Detail refresh.
- Browser production build passed.
- Debug Simulator build passed.
- Release Simulator build passed.
- generic iOS device Release build passed with signing disabled for compile verification.
- formal Release binary scan passed: 36 App files and 16 signed Web files; no Debug fixture/switch, Development URL, local path, secret or React credential surface.

## Final seven gates

| Gate | Result | Basis |
| --- | --- | --- |
| PRODUCT CONTRACT | PASS | exact count/order/absence tests and UI E2E |
| ONE REACT UI | PASS | shared renderers; only thin platform adapters remain |
| CURRENT CAPABILITY PRESERVATION | PASS | typed handoffs and explicit capability DTOs |
| BROWSER ↔ CAPACITOR | PASS | same React/CSS plus mobile and fixed-Simulator evidence |
| REFERENCE PARITY | PASS for applicable surfaces | formal Web/current rules/Lafayette reference checked independently; non-referenced states are N/A |
| FUNCTION / SEMANTIC | PASS | DTO source, ownership, actions, return paths and refresh verified |
| NEGATIVE CONTRACT | PASS | 13 forbidden-pattern families enforced |

## Remaining boundary

There is no known objective Batch 1 Product/architecture regression left in the scanned scope. Lafayette still remains the authority for subjective visual approval (fine spacing, aesthetic preference and real-device perception); that manual approval is not represented as an automated visual PASS. Native write migration remains Batch 2 and was not started.
