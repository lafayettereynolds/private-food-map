# Taste Map 连续串行执行总报告｜Task 07–12

日期：2026-08-30
分支：`main`
执行模式：连续串行；每个 Task 基于前一个已 push 的最新 `main`；无并行修改 main；无 force push/reset/rebase/history rewrite
Production：全流程未访问或修改

## 1. 总结

Task 07–11 已分别完成、独立 commit 并 push。Task 12 已完成所有当前可自主完成的代码、测试、Development migration/deploy/E2E 和 Release build；本报告与 Task 12 的独立提交一同交付，最终 commit/push 状态以交付消息和仓库 `main` 历史为准。

本轮最终形成的原生主线能力：

- Discovery / Community 产品一致性
- Premium / StoreKit 2 production-shaped architecture
- Share Extension / Public Sharing
- Web ↔ iOS 最终功能一致性审计
- Global Visual Restoration
- Account Delete / UGC Report & Block / duplicate Import fix
- Accessibility / Dark Mode / Reduce Motion / Release environment hardening
- Privacy Manifest / Release signing build / Development release-safety E2E

当前阻塞 App Store 发布的事项均是外部或高风险 Gate，不是继续写普通代码可以安全解决的事项。

## 2. Task 状态矩阵

| Task | 状态 | Commit | Push | Tests | Build |
| --- | --- | --- | --- | --- | --- |
| 07 Discovery + Community parity | 完成 | `6a8c6e184de0cb8deb9d1923b6f7d794bc5d2c4f` | `origin/main` 已同步 | 新增 7 项 parity unit、2 条 Task 07 UI path；Worker/Development suite 通过 | Debug/Release 通过 |
| 08 Premium + StoreKit | 自主工程完成；ASC Gate pending | `acccb8025cb0cc3425cf0634cdf4e75493d22474` | 已 push | Worker 15/15；iOS commerce 4/4；既有 entitlement 12/12 | Debug/Release Simulator 通过 |
| 09 Share Extension + Public Sharing | 自主工程完成；真机/Production domain Gate pending | `9b319c47e7dc8395abab1f82e02459460489bbd8` | 已 push | Worker 6/6；iOS pending-import/public-sharing suites 通过；Development E2E 通过 | Debug/Release + embedded extension validation 通过 |
| 10 Final Feature Parity Audit | 完成 | `ce24c389568092d13b23c452e901dc4387cc181f` | 已 push | Web/Worker 334 tests；iOS 526 tests；7 条跨模块 UI path | Debug/Release 通过 |
| 11 Global Visual Restoration | 完成 | `17d0fb5498150d6da328eb3559cd9cc0aa1b402a` | 已 push | Theme 2/2；Core visual UI 10/10 | Debug/Release Simulator 通过 |
| 12 Release Hardening | 自主工程完成；发布 Gate pending | 本报告所属 Task 12 独立提交 | 随 Task 12 提交推送；以交付消息和 `origin/main` 为准 | Worker 38/38；iOS full unit 554；UI smoke 5/5；Development E2E 通过 | Debug Simulator、Release Simulator、Release iPhoneOS 均通过 |

## 3. Task 07

完成：

- 发现页 适合你 / 同味 / 趋势模式。
- city/window/filter/sort/reasons/sample-aware similarity。
- Community public Visit/Want activity、viewer actions 与本地缓存。
- WantToGo / Visit / List / Roulette / Restaurant / Profile 导航闭环。
- 不伪造 similarity、trending 或推荐原因。

报告证据由 Task 10 最终 parity audit 统一收口。

## 4. Task 08

完成：

- StoreKit 2 product loading abstraction、purchase、restore、transaction updates。
- entitlement state machine、offline cache 与 user isolation。
- Worker Apple Server API verification boundary、transaction ledger、idempotency、expiry/revocation/refund handling。
- Development migration 0030 与 fail-closed 未配置状态。
- Paywall 使用 StoreKit 返回价格，不硬编码假价格。

Pending：正式 Product IDs、Subscription Group、ASC API credentials、Sandbox/TestFlight。

详细报告：`reports/TASK_08_PREMIUM_STOREKIT_REPORT.md`

## 5. Task 09

完成：

- 独立 Share Extension target。
- App Group pending import queue；extension 不接触 auth token。
- URL/text size/expiry/replay/malformed 防护。
- Restaurant/Profile/Public List 稳定 opaque public URL。
- strict anonymous public DTO 与动态 privacy revocation。
- Development AASA 与 Development E2E。

Pending：真机系统 Share Sheet、Production domain/AASA/Universal Link。

详细报告：`reports/TASK_09_NATIVE_SHARING_REPORT.md`

## 6. Task 10

完成：

- 重新扫描 Web、Worker、iOS、tests 和 migrations。
- 264 个原子 parity 检查项。
- 当时 release-scope A+D：245/255，96.1%。
- 低风险 UI harness 漂移修复。
- 将 Account Delete、duplicate Import、UGC Report/Block、StoreKit/Share/Legal/Production Gate 固化为唯一 blocker 清单。

Task 12 已关闭其中所有代码级 blocker；外部 Gate 仍保留。

详细报告：`reports/WEB_IOS_FEATURE_PARITY_AUDIT.md`

## 7. Task 11

完成：

- 以 Web 正式产品为视觉 Source of Truth。
- Core App semantic Theme 与 Analysis/Poster Theme 分层。
- 地图、Restaurant、Visit、Profile、Settings、Discovery/Community、Premium 等核心页面视觉恢复。
- 保留海报与 Roulette 已确认方向。
- 品牌灰蓝、冷白/浅冷灰蓝、深蓝灰文字、轻边框/阴影和可访问对比度。

详细报告：`reports/TASK_11_VISUAL_RESTORATION_REPORT.md`

## 8. Task 12

完成：

- F1-C4 duplicate Visit 修复与完整图谱二次导入 no-op regression。
- durable Account Delete + fresh re-auth + D1/R2 retry + session revoke + local purge + Keychain resume。
- UGC Report / Block 服务端闭环与 iOS 入口。
- 0032 Development migration/deploy/E2E。
- Privacy Manifest。
- Release/Development URL 和 entitlement 隔离。
- Dark Mode / Reduce Motion / safe concurrency warning 修复。
- 全量 unit、关键 UI、Debug/Release/iphoneOS signing build。

详细报告：`reports/TASK_12_RELEASE_HARDENING_REPORT.md`

## 9. 已完成能力

- 原生 iOS local-first Restaurant / Visit / Dish / Photo 全记录闭环。
- 去过 / 想吃 / 地图 / 列表 / 搜索 / 筛选 / Marker / Footprints。
- 完整 Restaurant Detail、Visit context、多维评分、菜品、照片。
- Auth / Keychain / Sync / D1 / R2 Development 链路。
- Profile / Social / Friend / Follow / Shared Meal。
- Discovery / Community / Like / Comment / Report / Block。
- Analysis / Monthly / Annual / Companion / Source / On This Day / Poster。
- Restaurant Lists / Roulette。
- Backup Export / Legacy/Backup Import 与 duplicate-safe merge。
- Premium/StoreKit architecture。
- Share Extension/Public links architecture。
- Account Delete architecture。
- Core Visual Theme、Dark semantic color、Reduce Motion、Accessibility baseline。

## 10. 未完成项 / Hard Gates

### Apple / App Store Connect

- Subscription Group。
- 正式 monthly/annual Product IDs、价格、地区、本地化、审核信息。
- Issuer ID / Key ID / `.p8` 通过 Worker secret 注入。
- App Store Server Notifications V2。
- Sandbox/TestFlight 真实 purchase/restore/renew/expire/refund/revoke。
- 锁定 marketing version/build，Archive/Upload/TestFlight RC。

### Production

- 取得明确批准后先做只读 preflight。
- 核对 Worker/D1/R2/secrets/auth/StoreKit/public sharing/account delete。
- 缺失 migrations 的 backup/rollback plan 和 incremental apply。
- Production Worker deployment。
- Production API Base URL。

### Legal / App Review

- Privacy Policy、Terms、Support 正式 HTTPS URL。
- App Store Privacy Labels / age rating / export compliance。
- UGC moderation 运营流程、内容政策、Review Notes。
- screenshots、metadata、审核说明。

### Capabilities / 真机

- Production public domain/AASA/Associated Domains。
- Share Extension / App Group / Universal Link 真机 smoke。
- 专用测试账户 20 步真机 smoke，包括真实 Apple 登录和 destructive Account Delete。
- VoiceOver、最大 Dynamic Type、Dark Mode、Reduce Motion 真机人工抽查。
- Instruments performance/memory trace。

## 11. 已知 bug

- F1-C4 duplicate Visit：**代码已修复、自动化已通过**；按用户指示未再次对同一真实导入文件执行第二次 destructive Import。Release 真机 smoke 只需验证正常首次 Import；若未来要验证二次真实导入，应使用可丢弃 fixture/test account。
- 当前没有其他已知代码级 P0/P1 data-loss/privacy blocker。
- Vite 保留已有 large-chunk advisory。

## 12. Production 状态

- Production Worker：未访问/未部署。
- Production D1：未查询/未 migration/未写入。
- Production R2：未访问/未修改。
- Production secrets：未读取/未修改。
- Production Auth/StoreKit/Public Sharing/Account Delete：尚未启用或验收。

## 13. Git 安全

- Task 07–11 全部独立 commit/push。
- Task 12 使用独立 commit message：`Complete release hardening and data safety`；不可自引用的最终 hash 以交付消息和仓库历史为准。
- 未 force push、未 reset、未 rebase、未改写历史。
- 未提交任何 secret、`.p8` 或正式 credential。
- 既有无关未跟踪文档和用户的 `project.pbxproj` cosmetic diff 被保留，不混入 Task 12。

## 14. 流水线停止原因

所有当前可安全自主完成的 Task 07–12 工程工作已经完成。剩余事项均需要以下至少一项：

- 用户本人在 Apple Developer/App Store Connect 配置或操作。
- 用户对 Production 只读/写入给出明确批准。
- 专用真实测试账户和 iPhone 人工交互。
- 不可逆 Production migration/deployment 前的确认。

因此连续流水线在此按 Hard Gate 规则停止，不自动开始 Production 或 App Store 提交。
