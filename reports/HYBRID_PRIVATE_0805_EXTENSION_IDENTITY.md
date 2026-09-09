# Hybrid Private 2026090805 — extension packaging identity

Date: 2026-09-08. This task owns device control. No smoke, purchases, TestFlight upload or HYBRID_PRIMARY switch performed.

## Root cause

Build 2026090804 supplied `INFOPLIST_FILE=BuildIdentity.plist` globally to xcodebuild. This replaced the Share Extension target's explicit plist as well as the main app's. The built appex lacked its CFBundleIdentifier, executable, versions and NSExtension dictionary. Its source plist and stable identifier were already correct. See `build/storekit-sandbox-e2e/hybrid-private-build.log` ProcessInfoPlistFile invocation.

## Source correction

The main app DebugPrivatePreview configuration alone now sets `INFOPLIST_FILE = BuildIdentity.plist`, with source commit/fingerprint substitution defaults. The build command has no global INFOPLIST_FILE override. Extension target and its explicit plist remain unchanged. Its existing identifier is `com.lafayette.tastemap.ShareExtension` (also present in previously signed archive).

DebugPrivatePreview uses the existing TasteMapRelease.entitlements: Apple sign-in, associated domain tastemap.cn and original App Group. Share Extension retains only its original App Group. Team remains 7G5J9MJX88. This is not a Production route cutover.

New mandatory `scripts/verify-ios-embedded-identity.py` audits every embedded appex, including executable, plist values, NSExtension, versions, codesign, provisioning, team and entitlement authorization. AGENTS.md makes this mandatory before device installs and Final RC. Negative verification rejects the malformed 0804; 0805 passes. No post-build plist patching.

## Artifact evidence

- Scheme: Taste Map Private
- Configuration: DebugPrivatePreview
- Runtime: HYBRID_DEVELOPMENT; expected renderer HYBRID
- Build: 2026090805; version 1.0
- Source commit: 4d5fe935ff8658644ef2ecf3cfc872b87a9fcc50, plus uncommitted integration changes
- Source fingerprint: 8ac95eadaa431bf415afdaaf061a3b8cbb4daefe0acac40f5b5e0f22ac622392 (734 inputs including extension source)
- Main ID: com.lafayette.tastemap
- Extension ID: com.lafayette.tastemap.ShareExtension
- Main / extension / embedded / codesign identity: PASS
- Both built version 1.0 / 2026090805; profile contains target device; matching original App Group
- Production API https://api.tastemap.cn; referralAvailable false
- 29 staged/bundled resources byte parity PASS
- 59 artifact files scanned, zero sensitive matches against local Offer inventory, available local Cloudflare credential values, private-key markers and known debug bypass symbols. No inventory changed or code consumed.
- Private preview compilation uses TASTEMAP_PRIVATE_PREVIEW without generic DEBUG; runtime selector resolves HYBRID_DEVELOPMENT, standard release remains NATIVE_PRIMARY.
- Full artifact identity PASS before install.

Machine evidence under `build/storekit-sandbox-e2e/`: `0805-artifact-gate.json`, `0805-embedded-identity.json`, `0804-rejected-by-extension-gate.json`, `0805-settings.log`, `hybrid-private-0805-build.log`.

## Device evidence and stop

Install succeeded at 17:18. Device re-read at 17:19 confirms com.lafayette.tastemap / 1.0 / 2026090805, installation container 76AF1FD3-2C88-4BFC-AB2B-5A738582E48E. Evidence: `0805-install.json`, `0805-device-apps.json`.

One launch attempted. iOS rejected it: CoreDevice10002 / FBSOpenApplicationServiceErrorDomain1 / FBSOpenApplicationErrorDomain3, Security: invalid code signature, inadequate entitlements or profile not explicitly trusted. This generic message does NOT identify which cause applies. Local codesign/provisioning passing does not prove device trust.

DEVICE BUILD: 2026090805 (read back)
DEVICE RENDERER: UNCONFIRMED (launch denied)
DEVICE BUILD IDENTITY: FAIL (incomplete runtime evidence)
SHARE EXTENSION DEVICE ENUMERATION/CALL: UNCONFIRMED
SAFE TO START REAL DEVICE SMOKE: NO

Stopped after first launch rejection; no repeated installation or alternative Scheme. Remaining: resolve iOS launch authorization for this exact installed artifact, prove live Hybrid renderer and Share Extension enumeration/call. Previous native UI/visual/map results are not accepted for this build.
