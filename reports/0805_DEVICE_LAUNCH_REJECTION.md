# 0805 launch rejection — evidence, 2026-09-08

No code/signing configuration changed; no replacement build or install performed. Smoke remains stopped.

## Authoritative evidence

One diagnostic launch of installed 0805 at 17:25 reproduced CoreDeviceError 10002, FBSOpenApplicationServiceErrorDomain 1 (RequestDenied), underlying FBSOpenApplicationErrorDomain 3 (Security). Raw output is private at `.private/launch-0805/launch.txt` and `.json`.

User's 17:25 iPhone system screenshot is more specific: 无法验证 App；需要互联网连接以验证是否信任开发者 Apple Development: Lu Jianbo (VVDCSHDW7V)；此 App 在验证前将不可用。

Confirmed blocker: device has not completed online developer-signature trust validation. Why the validation did not complete remains unproven; do not equate it with lack of general Internet connectivity, certificate revocation, or an Apple outage. 5G is valid; Wi-Fi is not required.

Device log collection through log collect requires root; noninteractive sudo is unavailable. Console currently exposes stale disconnected-device records, which are not evidence of this failure. No fresh amfid/trustd reason was obtained. Mac HTTPS GET to ppq.apple.com returns 200; that does not prove iPhone PPQ validation succeeded.

## Actual signed artifact vs previously working 0802

Both main and extension signing leaf certificates are byte-identical (SHA256 compared), not merely the same display name. Both use Apple Development: Lu Jianbo (VVDCSHDW7V), Team 7G5J9MJX88.

| Field | Working 0802 | 0805 | Assessment |
|---|---|---|---|
| Main profile UUID | bfb67d97-3da4-4b78-9867-a24b809044f6 | identical | no difference |
| Extension profile UUID | fa68de8f-8516-4fcd-a743-73c30b0be442 | identical | no difference |
| Main expiry | 2027-09-04 04:51:37 UTC | identical | valid |
| Extension expiry | 2027-09-04 04:51:30 UTC | identical | valid |
| Target UDID authorization | present in both | present in both | PASS |
| Main signed entitlements | app ID, team, get-task-allow true, Apple login, tastemap.cn, App Group | identical | PASS |
| Extension signed entitlements | extension app ID, team, get-task-allow true, App Group | identical | PASS |
| Explicit keychain-access-groups | absent | absent | no unauthorized value |

Profile entitlement subset check PASS for both targets. Actual signing certificate membership in each profile PASS. No evidence justifies changing signing settings, deleting capabilities or refreshing profiles. Signed-artifact comparison saved privately in `.private/launch-0805/profile-comparison.json`.

Permanent preinstall gate now additionally checks ApplicationIdentifierPrefix and actual signing leaf membership in DeveloperCertificates. Its pre-existing entitlement subset gate remains mandatory.

MAIN PROFILE: PASS
MAIN ENTITLEMENTS: PASS
SHARE EXTENSION PROFILE: PASS
SHARE EXTENSION ENTITLEMENTS: PASS
PROVISIONING ENTITLEMENT COMPATIBILITY: PASS
DEVICE TRUST: FAIL (online validation incomplete)
NEW BUILD: none; root cause of failed online validation not yet isolated
ARTIFACT IDENTITY: PASS (0805 prior gate)
DEVICE INSTALL: PASS (0805 prior device readback)
DEVICE LAUNCH: FAIL
DEVICE RENDERER: NOT RUN
SAFE TO START REAL DEVICE SMOKE: NO

Next necessary evidence: device Settings > General > VPN & Device Management developer entry / verification outcome on current 5G, or fresh trustd/amfid logs. Do not require Wi-Fi or rebuild speculatively. Once a fix is established, follow user-requested new build 0806 with all gates before install.

## Superseding evidence — collected device archive, 17:35

The user collected `.private/launch-0805/trust-diagnostic.logarchive`. Reading this archive isolated the precise failure:

- 17:18–17:20 online-auth-agent requests to https://ppq.apple.com/v2/authorization timed out: NSURLErrorDomain -1001, `The request timed out`.
- 17:22:42 amfid rejected the exact 0805 container executable with MISError 0xe8008026: `The provisioning profile requires online authorization`. Wrapper AppleMobileFileIntegrityError -400; SpringBoard FBSOpenApplicationErrorDomain 3.
- 17:25:24 the same app's online-auth-agent request completed over cellular (pdp_ip0), HTTP200, authorized=true. SpringBoard recorded `Online authorization succeeded`.
- 17:35:19 one diagnostic launch of the unchanged installed 0805 succeeded. Device-written event at 17:35:20, PID12967, confirms build2026090805, commit4d5fe935ff8658644ef2ecf3cfc872b87a9fcc50, source8ac95eadaa431bf415afdaaf061a3b8cbb4daefe0acac40f5b5e0f22ac622392, renderer=HYBRID_DEVELOPMENT, referralAvailable=false.

Conclusion: this launch rejection was caused by PPQ authorization requests timing out, leaving online authorization incomplete at launch. Subsequent successful authorization resolved rejection without a source, entitlement, certificate, Scheme or artifact change. It does not establish why the earlier HTTP requests timed out or imply a general cellular/Apple outage.

Device-selected profile for online authorization was 00f99b00-0208-4ba5-8da4-161bafda7f84, whereas embedded profile was bfb67d97-3da4-4b78-9867-a24b809044f6. misagent enumerated both. Authorization succeeded for the selected profile, and unchanged artifact subsequently launched; this difference is recorded, not claimed as a defect requiring profile deletion.

DEVICE TRUST: PASS for successful launch
DEVICE LAUNCH: PASS (unchanged0805 diagnostic confirmation)
DEVICE RUNTIME: HYBRID_DEVELOPMENT, proven in fresh device identity event
ACTUAL REACT SCREEN: awaiting visual confirmation
NEW BUILD: not generated; no configuration defect or source fix found. 0805 diagnostic launch is not a replacement Final QA build.
SAFE TO START REAL DEVICE SMOKE: NO (remain stopped pending visual identity and requested next QA build gates)

Raw logs retained privately in online-auth.txt, trust-filtered.txt, post-authorization-launch.json and post-authorization-events.jsonl. No further password or trust-menu action is needed for this successful launch.

## 17:40 user device screenshot — renderer confirmation

User screenshot f0b467ebd5f20273f3ff40a5b823380b.jpg shows the live Hybrid Map shell. Together with fresh device build/source/runtime log, DEVICE RENDERER = HYBRID is now confirmed for diagnostic0805. The visible error banner and `重试刷新` button match src/hybrid/app/HybridAppShell.tsx, not an inferred renderer from scheme alone.

Launch-root-cause closure: PASS. No configuration repair was necessary; PPQ online authorization completed after earlier request timeouts.

Screenshot also exposes discovery refresh failure (cached data warning) and banner button squeezed into vertical text. These are recorded as follow-up functional/visual defects; screenshot does not establish their underlying network/service cause. No code change, smoke run or visual/map performance PASS is made in this launch-only task. Extension enumeration/call remains unproven. Keep new QA build/extension identity gates before starting full smoke.

## Share handoff device evidence

Safari share sheet enumerated Taste Map; device process enumeration subsequently showed PID13026 executing the extension inside the verified0805 app container. Device App Group contains an unconsumed pending import created at 17:42:50 with sharedURL https://www.baidu.com/. The extension therefore executed and persisted this exact shared URL successfully. User reports no destination UI after manually foregrounding app.

Source investigation: extension enqueues and calls completeRequest after 450ms; it does not open the containing app. Hybrid runtime receive(sharedImport:) opens native-side Hybrid navigation and emits shareExtension.received. HybridAddRestaurantPage subscribes to that event, but HybridAppShell has no matching event handler. This is a concrete handoff gap to investigate/fix; persistence PASS does not imply end-to-end navigation PASS. Pending import was read only, not consumed or deleted. Share E2E remains FAIL.
