# Taste Map Final Release Fixes — Task 07 Release Candidate Acceptance

日期：2026-08-30

分支：`main`

基线：`e1c6c05080f9eca6c3fc7f0dea46ea3eee748149`（`Prepare production release configuration`）

## 1. 最终结论

**CONDITIONALLY READY**

当前代码、自动化测试、Development E2E、Debug/Release 构建和 Release 二进制静态审计均已达到 Release Candidate 的工程验收条件。P0 数据隔离与删除边界、Sync 状态机、F1-C4 重复导入、核心视觉路径、社交/公开分享/订阅安全投影均通过自动化复核。

当前 **Production 状态：NOT READY TO DEPLOY**。原因不是已知代码 blocker，而是正式 Production Worker/API 域名、Production D1/R2 授权预检、Legal URL、App Store Connect/StoreKit server 配置、Associated Domains/AASA 以及真实设备/最低系统人工验收尚未完成。本轮没有以假值绕过这些外部 Gate，也没有访问 Production。

## 2. P0 Re-audit

结果：**PASS**。

- `LocalMultiAccountIsolationTests` 证明 A/B 本地数据隔离、核心 `@Query` 读取边界、照片元数据/文件边界、mutation/checkpoint 隔离。
- 当前账户删除只清理当前 Taste Map User 的业务记录、sync state 和 owned photo files；另一账户未同步数据仍保留。
- Restaurant、Visit、Dish、VisitDish、PhotoAsset、列表、社交、分析、发现/社区投影均经过 account-scoped capture 或明确 owner 过滤。
- Development release-safety E2E 重新验证账户删除 job、owner 检查和清理投影；使用隔离测试用户并完成清理。
- 未读取、迁移、删除或上传真实用户数据。

P0 证据：完整 iOS suite 中本地多账户隔离 6/6；Development release-safety E2E 通过；Task 01 报告中的 full local purge/other-user survival 场景保持通过。

## 3. Sync Re-audit

结果：**PASS（真机重试仍列 Manual Gate）**。

- Empty queue 仍可完成成功 sync，并得到最终成功状态。
- Push / pull / reconciliation 阶段状态正确。
- Push 失败或 response 丢失时 mutation 不会提前从本地队列移除。
- Timeout、retry 与 backoff 有明确上限。
- Manual/automatic synchronization 复用同一个 single-flight coordinator。
- Apple Maps-only Restaurant、Visit 关系、cursor、serverVersion、tombstone 与用户隔离均在 Development E2E 通过。
- 真机当前候选版本的“重试同步”点击流程没有在本轮自动代替用户操作，保留为 Manual Gate。

证据：`P1D sync coordination` 15/15；Development P2-G rich graph E2E 通过并完成测试数据 cleanup。

## 4. F1-C4 exact regression

新增隔离内存自动化：

`Legacy v4 manual cross-provider merge re-resolves Visit and a second import is a no-op`

它精确覆盖：

1. 严格读取 Legacy Web v4 JSON；
2. 第一次导入；
3. 本地 AMap Restaurant 与输入 Apple Maps identity 构成 cross-provider candidate；
4. 用户选择 manual merge；
5. dependent Visit 重新解析到既有 Restaurant UUID；
6. 第二次使用同一个 source；
7. Visit 被识别为 `exactDuplicate`；
8. Restaurant/Visit 均不新增；
9. mutation 数量不增加。

该测试没有使用或重复导入真实用户文件。此前挂起的 F1-C4 duplicate Visit 场景已经由这个精确自动化证明关闭；没有执行第二次真实 Import。

## 5. Task 07 发现并修复的回归

### 5.1 Import 结果页账户作用域

首次关键 UI suite 暴露：Import 已成功写入当前账户，但“导入结果 → 查看餐厅”创建 `RestaurantCollectionView` 时遗漏 `currentTasteMapUserID`。Task 01 的隔离层因此正确地隐藏了该账户记录，并显示空状态。

修复：从 `BackupImportResult.currentTasteMapUserID` 向餐厅列表显式传递当前账户 ID。未改变 Import transaction、merge、owner、sync queue 或 SwiftData schema。修复后单次 Legacy v4 导入、查看餐厅并进入详情的 UI 路径通过。

### 5.2 Release test-tier 环境入口

Release 二进制首次扫描发现 `TASTEMAP_UI_TEST_RUNTIME`、`TASTEMAP_TEST_TIER` 和 `XCTestConfigurationFilePath` 三个 runtime probe 字符串。真实 UI fixtures 本来已全部使用 `#if DEBUG`；残留来自 runtime tier resolver。

修复：测试 tier 环境键和 resolver 仅在 Debug 编译。Release 的 `TasteMapRuntimeConfiguration.current` 无条件返回 `.application`，不能被环境变量或 launch argument 切换到 fixture/test tier。Debug UI/unit automation 保持可用。

## 6. Full test/build matrix

| 验收项 | 精确结果 | 状态 |
| --- | ---: | --- |
| Worker Vitest | 49 files，340 tests | PASS |
| TypeScript typecheck | `tsc --noEmit` | PASS |
| Vite production build | production bundle | PASS |
| iOS full unit/integration | 577 top-level tests；582 device-level parameter invocations；0 failed；0 skipped | PASS |
| Task 07 affected regression | 20 top-level tests；23 device-level parameter invocations；0 failed | PASS |
| Critical UI E2E | 10/10 effective paths；首轮 9 pass + 1 account-scope failure，修复后失败路径 1/1 pass | PASS |
| iOS Debug Simulator build | generic iOS Simulator | PASS |
| iOS Release Simulator build | generic iOS Simulator | PASS |
| iOS Release signed device build | generic iOS，Automatic Signing | PASS |
| Development D1 migration preflight | `No migrations to apply` | PASS |
| Development P2-G rich Visit graph E2E | Apple Maps-only / idempotency / cursor / conflict / tombstone / isolation | PASS |
| Development P3-E three-user social E2E | profile / search / privacy / photo / community / cleanup | PASS |
| Development Task 09 public sharing E2E | Restaurant / Profile / List / revocation / forged owner / anonymous allowlist | PASS |
| Development Task 12 release-safety E2E | account deletion / moderation / ownership / cleanup | PASS |

完整 iOS suite 中重点子集：

- Local multi-account isolation：6/6。
- P1-D sync coordination：15/15。
- F1-C3 import merge engine：14/14。
- Release Safety：4/4。

测试环境：iPhone 17 Pro Simulator，iOS 26.5，serialized test host。既有 StoreKitTest SDK deprecated header、部分 Swift 测试 warning 和 Xcode debugger-version/device-discovery diagnostics 未导致 test/build 失败，也不是本轮新增业务 warning。

## 7. Development E2E 与数据安全

所有远程 E2E 只使用：

- Worker：`https://api-dev.tastemap.cn`
- D1：`food-map-db-development`
- 隔离的 Development test identity / test records

P2-G、P3-E、public sharing 和 release-safety 四条链路全部通过，测试数据按各自 cleanup/tombstone 规则完成收口。Development D1 没有 pending migration。本轮没有部署 Worker、没有执行 migration、没有修改 schema。

Production Worker / D1 / R2：**未访问、未查询、未部署、未迁移、未写入**。

## 8. Visual RC

视觉验收结果：**PASS**。

- Map 保持地图为主界面；顶部仅一层紧凑浏览控制容器，没有大标题 + 多层 toolbar 继续挤压地图。
- UI assertion：地图高度大于 App frame 的 72%；主要控制区不超过 112 pt；控制区底部距地图顶部不超过 170 pt。
- List 使用紧凑信息行；长名称仍完整可读，行高不超过 96 pt。
- Restaurant Detail 首屏顺序为 hero → identity → rating/sample → actions；大圆评分、小圆样本数量语义保持不变。
- Light/Dark compact-map assertions 通过。

最终 RC 截图：

- [Map](final-release-fixes-07-assets/map.png)
- [List](final-release-fixes-07-assets/list.png)
- [Restaurant Detail](final-release-fixes-07-assets/restaurant-detail.png)
- [Map Dark](final-release-fixes-07-assets/map-dark.png)

## 9. Release binary audit

Release Simulator App 与 Share Extension 两个 executable 均扫描通过，以下 marker 计数全部为 0：

- Development URL：`api-dev.tastemap.cn`
- UI/test runtime：`TASTEMAP_UI_TEST_RUNTIME`、`TASTEMAP_TEST_TIER`、`XCTestConfigurationFilePath`、fixture environment keys
- Development auth：`development-test`、`X-Taste-Map-Test-User`
- Demo seed/admin：`seed-development-demo`、`ADMIN_EMAILS`
- Fake StoreKit ID：`dev.tastemap.storekit`
- App Store secret keys/private key markers
- embedded bearer/JWT/private-key marker

Release App metadata：

- Bundle Identifier：`com.lafayette.tastemap`
- Minimum iOS：`17.0`
- Version/build：`1.0 (1)`
- Team：`7G5J9MJX88`
- Sign in with Apple：保留
- App Group：`group.com.lafayette.tastemap`
- Development associated domain：不在 Release entitlement

Generic device build 当前由 Automatic Signing 的 Apple Development profile 签名，用于编译/签名可行性验收；Distribution/TestFlight archive 仍是人工发布流程。

## 10. 01–07 commits / push

| Task | Commit | Commit message | Push |
| --- | --- | --- | --- |
| 01 | `0eafe9f3dccee92678f8ebb8b4e868a6ebdc730a` | `Fix local multi-account data isolation` | pushed |
| 02 | `57f6af5f4f0d77882dc36c97b6ca5fd1aacab175` | `Fix SyncEngine retry and status handling` | pushed |
| 03 | `61321e6dac359b2e67639792d631b70ae1c1b8e2` | `Isolate test runtime and migration fixtures` | pushed |
| 04 | `c8cae534e00ad6910abce97df532bfae34e38bfe` | `Restore core Web layout parity` | pushed |
| 05 | `792ef6c799a8922c978c3ae4d6a81da3df8104f2` | `Finalize iOS release support scope` | pushed |
| 06 | `e1c6c05080f9eca6c3fc7f0dea46ea3eee748149` | `Prepare production release configuration` | pushed |
| 07 | 本报告所属独立 commit | `Complete release candidate acceptance` | commit 后立即 push 并在最终对话报告给出 hash |

## 11. Manual Gates（16 项）

1. **Production Worker/API domain**：在 Cloudflare 绑定正式 HTTPS custom domain；把同一 origin 注入 iOS Production API config；验证 Release 不 fallback 到 Development。
2. **Production D1 preflight/migration**：用户明确授权后先只读基线和备份，再逐个增量应用 pending migrations，禁止 reset/rebuild。
3. **Production R2**：确认 `taste-map-photos`、`PHOTO_STORAGE`、CORS/lifecycle/恢复策略；另行授权后用专用账号 smoke。
4. **Subscription Group / Product IDs**：在 App Store Connect 创建/确认月度和年度产品、价格、地区、本地化与审核资料；禁止使用 `dev.*`。
5. **App Store Server API key**：在 App Store Connect 创建最小权限 key；`.p8` 仅进入 Worker encrypted secret，不进聊天/客户端/Git。
6. **App Store Server Notifications V2**：先配置 Sandbox、后配置 Production notification URL，验证 notification UUID 幂等和 entitlement 投影。
7. **Sandbox/TestFlight StoreKit**：真机验证 product load、buy、pending、cancel、restore、renew、expire、billing retry、refund/revoke、restart 和 user switch。
8. **Legal URLs**：发布真实 Privacy Policy、Terms、Support HTTPS 页面并注入 Production configuration；validation 必须为零 issue。
9. **Production public origin / AASA / Associated Domains**：确认唯一分享域名、AASA、Release `applinks:`，刷新 profile 并真机验证公开/撤销/私密链接。
10. **Share Extension real-device**：分别从 Apple Maps、高德、普通 URL/text 分享；验证 App Group handoff、Restaurant 识别和 Universal Link。
11. **UGC moderation operations**：指定举报负责人、SLA、内容政策、封禁/申诉流程和真实 Support 联系方式。
12. **App Store Connect metadata**：完成 App Privacy、年龄分级、审核联系人/说明/账号、截图、Support/Privacy URL。
13. **Latest-build Sync retry**：在当前候选真机 build 的 Settings → Sync 执行一次 Sync Now/Retry，记录 stage/result。
14. **Latest-build general smoke**：真机验证 Sign in、Add Restaurant、Visit、Dish、Photo、Map/List/Search、Profile/List、Social、Like/Comment、Discovery/Community，以及一次安全 Import。
15. **Test-account Account Delete**：仅用专用测试账户执行真实不可逆删除，确认 server job、Keychain/local purge、其他账户不受影响。
16. **iOS 17 minimum-runtime smoke**：在 iOS 17.x 真机或 Simulator 验证 launch、登录、核心记录、照片、同步、Settings、分享与 Premium fail-closed。

详细操作位置和安全要求见根目录 [MANUAL_RELEASE_CONFIGURATION_CHECKLIST.md](../MANUAL_RELEASE_CONFIGURATION_CHECKLIST.md)。

## 12. P0 / P1 / P2 / P3 状态

- **P0 — 数据安全、身份、同步、删除：PASS。** 没有已知跨用户读取/照片/mutation/删除泄漏。
- **P1 — Release-critical product flow：PASS。** Map/List/Detail、Import、sync presentation、auth/account routes 通过自动化和构建；真实设备 smoke 待 Gate。
- **P2 — Rich records / sharing / Premium architecture：PASS。** Development-safe E2E 与自动化通过；正式 R2/StoreKit 外部配置待 Gate。
- **P3 — Social / discovery / community / release operations：PASS for code，PENDING for operations。** 三用户自动化和 privacy enforcement 通过；真实 moderation 运营与发布资料待 Gate。

## 13. 修改文件

- `ios/TasteMap/TasteMap/App/TasteMapRuntimeConfiguration.swift`
- `ios/TasteMap/TasteMap/Features/Settings/Import/BackupImportPlanView.swift`
- `ios/TasteMap/TasteMapTests/BackupImportMergeEngineTests.swift`
- `reports/FINAL_RELEASE_FIXES_07_RELEASE_CANDIDATE_ACCEPTANCE.md`
- `reports/final-release-fixes-07-assets/map.png`
- `reports/final-release-fixes-07-assets/list.png`
- `reports/final-release-fixes-07-assets/restaurant-detail.png`
- `reports/final-release-fixes-07-assets/map-dark.png`
- `TasteMap_FINAL_RELEASE_FIXES_REPORT.md`

没有修改：SwiftData schema、JSON contracts、Worker、D1、migration、R2、Production、Bundle Identifier、Team、signing setting、App Icon 或业务同步协议。

## 14. 距离 App Store 提交还剩什么

工程 RC 已关闭当前可自动完成的代码项；剩余内容集中为上述 16 个外部/真机 Manual Gates。完成 Production configuration 与授权预检、Legal/StoreKit/App Store Connect 配置、真实设备 smoke 后，需要再生成正式 Distribution archive，执行上传前 binary/entitlement/privacy/metadata 最终复核，才可将 Production 状态从 `NOT READY TO DEPLOY` 改为 `READY TO DEPLOY`。
