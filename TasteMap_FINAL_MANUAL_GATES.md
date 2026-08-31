# Taste Map｜Final Manual Gates

日期：2026-08-31  
适用基线：Final Integration 后的最新 `main`  
用途：**只列必须由 Lafayette 本人或已授权的真实账号/平台操作完成的事项。**  
Production 原则：任何 Production deployment、migration、secret change、R2/D1 write 都需要新的明确授权；本清单本身不构成执行授权。

## 使用方式

严格按以下顺序完成。每完成一项，把结果和非敏感标识告诉 Codex；Secret 不要粘贴到聊天、源码、报告或 Git。Codex 随后只做对应的安全验证，不会自行扩大 Production 权限。

---

## 1. Apple Developer

### 1.1 核对正式 Identifiers 和 Capability

- **去哪里：** Apple Developer → Certificates, Identifiers & Profiles。
- **做什么：**
  - 确认 App ID `com.lafayette.tastemap` 属于 Team `7G5J9MJX88`；
  - 确认 Sign in with Apple 与 App Group `group.com.lafayette.tastemap` 已关联；
  - 确认 Share Extension ID `com.lafayette.tastemap.ShareExtension` 及其 App Group；
  - 在 Production Universal Link 域名确定后，再为主 App 开启/更新 Associated Domains；不要添加 Development domain。
- **Codex 之后怎么验证：** 比对 Xcode Release entitlements、重新 Archive，并读取 archive 内 embedded entitlements/provisioning profile。
- **是否涉及 Secret：** 否。
- **是否不可逆：** 通常否；Capability/Profile 变更会影响签名，需谨慎但可恢复。
- **预计时间：** 10–20 分钟。

### 1.2 准备 App Store Distribution signing

- **去哪里：** Apple Developer 与 Xcode → Settings → Accounts / Organizer。
- **做什么：** 确保当前 Team 有有效 Apple Distribution certificate 与 App Store provisioning profile；继续使用 Automatic Signing，不改变 Team 或 Bundle IDs。
- **Codex 之后怎么验证：** 重新生成 Archive，确认 signing identity/profile 为 App Store distribution，且主 App/Extension 不再含 `get-task-allow=true`。
- **是否涉及 Secret：** Apple 私钥由 Keychain/Xcode 管理；不要导出或发送。
- **是否不可逆：** 否；不要撤销仍被其他发布使用的 certificate。
- **预计时间：** 10–30 分钟。

### 1.3 决定 Apple silicon Mac availability

- **去哪里：** App Store Connect → Pricing and Availability / platform availability。
- **做什么：** 决定 iPhone App 是否允许以 “Designed for iPhone” 形式安装在兼容 Mac；当前 Xcode target family 为 iPhone，但 Mac-designed availability 仍为 enabled。
- **Codex 之后怎么验证：** 审计最终 build settings 和 App Store Connect 非敏感截图/导出信息。
- **是否涉及 Secret：** 否。
- **是否不可逆：** 通常可调整。
- **预计时间：** 5 分钟。

---

## 2. App Store Connect 基础记录

### 2.1 核对 App record

- **去哪里：** App Store Connect → Apps → Taste Map。
- **做什么：**
  - 确认 Bundle ID 是 `com.lafayette.tastemap`；
  - 确认 App 名称、SKU、Primary Language、Category、年龄分级方向；
  - 确认版本号/Build 规划，不要在代码里临时伪造版本；
  - 确认账号角色允许管理 IAP、TestFlight、App Privacy 和提交。
- **Codex 之后怎么验证：** 对照 archive Info.plist、Bundle ID、version/build 与用户提供的非敏感 ASC 状态。
- **是否涉及 Secret：** 否。
- **是否不可逆：** SKU/初始 Bundle 绑定等部分字段创建后不易更改；确认后再保存。
- **预计时间：** 10–20 分钟。

### 2.2 准备 App metadata

- **去哪里：** App Store Connect → App Information / App Store Version。
- **做什么：** 准备正式名称、副标题、描述、关键词、分类、年龄分级、版权、Review contact、Review notes 和 demo/review account 策略。
- **Codex 之后怎么验证：** 做只读完整性清单核对；不会代替用户提交。
- **是否涉及 Secret：** Review 账号凭证属于敏感信息，只放 ASC 安全字段，不进 Git/报告。
- **是否不可逆：** 提交前通常可修改。
- **预计时间：** 30–60 分钟。

---

## 3. StoreKit / Subscriptions

### 3.1 创建并锁定 Subscription Group 与 Product IDs

- **去哪里：** App Store Connect → Taste Map → Monetization → Subscriptions。
- **做什么：**
  - 创建正式 Subscription Group；
  - 创建真实 Product IDs；
  - 配置 duration、subscription level、价格、display name、description、本地化和 review screenshot；
  - 把最终 Product IDs 作为非敏感配置记录交给 Codex接入/验证。
- **Codex 之后怎么验证：** 检查 Product provider、Worker allowlist 和 Release 二进制，确认无 fake Product ID、无 hardcoded price，并用 StoreKit/Sandbox 拉取真实产品。
- **是否涉及 Secret：** Product ID 不是 Secret。
- **是否不可逆：** Product ID 一旦创建/使用不能随意改名；Subscription Group 设计会影响升级/降级关系。保存前请仔细确认。
- **预计时间：** 30–60 分钟。

### 3.2 创建 App Store Connect API key

- **去哪里：** App Store Connect → Users and Access → Integrations / App Store Connect API。
- **做什么：** 创建最小必要权限的 Key，记录 Issuer ID、Key ID，并把 `.p8` 安全保存到 Secret manager/authorized Worker secret；不要交给 iOS、Git、Markdown 或聊天。
- **Codex 之后怎么验证：** 只验证 Worker Secret 名是否存在、Apple Server API 调用是否成功；绝不打印 secret value。
- **是否涉及 Secret：** **是。** `.p8` 是高敏感 Secret；Issuer ID/Key ID 也应按受控配置处理。
- **是否不可逆：** Key 可撤销；`.p8` 通常只能下载一次，丢失需轮换。
- **预计时间：** 10–20 分钟。

### 3.3 配置 App Store Server Notifications V2

- **去哪里：** App Store Connect → App Information → App Store Server Notifications。
- **做什么：** 在 Production Worker 经明确授权部署且 URL 稳定后，分别配置 Sandbox/Production V2 endpoint；不要指向 Development 临时地址冒充 Production。
- **Codex 之后怎么验证：** 发送 Apple Sandbox 流程触发通知，检查匿名日志中的 notification dedupe、Apple API re-fetch 和 entitlement reconciliation；不记录 transaction PII/token。
- **是否涉及 Secret：** URL 本身通常不是 Secret，但 Worker auth/API credentials 是 Secret。
- **是否不可逆：** 否，可更新；错误配置会丢失实时通知但可通过 reconciliation 恢复。
- **预计时间：** 10–15 分钟。

### 3.4 Sandbox / TestFlight 商店验收

- **去哪里：** App Store Connect Sandbox Testers、iPhone Settings/App Store、TestFlight。
- **做什么：** 验证产品加载、购买、取消、restore、续订、过期、退款/撤销、账号切换、App 重启 entitlement 恢复和多个设备。
- **Codex 之后怎么验证：** 观察非敏感 StoreKit/Worker diagnostics，核对 Taste Map user ownership、transaction idempotency 与 entitlement state。
- **是否涉及 Secret：** Sandbox Apple ID/密码是敏感信息，不发送给 Codex。
- **是否不可逆：** Sandbox 操作不影响真实收费；Production 购买会产生真实交易，初期只用 Sandbox/TestFlight。
- **预计时间：** 45–90 分钟（订阅时间压缩测试可能更久）。

---

## 4. Legal URLs, Privacy and UGC Operations

### 4.1 发布真实 Legal/Support URLs

- **去哪里：** 由 Lafayette 控制的正式 HTTPS 网站/CMS；随后 App Store Connect 与 Taste Map Release configuration。
- **做什么：** 发布并批准：
  - Privacy Policy；
  - Terms of Service；
  - Support/contact page；
  - Community/UGC rules（可作为 Terms/独立政策的一部分）。
  URL 必须真实可访问、移动端可读、无假占位。
- **Codex 之后怎么验证：** HTTPS/redirect/content 可达性检查、Release configuration validation、Settings 条件显示、archive scan。
- **是否涉及 Secret：** 否。
- **是否不可逆：** 否；政策内容变更可能需要通知用户和更新日期。
- **预计时间：** 技术配置 15–30 分钟；法律审阅时间另计。

### 4.2 完成 App Privacy Nutrition Labels

- **去哪里：** App Store Connect → App Privacy。
- **做什么：** 根据最终 Worker/D1/R2、Analytics、UGC、Photos、Account、Purchase 数据流填写 collected/linked/tracking/purpose；不要仅复制 `PrivacyInfo.xcprivacy`。
- **Codex 之后怎么验证：** 将 App Store 声明与代码/manifest/data-contract 做差异审计。
- **是否涉及 Secret：** 否。
- **是否不可逆：** 可更新，但错误声明会产生审核与合规风险。
- **预计时间：** 30–60 分钟。

### 4.3 指定 UGC moderation operations

- **去哪里：** 内部运营流程/支持系统/App Review notes。
- **做什么：** 指定真人审核负责人、正常/紧急 SLA、升级、申诉、封禁恢复与执法记录；准备 App Review 说明 report/block/delete-own-content 如何工作。
- **Codex 之后怎么验证：** 用非真实敏感内容跑 Development/TestFlight moderation smoke，核对状态与匿名日志。
- **是否涉及 Secret：** 支持系统凭证/用户报告内容可能敏感，不应进入 Git/公开报告。
- **是否不可逆：** Moderation 决策可能影响用户；正式执行前需流程和审计记录。
- **预计时间：** 30–60 分钟建立最小流程。

---

## 5. Cloudflare Production

### 5.1 给出 Production preflight/deploy 明确授权

- **去哪里：** 当前 Codex task 中明确授权；Cloudflare Dashboard 只由已授权账号操作。
- **做什么：** 指定/确认：
  - Production Worker URL；
  - public share origin；
  - Auth/Apple audience；
  - StoreKit Product IDs 和 API environment；
  - R2/D1 bindings；
  - AASA hosting strategy；
  - Production secrets 的注入责任人。
- **Codex 之后怎么验证：** 先只读 preflight；输出 bindings/migration/config 差异，不显示 Secret，不写 Production，等待单独确认后才部署。
- **是否涉及 Secret：** **是。** Cloudflare/API/App Store private key 必须进入 Secret manager，不进客户端或 Git。
- **是否不可逆：** 只读 preflight 否；部署会改变 Production，必须再次确认。
- **预计时间：** 15–30 分钟确认配置与权限。

### 5.2 配置 Production API 与 public origin

- **去哪里：** Authorized release configuration/Cloudflare Worker config/Xcode release config。
- **做什么：** 设置真实 Production HTTPS API base URL 与 `PUBLIC_SHARE_ORIGIN`；禁止 fallback 到 `api-dev.tastemap.cn`。
- **Codex 之后怎么验证：** Release archive plist/binary scan、health/auth smoke、public-link URL inspection。
- **是否涉及 Secret：** URL 通常不是 Secret；相关 token/key 是 Secret。
- **是否不可逆：** 配置可回滚；错误部署会影响正式用户。
- **预计时间：** 15–30 分钟（不含部署审批）。

### 5.3 部署 AASA 并启用 Production Associated Domain

- **去哪里：** Production domain/Cloudflare + Apple Developer/Xcode。
- **做什么：** 在正式域名无跳转提供 `/.well-known/apple-app-site-association`，内容绑定 Team ID `7G5J9MJX88` 与 App ID `com.lafayette.tastemap`；随后配置 Release `applinks:` entitlement/profile。
- **Codex 之后怎么验证：** HTTPS header/content 校验、archive entitlement 检查、真实 iPhone universal-link smoke。
- **是否涉及 Secret：** 否。
- **是否不可逆：** 否；错误 AASA/entitlement 会让链接退回浏览器。
- **预计时间：** 20–40 分钟，Apple CDN 缓存传播可能更久。

---

## 6. Production D1 / R2

### 6.1 只读 preflight 与备份计划

- **去哪里：** Cloudflare D1/R2 Dashboard/Wrangler，必须有新的明确 Production 只读授权。
- **做什么：**
  - 只读核对 migrations、tables/indexes、row counts、bindings；
  - 核对 R2 bucket/CORS/lifecycle；
  - 创建可验证的备份/rollback plan；
  - 先在 Development/staging 重放 migration 和 smoke。
- **Codex 之后怎么验证：** 输出无 PII 的 schema/migration/count 差异和备份可恢复证据。
- **是否涉及 Secret：** **是。** Cloudflare credentials 不输出。
- **是否不可逆：** 只读否；备份本身否。
- **预计时间：** 20–40 分钟。

### 6.2 Production migrations/bindings（单独审批）

- **去哪里：** Cloudflare Production；只有在 preflight 报告后单独授权。
- **做什么：** 仅应用缺失 incremental migrations，禁止 reset/rebuild/清库/ownership rewrite；更新已批准 bindings/secrets；记录 migration IDs 与结果。
- **Codex 之后怎么验证：** migration status、schema、约束/index、只读 smoke，随后最小测试用户 E2E。
- **是否涉及 Secret：** **是。** Secret 只注入平台。
- **是否不可逆：** **可能。** Schema/data migration 与错误 binding 可影响真实数据；必须有备份和 rollback/forward-fix plan。
- **预计时间：** 20–60 分钟，取决于 migration 差异。

---

## 7. TestFlight

### 7.1 清理 P1 Release-binary purity finding

- **去哪里：** 回到 Codex 代码任务（这是后续代码修复，不是当前只读审计）。
- **做什么：** 将 `IsolatedAuthCredentialStore`、`TestNetworkBlockerURLProtocol` 等 test-only 类型移出 Release compilation；保留测试能力；重新跑 regression 和二进制扫描。
- **Codex 之后怎么验证：** Release archive `strings`/recursive scan，确认类型、test env/header/fixture data 均不存在。
- **是否涉及 Secret：** 否。
- **是否不可逆：** 否；普通可回退代码修改。
- **预计时间：** Lafayette 只需批准/验收 5 分钟；Codex 开发时间另计。

### 7.2 生成 Distribution Archive 并上传 TestFlight

- **去哪里：** Xcode Organizer → Distribute App → App Store Connect → Upload。
- **做什么：** 在前述 P1 gates 关闭后生成新的 Distribution archive，确认主 App/Extension profile、entitlements、version/build、dSYM、Privacy manifest；由 Lafayette 明确执行/批准上传。
- **Codex 之后怎么验证：** archive validation、upload logs、ASC processing 状态；不会自动提交审核。
- **是否涉及 Secret：** Apple signing credentials 由 Xcode/Keychain 管理。
- **是否不可逆：** Build number 上传后不可复用；上传不等于发布。
- **预计时间：** 20–45 分钟，加 Apple processing 时间。

---

## 8. Real iPhone Smoke

### 8.1 TestFlight/Distribution 真机最小验收

- **去哪里：** Lafayette 的真实 iPhone、TestFlight、系统 Settings。
- **做什么：** 至少验证：
  1. 安装/首次启动；
  2. Sign in with Apple、重启 Keychain 恢复、refresh、logout；
  3. Production/TestFlight sync：Restaurant/Visit/Photo/offline queue/tombstone；
  4. Location precise/reduced/denied，Nearby 距离；
  5. Share Extension：Apple Maps/AMap/URL/text；
  6. Universal Links：Restaurant/Profile/List，以及 private/deleted/revoked；
  7. StoreKit Sandbox/TestFlight purchase/restore/expiry/refund/revoke；
  8. Report/block/delete-own-comment；
  9. Account Delete 只用 disposable test account；
  10. Map/Discovery/Profile/Restaurant Detail/Roulette/Analytics/poster smoke。
- **Codex 之后怎么验证：** 读取非敏感 diagnostics/logs 与截图；不会要求粘贴 token、Apple credential 或真实业务内容。
- **是否涉及 Secret：** Apple/TestFlight accounts 是敏感信息，不分享密码。
- **是否不可逆：** Account Delete、真实内容删除不可逆；必须用 disposable test account/test data。Production purchase 可能收费，优先 Sandbox/TestFlight。
- **预计时间：** 60–120 分钟。

---

## 9. App Store Submission

### 9.1 Final submission checklist

- **去哪里：** App Store Connect → App Store Version → Prepare for Submission / Submit for Review。
- **做什么：** 确认：
  - TestFlight accepted build；
  - screenshots/app preview；
  - description/keywords/category/age rating；
  - Privacy/Terms/Support URLs；
  - App Privacy Nutrition Labels；
  - export compliance；
  - IAP/subscription attached to version；
  - Review contact、review notes、demo/review account；
  - Sign in with Apple instructions；
  - UGC report/block/moderation说明；
  - Account Delete path；
  - Production health and rollback owner。
- **Codex 之后怎么验证：** 最终只读 release audit，对照 archive、ASC metadata、Production health 与 Manual Gate evidence；由 Lafayette 点击 Submit。
- **是否涉及 Secret：** Review credentials 只放 App Store Connect 安全字段。
- **是否不可逆：** Submit 可撤回；正式 release/automatic release 会面向用户，属于高影响操作。
- **预计时间：** 30–60 分钟。

## Completion Rule

只有以下全部成立，才可以从“Release Candidate”进入“App Store submission ready”：

- Distribution archive 不再是 Development signing，且无 `get-task-allow=true`；
- Release binary purity P1 已关闭；
- Production API/Worker/D1/R2 经授权部署并通过最小 smoke；
- StoreKit 真实产品、凭证、Notifications、Sandbox/TestFlight 验收完成；
- Privacy/Terms/Support 与 App Privacy 声明完成；
- AASA/Associated Domains 与真实 iPhone Universal Link 验收完成；
- moderation operations 和 App Review 说明完成；
- disposable-account Account Delete smoke 完成；
- TestFlight 真机总体验收通过；
- Lafayette 明确批准最终提交。

在此之前，不应上传或提交一个看似完整、实际仍依赖空 Production 配置的 build。
