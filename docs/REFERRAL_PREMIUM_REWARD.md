# Referral Premium Reward — local implementation / rollout gate

Date: 2026-09-07. Repository: `private-food-map-hybrid-final-integration`, branch `feature/hybrid-final-integration`, baseline HEAD `58bd556`. Existing unrelated dirty changes were preserved. No production deployment, database migration, StoreKit product creation or actual reward grant was performed.

## Data model and invariants

Migration `0035_referral_rewards.sql` adds:

| Table | Meaning / key constraints |
| --- | --- |
| `referral_codes` | One random 96-bit hex code per Taste Map userID, unique across users. |
| `referrals` | Invitee userID primary key; immutable referrer/code/boundAt; self-invite CHECK; statuses pending/qualified/capped/revoked. Unique `(referrer_id, slot)`, slot 1…5. Revoked qualified slots remain occupied forever. |
| `premium_rewards` | One row per `(invitee_id, role)`, fixed 30/14 days, immutable ownership/duration/grantedAt, states pending/active/lifetime/revoked, startsAt/expiresAt/revokedAt, actor/note/change time. IDs `referral:<inviteeID>:referrer|invitee`. |
| `referral_audit_log` | Append-only actor/action/before/after/reason/time with invitation, user and reward references. Database triggers couple audit and mutation in the same transaction. |

`membership_entitlements` gains the source `referral_reward` through the existing open source field; no new StoreKit product is involved. Source is fixed-term, not auto-renewing. Premium limits/features remain unchanged.

Only the verified Apple **new-account creation** transaction accepts `referralCode`. Existing-account login ignores it. No public bind/claim/grant endpoint exists. Invalid registration codes reject before creating a user. Valid Visit means same-owner Visit + Restaurant, both not deleted, restaurant not test data, parseable visitedAt no later than server time. Rating and visibility are irrelevant. Qualification is one conditional SQL update with triggers, so reserving a lifetime slot, creating both rewards and auditing are atomic. Repeated sync, dashboard reads and concurrent requests cannot award again.

A sixth qualifying attempt becomes capped, with no reward on either side. Revocation does not free the slot or permit a different referrer. Deleting a Visit after it already qualified does not automatically revoke the award; an internal administrator can revoke fraud with a reason. This is account/identity-level idempotency, not a claim of real-world person/device-farm detection across different Apple accounts.

## Premium settlement and precedence

- Free user: reward starts at qualification, lasts exactly 30 or 14 UTC days.
- Existing Gift/Reward: independent intervals append after current finite non-Apple coverage. The authoritative projection shows the combined continuous end date; original Gift grant facts remain intact.
- Active Apple entitlement: reward stays pending. Repeated Apple renewals keep it pending; neither Apple transaction rows nor renewal/expiry dates are rewritten by referral code.
- When Apple ends, settlement anchors reward start at the recorded entitlement end (or revocation time), not the user's next app launch. A five-minute Worker scheduled handler plus on-read settlement creates the independent reward entitlement idempotently.
- Lifetime present at grant: ledger becomes lifetime, without a duration entitlement. Invitation and earned-day history still count; pending balance is zero for these entries.
- Active-source display precedence: gift_lifetime > gift_annual > App Store > reward/other. Access is the union. Apple display retains Apple dates; non-Apple continuous Reward intervals extend the displayed coverage end. App Store purchase/restore/refund never deletes Reward rows.
- Revoke: both sides' corresponding rewards are revoked; later unconsumed reward intervals compact forward and receive rescheduling audits. Consumed time is not recoverable. Gift/Apple rows are untouched.

Native uses `PremiumEntitlementService`, including refresh after successful sync; React consumes only its platform DTO. Invite hints do not grant access and are not cached as membership. Native checks response owner before rendering; auth-changed events clear React data and invalidate in-flight dashboard requests.

## User and administrator operation

User: 我的 → 设置 → 邀请好友. The page shows code/link, X/5, earned days, pending days, records and rules. 分享邀请链接 opens `UIActivityViewController` through the existing bridge or Native `ShareLink` (Browser uses its system-share capability where available).

New user: open `/invite/<code>` in the installed app before Apple registration, or enter the code in the invitation page while signed out, then return to 我的 to sign in. The Native hint lasts up to 24 hours in memory; after an app restart reopen the link or re-enter it. Registering first and entering a code later does not qualify.

API:

- `GET /api/v1/referrals` — real Bearer session required; ignores userID query overrides; no credentials or internal notes in the DTO.
- `POST /api/v1/admin/referrals/revoke` — real administrator session plus the existing `MEMBERSHIP_ADMIN_USER_IDS` / verified `ADMIN_EMAILS` allowlist. Body: `{ "inviteeID": "<Taste Map userID>", "note": "<required revocation reason>" }`. Idempotent; revokes the invitation and both associated rewards. Public/test identities and forged email headers cannot use it.
- Audit inspection: query `referral_audit_log` by `invitee_id` or `user_id` with the existing internal database access. This version adds an administrator API, not a new consumer-visible Admin page.

## Changed-file inventory

Backend/model: `migrations/0035_referral_rewards.sql`, `worker/referralsV1.ts`, `worker/referralLandingPage.ts`, `worker/authV1.ts`, `worker/index.ts`, `worker/membershipV1.ts`, `wrangler.jsonc`, `src/contracts/authV1.ts`, `src/contracts/referralsV1.ts`, `src/types/membership.ts`.

Shared UI/bridge: `src/components/TasteMapReferralPage.tsx`, `src/components/TasteMapPremiumSettingsPages.tsx`, `src/hybrid/app/HybridAppShell.tsx`, `src/platform/TasteMapPlatform.ts`, `src/platform/TasteMapNativeAdapter.ts`, `src/platform/TasteMapBrowserAdapter.ts`, `src/services/membershipPresentation.ts`.

Native: `Services/ReferralService.swift`, `Services/AuthAPIClient.swift`, `Services/AppleSignInService.swift`, `Services/NativeAuthServices.swift`, `Services/PremiumEntitlementAPIClient.swift`, `Models/Remote/PremiumEntitlementContracts.swift`, `Features/Settings/ReferralPremiumView.swift`, `Features/Settings/TasteMapSettingsView.swift`, `Features/Premium/PremiumViews.swift`, `ContentView.swift`, `App/RootTabView.swift`, `Hybrid/TasteMapHybridContracts.swift`, `Hybrid/TasteMapHybridBridgeDispatcher.swift`, `Hybrid/TasteMapHybridRuntime.swift`, `Hybrid/TasteMapHybridRootView.swift` under `ios/TasteMap/TasteMap`.

Tests: `worker/referralsV1.integration.test.js`, `worker/authV1.integration.test.js`, `worker/appStoreCommerceV1.integration.test.ts`, `src/services/membershipPresentation.test.ts`, `src/hybrid/app/HybridRemainingUIContract.test.tsx`, Native `ReferralRewardTests.swift`, auth mocks in `AuthSessionManagerTests.swift` / `Task06SocialCommunityTests.swift`, `TasteMapUITests.swift`.

Release/docs: `hybrid/scripts/scan-formal-release-app.mjs`, generated `ios/TasteMap/HybridRuntimeResources/public`, this report, `PREMIUM_PRODUCT.md`, product design rules and both Hybrid architecture/status documents.

## Verification

- 182 JS/Worker tests in 11 suites passed; 11 dedicated referral DB tests plus real Apple-registration/sync integration exercise qualification, race/replay, cap, Gift extension, Apple balance/renewal/end, lifetime, revoke/compaction, audit rollback, auth denial and A/B/A isolation. Apple verification/network inputs are test fixtures, not a real Sandbox purchase.
- 27 Native tests in four targeted suites passed, covering referral contracts/hints, authentication, authoritative Premium account isolation and StoreKit provider behavior.
- One XCUITest covers two installed renderers (React Hybrid and Native), correct 2/5, earned/pending days, return-to-Settings navigation and actual system Share Sheet. No message was sent to a recipient.
- Formal staging and built Debug/Release app resources match all 26 Web files byte-for-byte. Release Simulator build and purity scan passed (50 app files / 26 Web files). Referral QA data is compiled only under DEBUG, and new fixture markers are banned by the Release scan. No Release entitlement bypass was added.
- Browser formal preview was inspected for route rendering, honest no-session/error state and retry. Browser does not have a new real Apple sign-in flow; full reward operation is delivered through the authenticated iOS app.

Evidence: `/tmp/tastemap-referral-regressions.log`, `/tmp/tastemap-referral-verified.xcresult`, `/tmp/tastemap-referral-verified-native.log`, `/tmp/tastemap-referral-release.log`. Screenshots from the preceding successful identical-UI run are in `/tmp/tastemap-referral-final-screenshots/`; the final verification reran all 27 Native tests and the two-renderer UI test after adding the sync-completion refresh observer. Native/Hybrid screenshots and both system-share screenshots were visually inspected. Renderer identity: same Debug app, `--tastemap-hybrid-development` only for Hybrid; DEBUG visual-QA mode rich + referral fixture flag. Release uses NATIVE_PRIMARY, with no fixture flags. Final rebuilt Debug/Release resources and Release purity were reverified after the observer change.

## Design System Compliance

Core UI: shared Hybrid headers, Settings section/entry rows, page action and native Settings theme/row composition; no page-local typography/spacing scale or Premium redesign. Food & Dining imagery: not applicable. Canonical template: Settings index + detail, one entry after Membership Benefits; navigation remains 地图 → 发现 → 我的. Duplicate Browser/Capacitor page: none. Native is the required shipping primary/rollback consumer, not a competing Hybrid page. Native system navigation and Share Sheet retain their platform treatment. No unrelated frozen composition was changed.

## Production release gate — not yet executed

1. Confirm production API/invitation domain. Checked-in `APIEnvironment.plist` is empty and `TasteMapRelease.entitlements` has no Associated Domains. Development uses `api-dev.tastemap.cn`. Do not treat the QA screenshot domain as a configured production service.
2. Configure the real Release endpoint and matching `applinks:<confirmed-domain>`, validate signing/provisioning and serve the added AASA `/invite/*` component publicly. Manual code entry remains the installation fallback; no deferred-install tracking provider is introduced.
3. Apply migration 0035 to the intended database, then deploy this isolated Worker scope and the five-minute cron. The dirty workspace contains unrelated held changes: do not blindly deploy the entire current workspace.
4. Verify Apple Server Notification/reconciliation configuration so ended/renewed entitlement dates remain authoritative.
5. Run real-device Apple signup → first Visit → 30/14 reward, subscription-expiry transition and Universal Link acceptance. No physical-device archive, TestFlight, production grant or remote migration was claimed here.
