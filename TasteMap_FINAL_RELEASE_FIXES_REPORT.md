# Taste Map Final Release Fixes — Final Report

日期：2026-08-30
分支：`main`

## 结论

**CONDITIONALLY READY**

Tasks 01–07 中所有当前可自主完成的代码、自动化、Development E2E、视觉 RC、Debug/Release build 和发布二进制审计已经完成。当前没有已知 P0 数据隔离、跨用户读取、照片、mutation、账户删除或同步状态机 blocker。

**Production：NOT READY TO DEPLOY。**

Production Worker/API、D1/R2、正式 Legal URL、App Store Connect/StoreKit server、AASA/Associated Domains 和真实设备人工验收尚未完成；本轮没有访问 Production，也没有用假配置绕过这些 Gate。

详细 Task 07 验收与证据：

[FINAL_RELEASE_FIXES_07_RELEASE_CANDIDATE_ACCEPTANCE.md](reports/FINAL_RELEASE_FIXES_07_RELEASE_CANDIDATE_ACCEPTANCE.md)

人工发布操作清单：

[MANUAL_RELEASE_CONFIGURATION_CHECKLIST.md](MANUAL_RELEASE_CONFIGURATION_CHECKLIST.md)

## 01–07 状态

| Task | 状态 | Commit | Push | 关键验收 |
| --- | --- | --- | --- | --- |
| 01 — Local multi-account isolation | PASS | `0eafe9f3dccee92678f8ebb8b4e868a6ebdc730a` | pushed | Full iOS 540/540；new isolation 6/6；Debug/Release |
| 02 — SyncEngine failure hardening | PASS | `57f6af5f4f0d77882dc36c97b6ca5fd1aacab175` | pushed | SyncCoordinator 15、SyncEngine 7、isolation 6、two-client 1；Dev E2E；Debug/Release |
| 03 — Test runtime/migration fixtures | PASS | `61321e6dac359b2e67639792d631b70ae1c1b8e2` | pushed | Worker 339；iOS full 575/575；runtime isolation 6；Debug/Release |
| 04 — Core layout parity | PASS | `c8cae534e00ad6910abce97df532bfae34e38bfe` | pushed | 78 relevant unit；7 UI evidence/regression paths；Debug/Release |
| 05 — iOS support scope | PASS | `792ef6c799a8922c978c3ae4d6a81da3df8104f2` | pushed | iPhone-only target consistency；iOS 17 compile guard；Debug/Release/device signing |
| 06 — Production readiness | PASS for code/config | `e1c6c05080f9eca6c3fc7f0dea46ea3eee748149` | pushed | Worker 23；StoreKit/Settings/UI；Web build；dry-run；Debug/Release signed |
| 07 — RC acceptance | PASS for autonomous scope | 本报告所属 `Complete release candidate acceptance` commit | commit 后 push；hash 见最终对话报告 | Worker 340；iOS 577/582 invocations；critical UI 10/10 effective；4 Dev E2E；Debug/Release/signed device |

## P0 / P1 / P2 / P3

- **P0：PASS。** A/B local isolation、`@Query` owner boundaries、photo/mutation/checkpoint isolation、current-user-only Account Delete 和 other-user unsynced survival 均有自动化证据。
- **P1：PASS for engineering RC。** Sync、Map/List/Detail、Import、Restaurant/Visit 核心闭环通过；当前候选真机 smoke 待人工 Gate。
- **P2：PASS for Development/code。** Rich Visit graph、照片/菜品/上下文、公开分享、Premium architecture 通过；正式 R2/StoreKit 配置待人工 Gate。
- **P3：PASS for code，PENDING for release operations。** 三用户社交、Discovery/Community、隐私/owner 检查通过；moderation 运营和 App Store 发布资料待完成。

## Task 07 最终测试矩阵

| 项目 | 结果 |
| --- | --- |
| Worker Vitest | 49 files，340/340 |
| TypeScript + Vite build | PASS |
| iOS full unit/integration | 577 top-level；582 parameter invocations；0 failed；0 skipped |
| Task 07 affected regression | 20 top-level；23 invocations；PASS |
| Critical UI | 10/10 effective；账户作用域问题修复后原失败路径 1/1 PASS |
| Debug Simulator | PASS |
| Release Simulator | PASS |
| Release generic device + Automatic Signing | PASS |
| Development D1 preflight | No migrations to apply |
| Development E2E | P2-G、P3-E、public sharing、release safety 全部 PASS + cleanup |

## F1-C4 duplicate Visit

此前挂起问题没有通过真实用户文件重复导入来测试。Task 07 增加隔离内存 exact regression，覆盖 Legacy v4 首次导入、cross-provider candidate、manual merge、dependent Visit re-resolve、第二次同 source、duplicate Visit skip、无新 Visit、无额外 mutation；测试通过。该精确场景现在有自动化关闭证据。

## Release binary

Release App 与 Share Extension 扫描中以下内容均为 0：Development URL、UI/test runtime keys、test auth header、demo seed/admin、`dev.*` Product IDs、App Store private key markers、embedded bearer/JWT/private key。

- Bundle Identifier：`com.lafayette.tastemap`
- Team：`7G5J9MJX88`
- Minimum iOS：`17.0`
- Sign in with Apple / App Group：保留
- Release 不含 Development Associated Domain

## Visual RC

- [Map](reports/final-release-fixes-07-assets/map.png)
- [List](reports/final-release-fixes-07-assets/list.png)
- [Restaurant Detail](reports/final-release-fixes-07-assets/restaurant-detail.png)
- [Map Dark](reports/final-release-fixes-07-assets/map-dark.png)

Map 顶部控制区保持一层紧凑结构，地图面积断言大于 72%，没有恢复成多层工具栏压缩地图。

## Manual Gates：16

1. Production Worker/API custom domain + iOS Production base URL。
2. Production D1 read-only preflight、备份、授权后增量 migration。
3. Production R2 binding/lifecycle/CORS/恢复策略。
4. App Store Connect Subscription Group、Product IDs、价格、本地化、审核资料。
5. App Store Server API 最小权限 key 与 Worker encrypted secret。
6. App Store Server Notifications V2。
7. Sandbox/TestFlight purchase/pending/cancel/restore/renew/expire/refund/revoke/restart/user switch。
8. Privacy Policy、Terms、Support 正式 HTTPS URL。
9. Production public origin、AASA、Release Associated Domains。
10. Share Extension 真机 Apple Maps/高德/URL/text/App Group/Universal Link。
11. UGC moderation 负责人、SLA、内容政策和申诉流程。
12. App Store Connect Privacy/年龄分级/审核资料。
13. 当前候选真机 Sync Now/Retry。
14. 当前候选真机 Sign in、Add Restaurant、Visit、Dish、Photo、Map/List/Search、Profile/List、Social、Like/Comment、Discovery/Community、单次 Import。
15. 专用测试账户 Account Delete 不可逆 smoke。
16. iOS 17.x 最低系统 smoke。

## Production 与 App Store 提交

本轮 Production Worker、D1、R2、secrets、migration：全部未访问、未部署、未写入。完成上面 16 项后，还需生成正式 Distribution archive，复核 entitlement、privacy、metadata 和 TestFlight build，才能改为 `READY TO DEPLOY` / `READY`。

## Git 与受保护工作

Task 07 只应提交其三个源代码变更、两个报告和四张 RC 截图。任务前已有的 Xcode project group 重排、stash、独立审计文档、旧 reports 和 `pnpm-workspace.yaml` 均保持原状、不混入 Task 07 commit。
