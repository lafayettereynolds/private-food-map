# Taste Map Task 08 — Premium + StoreKit 2 验收报告

日期：2026-08-30

分支：`main`

基线：`6a8c6e184de0cb8deb9d1923b6f7d794bc5d2c4f`

## 1. 结论

Task 08 的可自主完成部分已完成：iOS 已接入 StoreKit 2 商品加载、购买状态、交易更新、当前权益恢复、显式恢复购买和管理订阅；Worker 已建立版本化 StoreKit commerce API、Taste Map 用户级 `appAccountToken`、Apple Server API 复核、交易账本、订阅 owner 锁定、幂等通知和 membership entitlement 投影。

正式 App Store Connect 商品、Sandbox/TestFlight 购买和 Production 配置仍是 Release Gate。本任务没有伪造正式 Product ID、价格、Issuer ID、Key ID 或 `.p8`，也没有访问 Production。

## 2. iOS 架构

- `StoreKitMembershipPurchaseProvider` 是唯一正式 StoreKit 2 provider。
- 商品标识及 `appAccountToken` 只从已认证 Worker `/api/v1/storekit/config` 获取。
- 价格、商品名和账期展示来自 StoreKit `Product` / `displayPrice`，不硬编码价格。
- `purchase` 明确区分 completed、pending、user-cancelled 和 unverified。
- verified transaction 必须成功调用 Worker reconcile 后才 `finish()`；客户端 Premium bool 不是 authority。
- App 启动后监听 `Transaction.updates`，登录用户激活时处理 `Transaction.currentEntitlements`。
- Restore 是明确用户操作，调用 `AppStore.sync()`；Manage 使用系统订阅管理页面。
- Worker entitlement 更新后，现有 `PremiumEntitlementService` 重新拉取服务端 projection。
- 离线权益仍复用现有 Keychain cache 与最大七天验证窗口；logout 删除当前用户缓存，用户切换按 Taste Map User ID 隔离。
- Terms / Privacy 只在 `ReleaseConfiguration` 中存在正式 HTTPS URL 时显示。

## 3. Worker API

### `GET /api/v1/storekit/config`

需要 Taste Map access token。返回：

- `apiVersion`
- `configured`
- 当前 Taste Map 用户稳定且独立的 `appAccountToken`
- Product ID + monthly/annual period 引用

不返回价格，不接受客户端 userId。

### `POST /api/v1/storekit/transactions/reconcile`

客户端只提交十进制 `transactionId`。Worker：

1. 使用 secret 注入的 App Store Connect Issuer/Key/private key 创建短期 ES256 server JWT。
2. 从 Apple App Store Server API 读取交易。
3. 校验 transaction/original transaction、Bundle ID、允许的 Product ID、订阅类型、environment、日期和 `appAccountToken`。
4. 要求交易 token 与当前已认证 Taste Map User 的 server-side account mapping 一致。
5. 原始订阅一旦归属某用户，不能被其他 Taste Map User 认领。
6. 幂等写入 transaction ledger，并投影到现有 `membership_entitlements`。

### `POST /api/v1/storekit/notifications`

通知内 JWS 只用于路由交易 ID；Worker 不直接相信其 entitlement 内容，而是重新通过 Apple Server API 获取交易。`notificationUUID` 去重；未知 `appAccountToken` 不会自动绑定第一个或任意用户。

## 4. D1 migration `0030`

仅应用到 `food-map-db-development`：

- `app_store_accounts`
- `app_store_subscription_owners`
- `app_store_transactions`
- `app_store_notification_events`
- 必要的 user/original transaction 查询索引

迁移为增量、幂等 DDL；不删除或重建已有表。Production D1 未查询、未 migration、未写入。

## 5. Development 验收

- Development Worker：`https://api-dev.tastemap.cn`
- Worker version：`08b4fb5b-ce6d-4a0e-ad90-61d71bf43948`
- Development D1：`food-map-db-development`
- `0030_app_store_commerce.sql`：成功应用
- `/api/v1/storekit/config`：HTTP 200；因正式商品未配置，明确返回 `configured: false`、空 products、稳定 server-side token
- `/transactions/reconcile`：HTTP 503 `storekit_catalog_not_configured`，安全失败且不回退到假商品
- smoke test 临时用户及其 account/profile 记录已按精确 ID 清理

## 6. 自动化测试

- Worker migration + commerce/auth tests：15/15 passed
- iOS `Task08PremiumCommerceTests`：4/4 passed
- iOS 现有 `P4HPremiumEntitlementTests`：12/12 passed
- Web/Worker TypeScript build + Vite build：passed
- iOS Debug Simulator build：passed
- iOS Release Simulator build：passed
- `git diff --check`：passed

覆盖：用户 token 隔离、目录无价格、交易幂等、跨用户认领拒绝、旧交易不回退续订、到期、退款/撤销、通知去重、未知 token 不认领、缺 secret fail-closed、pending/cancelled、用户切换/logout、Development-only StoreKit fixture。

## 7. Release Gates

App Store 上线前仍必须由项目所有者在 App Store Connect / Apple Developer 完成：

1. 创建 Subscription Group。
2. 创建并确认月度、年度正式 Product ID。
3. 完成价格、地区、本地化、审核信息与订阅条款。
4. 创建 In-App Purchase App Store Connect API key，安全提供 Issuer ID、Key ID、`.p8` 给 Worker secret 管理；不得进入 Git 或客户端。
5. 为 Development Worker 注入 Sandbox catalog/server secrets，执行真实 Sandbox/TestFlight buy、pending、cancel、restore、renew、expire、refund/revoke smoke。
6. 配置 App Store Server Notifications V2 的 Development URL。
7. 锁定正式 Privacy Policy / Terms HTTPS URL。
8. Task 12 获得明确批准后，才可迁移/部署 Production D1/Worker 和 Production App Store 配置。

这些 gate 不阻塞 Task 09–11 的独立开发，但在 Task 12 发布关闭前必须完成，不能宣称正式收费已上线。

## 8. 安全边界

- 没有 secret 写入 iOS、plist、测试 fixture 或 Git。
- Local `.storekit` 只存在于 Tests，Product ID 以 `dev.` 开头且明确不是正式商品。
- 客户端 userId、Premium bool、商品价格和通知 payload 均不具有授权意义。
- Production Worker、D1、R2、migration 和 secrets 均未访问。
