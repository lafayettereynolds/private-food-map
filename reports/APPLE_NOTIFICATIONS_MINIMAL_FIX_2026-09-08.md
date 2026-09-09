# Apple Notifications V2 — minimal fix and concurrent Production baseline change

CURRENT STATUS: dd0369b9-26c1-4fe7-a23b-9a56f5887661 is the user-confirmed CURRENT PRODUCTION BASELINE / PASS. 87b45679 is the previous verified baseline / rollback reference only. Notifications/Sandbox TEST/signature/UUID gates are PASS; malformed 400 JSON is valid. No minimal patch or further baseline confirmation is required. The diagnostic narrative below is historical evidence, not current deployment instructions. See PRODUCTION_BASELINE_ADOPTION_2026-09-08.md for the approved two-path real-device plan and remaining gates.

## Outcome

Real Apple Sandbox delivery, verified TEST audit and UUID replay **PASS on current Production `87b45679-2bc8-4f4b-b0a4-c82b65c155e9`**. This is **not** a claim that this task deployed its independent minimal candidate. Another window deployed a broader StoreKit integration during diagnosis. The independent candidate was not activated, and the other window's version was not rolled back.

The strict requested minimal-patch workflow remains incomplete: its locked baseline changed concurrently, and the new live version rejects malformed JWS with400 JSON, whereas this request explicitly specified401. The independent candidate passes that401 test. Do not overwrite the broader live version with the older baseline candidate without a new baseline decision.

## Root cause — established with the same real bytes

Original deployed module: `2d382c6d-5a51-4339-8fa4-df918348030a`, SHA256 `7139144c4761ebd47d3ab6839473f4768283274ff1b08f288c8e99bce983bf34`.

An independent detached worktree at source a39cdaaaefa333e602d219a001ac5d61057da2eb was reconstructed using only the previously published backend overlay and its locked dependencies. Its unpatched build reproduces that module hash exactly. No current frontend, native, Gift, Referral or Discovery changes were copied.

The original Worker verifier fails during Apple online OCSP transport with:

```text
VerificationException
status = 2 (RETRYABLE_VERIFICATION_FAILURE)
cause = TypeError
(0 , node_fetch_1.default) is not a function
```

Wrangler's node-fetch compatibility export is callable CommonJS but lacks the `.default` function expected by Apple's SDK. Native fetch Responses also lack SDK-required `buffer()`. The minimal adapter restores default export and binary buffer transport contracts, including timeout/failure propagation. Apple certificate/JWS/OCSP validation remains unchanged and online checks remain enabled.

Local Miniflare has a separate reproducible transport artifact: its default CF-Worker header contains `example.com`, causing Apple OCSP403. Adding that same header to the otherwise successful Node request reproduces403; using an actual domain returns200. The local test harness sets Miniflare's documented `dev.zone` to tastemap.cn. No production header spoofing or certificate-check bypass is in the patch.

Checks on the genuine fixture: alg ES256; no kid; x5c chain length3; DER certificates parse; certificate dates and adjacent issuer signatures pass; leaf EC curve prime256v1/P-256; signature64 bytes in IEEE P1363 format; original unmodified `base64url(header) + '.' + base64url(payload)` verifies with SHA256. Official Node verifier with Apple root and online checks passes. Workerd original bundle fails; patched full bundle passes.

The prior turn's payload was memory-only and could not be recovered from that terminated process. A new genuine Apple TEST was captured for this task and the same bytes used across the comparisons. Neither an unsigned synthetic fixture nor a reserialized payload was substituted.

## Independent files and fixture guard

Root: `/tmp/tastemap-notification-fix.d4XNwx/source`.

Shipping delta relative to the reproduced Production backend:

- worker/appleNotificationFetch.ts — SDK transport adapter; no diagnostic logging.
- worker/appleSignedData.ts — malformed payload parsing normalized to401.
- wrangler.jsonc — node-fetch alias; isolated verified asset directory; includes the already existing formal custom domain to avoid removing it (no new domain intended).

Test/operator files:

- worker/appleNotificationFetch.test.ts —3 transport cases.
- scripts/notification-runtime-regression.mjs —10 original/patched full-Workerd checks and tracked-file fixture guard.
- scripts/notification-private-test.mjs — official TEST request/status/capture/verification, no payload/token logging.
- scripts/notification-live-audit.mjs — exact UUID/digest audit correlation, replay and in-memory entitlement/reward state comparison.
- scripts/notification-preflight.mjs — version/module/binding/domain/route and28-asset evidence.
- worker/notificationRuntimeDiagnostic.ts and notification-diagnostic.jsonc — local-only diagnosis; not the Production entry point.

Private artifacts: `.private/apple-notifications/{baseline-signed-payload.json,signed-payload.json,test-token.json}`. Directory0700/files0600; existing .gitignore covers .private; git check-ignore PASS; tracked-file scan finds no real payload. Nothing was committed. Full JWS, tokens, certificates and keys are not in this report. Local test servers and remote preview session were stopped.

Candidate module hash: `f0d957654a722a2d7143478c9e39e3ceba5a5118efd940d6a6a255369d639d24`.

## Automated tests

- TypeScript worker check PASS after correcting the test mock's type annotation.
- Transport tests3/3 PASS: exact binary bytes, HTTP failure retained, network failure propagated.
- Full Workerd checks10/10 PASS: baseline401 reproduction, genuine TEST acceptance, same JWS duplicate handling, one-byte payload mutation, signature mutation, header mutation, certificate mutation, malformed401 JSON, unsigned rejection, exactly one notification audit.
- Local trusted decoded environment Sandbox/type TEST confirmed.
- No changes to SDK validation assertions; no TEST/Sandbox trust shortcut.

## Deployment concurrency and preflight

Preflight snapshot: `/tmp/tastemap-notification-fix.d4XNwx/preflight.json`; postflight snapshot: `postflight.json` in the same directory.28 public assets were fetched from the formal domain and compared with the established production hashes, not just page-load checked.

While this task was running, the other window deployed87b45679 at07:23:08 UTC with message `Deploy verified 4d5fe935 StoreKit integration with OCSP transport compatibility and verified App Apple ID; preserve 28 production assets`.

The final baseline check detected drift. A CLI publish command had started upload preparation and was interrupted; this task did not activate its minimal candidate. Final deployment readback remains87b45679 at100%, module hash `a3af88bf140f08d875c330efef1002b9852fa4a605f9a54d7748c322ae149f14`, different from this task's candidate. No rollback to2d382c6d was attempted because that would undo the other window's independently deployed work.

The active version now includes APP_STORE_APP_APPLE_ID=6804560641 and the environment-isolated notification schema from that broader integration. Active version bindings, rather than latest-upload draft settings, are used for final evidence. D1 database ID and R2 bucket are unchanged; three Apple secret names are unchanged. Logical routes/domains are unchanged, although route object IDs differ from the original preflight. This report does not claim the broader deployment was a minimal-only delta.

## Actual live acceptance on87b45679

- A **new official Apple Sandbox TEST request**, not local replay, returned a token; Apple's delivery status is **SUCCESS**.
- Official verifier confirms version2.0, environment Sandbox, type TEST, expected bundle.
- D1 app_store_notification_events_v2 has exactly one matching Sandbox UUID record, type TEST, disposition test and exact SHA256 payload digest.
- Subsequent replay returns HTTP200 and duplicate=true; matching audit remains byte-equivalent and singular.
- membership_entitlements, sandbox_membership_entitlements and premium_rewards were compared in memory before/after replay: identical row counts and state hashes. No user data was printed. TEST has no transaction and test disposition, not a reward/purchase effect.
- health200 exact JSON; ready200 all core checks true, optional admin remains non-blocking; unauthenticated sync401 JSON; malformed Admin Bearer401 JSON.
- Malformed Apple payload rejected400 JSON (not the requested401); no acceptance bypass. Original minimal candidate's malformed path is401.
-28/28 static assets byte/hash parity PASS, including index, direct JS/CSS, lazy chunks, manifest/icons/images.

## Gate summary

| Gate | Result |
|---|---|
| Independent minimal candidate tests | PASS |
| This task's minimal Production deployment | NOT ACTIVATED — concurrent baseline change |
| Current Production version |87b45679-2bc8-4f4b-b0a4-c82b65c155e9 (other window) |
| Static asset parity | PASS28/28 |
| Core regression | PASS |
| Apple real Sandbox TEST request | PASS |
| Apple delivery | PASS, SUCCESS |
| Signed payload verification | PASS |
| Environment / type | Sandbox / TEST |
| Server audit | PASS |
| UUID idempotency | PASS |
| Fake payload rejection | PASS;400 rather than requested401 |
| App Store Server Notifications | PASS for current87b45679 real delivery chain |
| Strict completion of this minimal-only deployment request | NOT COMPLETE; baseline/scope decision required |
| Rollback | NOT REQUIRED for this task's inactive candidate; other deployment retained |

Next TestFlight blockers remain Offer mapping, real-device StoreKit/Offer acceptance, and real-device core smoke. First resolve ownership of87b45679 as the baseline if further patches are requested. No Hybrid cutover, Final RC, TestFlight upload, Offer Code consumption or key generation was performed by this task.
# Superseding decision — 2026-09-08

The user has accepted malformed JWS 400 JSON and formally closed Notifications, Sandbox TEST, signed verification and UUID idempotency as PASS. Do not deploy the independent status-code patch. See PRODUCTION_BASELINE_ADOPTION_2026-09-08.md for the formally adopted current baseline dd0369b9 and previous verified rollback reference 87b45679. Conflicting deployment/blocker language elsewhere in this diagnostic report is historical, not an active requirement.
