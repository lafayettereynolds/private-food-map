# Task 12 — StoreKit Local Automation + Entitlement Verification Hardening

Date: 2026-09-01
Branch: `fix/product-ux-correction-8-tasks`

## Outcome

Task 12 completed every safe, autonomous verification that does not require App Store Connect credentials or Production access. The existing StoreKit 2 purchase architecture, Worker reconciliation, owner isolation, idempotency, expiration/revocation behavior, and Release fail-closed behavior remain intact.

No App Store Connect product, subscription group, API key, `.p8`, Sandbox account, TestFlight build, Production Worker, Production D1, or Production secret was created or accessed.

## iOS StoreKit 2 architecture audit

`StoreKitMembershipPurchaseProvider` already provides:

- localized `Product.products(for:)` loading and `displayPrice`;
- purchase with the Worker-issued per-user `appAccountToken`;
- completed, pending, and user-cancelled results;
- `AppStore.sync()` restore;
- `Transaction.currentEntitlements` reconciliation;
- continuous `Transaction.updates` handling;
- verified-transaction-only reconciliation and finishing;
- activation isolation on Taste Map user switch and logout;
- Release fail-closed behavior when the Worker catalog is not configured.

The shared Xcode scheme now points to the existing Development-only `TasteMapDevelopment.storekit` fixture. Task 12 tests validate that the fixture contains only the localized monthly and annual Development products and no server credential material. Tests also validate that the unconfigured Release provider exposes no product or purchase/restore success.

## Local StoreKit automation limitation

Xcode 26.6 recognizes the StoreKit configuration in the shared scheme and the fixture is readable from the test target. On the fixed iOS 26.5 Simulator, however, `SKTestSession` transaction controls consistently return `SKInternalErrorDomain Code=3`; product loading consequently returns no local products. This persists with:

- the StoreKit configuration selected in the shared Run scheme;
- both `SKTestSession(contentsOf:)` and `SKTestSession(configurationFileNamed:)`;
- signed simulator test runs;
- serial, non-parallel execution on the fixed Simulator.

No failing or misleading transaction test was committed. Local purchase, renewal, Ask to Buy, billing-retry/grace, refund, and transaction-update automation therefore remains a **P2 toolchain/manual StoreKit Gate** for an Xcode/Simulator environment where Apple’s local StoreKit test service is available. The formal provider and Worker paths remain covered by deterministic abstraction and integration tests.

## Worker entitlement verification

The Worker verification path was re-audited and regression-tested:

- client submits only a numeric transaction identifier;
- Worker creates an authenticated App Store Server API JWT;
- Worker re-fetches the transaction from Apple’s Sandbox or Production endpoint according to explicit environment configuration;
- bundle ID, Product ID allowlist, StoreKit environment, transaction IDs, subscription type, dates, and `appAccountToken` are validated;
- `originalTransactionId` has a stable owner and cannot be claimed by another Taste Map user;
- `transaction_id` is idempotent;
- a stale transaction cannot regress a newer renewal;
- expiration, refund, and revocation remove Premium without deleting user data;
- notification UUIDs are deduplicated;
- an unknown `appAccountToken` is never linked to the first or arbitrary user;
- missing or unsafe catalog/server configuration fails closed.

## JWS / x5c defense-in-depth audit

The Worker decodes notification JWS only as routing evidence, then re-fetches the transaction through Apple’s authenticated App Store Server API before making any entitlement decision. This prevents a client-supplied or forged notification payload from directly granting Premium.

The returned `signedTransactionInfo` JWS is not yet independently verified against Apple’s `x5c` certificate chain. Implementing that without a vetted Apple trust-chain implementation and fixed official fixtures would risk fake cryptography, so no unsafe substitute was added. Independent `x5c` verification remains a **P2 Production defense-in-depth gate**. It is not the sole authorization boundary because authenticated Apple API re-fetch plus strict transaction validation remains mandatory.

## Automated results

- App Store commerce migration: **PASS**
- Worker App Store commerce / membership / auth: **17 passed**
- TypeScript application + Worker typecheck: **PASS**
- Vite production build: **PASS** (existing large-chunk warning only)
- iOS Task 12 configuration and fail-closed tests: **3 passed**
- iOS Task 08 commerce regression: **5 passed**
- iOS P4-H Premium entitlement regression: **12 passed**
- Debug Simulator build: **PASS**
- Release Simulator build: **PASS**
- Generic physical-device Release build: **PASS**

## Release binary purity

The Release device app and Share Extension were scanned. Results:

- no `.storekit` file in the Release bundle;
- no `dev.tastemap.storekit.*` Product ID in the app or extension executable;
- no `TASTEMAP_VISUAL_QA` switch;
- no fake entitlement or Premium bypass marker;
- no private-key marker or App Store server secret identifier/value;
- no development-test user header.

## Manual App Store gates

Lafayette must still complete, in App Store Connect / Apple-controlled environments:

1. create the real Subscription Group;
2. create and approve final monthly/yearly Product IDs;
3. set pricing, territories, localization, review metadata, and subscription terms;
4. provide Worker secrets through secure deployment configuration: Issuer ID, Key ID, and `.p8` private key;
5. configure App Store Server Notifications V2 to the final Production endpoint;
6. run Sandbox purchase, cancellation, pending, restore, renewal, expiration, refund/revoke, restart, and user-switch tests;
7. run TestFlight purchase and restore smoke tests;
8. complete the independent Apple `x5c` JWS verification gate before Production release.

## Classification

- P0: none
- P1: none
- P2: local `SKTestSession` transaction environment; independent Apple JWS `x5c` validation; real App Store Connect/Sandbox/TestFlight configuration
- P3: none

No Production system was accessed or modified.
