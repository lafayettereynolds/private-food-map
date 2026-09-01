# Taste Map｜Task 01–14 最终自动验收总报告

日期：2026-09-01

分支：`fix/product-ux-correction-8-tasks`

Task 14 commit：包含本报告、最终截图和审计修复的 `Complete autonomous release candidate audit` commit（精确 hash 以该分支 `git log -1` 与最终交付为准）

Production / TestFlight / App Store 写操作：**0**

## 最终结论

# READY FOR REAL-DEVICE RELEASE SMOKE

当前工程层面：

- P0：**0**
- P1：**0**
- P2：外部平台、真实设备、Distribution、Legal、StoreKit、Production 与运营 Gate，详见 [最终人工 Gate 清单](TasteMap_FINAL_REAL_DEVICE_AND_RELEASE_GATES.md)
- P3：既有 Vite large-chunk warning，非本轮引入，不阻塞真机 smoke

该结论表示：自主代码、自动化测试、Simulator、Generic Device Release、signed Development Archive 与 Release binary purity 已通过，可以开始真实 iPhone 最终 smoke。它**不等于** Production Ready、TestFlight Ready 或 App Store Ready。

## Task 01–14 状态与 commit

| Task | 内容 | Commit | 状态 | Push |
|---:|---|---|---|---|
| 01 | Canonical Product / Design Rules | `60f9b42` | PASS | 已推送 |
| 02 | Map / Discovery / Activity | `5b9c861` | PASS | 已推送 |
| 03 | Restaurant Acquisition | `c8bbccb` | PASS | 已推送 |
| 04 | Restaurant Detail IA / global body | `7ea941a` | PASS | 已推送 |
| 05 | Profile / Lists / Premium presentation | `6557e86` | PASS | 已推送 |
| 06 | Roulette / 今天吃什么 | `0d33f92` | PASS | 已推送 |
| 07 | Analytics + 5 poster families | `b69a186` | PASS | 已推送 |
| 08 | Product UX closure | `9ee14d7` | PASS | 已推送 |
| Override | My Map / My List title switch | `7572218` | PASS | 已推送 |
| 09 | Accessibility / Dark Mode / Locale / Visual QA | `5296907` | PASS | 已推送 |
| Governance | Design System workflow | `edb1957` | PASS | 已推送 |
| 10 | Performance / Memory / Large Dataset | `a759159` | PASS | 已推送 |
| 11 | Share Extension / Public Sharing | `8bd36fd` | PASS; real-device pending | 已推送 |
| 12 | StoreKit local / Entitlement verification | `3c96a8e` | PASS with P2 Apple toolchain/external gates | 已推送 |
| 13 | Privacy / Security / UGC / Release config | `43de60f` | PASS | 已推送 |
| 14 | Final autonomous RC audit | 本报告所在 commit | PASS | 提交后执行并在最终交付验证 |

每个正式 Task 保持独立 commit；未 squash、未 amend 已完成 Task、未 rebase、未 reset、未 rewrite history。

## Task 14 实际收口

Task 14 没有新增产品功能。最终组合审计发现并修复两个只影响自动验收稳定性的日期问题，以及一个 Release 字面量纯净问题：

1. 月度回顾 DEBUG fixture 原本使用 `.now - index × 9 days`，在每月 1 日会改变“本月”基础样本，导致 12 次/5 家漂移为 9 次/4 家。现固定为当前月 4 条基础 Visit（跨 2 家 Restaurant），其余基础历史放在上一月；正式 Analytics 模型和用户数据未变。
2. 月度 UI test 把“上个月”硬编码为 `2026 年 7 月`。现按系统日历计算上一月；严格的 12/5、13/5、历史月份、海报与分享断言均保留。
3. 分享海报继续拒绝 `workers.dev` 目标，但 Release 代码不再携带该完整开发域名字面量；对应 QR fail-closed 回归通过。

## 自动化结果

### Web / Worker

| 检查 | 结果 |
|---|---|
| Full tests | PASS — 49 files / 343 tests |
| Application TypeScript typecheck | PASS |
| Worker TypeScript typecheck | PASS |
| Vite production build | PASS |
| 既有 warning | large chunk warning，仅 P3 记录 |

### iOS unit / integration

| 检查 | 结果 |
|---|---|
| Full unit/integration | PASS — **615 tests / 63 suites** |
| F1-C3/C4 Import | PASS |
| F1-C4 exact duplicate Visit regression | PASS |
| Multi-account isolation | PASS |
| SyncEngine / two-client reconciliation | PASS |
| Map/List/Filters / independent markers | PASS |
| Add/Nearby deterministic logic | PASS |
| Restaurant Detail cross-entry | PASS |
| Discovery/Community/Same Taste fixtures | PASS |
| Lists / Roulette | PASS |
| Analytics + 5 poster families | PASS |
| Share Extension / Public sharing | PASS |
| StoreKit abstraction / Worker entitlement | PASS |
| Privacy / UGC / Account Delete boundaries | PASS |

Final full unit log: `/tmp/tastemap-task14-ios-full-unit-final.log`

### iOS UI E2E

关键矩阵最终为 **18/18 PASS**：

- My Map / My List 标题切换、filter state 保持；
- compact filters、独立 marker、Add/Nearby；
- Map → global Restaurant Detail；
- Discovery 五个一级入口与 Community；
- Profile dashboard、Lists；
- Roulette；
- 我的口味档案、最佳饭搭子、谁最会种草、本月回顾、年度回顾及海报；
- Settings / Backup / Sync；
- F1-C4 formal Import UI；
- Rich Visual QA Logged In + Premium accessibility path。

原矩阵 17 项直接通过；唯一跨月 fixture 失败在修正后完整复跑并通过，包括：

- `12 次用餐，5 家餐厅`；
- 当前月 / 上一月切换；
- Restaurant Detail 往返；
- 9:16 Poster preview；
- system Share Sheet 打开/关闭；
- fixture 新增后 `13 次用餐，5 家餐厅`。

相关日志：

- `/tmp/tastemap-task14-ui-e2e.log`
- `/tmp/tastemap-task14-ui-monthly-rerun-2.log`
- `/tmp/tastemap-task14-share-safety-regression.log`

## Build / Archive

| 产物 | 结果 |
|---|---|
| Debug Simulator | PASS |
| Release Simulator | PASS |
| Generic iOS Device Release | PASS |
| Signed Archive | PASS |
| Main App embedded validation | PASS |
| Share Extension embedded validation | PASS |

最终 Archive：`/tmp/TasteMapTask14Final-20260901-1154.xcarchive`

Archive 沿用现有：

- Team ID：`7G5J9MJX88`
- Main Bundle ID：`com.lafayette.tastemap`
- Share Extension：`com.lafayette.tastemap.ShareExtension`
- App Group：`group.com.lafayette.tastemap`
- Sign in with Apple：保留

当前可用签名是 Apple Development provisioning，因此 Archive 中 `get-task-allow=true`。正式 Distribution Archive / `get-task-allow=false` 是明确人工 Release Gate；本轮没有修改 Team、Signing、Bundle ID 或 Capability。

Build logs：

- `/tmp/tastemap-task14-debug-build.log`
- `/tmp/tastemap-task14-release-sim-build.log`
- `/tmp/tastemap-task14-generic-release-build.log`
- `/tmp/tastemap-task14-archive.log`

## Release binary purity

对 Archive 中主 App 与 Share Extension 的 executable 和 bundle 进行最终扫描，结果均为 CLEAN。未发现：

- `TASTEMAP_VISUAL_QA_MODE` / UI-test / test-tier activation；
- Rich Demo fixture、fixture user、fixture records；
- `IsolatedAuthCredentialStore`；
- `TestNetworkBlockerURLProtocol`；
- `DevelopmentPremiumOverride` / Premium bypass；
- fake Product ID 或 `.storekit`；
- Development Worker URL；
- development-test auth / test-user header；
- `workers.dev` QR/domain 字面量；
- `.p8`、private-key marker；
- Cloudflare / R2 / D1 / StoreKit Secret；
- bearer/JWT credential value。

Release Premium 仍只由正式 StoreKit / Worker entitlement 路径决定。DEBUG Visual QA 不可由 Release environment 或 launch argument 启用。

## F1-C4 duplicate Visit 最终状态

**正式关闭 Release blocker。**

最终 615-test 组合代码中以下精确路径通过：

`Legacy v4 first import`
→ `second identical source`
→ `cross-provider Restaurant candidate`
→ `manual merge`
→ `dependent Visit re-resolve`
→ `exactDuplicate`
→ `no second Visit`
→ `no extra mutation`

结论：不再要求使用真实用户数据进行危险的第二次 Import。以后若重构 Import，必须保留该精确 regression。

## Performance 总结

以下均为 Simulator / test-host 指标，不伪装为真机 Instruments 数据：

- 1,000 Restaurants / 10,000 Visits / 5,000 Dishes / 2,000 Photos 的完整 projection + filter + search：约 **0.481–0.719 秒**；
- 1,000 marker presentation：约 **0.020 秒**；
- padded viewport selection：约 **0.007–0.011 秒**；
- 五类 1080×1920 poster × 2（共 10 张）：约 **0.51 秒**；
- targeted regression process max RSS：约 **293 MB**，peak footprint：约 **192 MB**，swaps：0。

真机持续 pan/zoom、memory warning、poster repeated export 和 Instruments 仍在人工 Gate 内。

## DEBUG-only Visual QA / Rich Demo

当前固定 Simulator：

- Device：iPhone 17 Pro / iOS 26.5
- UDID：`E4F3EED9-89D8-405C-B4CB-7CA816CE3405`
- 状态：Booted
- App：最终 Debug build 已安装并启动
- 默认：Logged In + Rich Demo User + Premium Active
- 网络：禁用自动服务，不访问 Development/Production
- Keychain：隔离，不读取/写入真实 Keychain

启动命令：

```sh
SIMCTL_CHILD_TASTEMAP_VISUAL_QA_MODE=rich \
SIMCTL_CHILD_TASTEMAP_CORE_PARITY_INITIAL_TAB=map \
xcrun simctl launch --terminate-running-process \
E4F3EED9-89D8-405C-B4CB-7CA816CE3405 \
com.lafayette.tastemap
```

可将 `rich` 改为：`empty`、`normal`、`very-rich`、`long-text`、`missing-photo`、`error`、`offline`、`free`。

默认 Rich 数据：

| 数据 | 数量 |
|---|---:|
| Visited Restaurants | 90 |
| Want-to-go Restaurants | 25 |
| Visits | 275 |
| Local fixture photos | 60 |
| Dishes | 130 |
| Dining companions | 10 |
| Recommendation sources | 12 |
| Lists | 7 |
| Following | 48 |
| Followers | 73 |
| Discovery / Community items | 每个 rich surface 12 |

默认 Rich 状态通过现有 Premium registry 解锁全部当前正式 Premium 功能；`free` 用于检查 Paywall。两者均只存在于 DEBUG compilation。

## Final Screenshot Pack

完整目录：[Task 14 Final Screenshot Pack](remaining-09-14-assets/task-14-final/)

### Core / Map / Discovery

- [最终固定 Simulator Rich Map](remaining-09-14-assets/task-14-final/fixed-simulator-rich-demo-final.png)
- [我的地图](remaining-09-14-assets/task-14-final/my-map.png)
- [我的列表](remaining-09-14-assets/task-14-final/my-list.png)
- [当前位置头像 Marker](remaining-09-14-assets/task-14-final/map-user-avatar.png)
- [独立 Restaurant Markers（无数字 cluster）](remaining-09-14-assets/task-14-final/map-independent-markers.png)
- [Discovery](remaining-09-14-assets/task-14-final/discovery.png)
- [Community](remaining-09-14-assets/task-14-final/community.png)
- [Task 09 Rich Discovery Accessibility](remaining-09-14-assets/task-14-final/task-09-rich-discovery-accessibility.png)

### Acquisition / Restaurant / Profile / Lists

- [Add Restaurant / Nearby](remaining-09-14-assets/task-14-final/add-restaurant-nearby.png)
- [Add Restaurant Search Preview](remaining-09-14-assets/task-14-final/add-restaurant-search-preview.png)
- [Restaurant Detail top](remaining-09-14-assets/task-14-final/restaurant-detail-local-top.png)
- [Restaurant Detail downstream](remaining-09-14-assets/task-14-final/restaurant-detail-local-downstream.png)
- [Remote Restaurant Detail](remaining-09-14-assets/task-14-final/restaurant-detail-remote.png)
- [Profile](remaining-09-14-assets/task-14-final/profile.png)
- [Public Profile](remaining-09-14-assets/task-14-final/public-profile.png)
- [Lists](remaining-09-14-assets/task-14-final/lists.png)
- [Public List](remaining-09-14-assets/task-14-final/public-list.png)

### Roulette / Premium

- [Roulette large library](remaining-09-14-assets/task-14-final/roulette-large-library.png)
- [Roulette dark](remaining-09-14-assets/task-14-final/roulette-dark.png)
- [Roulette result](remaining-09-14-assets/task-14-final/roulette-result.png)
- [Approved Premium hamburger](remaining-09-14-assets/task-14-final/premium-hamburger.png)
- [Premium Paywall](remaining-09-14-assets/task-14-final/premium-paywall.png)

### Analytics / 5 Posters

- [我的口味档案](remaining-09-14-assets/task-14-final/taste-profile.png)
- [我的口味档案 Poster](remaining-09-14-assets/task-14-final/taste-profile-poster.png)
- [最佳饭搭子](remaining-09-14-assets/task-14-final/best-companion.png)
- [最佳饭搭子 Poster](remaining-09-14-assets/task-14-final/best-companion-poster.png)
- [谁最会种草](remaining-09-14-assets/task-14-final/recommendation-source.png)
- [谁最会种草 Poster](remaining-09-14-assets/task-14-final/recommendation-source-poster.png)
- [本月回顾 Final](remaining-09-14-assets/task-14-final/monthly-recap-current-final.png)
- [本月回顾历史月 Final](remaining-09-14-assets/task-14-final/monthly-recap-previous-final.png)
- [本月回顾 Poster Final](remaining-09-14-assets/task-14-final/monthly-recap-poster-final.png)
- [年度回顾](remaining-09-14-assets/task-14-final/annual-recap.png)
- [年度回顾 Poster](remaining-09-14-assets/task-14-final/annual-recap-poster.png)

## 剩余 P2 Manual / External Gates

1. 真实 iPhone 最终 Product、GPS、Share、Sync、Haptics、Poster smoke。
2. 仅使用一次性 Development 账号做 Account Delete confirm smoke。
3. Distribution certificate/profile 与 Distribution Archive。
4. App Store Connect Subscription Group、正式 Product ID、价格、本地化、Sandbox/TestFlight。
5. Apple App Store Server API Secret 注入与独立 `x5c` 验证。
6. 正式 Privacy / Terms / Support URL、App Privacy 与 UGC moderation 运营流程。
7. Lafayette 明确授权后的 Production Worker/D1/R2 preflight、incremental migration 和 deploy。
8. Production AASA / Associated Domains。
9. TestFlight 和最终 App Store submission。

详情与执行顺序见 [TasteMap_FINAL_REAL_DEVICE_AND_RELEASE_GATES.md](TasteMap_FINAL_REAL_DEVICE_AND_RELEASE_GATES.md)。

## 最终边界确认

- Production Worker：未访问、未修改、未部署。
- Production D1：未查询、未 migration、未写入。
- Production R2：未读取、未写入。
- App Store Connect：未写入。
- TestFlight/App Store：未上传。
- App Icon：未修改。
- 真实账户：未删除。
- 真实用户数据：未执行破坏性第二次 Import。

工程已完成当前可自主完成的 Task 01–14，下一步只能进入上述真实设备与外部发布 Gate。
