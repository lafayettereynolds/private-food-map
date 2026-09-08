# Premium catalog setup — 2026-09-08

## Scope and implementation

The reported failure was missing monthly/annual prices and purchase actions. StoreKitMembershipPurchaseProvider now loads the two formal public product IDs without depending on an authenticated Taste Map catalog request. Prices continue to use Product.displayPrice. TasteMap.xcscheme no longer overrides the App Store catalog with the unrelated dev.* StoreKit fixture; the QA scheme and Development fixture are preserved.

Before starting a new purchase, iOS reloads the authenticated server catalog and requires purchaseReady == true. The additive optional field fails closed on older servers. The Worker derives readiness from its existing required catalog, signing credential and environment checks; no private credential is returned. Readiness means configured, not proof of successful Apple authentication. Transaction verification and appAccountToken ownership remain required.

The shared Browser/Capacitor Premium page and Native rollback paywall put subscription actions before the long benefits/comparison sections and offer a reload action when products are unavailable. The existing Browser PremiumPaywall already has load/error/retry handling and a plan-first subscription flow. Share Extension has no subscription purchase UI. Existing preview consumers reuse these owners.

## Current operational limits

No new production Worker version was deployed. A targeted two-binding update was rejected by Cloudflare (10214): latest uploaded version differs from the deployed version. The attempted patch did not change production settings. Do not deploy the dirty working tree to resolve this; preserve the deployed version and prepare an isolated commerce update. The source returned by GET /workers/scripts/private-food-map is not sufficient evidence of the deployed version.

APP_STORE_ISSUER_ID, APP_STORE_KEY_ID and APP_STORE_PRIVATE_KEY still need to be configured after the account owner generates the In-App Purchase key. User confirmed the key does not yet exist. Receive only local .p8 path and identifiers; keep the key out of source, app resources and logs.

The current backend keeps Production and Sandbox verification strictly separated. TestFlight/Sandbox end-to-end verification remains an independent validation requirement and must not be claimed complete from a successful product query. No purchase or Apple charge was initiated during this task.

## Evidence

Evidence folder: build/premium-catalog.
- Worker commerce/membership: 14 tests passed (tests.log).
- iOS commerce: 7 tests passed (xcode-tests-final.log).
- UI topology/return contracts: 5 tests passed (ui-contracts-final.log).
- Real StoreKit response on the Simulator: formal annual and monthly products, US$11.99 and US$0.99. No hardcoded price fallback. This is not China-storefront proof; the user's App Store Connect screenshots show CNY80/year and CNY8/month.
- Debug and Release builds passed; each built app matches all 26 staged web resources. Release purity scan passed (54 app files, 26 web files).
- Native rollback was inspected using the same Debug app without the Hybrid launch argument: both real StoreKit prices and the purchase action appear before benefits (native-premium-final.png).
- Runtime inspection: React Hybrid, Debug app from build/DerivedData-Tests/Build/Products/Debug-iphonesimulator/TasteMap.app, iPhone 17 Pro E4F3EED9-89D8-405C-B4CB-7CA816CE3405. Launch --tastemap-hybrid-development, TASTEMAP_VISUAL_QA_MODE=free. Profile uses a Debug fixture; StoreKit product metadata is real. Route: 我的 → 开通 Premium. Fixture membership is not purchase verification.

## Design System Compliance

Core UI: existing cards/buttons, shared spacing and 44-point minimum target; plan name and renewal text are stacked with a separately aligned price. Food & Dining: existing approved hamburger retained. Canonical Page Templates: preserve the paywall and temporary return layer; move purchase actions forward within the user's requested discoverability scope. Remaining duplicate components: formal shared React page, legacy Browser paywall, and Native rollback retain their existing architecture and consume provider data. No default SwiftUI replacement style or new food asset was introduced. Remaining acceptance gaps: browser-host visual inspection, China storefront verification, credentials and production/Sandbox end-to-end transaction verification. Do not mark commerce release acceptance complete yet.
