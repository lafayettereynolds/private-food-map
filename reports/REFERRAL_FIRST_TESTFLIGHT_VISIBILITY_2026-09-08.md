# First TestFlight Referral visibility closure

User decision: defer real A→B qualified invitee14D/referrer1 E2E to internal beta. Do not require another Apple account as current cutover blocker. Preserve ordinary StoreKit real-device PASS.

Implementation: reuse signed ProductionEnvironment.json with referralAvailable=false. This is a release product-visibility policy, not a remote/user-editable Debug switch. Shared TS policy feeds Worker and Browser/Hybrid, Native reads same bundled JSON, missing configuration fails closed. Settings invite row hidden; direct React/Native invitation screen, native bridge dashboard and code preparation disabled; stale invitation code cannot reach Apple login. Worker rejects invitation landing links (404), dashboard (403), and registration payloads with referralCode (403). Existing gift/subscription/entitlement, settlement/admin/revocation code, DB/mappings/inventory retained. No new migration or feature-flag platform.

Deployment: pinned existing Production/Development modules patched only at invitation entry boundary, rather than deploying unrelated shared worktree changes. Bindings identical pre/post, assets explicitly retained. Development c425a15a45c84a8ea6ef1e0f446ad613; Production 8d658accc58a4486becf850cfcbdd467. Initial Production attempt was rejected without changing old module; retry using Wrangler-supported keep_assets succeeded. No Production assets upload, gift mutation, subscription change, code consumption or key rotation.

Validation: 67 targeted tests in auth, release referral boundary, referral rewards, inventory and shared UI; TypeScript app/Worker checks; formal Hybrid build and 26-file staging/built bundle byte equality; ReleaseSandbox iOS build succeeded; codesign --verify --deep --strict succeeded. Installed exact build/DerivedData-SandboxTestFlight/Build/Products/ReleaseSandbox-iphoneos/TasteMap.app on iPhone17ProMax; launch succeeded. Bundle config checked false. Physical Settings visual confirmation and full core smoke are the next user checkpoint, not claimed PASS from compilation. Current build remains Native primary/Development API, not Final RC or signed distribution Archive. Production website existing assets retained; first-TestFlight app resources contain hidden UI.

Core UI: existing SettingsDestinationLabel/HybridEntryRow and shared unavailable state reused. Food/Dining assets unchanged. Canonical Settings template retains all non-referral sections. Native rollback and shared Browser/Hybrid both covered; no new duplicate page/layout. Remaining design gap: actual installed Settings visual acceptance and final Map feel/core smoke.

Reopening: only after isolated dual-account E2E and reviewed config/build/deployment. Re-enable matching server and clients together; no client runtime override. Reward2–5 and all 60 code inventory items untouched.

REFERRAL FIRST-TESTFLIGHT VISIBILITY: DISABLED (built/installed policy + server enforcement; physical visual confirmation pending smoke)
NORMAL STOREKIT: PASS
REFERRAL E2E: DEFERRED TO TESTFLIGHT INTERNAL BETA
ACCOUNT ISOLATION: automated auth protections retained; real account switching remains core smoke item, no two-account device PASS claimed
REAL DEVICE CORE SMOKE: READY to start, not PASS
FINAL CUTOVER GATE: CLOSED until core smoke + visual/Map approval
TESTFLIGHT READINESS: NOT READY for upload; remaining ordered release/archive/purity/regression/RC gates follow smoke


## 16:29 real-device Settings visibility evidence
User-provided screenshot confirms Native Settings has no invitation section between membership and private directory. Account, Premium, private directory, backup/local-clear, sync and visible privacy entry remain present. Referral Settings visibility physical-device check PASS. This screenshot proves entry visibility only, not execution of backup/sync/privacy, unseen lower sections, Hybrid runtime or Map gestures. Next core-smoke checkpoint: real map pan/pinch, marker/detail navigation, viewport retention. No final cutover or upload.
