# Taste Map｜Post-Integration Release Preflight

审计日期：2026-08-31  
仓库：`/Users/lafayette/Projects/private-food-map`  
审计基线：`main@11c7e2ebb946fcc356b3ccf713a23a9c819da09e`  
可执行代码树：`f9e8f5b11803540e97506ddfba2592000da6cbd8`（与已合并 Product Parity 可执行树一致）  
Production：**未访问、未部署、未迁移、未写入**  
审计性质：READ-ONLY / NON-DESTRUCTIVE；没有修改 App 代码、配置、Signing、Capability、App Icon、Worker、D1 或 R2。

## 1. Executive Summary

最终整合后的代码与自动化回归是稳定的，Xcode 可以完成 Release Simulator build、Generic iOS Device Release build，并可以生成包含主 App、Share Extension、Privacy Manifest 和 dSYM 的 `.xcarchive`。

当前状态不是“可直接上传 App Store”的状态，而是：

> **Code-integrated and archive-capable, with mandatory Release Gates still open.**

主要 Release Gates：

| Severity | Gate | 当前结论 |
| --- | --- | --- |
| P1 | Distribution signing | Archive 成功，但当前实际使用 Apple Development signing，主 App 与 Extension 都带 `get-task-allow=true`；不能作为 App Store distribution artifact。 |
| P1 | Production API configuration | Release 包内 `APIEnvironment.plist` 为空，符合 fail-closed，但真实 Production 登录、同步、社交、分享与 StoreKit 服务端链路无法工作。 |
| P1 | Legal URLs | Production Privacy Policy、Terms of Service、Support URL 均为空；正式 UI 会按设计隐藏假链接，但 App Store submission 前必须配置真实 HTTPS URL。 |
| P1 | StoreKit external configuration | 代码链路存在，但 Subscription Group、Product IDs、价格、本地化、App Store API 凭证、Sandbox/TestFlight 验收尚未完成。 |
| P1 | Universal Links production configuration | Release entitlement 当前没有 Associated Domains，仓库中没有 Production AASA；公开分享只能视为 code-ready，不能视为 Production universal-link-ready。 |
| P1 | Release binary purity | Release 二进制仍包含 `IsolatedAuthCredentialStore` 与 `TestNetworkBlockerURLProtocol` test-support 类型。Release runtime 无法启用它们，测试环境变量、测试 Header、demo data 均未进入二进制，但上架前仍应将 test-only 类型移出 Release target。 |
| P2 | App Store Server JWS defense-in-depth | Entitlement 不直接信任通知 payload，而是向 Apple Server API 重新拉取验证；仍建议在 Production 前补齐/确认 JWS `x5c` 签名链的直接密码学验证。 |
| P2 | UGC operations | Report / Block / Delete-own-content 的代码能力存在；仍需真人负责人、审核 SLA、申诉/升级与 App Review 说明。 |
| P2 | Mac availability decision | Target device family 是 iPhone-only，但 `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD=YES`；需要在 App Store Connect 明确是否允许 Apple silicon Mac 安装。 |

以上 P1 均没有被隐藏或绕过。本轮没有为了“通过扫描”写假 URL、假 Product ID、假 Secret 或改变 Signing。

## 2. Baseline and Evidence

### Git

- 审计开始时：`HEAD == origin/main == 11c7e2ebb946fcc356b3ccf713a23a9c819da09e`。
- Final Integration code merge：`f9e8f5b11803540e97506ddfba2592000da6cbd8`。
- Final Integration report commit：`11c7e2ebb946fcc356b3ccf713a23a9c819da09e`。
- 主工作目录既有用户修改、untracked audit/report 文件和 stash 均保持原样，没有被本轮 stage、覆盖、清理或恢复。

### Combined Regression inherited from the same executable tree

Final Integration 已在同一可执行代码树上完成：

- Worker/Web Vitest：49 files / 342 tests，PASS；
- App/Worker TypeScript typecheck：PASS；
- Vite production build：PASS；
- iOS full unit/integration：581 tests / 57 suites，PASS；
- Key UI E2E：12 tests / 0 failures，PASS；
- Debug Simulator build：PASS；
- Release Simulator build：PASS；
- Generic iOS Device Release build：PASS。

本轮额外完成 signed Archive 与 archive payload/entitlement/binary scan；没有重复执行破坏性 Import、真实 Account Delete 或 Production 测试。

## 3. Release Build and Archive Readiness

### Xcode project

正式工程：

`/Users/lafayette/Projects/private-food-map/ios/TasteMap/TasteMap.xcodeproj`

已确认 targets：

- `TasteMap`
- `TasteMapShareExtension`
- `TasteMapTests`
- `TasteMapUITests`

已确认 schemes：

- `TasteMap`
- `TasteMapShareExtension`

### Main App

| Item | Release value | Result |
| --- | --- | --- |
| Bundle Identifier | `com.lafayette.tastemap` | PASS |
| Team | `7G5J9MJX88` | PASS；未修改 |
| Signing style | Automatic | PASS；未修改 |
| Deployment target | iOS 17.0 | PASS |
| Target device family | iPhone (`1`) | PASS |
| Display Name | `Taste Map` | PASS |
| Version / Build | `1.0` / `1` | Read dynamically/configured; release metadata still needs App Store review |
| Non-exempt encryption | `ITSAppUsesNonExemptEncryption = NO` | PASS under current system-HTTPS/system-crypto architecture |
| Sign in with Apple | Release entitlement present | PASS |
| App Group | `group.com.lafayette.tastemap` | PASS |

### Share Extension

| Item | Release value | Result |
| --- | --- | --- |
| Bundle Identifier | `com.lafayette.tastemap.ShareExtension` | PASS |
| Team / Signing | `7G5J9MJX88` / Automatic | PASS |
| Deployment target | iOS 17.0 | PASS |
| Target device family | iPhone (`1`) | PASS |
| App Group | `group.com.lafayette.tastemap` | PASS; matches main app |
| Embedding | Embedded in main app | PASS |
| Extension activation | Text and up to one web URL | PASS |

### Archive result

A signed `xcodebuild archive` completed successfully and produced a structurally valid archive containing:

- arm64 main App;
- embedded Share Extension;
- `PrivacyInfo.xcprivacy`;
- app/extension dSYMs;
- expected bundle metadata and entitlements.

`codesign --verify --deep --strict` passed for the archived App.

Archive readiness classification:

- **Archive pipeline:** PASS.
- **App Store distribution signing:** NOT READY / MANUAL GATE.

The archive was signed with Apple Development credentials and contains `get-task-allow=true` for the app and extension. A release-distribution archive must be regenerated/exported through Xcode Organizer using the existing Team and valid Apple Distribution/App Store profiles. No Signing setting was changed in this audit.

## 4. Entitlements and Capability Audit

### Main App Release entitlements

- Sign in with Apple: `Default`;
- App Group: `group.com.lafayette.tastemap`;
- no Associated Domains in Release.

### Main App Debug entitlements

- Sign in with Apple;
- same App Group;
- Development associated domain: `applinks:api-dev.tastemap.cn?mode=developer`.

### Share Extension entitlements

- same App Group;
- no unrelated capability was found.

Conclusion:

- Development Associated Domain is correctly absent from Release.
- Production Universal Links are not yet configured; this is a deliberate fail-closed state, not a completed release configuration.
- Existing Team, Bundle IDs, Automatic Signing and capabilities were preserved.

## 5. Release Binary Safety Scan

The actual archived main app and extension were scanned, excluding code-signature/provisioning payloads where appropriate.

### No release payload match found

- `api-dev.tastemap.cn`;
- Development Associated Domain;
- `development-test` authentication mode;
- `X-Taste-Map-Test-User` or other test user authorization header;
- UI test environment keys and fixture values;
- demo user IDs/demo seed data;
- fake StoreKit Product IDs used by tests;
- private key markers;
- Cloudflare API Token, D1 Token, R2 Secret, Worker Secret or App Store `.p8` content;
- literal bearer token or JWT credential.

### Fail-closed configuration observed

- Archived `APIEnvironment.plist` is empty: no dev URL leak and no guessed Production URL.
- Archived `LegalEnvironment.plist` contains the expected keys but all Production/Development URL values are empty.
- Production API and legal behavior therefore fail closed rather than silently falling back to Development.

### P1 release-purity finding

The Release binary still contains symbols/strings for:

- `IsolatedAuthCredentialStore`;
- `TestNetworkBlockerURLProtocol`;
- generic backup-import fixture injection scaffolding.

Risk assessment:

- Release runtime tier is hardcoded to normal `.application` behavior;
- activation/insertion paths for UI fixture data are wrapped in `#if DEBUG`;
- actual test environment variable names, test user header, demo/fixture records and development auth values were not found in the archived payload;
- no privilege bypass, test identity or secret leak was demonstrated.

Nevertheless, test-only support types should not ship in the production binary. Before App Store submission, move or compile-gate them out of Release and re-run this exact binary scan. This task is read-only, so the code was not changed here.

## 6. Production Environment Configuration

### API

The App environment architecture supports Development/Production separation and fails explicitly when Production is not configured. Current Release bundle has no Production Worker base URL.

Result: **P1 Manual/Release Gate.** Production authentication and sync cannot be accepted until a real Production HTTPS Worker URL is approved, injected through the centralized configuration, and verified without fallback to Development.

### Production access in this audit

- Production Worker: not accessed;
- Production D1: not queried/migrated/written;
- Production R2: not read/written;
- Production secrets: not viewed or changed;
- App Store Connect: no upload/product creation/configuration.

## 7. StoreKit Readiness Audit

### Code-ready capabilities

| Capability | Status | Evidence/behavior |
| --- | --- | --- |
| Product loading | CODE READY | `Product.products` through a provider abstraction; IDs come from authenticated server configuration. |
| Price display | CODE READY | Uses StoreKit product display price; no fake production price. |
| Purchase | CODE READY | StoreKit 2 purchase with per-user `appAccountToken`. |
| Client verification | CODE READY | Uses `VerificationResult` before reconciling/finishing. |
| Server reconciliation | CODE READY | Transaction sent to Worker; server validates ownership/environment/product before entitlement projection. |
| Restore | CODE READY | `AppStore.sync()` plus current entitlement reconciliation. |
| Transaction updates | CODE READY | Long-lived transaction update observer exists. |
| Expiry/refund/revoke | CODE READY | Server entitlement projection covers expiration, refund and revocation. |
| Idempotency | CODE READY | Transaction/original-transaction ownership and idempotent upsert constraints. |
| User isolation | CODE READY | Stable server-controlled Taste Map user ↔ appAccountToken mapping; cross-user original transaction reuse rejected. |
| Notifications V2 endpoint | CODE READY | Versioned Worker integration point exists with notification dedupe. |

### Server notification trust boundary

The notification payload is used as a routing hint and is not trusted to grant Premium. The Worker re-fetches transaction/subscription state through authenticated Apple Server API access and validates bundle ID, product, environment and `appAccountToken` before changing entitlement.

Remaining P2 hardening: directly verify the signed JWS `x5c` chain according to current Apple guidance, in addition to the existing authenticated server re-fetch. This is defense-in-depth; the current design does not grant entitlement solely from an unverified notification payload.

### External configuration still required

- Subscription Group;
- real Product IDs;
- pricing and localization;
- App Store Connect Issuer ID / Key ID / `.p8` secret injection;
- App Store Server Notifications V2 Production/Sandbox endpoint configuration;
- Sandbox purchase/restore/renew/expire/refund/revoke tests;
- TestFlight purchase and account-switch smoke.

No fake Product ID or credential was created. Production StoreKit remains fail-closed.

## 8. Legal, Privacy and UGC Readiness

### Privacy configuration

`PrivacyInfo.xcprivacy` is included in the archive. It declares the relevant accessed API reason and collected-data categories currently represented by the application architecture. This must still be reconciled with the final App Store Connect Privacy Nutrition Label; the manifest does not replace the questionnaire.

Usage descriptions present:

- Location usage description;
- Photo Library add-only usage description.

The app uses system `PhotosPicker` for user-selected media and add-only authorization for saving generated posters; it does not invent a full-library permission state where the system picker does not require it.

### Legal configuration

The app has a centralized legal-link configuration layer with validation and Release-safe conditional visibility. It does not show fake links when URLs are missing.

Current real values:

- Privacy Policy URL: missing;
- Terms of Service URL: missing;
- Support URL/contact: missing.

Result: **P1 Release Gate.** Publish and approve real HTTPS documents/endpoints, then configure and validate them before TestFlight/App Review.

### Account Delete

Code readiness includes:

- authenticated preview;
- fresh Apple re-authentication;
- durable deletion job;
- business-data and media cleanup orchestration;
- session revocation;
- Keychain/local session purge and recovery behavior.

Real destructive verification was intentionally not performed. A disposable test account must be used later; never a production user containing irreplaceable data.

### UGC safety capabilities

Code-ready:

- report content/user/comment;
- block user;
- delete own comment/content paths;
- moderation endpoints/hooks;
- ownership and idempotency enforcement.

Manual operations gate:

- name a moderation owner;
- define review SLA and urgent escalation;
- define appeal/support route;
- prepare content policy/community standards and App Review notes;
- verify revoked/deleted/private content disappears from public views and links.

## 9. Share Extension and Universal Link Readiness

### Share Extension ingestion

Status: **CODE READY / ARCHIVE PRESENT.**

- Share Extension is embedded and uses the same App Group as the main app.
- It accepts HTTPS URL and/or text within bounded input size.
- Shared payload storage is atomic, deduplicated and expires stale records.
- Apple Maps, AMap and generic URL/text ingestion paths exist.
- The main app requires explicit user confirmation before creating a Restaurant.

### Public sharing

Status: **CODE READY.**

- Restaurant, Profile and List share types exist;
- share creation is authenticated and visibility/ownership-aware;
- anonymous read re-checks current visibility/deletion state;
- private, deleted or revoked share content resolves unavailable rather than leaking stale data;
- share IDs are high-entropy and public reads are rate-limited.

### Universal Links

Status: **PRODUCTION DOMAIN PENDING / REAL DEVICE PENDING.**

Missing release work:

- approve a real public share origin;
- configure `PUBLIC_SHARE_ORIGIN` in authorized Production Worker configuration;
- serve valid `/.well-known/apple-app-site-association` over HTTPS without redirects;
- add the Production `applinks:` domain to the Release Associated Domains capability/profile;
- install a distribution/TestFlight build and test Restaurant/Profile/List links plus private/deleted/revoked behavior.

No Production Associated Domain was guessed or added during this audit.

## 10. iPhone-only and Platform Availability

The Xcode targets use `TARGETED_DEVICE_FAMILY = 1`, so the native target is iPhone-only rather than an iPad target.

`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = YES` remains enabled. This does not change the iPhone deployment target, but App Store Connect may make the app available on compatible Apple silicon Macs. Lafayette must decide whether this is desired and update distribution availability through the normal Apple workflow if necessary.

## 11. Readiness Matrix

| Area | Code Ready | Archive Ready | Production Ready | Manual/External Gate |
| --- | --- | --- | --- | --- |
| Main App | Yes | Yes | No | Distribution signing, Production API |
| Share Extension | Yes | Yes | No | Distribution profile, real-device smoke |
| Sign in with Apple | Yes | Capability present | No | Production Worker/auth validation and TestFlight smoke |
| Sync / local-first | Yes | Yes | No | Production endpoint/D1/R2 rollout authorization |
| StoreKit | Yes | Yes | No | ASC products/API credentials/Sandbox/TestFlight |
| Legal | Config layer ready | Yes | No | Real Privacy/Terms/Support URLs |
| Privacy manifest | Yes | Included | Pending final declaration | ASC Privacy Nutrition Label |
| Account Delete | Yes | Yes | Pending | Disposable-account end-to-end smoke |
| UGC controls | Yes | Yes | Pending | Moderation operations/process |
| Public sharing | Yes | Yes | No | Public origin/AASA/Associated Domains |
| App Store submission | No | No distribution artifact | No | All P1 gates must close |

## 12. Release Decision

### What is accepted

- Final Integration code is structurally stable.
- Release Simulator and Generic Device Release builds pass.
- Xcode Archive flow works.
- Main App and Share Extension identifiers, App Group and core entitlements are internally consistent.
- No Development URL/auth mode/test user header/demo seed/fake product/secret was found in the archive.
- StoreKit, account deletion, UGC and public sharing have meaningful code architecture rather than placeholder UI.
- Production remained untouched.

### What is not accepted yet

- App Store upload/distribution signing;
- Production backend/API connectivity;
- real StoreKit product and credential configuration;
- real Legal/Support URLs;
- Production Universal Links/AASA;
- final App Privacy declarations and moderation operations;
- real TestFlight/iPhone release smoke;
- removal of Release-compiled test-support types.

Therefore:

> **Taste Map is ready to enter the manual release-gate sequence, but is not yet ready for App Store upload or submission.**

The exact Lafayette-only sequence is documented in `TasteMap_FINAL_MANUAL_GATES.md`.
