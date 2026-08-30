# Taste Map Final Release Fixes 06 — StoreKit / Production / Legal / Associated Domains

日期：2026-08-30

分支：`main`

基线：`792ef6c799a8922c978c3ae4d6a81da3df8104f2`（`Finalize iOS release support scope`）

## 1. 结论

Task 06 所有不依赖外部凭证、Production 授权或 Lafayette 人工后台操作的发布准备已经完成。StoreKit 2、服务端交易复核、用户隔离、公开分享、AASA、账户删除和 UGC 安全闭环均复用现有正式实现；本轮补上了 StoreKit 本地会话自动化、Production Worker 的已确认非 Secret 配置、Store server 环境 fail-closed、完整 Legal validation，以及统一人工发布清单。

没有部署、查询、迁移或写入 Production Worker / D1 / R2；没有添加正式 Product ID、价格、Issuer ID、Key ID、`.p8` 或假 Legal URL。

## 2. StoreKit 2 readiness

现有正式能力保持不变：

- 商品由认证后的 Worker catalog 提供 Product ID，再由 StoreKit 2 读取名称、周期和价格。
- 购买区分 completed / pending / user-cancelled / unverified。
- verified transaction 经 Worker server reconciliation 成功后才 finish。
- `Transaction.updates`、`Transaction.currentEntitlements`、restore 与 manage subscription 使用系统能力。
- entitlement authority 在 Worker/D1；客户端缓存按 Taste Map User 隔离且有失效边界。
- Worker 使用 `appAccountToken` 绑定 Taste Map User，原始订阅不能被另一用户认领。
- notification UUID、transaction 和 ownership 写入具备幂等边界；到期、退款、撤销由服务端投影。

本轮为 App target 声明 In-App Purchase capability，并用 `SKTestSession` 打开 Development-only `.storekit` fixture、清理/重置隔离的 simulated transaction state。测试 fixture 的两个 `dev.*` 商品仍明确不是正式 App Store 产品。

`SKTestSession` 当前自动化只声明已验证的 fixture/session 生命周期，不虚报真实 Sandbox/TestFlight 购买。真实 buy、pending、cancel、restore、renew、expire、refund/revoke 仍列为 Manual Release Gate。

## 3. Worker 安全补强

Store server reconciliation 现在要求 `APP_ENVIRONMENT` 必须明确为 `development` 或 `production`：

- 缺失/未知环境返回 `app_environment_not_configured`。
- Development 只能使用 Apple Sandbox API。
- Production 只能使用 Apple Production API。
- Product IDs、Issuer ID、Key ID 或 private key 缺失时继续 fail-closed。

新增 regression 覆盖缺失环境以及 Production 错指 Sandbox；既有交易幂等、跨用户认领拒绝、到期/退款/撤销与通知去重测试保持通过。

## 4. Production Worker repository configuration

`wrangler.jsonc` 只加入已经确认、且不属于 Secret 的静态发布配置：

- `APP_ENVIRONMENT=production`
- `SYNC_AUTH_MODE=cloudflare-access`
- `APPLE_CLIENT_IDS=com.lafayette.tastemap`
- `APP_STORE_BUNDLE_ID=com.lafayette.tastemap`
- `APP_STORE_API_ENVIRONMENT=production`
- R2 binding `PHOTO_STORAGE` → `taste-map-photos`

Production API custom domain、`PUBLIC_SHARE_ORIGIN`、正式 StoreKit Product IDs 和 server credentials 均未猜测、未填写。修改配置文件不等于部署；本轮没有执行 `wrangler deploy` 或任何 Production remote command。

## 5. Legal readiness

`ReleaseConfiguration` 继续只接受无 credentials、无 userinfo 的 HTTPS URL。Production validation 现在同时要求：

- Privacy Policy
- Terms of Service
- Support

缺少任一项都会产生明确 validation issue；Debug/Development 不会因此 crash，Release UI 也不会显示假链接。当前三个正式 URL 均未知，因此保留为空并列入 Manual Gate。

## 6. Associated Domains / public sharing

现有实现已经具备：

- AASA endpoint：`/.well-known/apple-app-site-association`
- Restaurant / Profile / List 的公开 share link 与匿名读取
- public/friends/private 权限检查
- revoked、private、deleted 内容不可访问
- 安全 HTTPS 图片 URL 过滤
- Debug entitlement 仅含 `api-dev.tastemap.cn?mode=developer`
- Release entitlement 在 Production domain 未确认前不伪造 Associated Domain

Production public origin、Release `applinks:` entitlement、Apple profile 刷新和真机 Universal Link 属于 Manual Gate。

## 7. UGC / App Review readiness

代码级最小闭环已存在并通过回归：

- 举报内容，包含 request fingerprint 幂等与限流。
- 屏蔽/取消屏蔽用户，并在 Feed、Search、Profile、Comment 和直接读取执行服务端隔离。
- 用户可删除自己的评论/内容。
- 账户删除正式闭环已实现。

真实 moderation 负责人、响应 SLA、内容政策、申诉/封禁流程和正式 Support 联系入口是运营 Manual Gate，不能由代码伪造。

## 8. D1 与 migration

Migration 顺序保持 `0001` 到 `0032_release_safety.sql`，本轮未新增或修改 migration。Production migration 必须先完成只读 preflight、备份与逐项授权；禁止 reset、重建或清空。

本轮 Production D1：未访问。

Development D1：未修改。

## 9. 自动化测试与构建

- Worker StoreKit / public sharing / release safety / social collaboration：4 files，23 tests，通过。
- iOS `Task08PremiumCommerceTests` + `SettingsFoundationTests`：全部通过。
- 最小 Premium UI smoke：`testP4HFreeProfilePaywallFeatureGateAndDevelopmentUpgrade`，通过。
- TypeScript typecheck + Vite production build：通过。
- Production Wrangler repository config：`wrangler deploy --dry-run` 通过；只生成本地 bundle，没有远程部署。
- iOS Debug Simulator build：通过。
- iOS Release Simulator build：通过。
- iOS Release generic device signed build：通过；Bundle ID `com.lafayette.tastemap`，Team `7G5J9MJX88`，最低系统 `17.0`，Release entitlement 不含 Development associated domain。
- Release Simulator App 扫描：不含 `api-dev.tastemap.cn` 或 Tests 的 `dev.*` StoreKit Product ID。
- StoreKitTest SDK 自带的 deprecated header warning 与仓库已有测试 warning 未由本轮引入，记录但未扩大范围处理。

## 10. Manual gates

完整、可执行且不含假值的人工步骤见：

[`MANUAL_RELEASE_CONFIGURATION_CHECKLIST.md`](../MANUAL_RELEASE_CONFIGURATION_CHECKLIST.md)

核心未完成外部项：App Store Connect 商品/订阅组、IAP API key、Sandbox/TestFlight、正式 Legal URL、Production API/public origin、AASA + Release Associated Domain、Production D1/R2/Worker 获授权后的预检与发布、UGC 运营流程、iOS 17 真机 smoke。

## 11. 修改边界

- SwiftData schema：未修改。
- 业务数据模型：未修改。
- 已执行 migration：未修改。
- Development Worker/D1：未部署、未写入。
- Production：未访问、未部署、未迁移、未写入。
- Secret：未写入客户端、plist、测试或 Git。
