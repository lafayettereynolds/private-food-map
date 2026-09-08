# Premium Gift — implementation and operations

Date: 2026-09-07. Repository: `private-food-map-hybrid-final-integration`.
Base: `feature/hybrid-final-integration`, `58bd556b8382734aeae1f08937ba649563682140`, with existing uncommitted product work preserved.

## Delivery boundary

Implemented locally, including real Worker/D1 integration tests, Native service tests,
and installed Simulator Hybrid/Native Gift UI tests. No production deployment,
remote database migration, real-user grant, physical-iPhone install, App Store product
change, or new StoreKit product was performed. Existing unrelated Worker deployment
holds still apply; do not deploy this entire dirty worktree without isolating the intended release.

## Model

Use the existing `membership_entitlements` and `membership_audit_log` tables.
Apply migration `0034_premium_gifts.sql` after all earlier migrations.

| Meaning / API field | Stored column | Rule |
| --- | --- | --- |
| entitlement ID | id | Unique Gift record, independent of app-store transaction IDs |
| userID / userId | user_id | Taste Map account ID, never device ID |
| source | source | New writes: app_store_monthly, app_store_annual, gift_annual, gift_lifetime |
| startedAt (startsAt compatibility alias) | starts_at | Server grant time; immutable for Gift |
| expiresAt | expires_at | Grant + one UTC calendar year; null only for lifetime Gift |
| grantedAt | created_at | Original grant time, immutable |
| grantedBy | created_by_user_id | Authenticated administrator, never accepted from request body |
| note | note | At most 160 characters; all changes retained in audit snapshots |
| status | status | active / revoked; expiry is evaluated by authoritative service |
| revokedAt / revokedBy | revoked_at / revoked_by_user_id | Soft revoke; retain the entitlement row |
| latest actor | updated_by_user_id | Added by this migration for transactional mutation auditing |

The migration normalizes existing app_store_yearly rows to app_store_annual; it does
not rename any product or change transaction records. Legacy admin_grant, promo,
redeem_code and app_store_lifetime rows remain readable and retain their original
terms. They are not creation options in the new Admin page. Old Native cached source
aliases also remain decodable. Roll out the compatible App before enabling new source
responses/grants for users of older clients.

Gift annual is a calendar year, not 365 days: 2028-02-29 12:34:56.789Z becomes
2029-02-28 12:34:56.789Z. Access uses startedAt <= now < expiresAt. Extension adds
one calendar year to max(now, expiresAt) while preserving original grant facts.
Lifetime cannot be extended or converted by an update; revoke and separately grant
if a different entitlement is intended. Revoked Gift cannot be resurrected by extension.

Every Gift INSERT/UPDATE writes audit via a database trigger in the same transaction.
If audit insertion fails, the entitlement write rolls back. Audit stores actor_user_id,
target_user_id, action (grant/extend/note/revoke), entitlement_id, before_json,
after_json, reason and created_at. The JSON snapshots explicitly contain userID,
source, startedAt, grantedAt, expiresAt, grantedBy, note and revokedAt. No audit is
rewritten when later operations occur. Query ordered by created_at for the target user.

## Entitlement precedence

Access is the union of valid records belonging to the authenticated user. Display
source precedence is gift_lifetime > gift_annual > valid App Store/legacy records.
Within the same precedence group, lifetime wins, then latest expiresAt, then stable ID.
Expiry/revoke removes only that record from consideration. An active Apple subscription
still unlocks Premium after all gifts are revoked; an expired/refunded Apple record
cannot remove an active Gift. StoreKit reconciliation only writes its own
app-store:<originalTransactionId> record.

`PremiumEntitlementService` remains the native authority. Hybrid receives state,
source, startedAt, expiresAt, statusText and canManageSubscription from its typed
platform bridge. React does not infer Premium from a cached user-profile tier. Gift
uses the existing feature registry and 20-photo allowance. Account changes reset
state and invalidate request generations, including A→B→A. Keychain remains user-scoped.
The original offline cache policy remains at most 7 days and never past annual expiry;
offline revocation cannot be instantaneous. Opening Premium refreshes authority.

## Admin operation

1. Apply migration 0034 to the intended environment after migration preflight; deploy
   only the reviewed Gift backend changes with all required prior schema changes.
2. Configure Worker `MEMBERSHIP_ADMIN_USER_IDS` with comma-separated real Taste Map
   userIDs. Existing `ADMIN_EMAILS` is accepted for compatibility; userID allowlisting
   is preferred. No default admin is created, and no credentials are committed.
3. Open `/internal/premium` on the same origin as that Worker. There is no entry in
   the consumer App. This first internal version accepts a current, valid Taste Map
   administrator Access Token; it does not create/issue a new login or expose Native
   credentials through React. Obtain the token through the existing internal auth
   workflow. It is kept only in page memory, not localStorage/cookies/URL, and cleared
   on exit/navigation. A future browser Sign in with Apple flow is not included.
4. Verify administrator identity, search by exact userID or nickname/email/city, select
   the target and double-check the displayed userID. Enter a note and select
   “赠送 Premium 1 年” or “赠送 Premium 永久”.
5. Existing records show source, status, start/expiry, grant actor, note and revocation.
   Annual offers “延长 1 年”. Both Gifts offer “保存备注” and “撤销 Gift”. Leaving the
   note blank during extension preserves it; explicitly saving a blank note clears it
   with an audit entry. Each successful operation re-reads authoritative membership.
6. “退出管理” clears the session and all results. Expired/revoked login or loss of admin
   permission clears the page state; API returns 401/403. Ordinary users cannot search
   or mutate, including by calling the endpoints directly.

API: GET/POST `/api/v1/admin/memberships`; old `/api/admin/memberships` is guarded by
the same real-session check. Bodies: grant {userId, source, note}, extend/note/revoke
{entitlementId, note}. Client-supplied actor identities are ignored. Development user
headers, localhost implicit identities and spoofed Cloudflare Access email headers
cannot authorize administration. The HTML uses a nonce CSP, no external scripts,
no-store responses and textContent for user-controlled content.

## Verification

Final result: 147 JS tests in 11 suites passed; 21 Native tests in 2 suites passed;
1 installed UI test with all 4 Gift/render combinations passed. Final Debug and
Release apps each matched all 26 staged Web resources byte-for-byte. The final
Release simulator app built successfully and passed the strengthened formal purity
scan (50 app files / 26 Web files), including explicit rejection of the development
Premium override symbols and internal Admin routes. No new runtime bypass exists
in that Release artifact. A signed physical-device archive/TestFlight run was not performed.

- JS/Worker coverage: Gift annual including leap-day/exact expiry; lifetime without
  transactions; grant/extend/note/revoke audit; audit failure rollback; real bearer
  authorization/403/forged-header rejection; user search; A/B isolation; App Store
  purchase/refund/repeated reconcile preserves both gifts; legacy contracts;
  feature policy, platform/Hybrid contracts and release-safety regression.
- Native: P4HPremiumEntitlementTests + Task08PremiumCommerceTests, 21 tests. Includes
  same feature access for both Gift types; empty/unavailable restore preserves Gift;
  revoke wins over cache; late A→B→A response cannot repopulate premium/cache.
- Installed UI: one test with four actual launches (annual/lifetime × Hybrid/Native),
  correct Gift copy and no management button. Simulator iPhone 17 Pro,
  E4F3EED9-89D8-405C-B4CB-7CA816CE3405, iOS 26.5. Synthetic records are explicit DEBUG
  Visual QA fixtures, not claims of a real production grant or real StoreKit purchase.
- Render identity: Hybrid launches use --tastemap-hybrid-development; Native launches
  omit it. TASTEMAP_VISUAL_QA_MODE=rich and TASTEMAP_P4H_PREMIUM_UI_TEST=giftAnnual or
  giftLifetime choose the isolated service fixture. Premium route opened via Settings
  (Hybrid) / approved Profile badge (Native); existing benefits/hamburger retained.
- Admin browser smoke uses `scripts/premium-gift-admin-smoke.mjs` with ephemeral
  SQLite and synthetic users, real production-route authentication and the actual
  server HTML. Search, annual, extension, notes, lifetime, revoke-to-annual and
  revoke-to-free were clicked and verified. No real account data is involved.
- Formal stage verifies dist/staged/built `.app` resources byte-for-byte. Release
  build and formal purity scan check that Debug overrides, development auth/URLs,
  fixture token and Admin implementation are absent from the App.

Evidence files: `/tmp/tastemap-gift-final.xcresult`,
`/tmp/tastemap-gift-all-js-tests.log`,
`/tmp/tastemap-gift-final-native.log`, `/tmp/tastemap-gift-final-release.log`,
`/tmp/tastemap-gift-core-tests.log`, `/tmp/tastemap-gift-regression.log`,
`/tmp/tastemap-gift-stage-final.log`. Initial four reviewed screenshots are exported
under `/tmp/tastemap-gift-screenshots/` with a manifest linking render names.
These local temporary logs may be removed by system cleanup; source tests are reproducible.

## Files touched by this task

- Backend: worker/index.ts, worker/membershipV1.ts, worker/appStoreCommerceV1.ts,
  worker/premiumAdminPage.ts, migrations/0034_premium_gifts.sql.
- Native: Services/PremiumEntitlementService.swift,
  Models/Remote/PremiumEntitlementContracts.swift, Features/Premium/PremiumViews.swift,
  Hybrid/TasteMapHybridRuntime.swift (all under ios/TasteMap/TasteMap).
- React/platform: src/platform/TasteMapPlatform.ts, TasteMapBrowserAdapter.ts;
  src/types/membership.ts; src/services/membershipPresentation.ts, membershipService.ts;
  src/components/TasteMapPremiumSettingsPages.tsx, MembershipAdminPanel.tsx.
- Tests/tools: worker/premiumGifts.integration.test.js,
  worker/appStoreCommerceV1.integration.test.ts, worker/membershipV1.test.ts,
  src/services/membershipPresentation.test.ts,
  ios/TasteMap/TasteMapTests/P4HPremiumEntitlementTests.swift,
  ios/TasteMap/TasteMapUITests/TasteMapUITests.swift,
  App/TasteMapUITestFixtures.swift and TasteMapApp.swift (DEBUG fixture routing only),
  hybrid/scripts/scan-formal-release-app.mjs, scripts/premium-gift-admin-smoke.mjs.
- Documentation: this guide, PREMIUM_PRODUCT.md, TASTEMAP_PRODUCT_DESIGN_RULES.md,
  TASTEMAP_HYBRID_ARCHITECTURE.md, TASTEMAP_HYBRID_MIGRATION_STATUS.md.
- Generated formal HybridRuntimeResources/public index and hashed assets were restaged.

## Design System Compliance

Core UI: retained existing consumer controls/spacing/styles. Food & Dining visuals:
approved hamburger and all existing benefit artwork retained. Canonical Page Templates:
unchanged except requested status text and manage-button capability. No new consumer
page duplicates or default-SwiftUI regressions were introduced. Internal Admin uses
a deliberately simple separate tool page, not an additional consumer Premium design.
Broader pre-existing Browser/Native presentation differences and unrelated visual
approval gates are outside this change. No physical-device or production acceptance
is implied by the local checks.
