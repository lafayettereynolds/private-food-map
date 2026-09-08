# iPhone test deployment — 906.26

- Requested device: iPhone 17 Pro Max, CoreDevice `60BBB934-D441-53FB-B8CF-0E3DB5878C4D`. User explicitly selected it and requested both apps. iPhone 12 was not modified.
- Private app: `com.lafayette.tastemap`, `Taste Map Private` scheme, `DebugPrivatePreview`, version 1.0 (906.26). Previous installed build 906.17.
- Isolated QA app: `com.lafayette.tastemap.qa`, `TasteMap QA` scheme, `DebugQA`, version 1.0 (906.26). Previous installed build 1.
- Both signed builds succeeded; both were installed in place without uninstall, account changes, reset arguments or fixture arguments. Existing private bundle identifier and App Group preserved.
- Device app inventory confirmed both installed build numbers; CoreDevice launch succeeded for both identifiers on 2026-09-06 at approximately 20:10–20:12 Asia/Shanghai.
- Private artifact: `/tmp/tastemap-phone-90626-private/Build/Products/DebugPrivatePreview-iphoneos/TasteMap.app`.
- QA artifact: `/tmp/tastemap-phone-90626-qa/Build/Products/DebugQA-iphoneos/TasteMap.app`.
- Formal build/stage passed TypeScript checking and local-bundle release verification. All 18 resources matched byte-for-byte between dist, formal stage and each built app.
- Focused analytics/social-report/share/policy regression: 4 files, 72 tests passed.
- Annual source analysis now delegates to the shared recommendation analyzer; this removes the deleted fixed-low-score constant reference that blocked the current build and aligns its history baseline with the current analyzer.

## Acceptance boundaries

This is an installation checkpoint, not acceptance of every outstanding product request. iPhone Mirroring remained at its unlock-required screen, so affected on-device layouts were not visually verified. No claim is made that historical UI defects, New York search, public-feed inclusion or all five posters are complete.

The newly supplied illustration sheets have not yet been extracted/integrated. Remaining source-analysis work includes legacy presentation/semantics review, privacy projection review and poster visual/export acceptance. The 72 focused tests are not a full app regression suite.

Design-system status: no new UI scale or page template introduced in this deployment step; Food & Dining asset integration, remaining shared-consumer drift and full runtime visual acceptance remain open.
