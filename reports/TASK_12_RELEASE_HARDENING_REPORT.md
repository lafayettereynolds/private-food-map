# Taste Map Task 12｜Release Hardening 验收报告

日期：2026-08-30
分支：`main`
基线：`17d0fb5498150d6da328eb3559cd9cc0aa1b402a`（`Complete Taste Map visual restoration`）
范围：所有当前可自主完成的 Release Hardening、账户删除、UGC 安全、回归测试与 Development 验收
Production：未访问、未查询、未迁移、未部署、未写入

## 1. 结论

Task 12 的自主工程部分已经完成，并关闭 Task 10 的三个代码级发布阻塞项：

1. F1-C4 同一备份第二次导入产生 duplicate Visit：已修复，并增加完整 Restaurant / Visit / Dish / Photo / Companion / Source / List 图谱的二次导入 no-op regression。
2. Account Delete：已实现 authenticated preview → fresh Apple re-auth → durable deletion job → D1/R2 清理 → session revoke → iOS local purge → Keychain 清理的正式闭环。
3. UGC Report / Block：已实现服务端举报、幂等、限流、屏蔽/取消屏蔽，以及 Feed、公开主页、搜索、评论和直接交互的服务端过滤。

当前仍不能宣称“已经提交 App Store”或“Production 已上线”。Production 变更、真实 StoreKit、TestFlight、正式 Legal URL、Production Universal Link/AASA、真机完整 smoke 和测试账户真实删除，均属于必须由项目所有者参与或明确批准的 Release Gate。

因此本轮状态为：

- **代码与 Development 验收：完成。**
- **Task 07–12 当前可自主完成部分：完成。**
- **Production / TestFlight / App Store 发布：Pending Release Gates。**
- **Release tag：未创建，避免把未通过外部 Gate 的版本伪装成正式 RC。**

## 2. F1-C4 duplicate Visit 修复

`BackupImportPlanEngine` 现在将备份源实体 ID 稳定映射到本地/远端实际 ID，并对以下完整图谱识别已经导入的 deterministic target：

- Restaurant
- Visit
- Dish
- Photo
- VisitDish
- DiningCompanion
- RecommendationSource
- RestaurantList / RestaurantListItem
- tombstone

同一份 Backup v1 第二次导入现在是严格 no-op：

- 不重复建立 Restaurant。
- 不重复建立 Visit。
- 不重复建立 Dish、Photo、关系或榜单项。
- 第一次导入后用户自己做的本地修改不会被旧备份覆盖。
- 不执行或依赖第二次真实 Import 文件 destructive smoke；回归使用隔离 fixture/SwiftData store。

## 3. Account Delete 架构

### Worker API

- `GET /api/v1/account-deletion/preview`
- `POST /api/v1/account-deletion/confirm`
- `GET /api/v1/account-deletion/status`
- `POST /api/v1/account-deletion/retry`

`preview/confirm` 只接受 Worker 认证出的 Taste Map User；客户端 `userId` 没有授权意义。真实账户 confirm 要求 10 分钟内的 fresh Apple authentication。Development test identity bypass 只在 `APP_ENVIRONMENT=development` 且 Development auth 模式下生效。

### Durable job

- 客户端生成随机 request ID 和 opaque status token。
- D1 只保存 status token SHA-256，不保存原文。
- `(user_id, request_id)` 唯一，重复请求指纹不一致时拒绝。
- D1 数据和 R2 对象分阶段处理；R2 失败保留 job/object 状态并可安全重试。
- status/retry 只持有专用 opaque token，不要求已经被撤销的 access token。
- 完成后撤销该 Taste Map User 的全部 auth session，删除 Apple auth identity mapping，并将 user/profile 做隐私安全 tombstone。
- 同一 Apple subject 以后再次注册会得到新的 `tm_...` 用户，不恢复旧 ownership。

### 删除边界

当前用户拥有的数据会 soft-delete/scrub：

- Restaurant / Visit / Dish / VisitDish
- Photo metadata 与 R2 originals/thumbnail
- Companion / RecommendationSource
- Restaurant Lists / Items
- WantToGo
- follows / friendships / shared meals / collaboration edges
- likes / current-user comments
- public share links
- current profile
- auth identity / sessions

不会删除其他用户自己的 Visit、List 或 Comment。其他用户指向被删用户的 companion/source identity 引用会解除。App Store transaction/ownership ledger 与必要的安全审计记录保留，用于退款、争议与反滥用审计；不再授予已删除账户业务访问权限。

### iOS 流程

`Settings → Account → Delete Account`：

1. 显示删除范围与本机 pending sync。
2. 提供 Backup v1 导出入口。
3. 使用 Apple 登录 fresh re-auth。
4. 只有重新认证映射到同一 Taste Map `tm_...` 用户才接受新 session。
5. 如果误选不同 Apple 账户，临时 session 立即撤销，且不会覆盖当前 Keychain session。
6. 用户必须输入精确 `DELETE` 并通过最终 destructive confirmation。
7. status token 在发送 confirm 前保存到独立 ThisDeviceOnly Keychain item。
8. server job 完成后才清理 SwiftData、sync queue、derived cache、本地照片和 auth Keychain。
9. App 在 confirm response 丢失或被杀死后，会在下一次启动用 status token 恢复并完成本地清理。
10. 离线/服务端失败不会假装账户已删除。

## 4. UGC 举报与屏蔽

新增：

- `POST /api/v1/community/reports`
- `PUT /api/v1/community/blocks/:userId`
- `DELETE /api/v1/community/blocks/:userId`

安全语义：

- reporter/blocker 只来自认证 session。
- 不能举报或屏蔽自己。
- 举报 request ID + fingerprint 幂等，冲突 payload 返回错误。
- 举报和屏蔽有独立 rate-limit bucket。
- 屏蔽立即解除双方 follow/friendship。
- 屏蔽是可见性上的双向隔离：Feed、公开主页、用户搜索、评论读取与直接互动都会在服务端过滤，不能通过直接猜 ID 绕过。
- iOS Community、Visit/Comment interaction 和公开主页均有真实举报/屏蔽入口，不是仅本地隐藏。

生产运营仍需配置实际 moderation review 流程、内容政策和响应 SLA；代码已提供最小 App Review 闭环，但没有伪造后台人工审核已经运行。

## 5. D1 migration `0032_release_safety.sql`

仅新增：

- `account_deletion_jobs`
- `account_deletion_objects`
- `user_blocks`
- `content_reports`
- 所需唯一索引、pending/status 查询索引和 moderation 查询索引

Migration 是 additive incremental DDL，使用 `IF NOT EXISTS`，不重建、不清空、不删除既有表，也不修改已经执行过的 migration。

Development D1 `food-map-db-development`：

- preflight 时唯一 pending migration：`0032_release_safety.sql`
- 0032：成功应用
- 完成后 preflight：`No migrations to apply`
- Task 12 活跃测试用户：`0`

Production D1 未访问。

## 6. Development Worker / E2E

- URL：`https://api-dev.tastemap.cn`
- Worker：`private-food-map-development`
- Version ID：`97e287fd-b2a3-461b-bf6d-de78e11d55e6`
- D1：`food-map-db-development`
- R2：`taste-map-photos-development`

真实 HTTPS Development E2E 已验证：

- sync payload 伪造 owner 被 Worker 覆盖。
- 用户 B 无法读取用户 A Restaurant。
- report create + duplicate idempotency。
- block + duplicate + unblock。
- account deletion preview current-user scope。
- confirm 完成与 durable status 重复读取。
- 删除后旧 Development identity 无法访问 sync。
- 两个隔离 fixture user 均通过正式 deletion path 清理。

没有查询或调用 Production endpoint。

## 7. Privacy Manifest / Legal / Release 配置

新增 `PrivacyInfo.xcprivacy`：

- Tracking：false
- Required Reason API：File Timestamp / `C617.1`
- linked app functionality data：name、email、user ID、purchase history、photos/videos、other user content

Release 产物已确认包含 Privacy Manifest。

正式 Privacy Policy、Terms 和 Support URL 当前仍未配置。`ReleaseConfiguration` 继续 fail-closed：

- Debug 不因缺 URL crash。
- Release 不显示假链接。
- release validation 可以报告缺项。

App Store Connect Privacy Nutrition Labels 仍需项目所有者根据最终 Production 数据流人工确认并填写，Privacy Manifest 不能替代 App Store Connect 表单。

## 8. Release / Development 隔离

- Bundle ID：`com.lafayette.tastemap`
- Team：`7G5J9MJX88`
- Automatic Signing：保持
- Sign in with Apple：保持
- App Group：`group.com.lafayette.tastemap`
- Share Extension：保持

配置处理：

- `APIEnvironment.plist` 不再携带 Development URL。
- `https://api-dev.tastemap.cn` 只在 `#if DEBUG` 的集中 `AppEnvironment` Development default 中存在。
- Release 缺少 Production URL 时明确不可联网，不会 fallback 到 Development。
- Debug entitlement 保留 Development Associated Domain。
- Release 使用独立 `TasteMapRelease.entitlements`，当前只保留 Apple 登录和 App Group；未在 Production domain/AASA 未确认时伪造 Associated Domain。

最终 Release Simulator 与 Release iPhoneOS app 均扫描确认：

- `api-dev.tastemap.cn`：不存在。
- Development applink：不存在。
- Bundle ID / Team entitlement：正确。
- Privacy Manifest：存在且 plist 合法。

## 9. Accessibility / Dark Mode / Reduce Motion

- Core Theme 增加 Dark palette contract 和对比度测试。
- Analysis App pages 改用动态 semantic canvas/card/ink/hairline；独立分享海报继续固定 light，保证导出视觉一致。
- Premium 页面移除强制 light mode 和硬编码白色主表面。
- Roulette 与自定义 segmented control 尊重 Reduce Motion；无障碍开启时不执行非必要动画。
- 举报/屏蔽、账户删除和 icon-only actions 提供可读 label/identifier。
- 已有 Dynamic Type、44pt control、rating 可读语义和业务关键信息完整展示继续由全量 UI/unit suite 覆盖。

真机 VoiceOver、最大 Accessibility Dynamic Type、Dark Mode 多设备人工巡检仍属于 Release Smoke，不伪报已人工完成。

## 10. Performance / Stability

现有并在本轮全量单元测试中通过的规模 fixture：

- 1,000 Restaurants
- 10,000 Visits
- 5,000 Dishes
- Backup Export / Import / Legacy Decoder
- map/list/filter projection
- annual recap / On This Day aggregation

本轮安全修复还处理了可安全消除的 Swift actor-isolation/concurrency warning，并保持 model/network/view 职责不变。

真机 Instruments 的 launch、map scroll、gallery、poster export、import transaction 和 memory trace 尚未执行，列为 Manual Release Gate。

## 11. 自动化测试

### Web / Worker

- `pnpm typecheck`：通过。
- `pnpm run build`：通过。
- `pnpm run test:task12`：通过。
  - migration test：通过。
  - 5 Worker files / 38 tests：全部通过。
- `pnpm run test:task12:development`：真实 Development HTTPS E2E 通过。
- Vite 仅保留已有 large-chunk advisory，不是 build failure。

覆盖：preview/confirm、D1+R2、R2 failure/retry、double confirm/idempotency、session revoke、新 Apple 登录获得新 tm user、A/B 隔离、举报幂等、自举报拒绝、屏蔽对 feed/profile/search/comments 的强制执行。

### iOS unit

- 全量 `TasteMapTests`：554 tests passed，0 failed，0 skipped。
- 最终 targeted ReleaseSafety/Auth/Configuration regression：全部通过。
- 关键性能、Import/Export、offline/sync、user isolation、Premium、public sharing、P0–P4 既有回归均在全量 suite 中通过。

### iOS UI smoke

最终路径：5/5 通过。

- Settings → Backup privacy flow
- Task 07 Community actions
- Premium paywall / Development entitlement fixture
- Public Profile List → WantToGo → visibility revocation
- P1-D offline create → second Visit → edit one Visit → delete one Visit

首轮两条失败是 UI test 仍使用旧文案/旧表单顺序；改为稳定 identifier 与当前正式页面顺序后单独回归通过，没有修改 Visit 或 List 业务语义。

### Builds

- Debug iPhone 17 Pro Simulator：通过。
- Release generic iOS Simulator：通过。
- Release generic iOS device：通过。
- iPhoneOS signing：Apple Development + `iOS Team Provisioning Profile: com.lafayette.tastemap`，Team `7G5J9MJX88`。

## 12. Git / Production

- 计划 commit message：`Complete release hardening and data safety`
- 报告内不自填不可稳定的自引用 commit hash；最终 hash 与 push 结果见流水线总报告和 `git log`。
- Production Worker：未访问。
- Production D1：未访问。
- Production R2：未访问。
- Production secrets：未读取、未修改。
- Production migration：未执行。

## 13. Pending Release Gates

1. 明确授权 Production 只读 preflight。
2. 为 Production Worker 配置正式 API base URL、secrets presence、Apple auth、StoreKit validation 和 public sharing；任何 secret 不进入 Git/iOS。
3. 备份/回滚计划确认后，将 0030、0031、0032 等缺失 migration 增量应用到 Production D1；禁止 reset/rebuild。
4. 配置正式 public domain、AASA 和 Release Associated Domains，再重新生成/刷新 provisioning。
5. 配置正式 Privacy Policy、Terms、Support HTTPS URL。
6. App Store Connect 创建 Subscription Group、正式 Product IDs、价格、地区、本地化和审核材料。
7. 将 Issuer ID、Key ID、`.p8` 只注入 Worker secret；配置 App Store Server Notifications V2。
8. 真实 Sandbox/TestFlight purchase、pending/cancel、restore、renew、expire、refund/revoke。
9. 真机 Share Extension + App Group + Universal Link smoke。
10. 使用专用测试 Apple/Taste Map 账户执行完整 20 步 smoke；绝不能用主账户做 destructive delete。
11. 真机 Instruments 与 VoiceOver/Dynamic Type/Dark Mode 人工抽查。
12. App Store Connect Privacy Labels、age rating、export compliance、screenshots、metadata、review notes。
13. 锁定正式 marketing version/build number，Archive/Upload/TestFlight RC。
14. 所有 Gate 通过后才创建 release tag；当前不创建 tag。

## 14. 已知问题

- F1-C4 duplicate Visit：代码与自动化 regression 已关闭；尚未进行第二次真实 Import destructive smoke，按用户指示不重复执行该真实文件测试。
- Production 尚未配置，因此 Release build 会明确缺失 Production API URL；这是 fail-closed 的发布配置 Gate，不是 Development 回退。
- StoreKit 正式商品和 Sandbox/TestFlight 尚未配置/人工验证。
- Production Universal Link/AASA 尚未配置。
- Legal URL 尚未锁定。
- 真机完整 smoke、真实测试账户删除、Instruments 尚未执行。
