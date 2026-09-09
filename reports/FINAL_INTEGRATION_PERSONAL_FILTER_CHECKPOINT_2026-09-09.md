# Final Integration / personal recommendation filters checkpoint

Date: 2026-09-09 (Asia/Shanghai). This is NOT a Final RC or a new physical-device acceptance.

## Preserved input

- Branch: `feature/hybrid-final-integration`; HEAD `9859b8cbc99e65984c8cfd935b2ec82a4e2be2a8`. HEAD alone does not identify the accepted dirty workspace.
- Complete protected copy: `/Users/lafayette/Projects/tastemap-final-freeze.4LXM27/workspace`. Parent also contains history.bundle, tracked/index patches, status and a 2,106-path source manifest, verified against copied bytes.
- BEFORE source fingerprint: `4dc7da196d4f3d5912780a7a3073739fc418f8f77ed6e56250a3bbe181cf0e54` (not the new candidate fingerprint).
- No reset/rebase/discard or whole-file replacement of high-conflict recovery files.

## Integrated behavior

Sync recovery and Photo Delete were integrated semantically through verified `8567035`. Current SyncEngine, SyncCoordinator, PhotoTransferCoordinator, Worker syncV1 and photoBinaryV1 have zero diff against that source. Discovery optimization and accepted dirty workspace changes were retained. QA-only `f492503` control-case correction was included without enabling a Release fixture.

The two personal dimensions are separate:

- 预计喜欢度: predicted owner rating /10, reusing the existing historical weighted-rating estimator through `src/contracts/predictedLiking.ts`. Not calibrated probability, public rating, or renamed match percentage.
- 口味匹配度: existing matching percentage.
- For You filtering/sorting no longer offers community/public rating. Old API fields remain compatible; new UI queries clear them.
- Missing prediction does not borrow public rating/match. Worker filters before pagination. Native rollback retains its explicit already-loaded-card scope.
- Browser, Hybrid controls, Native filters, bridge Codable/query/cache and Worker DTO carry separate fields. Existing detail/community rating displays are not indiscriminately deleted.
- Forecasts use authorized owner history. Formula explanations are not permanently added to the filter UI.

## Evidence

Evidence root: `/tmp/tastemap-final-integration.DmrlU6`.

| Check | Result | Evidence |
| --- | --- | --- |
| Latest full Web/Worker source suite | 1558/1558 PASS, zero failures/skips/todos | source-latest.log |
| TypeScript, formal Web build | PASS | stage-latest.log |
| Actual local browser filter controls | PASS: independent thresholds/sort/reset/city, public rating absent | personal-filters-final.png; scripts/test-discovery-personal-filters.mjs |
| Native personal filter/query tests | 16/16 PASS, zero skipped | native-personal-filters.xcresult |
| Capacitor Photo Delete + no-delete Map/List/Map control | 2/2 PASS, zero skipped | photo-capacitor.xcresult |
| Frozen baseline Native full suite | 830 passed / 49 failed / 2 skipped; 881 total | baseline-native.xcresult |
| Integrated Native full suite before final Native-filter delta | 853 passed / 49 failed / 2 skipped; 904 total | native.xcresult |
| Failure identifier comparison | Identical 49-item set; zero new failures. Final Native-filter delta covered separately by 16 tests above | both xcresult summaries |
| Unsigned Release device compile; NATIVE_PRIMARY unchanged | PASS | release.log; Release/Build/Products/Release-iphoneos/TasteMap.app |
| dist / staged / built app | 26/26 byte-identical PASS | formal asset verifier |
| Release purity | PASS: no QA fixture/debug switch/Development URL/React credential surface | formal scanner: 49 app files, 26 web files |

Historical Native failures are NO NEW REGRESSION per the user's instructions, not full-suite PASS. Simulator/QA checks do not replace new RC physical-device smoke. This unsigned Release compile is not a signed RC/archive.

## Development ledger / deployment boundary

Read-only remote verification confirmed 0041 Discovery applied `2026-09-09 03:26:51` and 0042 Photo Delete applied `2026-09-09 08:11:57` (database timestamps). Source/fixture registry preserves both identities. Neither was rerun or renumbered.

0040 privacy retention has no ledger row. PRAGMA confirms `account_deletion_jobs` lacks `cleanup_lease` and `cleanup_lease_until`. Current `worker/accountDeletionV1.ts` uses both fields in cleanup claim/release. Blind complete-workspace Worker deployment is therefore unsafe, although the new Discovery prediction itself needs no migration. Historical duplicate 0036/0038 prefixes are preserved, not renumbered.

No Development/Production deployment or migration was performed. Prediction API is NOT claimed live. Next deployment requires a separately reviewed/authorized missing-0040 dependency or a bounded compatible Worker patch, without reapplying 0041/0042 or activating unrelated retention behavior.

## Remaining gate

FINAL INTEGRATION: IN PROGRESS

NEW REGRESSIONS (executed checks): 0

HYBRID_PRIMARY / NEW SIGNED FINAL BUILD / ARCHIVE / SIGNING: NOT RUN

NEW REAL DEVICE SMOKE / INTERNAL TESTFLIGHT UPLOAD: NOT RUN

iPhone, account, photos, queue and Production were not modified. Previously accepted 0905/0906 evidence remains attached to those builds, not reassigned to new source. No newer build was installed; data sync alone cannot put these new controls on the phone.

Next: resolve Development deployment compatibility, then gated cutover, distinct signed build/archive, backed-up physical-device smoke and Internal TestFlight upload.
