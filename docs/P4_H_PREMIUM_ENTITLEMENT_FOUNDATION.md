# P4-H — Premium entitlement foundation

更新时间：2026-08-29

## Scope and source of truth

P4-H adds the native iOS Premium entitlement, gating and Paywall foundation. It does not create App Store Connect products, choose prices, choose a final subscription/lifetime business model, call StoreKit, validate production transactions, or access Production D1/Worker. The existing Web product behavior and `PREMIUM_PRODUCT.md` remain the product source; iOS does not invent additional paid features.

Premium belongs to the authenticated `tm_...` Taste Map user. Apple `sub`, device identity, display name, a SwiftData Boolean and a global UserDefaults flag are never authorization sources. D1/Worker is authoritative; iOS keeps a short-lived, user-scoped Keychain cache only for offline continuity.

## Web → native audit matrix

| Capability | Web evidence | Web Free behavior | Web Premium behavior | Native before P4-H | P4-H result | Product confirmation |
| --- | --- | --- | --- | --- | --- | --- |
| Complete taste profile | `ProfilePage.tsx`, `featurePolicy.ts` | Gate/teaser | Full analysis | P4-A was directly accessible | Central gate + poster protection | Confirmed Premium |
| Companion analysis | `ProfilePage.tsx`, `featurePolicy.ts` | Recording remains available | Full private analysis | P4-B was directly accessible | Central gate + poster protection | Confirmed Premium |
| Recommendation-source analysis | `ProfilePage.tsx`, `featurePolicy.ts` | Recording remains available | Full analysis including “最坑推荐来源” | P4-C was directly accessible | Central gate + poster protection | Confirmed Premium |
| Similar Taste | `CommunityPage.tsx`, `featurePolicy.ts` | No similar-taste results | Similar-taste cards/ratings | P3-C was directly accessible | iOS gate + Worker 403 | Confirmed Premium |
| Deep recommendation | `CommunityPage.tsx`, `featurePolicy.ts` | One truthful basic reason | More complete explanations | Basic native Discovery existed | Registry + Worker Free redaction | Confirmed Premium |
| Advanced recommendation filters | `CommunityPage.tsx`, `featurePolicy.ts` | Basic discovery | Source/context/companion filters | Not yet present natively | Registry only; no fabricated UI | Confirmed Premium; native UI later |
| Monthly recap | `ProfilePage.tsx`, `featurePolicy.ts` | Teaser only | Full recap | P4-D was directly accessible | Central gate + poster protection | Confirmed Premium |
| Annual recap | `ProfilePage.tsx`, `featurePolicy.ts` | Teaser only | Full annual report | P4-E was directly accessible | Central gate + poster protection | Confirmed Premium |
| Spending insights | `featurePolicy.ts`, `PREMIUM_PRODUCT.md` | Core spend fields still recorded | Complete aggregate insight | Part of P4 reports | Registry; protected with its parent report | Confirmed Premium |
| Companion recommendation | `featurePolicy.ts` | Companion records remain usable | Companion-aware selection | No separate native feature | Registry only; no fabricated UI | Confirmed Premium; native UX later |
| Custom avatar | `ProfilePage.tsx`, `featurePolicy.ts` | All preset avatars | Upload a personal image | P3-A allowed picker | Picker gate + server profile mutation check | Confirmed Premium |
| Expanded Visit photos | `VisitPhotoPicker.tsx`, `featurePolicy.ts` | Add up to 3 new photos per Visit | Add up to 20 | Technical limit was 10 | Central 3/20 policy + server mutation check | Confirmed Premium |
| Restaurant / Visit / WantToGo | `PREMIUM_PRODUCT.md` | Fully usable | Fully usable | Implemented | Unchanged and never registered as Premium | Confirmed Free |
| Search / Restaurant Detail | `PREMIUM_PRODUCT.md` | Fully usable | Fully usable | Implemented | Unchanged | Confirmed Free |
| Dish/basic ratings/notes/context | `PREMIUM_PRODUCT.md` | Fully usable | Fully usable | Implemented | Unchanged | Confirmed Free |
| Profile basics/preset avatars | `PREMIUM_PRODUCT.md` | Fully usable | Fully usable | Implemented | Unchanged | Confirmed Free |
| Social/public profiles/community privacy | `PREMIUM_PRODUCT.md`, Worker privacy filters | Same privacy rules | Same privacy rules | Implemented | No authorization bypass | Confirmed Free |
| Ordinary restaurant lists | `PREMIUM_PRODUCT.md` | Fully usable | Fully usable | P4-F | Unchanged | Confirmed Free |
| “今天吃什么” roulette | no Premium key; P4-G contract | Fully usable | Fully usable | P4-G | Unchanged; no badge/gate | Confirmed Free |

The final StoreKit product IDs, price points, supported storefronts, subscription periods, free trial/introductory offer, family sharing behavior, and the final choice between recurring and lifetime products remain unconfirmed. P4-H models monthly, annual and lifetime neutrally but displays none unless a future StoreKit provider returns real products.

## Native architecture

- `PremiumEntitlementResponseV1` is the minimal authenticated JSON contract. It supports `free`, `active`, future `expired` and `grace_period`, a neutral kind, source, optional dates and server verification time.
- `MembershipStatus` represents `loading`, `unknown`, `free`, `premium`, `expired` and `gracePeriod`. Loading/unknown never briefly render a Free Paywall.
- `PremiumFeatureRegistry` is the single catalog of the 12 confirmed feature keys. `PremiumFeatureAccessPolicy` is the single operation/photo-limit policy.
- `PremiumEntitlementService` owns activation, server refresh, cache reconciliation, account switching, logout and Paywall presentation. Views never own HTTP or durable membership Booleans.
- `PremiumFeatureGate` covers page content and direct navigation. The five existing P4 analyzers are created only inside allowed content.
- `AnalysisPosterExportSheet` checks `posterRender`, `posterSave` and `posterShare`; hiding a toolbar button is not the protection boundary.
- `MembershipPurchaseProviding` abstracts products, purchase, restore and subscription management. The shipped provider is explicitly unconfigured and cannot return a fake success.

## API and D1

`GET /api/v1/me/entitlements` authenticates through the existing Taste Map session, derives the `tm_...` viewer on the Worker and ignores client-supplied `userId`. Its allowlisted response contains only:

- `apiVersion`, authenticated `userId`, `verifiedAt`;
- entitlement state, Boolean projection, source, neutral kind;
- optional start/expiry/update timestamps and lifetime flag.

It never returns admin notes, metadata, audit log, transaction identifiers, other users’ records, Apple subject or token material. Existing D1 migration `0010_membership_entitlements.sql` already supplies `membership_entitlements` and `membership_audit_log`, so P4-H adds no migration and does not modify an executed migration.

The Worker also applies server-side product checks to server-cost/private mutations:

- Free Similar Taste is rejected; Free “For You” remains available with one basic reason and no similar-taste projection.
- Sync V1 accepts no client `premium` field. The Worker reads the authenticated user’s effective entitlement.
- New custom-avatar assignment requires Premium. A previously assigned avatar remains stored/readable after downgrade.
- New active Visit photo metadata is limited to 3 for Free and 20 for Premium. Existing over-limit photos remain readable; no data is deleted on downgrade.

## Cache, offline, logout and devices

The cache uses Keychain service `com.lafayette.tastemap.premium-cache` with account `premium-v1:<tm_user_id>`, `ThisDeviceOnly`, and a maximum online-verification age of seven days. A recently verified Premium user can continue pure local analysis offline; a stale, malformed, expired or wrong-user cache becomes `unknown`, not Premium. Online Free/revoke always overrides cached Premium.

Logout clears active in-memory membership and any Development override. Cached entries remain keyed by their owner so the same user can recover offline on a later sign-in, while another user can never inherit the status. Multiple devices independently fetch the same server entitlement; revoke/expiry wins on their next online refresh. Premium expiry changes access only and never removes Restaurant, Visit, Photo, Dish, Companion, RecommendationSource, list, profile or social data.

## Paywall and Development safety

The native Paywall uses the Taste Map light canvas, brand blue, food colors, a small burger badge and food motif. It has a compact hero, six real benefits, Free/Premium comparison, entitlement status, product area and data-ownership note. It has no countdown, fake scarcity, hard-coded price, fake purchase or fake restore result. Dark Mode intentionally retains the complete light branded surface so white cards and text cannot become illegible; Dynamic Type and VoiceOver labels remain available.

Development override is compiled only under `DEBUG` and additionally requires `TasteMapAppEnvironment.development`. UI tests and previews may select Free/Premium. Release/Production has no override state, button or environment-variable path. Development API test identities stay subject to the existing Worker rule: `development-test` auth is rejected unless `APP_ENVIRONMENT=development`.

## Verification contract

P4-H tests cover contract validation; every registry key; Free/Premium/unknown; user-scoped cache; logout/account switching; recent/stale offline cache; online revoke; Development/Release isolation policy; every protected operation; 3/20 limits; unconfigured provider failures; multi-device refresh; authenticated API ownership; forged `userId`; response allowlist; Production Development-auth rejection; Similar Taste server enforcement; server photo/avatar enforcement; Free Paywall; no-products state; close/source context; direct navigation gate; Development upgrade; and Premium navigation without repeated Paywall.

P0–P4-G remain regression requirements. P4-H does not change Bundle Identifier, Team, signing, capabilities, auth/session contracts, sync identity, App Icon, existing migrations, Web UI or Production resources.

## StoreKit follow-up (not implemented)

Before real sales, product decisions and release work still require: the final subscription/lifetime decision; App Store Connect product IDs and localized pricing; terms/privacy URLs; StoreKit 2 product loading, purchase, restore and transaction-update handling; server transaction verification and signed App Store notifications; refund/revoke/renewal/grace handling; Sandbox/TestFlight multi-account tests; and Production entitlement deployment/migration preflight. None is represented as complete by P4-H.
