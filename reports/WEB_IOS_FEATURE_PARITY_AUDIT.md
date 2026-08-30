# Taste Map Web ↔ iOS Final Feature Parity Audit

审计日期：2026-08-30  
执行范围：Task 10｜最终 Web ↔ iOS Feature Parity Audit + 一次性补漏  
基线：`9b319c47e7dc8395abab1f82e02459460489bbd8`（`Complete native sharing integration`）  
分支：`main`

## 1. 结论先行

本次没有沿用旧 419 项审计的状态结论，而是重新扫描当前 `src/`、`worker/`、`ios/TasteMap/TasteMap/`、iOS tests/UI tests、当前 migrations 和 Task 02–09 的实际提交。

当前结论：

- Web 产品主线已经由 Task 02–09 大范围迁入原生 iOS；旧审计中关于 Map/List/Filters、Restaurant Detail/Edit/Actions、Visit/Dish/Photo、Profile/Lists、Shared Meal、Like/Comment、Discovery/Community、Premium 架构和 Public Sharing 的多数缺口已经失效。
- 本轮记录 264 个原子检查项，其中 9 项为明确移出首发范围的 E 项；255 个 release-scope 检查项中：A 230、D 15、B 9、C 1。
- A + D = 245 / 255 = **96.1%**。
- 仍存在两个不能伪报关闭的 P0 Release Blocker：
  1. Account Delete 尚未实现真实服务端闭环；
  2. F1-C4 已知“同一备份第二次导入会产生重复 Visit”问题尚未修复。
- 另有 UGC 举报/屏蔽、真实 App Store Connect/StoreKit、Share Extension 真机与 Production domain 等 Release Gates；这些不是本轮可以凭空配置或通过 Production workaround 完成的事项。
- 按连续流水线规则，Task 10 的“重新审计、低/中风险补漏、证据固化”已完成；**发布关闭尚未完成**，以上 blocker 必须在 Task 12 重新纳入最终 gate。

## 2. 状态定义

| 状态 | 定义 |
| --- | --- |
| A | Web 正式能力在 iOS 已完整实现，并有现行代码/测试证据 |
| B | 核心能力存在，但仍缺人工、外部配置、发布治理或已知边界 |
| C | release scope 明确要求，但当前没有可用闭环 |
| D | 平台实现不同，但用户能力、数据语义和安全边界等价 |
| E | 已明确废弃、首发移除或由产品决策延期，不计首发缺失 |

## 3. 汇总计数

| 模块 | A | B | C | D | E | 原子检查数 | 主要证据 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Account / Auth / Import / Settings | 16 | 1 | 1 | 1 | 3 | 22 | `TasteMapSettingsView.swift`、Auth/Backup Import services/tests |
| Map / List / Search / Filters / Footprints | 24 | 0 | 0 | 2 | 0 | 26 | `MapHomeView.swift`、Personal filters、Map parity tests |
| Restaurant Acquisition / Detail / Edit / Actions | 28 | 0 | 0 | 2 | 0 | 30 | Restaurant feature files、Task 03 tests/UI tests |
| Visit / Dish / Photo | 34 | 0 | 0 | 2 | 6 | 42 | Visit editor/local stores/photo pipeline、Task 04 tests |
| Profile / Lists / On This Day | 25 | 0 | 0 | 2 | 0 | 27 | Profile/Lists/On This Day files and parity tests |
| Social / Public Profile / Shared Meal / UGC | 27 | 2 | 0 | 1 | 0 | 30 | Social collaboration, Community API/UI, Task 06 tests |
| Discovery / Community | 23 | 0 | 0 | 2 | 0 | 25 | Discovery/Community clients, caches, UI and Task 07 tests |
| Analysis / Recaps / Roulette | 22 | 0 | 0 | 2 | 0 | 24 | P4 analysis/recap/roulette views and tests |
| Premium / StoreKit | 15 | 3 | 0 | 0 | 0 | 18 | StoreKit provider, Worker commerce API, Task 08 tests |
| Share Extension / Public Sharing | 16 | 3 | 0 | 1 | 0 | 20 | Share Extension, public share contracts/API/landing, Task 09 tests |
| **总计** | **230** | **9** | **1** | **15** | **9** | **264** | — |

## 4. 当前 Web → iOS 页面与入口矩阵

### 4.1 Account、Auth、Import、Settings

| 原子能力 | Web 证据 | iOS 证据 | 状态 | 处置 |
| --- | --- | --- | --- | --- |
| Sign in with Apple / 稳定 Taste Map User | Worker auth/session | `AppleSignInService`、`AuthSessionManager` | D | Apple 原生平台等价，服务端仍以 `tm_...` 为业务身份 |
| access/refresh/rotation/logout | Worker auth v1 | Keychain + single-flight refresh | A | 保持一个真实 auth flow |
| 用户隔离 | Worker owner authority | local stores + authenticated APIs | A | client `userId` 不具授权意义 |
| Export Backup v1 | Web backup contract | `BackupExportService` + Settings | A | 当前用户 allowlist，照片原图不在 JSON |
| Import Backup v1 | Web Backup v1 | Preflight → plan → confirm → atomic writer | A | 首次导入闭环存在 |
| Import Legacy Web v4 | Web v4 backup | strict decoder + adapter + review UI | A | provider/auth authority 会被剥离 |
| Import rollback / user switch guard | Web local import safety | transaction writer / final revalidation | A | 自动化覆盖 |
| 重复导入幂等 | Web 主键/IndexedDB 语义 | F1-C4 第二次导入已知重复 Visit | **B / P0** | 禁止再次真实复现；Task 12 前必须修复并补 regression |
| Settings 正式 IA | Web Settings modal | Account/Data/Sync/Privacy/Permissions/Storage/Premium/Help/About | A | 已迁入正式原生导航 |
| Legal URL 配置层 | Web deploy config | `ReleaseConfiguration` | A | Production URL 缺失在 Task 12 检测，不硬编码假链接 |
| Account Delete | release scope 决策 | 仅有 hidden availability placeholder；无 Worker endpoint | **C / P0** | 当前用户明确暂缓；发布前必须做真实 backend + reauth + ownership/data policy |
| Restore My Backup | 产品决策 | 不在 Release UI | E | 首发移除，不计缺失 |
| Remote Legacy Claim | 产品决策 | 不在 Release UI | E | 首发移除，不计缺失 |
| Google Drive | Web 历史实现 | iOS 不接入 | E | 已取消，不计缺失 |

### 4.2 Map、List、Search、Filters、Footprints

| 能力群 | Web 证据 | iOS 证据 | 状态 | 验证 |
| --- | --- | --- | --- | --- |
| Map/List 双模式、去过、想吃 | `MapView` / `RestaurantList` | `MapHomeView` / `RestaurantBrowseList` | A | `MapBrowsingParityTests`、UI path |
| 适合你入口 | recommendations | Discover hub/Discovery | D | 由服务端 rank，不伪造推荐 |
| 本人 Restaurant 搜索 | Web filters/search | `RestaurantBrowseSearch` | A | name/city/address/note/dish 等字段 |
| Web 正式筛选矩阵 | `RestaurantFilters` | `PersonalRestaurantFilterEngine` | A | rating/visit count/city/mode/date/spend/queue/companion/source/scene/tag/distance |
| 排序 | Web sort | `PersonalRestaurantSort` | A | 默认/最近/评分等 |
| Map/List 同源结果 | shared Web filters | one browse snapshot/filter result | A | 数量与 tombstone 语义一致 |
| Footprints | `TasteFootprints` | `TasteFootprintsView` | A | 多 Visit、多城市、nil、不含 tombstone |
| Marker/photo/emoji/fallback | Web marker utils | native marker builder | A | status、photo、emoji、fallback |
| Cluster / fit camera / location | Web map | native MapKit clustering | D | iOS MapKit 平台实现 |
| denied/loading/empty/error/retry | Web states | `MapHomeView` states | A | UI/fixture 覆盖 |
| Profile 去过/想吃下钻 | Web Profile counts | `ProfileBrowseDestination` | A | 不再是静态统计 |
| 1k/10k 数据形态 | Web data projection | map parity performance tests | A | 聚合提前构建，避免 View 内 O(n²) |

### 4.3 Restaurant

| 能力群 | Web 证据 | iOS 证据 | 状态 | 验证 |
| --- | --- | --- | --- | --- |
| Nearby / city / MapKit search | restaurant search | acquisition center | D | 原生 MapKit 替代 Web map provider |
| Apple Maps / AMap / webpage / shared text | Web resolver | local parser + authenticated Worker resolver | A | provider-neutral identity tests |
| manual add / coordinates / offline | add modal | manual acquisition | A | local-first queue |
| identity dedupe | restaurant identity | Global Restaurant ID + place identities | A | Apple Maps-only 可用 |
| Detail metadata | Restaurant detail | business info sections | A | phone/opening hours/reference price/long note/nil handling |
| personal/aggregate ratings | social stats | rating references + sample gates | A | 无样本不显示假 0 |
| spend/queue/tags/context | Web summaries | presentation aggregators | A | nil 不当零 |
| user photos/dishes/history | Web cards | native gallery/dish/history | A | photo retry/full screen 为 iOS 增强 |
| edit metadata/status/marker | editor modal | `RestaurantEditView` | A | Provider identity/coordinates 保持稳定 |
| actions | quick actions | Visit/Want/List/Roulette/Copy/Maps/Share | A | UI 主路径 |
| delete/tombstone | confirmed delete | dependency-aware local store | A | stale mutation 不复活 |
| public share | Web public route | Task 09 stable public URL | A | visibility dynamically checked |

### 4.4 Visit、Dish、Photo

| 能力群 | Web 证据 | iOS 证据 | 状态 | 验证 |
| --- | --- | --- | --- | --- |
| nullable minimal Visit | Add Visit | `VisitDraft` / `VisitEditorView` | A | nil rating/spend 保持 nil |
| half-star rating | StarRating | HalfStar picker | D | 原生交互等价 |
| rich Visit fields | Visit extras | native context controls | A | date/mode/party/ratings/spend/payment/queue/scenes/tags/noise/duration/portion/transport/notes/visibility |
| independent multiple Visits | Web records | Restaurant + Visit split | A | second visit never overwrites first |
| double-submit protection | Web sticky save | submission gate | A | UI + unit regression |
| offline / restart / sync queue | IndexedDB | SwiftData local-first | D | local save authoritative，云失败不阻塞 |
| edit/delete Visit | Web editor | native editor/tombstone | A | other Visits unchanged |
| Dish CRUD/reuse/VisitDish | Dish editor | Dish/VisitDish stores | A | restaurant scoped, historical reuse |
| Dish rating/price/note/photo | Web Dish fields | native Dish manager | A | price does not alter Visit spend |
| Photo multi-select/order | file picker | PhotosPicker ordered | A | Free/Premium limit from entitlement |
| Photo local/upload/retry/cache/delete | photo services | Worker/R2 provider boundary | A | local-first + tombstone |
| gallery/full-screen/missing/offline | Web image cards | native gallery/viewer | A | iOS viewer is platform enhancement |
| 是否愿意再来 | 明确废弃 | 不实现 | E | 产品决定 |
| 推荐菜 | 明确废弃 | Dish 记录替代，不保留该旧字段 | E | 产品决定 |
| 避雷菜 | 明确废弃 | Dish 记录替代，不保留该旧字段 | E | 产品决定 |
| 座位情况 | 明确废弃 | 不实现 | E | 产品决定 |
| 等位之外的订位情况 | 明确废弃 | 不实现 | E | 产品决定 |
| 最佳到访时间 | 明确废弃 | 不实现 | E | 产品决定 |

### 4.5 Profile、Lists、On This Day

| 能力群 | Web 证据 | iOS 证据 | 状态 | 验证 |
| --- | --- | --- | --- | --- |
| Profile identity/edit/stats | `ProfilePage` | `ProfileView` | A | avatar/name/bio/city/joined/Premium/real counts |
| stats destinations | Web Profile | native drill-down | A | visited/want/footprints/lists/social |
| Restaurant Lists CRUD | `RestaurantListsPanel` | native list store/views | A | create/edit/delete/tombstone |
| visibility/ranked/reorder/note | Web lists | native list editor/detail | A | public/friends/private permissions |
| cover | Web cover | safe existing-photo cover | D | 原生复用安全 Photo，不制造 provider URL |
| public list browsing | public profile | native public profile/list API | A | server authority |
| stable public list share | Web hash route | Task 09 public share URL | A | private/friends 不通过 anonymous URL 暴露 |
| On This Day | Web memory | native analyzer/screen | A | timezone/current-year exclusion/multiple years/Feb 29 |
| On This Day poster/share | Web poster | SwiftUI ImageRenderer | D | 独立 1080×1920 image，不是页面截图 |

### 4.6 Social、Public Profile、Shared Meal、Like/Comment

| 能力群 | Web 证据 | iOS 证据 | 状态 | 验证 |
| --- | --- | --- | --- | --- |
| search/friend/follow | `FriendsPage` / social API | native social views/API | A | request/accept/reject/cancel/unfriend/follow/unfollow |
| suggestions / followers / following | Web | native paged destinations | A | user isolation |
| Companion explicit link | Web companion link | collaboration service/UI | A | 不按名字自动绑定 |
| Shared Meal invite/inbox/accept/reject | Web | Worker + native outbox/inbox | A | idempotent + owner authority |
| receiver own Visit | Web shared meal | native prefill flow | A | sender不能改 receiver Visit |
| Public Profile | Web public profile | native public profile | A | public projection/server filters/direct ID defense |
| common WantToGo / public Lists / footprint | Web | native profile sections | A | privacy-aware |
| Like/unlike | Web interaction | authenticated Worker + native UI | A | real counts/idempotent |
| comments pagination/add/delete own | Web comments | native comments sheet + Worker | A | 280 chars、ownership、rate limit、tombstone |
| Report UGC | App Store UGC requirement | 只有未来 service boundary，无正式入口/API | **B / P1** | Task 12 Release Gate |
| Block user/content | App Store UGC requirement | 未实现真实屏蔽策略 | **B / P1** | Task 12 Release Gate；不能做仅本地假屏蔽 |

### 4.7 Discovery、Community

| 能力群 | Web 证据 | iOS 证据 | 状态 | 验证 |
| --- | --- | --- | --- | --- |
| For You / Similar / Trending | recommendation services | native Discovery API/cache/view | A | 真实服务端 projection |
| 7d/30d / city / filters/sort | Web controls | native browse presentation | A | Task 07 UI path |
| reasons/detail/sample counts | Web cards | native reasons sheets | A | sparse similarity 不显示伪精确百分比 |
| actions | Web quick actions | Want/Visit/List/Roulette/Profile/Restaurant | A | viewer only writes own data |
| pagination/refresh/loading/empty/error | Web states | native paged/cache state | A | offline stale permission invalidation |
| Community latest/following | community page | native feed | A | public Visit/Want activities |
| multi-photo/navigation/interaction | Web feed | native community cards | A | Like/Comment 真实 backend |
| offline cache | Web local cache | SwiftData cache | D | privacy change clears stale content |
| map provider differences | Web map | MapKit/native URLs | D | 数据 identity 与 provider 解耦 |

### 4.8 Analysis、Recaps、Roulette

| 能力群 | Web 证据 | iOS 证据 | 状态 | 验证 |
| --- | --- | --- | --- | --- |
| taste/companion/source analysis | Web panels/services | native analyzers/views | A | 真实本地数据、nil/sufficiency |
| monthly/annual recap | Web analysis | native period analyzers | A | spend coverage、taste journey、representative restaurants |
| share posters | Web renderer | SwiftUI ImageRenderer | D | 独立分享图，不是截图 |
| public-safe story/photos | Web allowlist | native photo references | A | owner-scoped |
| Restaurant Roulette | Web roulette | native engine/view | A | real candidate pool |
| filter/candidate/spin/reroll | Web | native equivalent | A | empty/single/large pool tests |
| animation/navigation | Web animation | native animation/sheet | D | 平台交互不同但结果语义等价 |

### 4.9 Premium / StoreKit

| 能力 | Web/产品证据 | iOS/Worker 证据 | 状态 | 处置 |
| --- | --- | --- | --- | --- |
| entitlement state machine | membership services | `PremiumEntitlementService` | A | free/loading/premium/grace/expired/offline |
| feature limits | Web policy | one registry + server authority | A | photo/analysis/list/roulette 等统一 gate |
| StoreKit 2 product loading/purchase/restore | release scope | native provider | A | price 仅来自 StoreKit |
| transaction updates / reconcile | release scope | StoreKit updates + Worker API | A | verified transactions only |
| server verification/idempotency/isolation | release scope | Task 08 Worker/migration | A | Development tests passed |
| expiry/refund/revocation | release scope | notification/reconcile model | A | server authority |
| real Product IDs / subscription group | App Store Connect | intentionally unconfigured | **B / Release Gate** | 用户在 App Store Connect 提供正式配置 |
| App Store Server API key/issuer/key ID | App Store Connect | secret/config injection boundary only | **B / Release Gate** | `.p8`/secret 不进 Git |
| Sandbox/TestFlight purchase/restore/refund | App Store | local StoreKit tests only | **B / Manual Gate** | Task 12 真机/TestFlight 验证 |

### 4.10 Share Extension / Public Sharing

| 能力 | Web/产品证据 | iOS/Worker 证据 | 状态 | 处置 |
| --- | --- | --- | --- | --- |
| URL/text Share Extension | external share scope | real extension target | A | activation plist + build validation |
| no auth token in extension | security requirement | App Group pending queue only | A | queue tests |
| duplicate/replay/expiry/malformed | security requirement | bounded SHA-256 queue | A | tests passed |
| main app confirmation/dedupe | acquisition flow | existing acquisition center | A | user confirms before write |
| stable Restaurant/Profile/List URL | Web public route | Task 09 Worker/API/native actions | A | opaque IDs |
| anonymous allowlisted projection | public landing | strict public DTO | A | no owner/internal/provider/private fields |
| privacy/deletion revocation | Web privacy | checked on every read | A | Development E2E |
| system share sheet/copy | Web share hooks | native share sheet/pasteboard | D | platform equivalent |
| physical-device extension/App Group smoke | iOS platform | simulator/build only | **B / Manual Gate** | Task 12 真机验证 |
| Production Associated Domain/AASA | release platform | Development domain only | **B / Production Gate** | 需 Production approval |
| Production public sharing deploy | release platform | Development Worker/D1 only | **B / Production Gate** | 需 Production approval |

## 5. 本轮直接修复的低风险缺口

本轮没有重写业务模块。静态审计和 UI 回归发现两个测试层面的低风险漂移，并已修正：

1. Restaurant UI E2E 仍在断言 Task 09 前的“公开分享尚未接通”旧文案。现在改为验证真实分享隐私门槛：公开主页 + 至少一个公开 Visit；同时验证不满足条件时按钮 disabled。
2. 通用 UI 测试滚动 helper 过去只看 `isHittable`，当元素只有一小部分位于自定义底部导航下方时会产生 no-op tap。现在保留 92pt 安全点击边距，修复长 Profile/Settings 路径的边缘点击问题。

这两项只修改 UI test harness/断言，不修改业务逻辑、SwiftData、Worker、D1 或 Production。

## 6. 所有未关闭 gap（唯一权威清单）

| ID | Gap | 状态/风险 | Web 证据 | iOS/Worker 证据 | Disposition | 目标任务 | 回归要求 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GAP-001 | F1-C4 第二次导入重复 Visit | B / **P0 data integrity** | Backup/Import contract | current Import transaction pipeline | 继续挂起，不再执行第二次真实导入；先做纯 fixture regression，再修 stable identity/matching | Task 12 前 | 同文件重复导入 2 次、Visit 数不变、无跨用户合并 |
| GAP-002 | Account Delete | C / **P0 release** | release scope 决策 | Settings 仅 hidden placeholder，无 backend | 需要 reauth、server deletion job、session revoke、ownership/retention/tombstone policy；不得本地假删除 | Task 12 | A/B 用户、重试、partial failure、session invalidation、audit |
| GAP-003 | UGC report | B / P1 App Review | Community UGC | Like/Comment 有真实 backend；无 report | 建真实 server-authoritative report flow | Task 12 | author/viewer/moderation、rate limit、private/deleted content |
| GAP-004 | Block user/content | B / P1 App Review | Social/Community UGC | 无 block policy | 建 server-side visibility enforcement，不做 local-only 假屏蔽 | Task 12 | feed/profile/direct ID/search/interaction 全链路 |
| GAP-005 | StoreKit Product IDs/Group | B / external | Premium scope | configuration intentionally unconfigured | App Store Connect 配置并通过正式 config 注入 | Task 12 | Product load/price/period |
| GAP-006 | App Store Server API credentials | B / external secret | server verification scope | secret boundary 已有 | 配置 issuer/key ID/private key secret；不得 commit | Task 12 | signed transaction/notification verification |
| GAP-007 | StoreKit Sandbox/TestFlight | B / manual | purchase release scope | local StoreKit config passed | 真人 Sandbox/TestFlight purchase/restore/expiry/refund | Task 12 | device logs + server entitlement |
| GAP-008 | Share Extension real-device smoke | B / manual | external sharing scope | target/build/tests passed | 真机 Apple Maps/web share → App Group → confirmation | Task 12 | install/activation/import/dedupe |
| GAP-009 | Production public domain/AASA/deploy | B / Production | public share scope | Development passed | 取得用户 Production approval 后部署并验收 | Task 12 | AASA/Universal Link/privacy revocation |
| GAP-010 | Privacy/Terms/Support URLs | B / release config | Settings/legal IA | config validator exists，值为空 | 确认正式 URL 并注入 Production config | Task 12 | URL/HTTPS/App Review metadata |

## 7. 测试与构建

### Web / Worker

- `pnpm test`: **47 files / 334 tests passed**。
- `pnpm run typecheck`: passed。
- `pnpm run build`: passed。
- Vite 仅保留现存的 large-chunk advisory；不是 build failure。

### iOS unit tests

- 正常 Simulator 签名条件：**51 suites / 526 tests passed**。
- 使用 `CODE_SIGNING_ALLOWED=NO` 时 Keychain test 会得到 `errSecMissingEntitlement (-34018)`；这是错误的认证测试运行条件。恢复正常 Simulator 签名后同一测试及全量 suite 通过，项目 Signing/Capabilities 未被修改。

### iOS UI paths

以下 7 条跨模块路径均已通过；首次组合运行暴露的两条过期断言/安全点击边距问题已修复并单独回归为绿：

- Map/List → shared Restaurant Detail。
- Restaurant actions/share privacy gate/confirmed delete。
- Visit double-tap single-flight save。
- Restaurant List create/add/reorder/edit/remove/public/restart。
- Discovery filters/reasons/viewer actions。
- Community viewer actions/WantToGo activity。
- Free Premium paywall → feature gate → Development upgrade。

### Release build

- Task 10 最终 Release Simulator build 必须在 commit 前通过；结果记录在本任务 commit 验收中。

## 8. Backend / data safety

- 本轮 Worker diff：0。
- 本轮 D1 migration diff：0。
- Development Worker/D1 未因 Task 10 改动。
- Production Worker/D1/R2/secrets/migrations：**未访问、未修改**。
- SwiftData schema：未修改。
- 未执行 F1-C4 第二次真实导入。
- 未重新 seed 50 个 demo users。

## 9. Task 10 disposition

- Feature parity audit：完成。
- 旧审计过期结论：已被本报告替代；原有未跟踪 `docs/WEB_IOS_FEATURE_PARITY_AUDIT.md` 未覆盖、未提交。
- 可安全处理的低/中风险 gap：已处理。
- P0 release blocker：仍有 2 个，均已明确进入 Task 12，而非伪报关闭。
- 下一步：进入 Task 11 Global Visual Restoration；功能架构不再在视觉任务中被重写。
