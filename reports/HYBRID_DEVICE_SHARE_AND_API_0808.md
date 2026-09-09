# Hybrid device Share and API closure — 2026-09-08

## Scope and identity
Only `Taste Map Private` / `DebugPrivatePreview` / `HYBRID_DEVELOPMENT`; no renderer cutover, TestFlight upload, purchase, reward redemption or account replacement.

## Share handoff
The extension successfully wrote the pending import into the shared App Group. It completes the share request and expects the user to return to Taste Map. The Hybrid shell did not handle `shareExtension.received`, while the Add page subscribed only after mounting. The shell now routes that event to the existing Add page and that page opens its existing shared-import panel when a pending fingerprint is present. No import is saved or consumed by this route change.

Lafayette confirmed on the real iPhone that build 0806 now shows the panel. This proves pending-share delivery/UI handoff; restaurant parsing and an actual save are separate smoke checks.

## API root cause
The signed `ProductionEnvironment.json` now includes Boolean `referralAvailable: false`. `APIConfiguration.current` decoded the entire document as `[String: String]`, so the mixed-type document failed decoding and returned a nil API base URL. Requests failed before authorization/URLSession. Generic Discovery error handling mislabeled that local configuration failure as an internet connection problem.

The API reader now decodes a typed `apiBaseURL` field, ignores unrelated signed product fields and retains fail-closed behavior for missing/malformed endpoints. Referral remains false. No endpoint override or authentication bypass was added.

Reproduction: the old parser compiled without DEBUG against the exact 0807 app bundle prints `MISSING_API_BASE_URL`. The fixed parser passes five tests using the actual signed resource, mixed future fields, missing endpoint, incorrect type and malformed endpoint. Run:

```sh
xcrun swiftc ios/TasteMap/TasteMap/Configuration/AppEnvironment.swift scripts/test-ios-production-api-configuration.swift -o /tmp/tastemap-api-config-test
/tmp/tastemap-api-config-test
```

## Verification
- TypeScript typecheck and 92 product/snapshot tests: PASS.
- Discovery refresh native tests: 8 PASS; errors distinguish offline, timeout and invalid response.
- Production API configuration regression: 5 PASS.
- 0806 device share panel: PASS (user confirmation).
- 0808 installed/read back/launched: PASS. Device build 2026090808; fingerprint `654460c705519e4b4fd0cacafb0662503f94211ff18f2bc07900baed82c83840`; renderer HYBRID_DEVELOPMENT, Referral false.
- 0808 signed extension identity, 29 bundled resources and 59-file sensitive scan: PASS.
- Device now reaches authentication service: refresh returns HTTP 401 at 18:56:11, then `not_authenticated`; existing session manager invalidates rejected credentials. No account data was deleted.
- Discovery success is NOT yet proven. User must sign in again with the original Apple identity; no second account/purchase required. Relaunched unchanged 0808 at 18:57:28 to allow auth-required bootstrap.
- Do not attribute the remaining auth rejection to 5G or declare Discovery/Core smoke PASS.
- Discovery visual acceptance, Map hand feel, core smoke and Final Cutover: remain unaccepted.

## Design System Compliance
Core UI: existing shared shell banner retained; retry text no longer shrinks into a vertical stack. Food/dining visuals unchanged. Canonical Add template and existing share panel reused; no additional primary paste/share entry. No SwiftUI replacement renderer. No new duplicate components. Full device banner geometry and Discovery screen review remain pending.
