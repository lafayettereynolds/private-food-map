# Taste Map｜Full Product Parity Module 3

## Discovery + Community

日期：2026-08-31

分支：`fix/full-product-parity-restoration`

范围：Discovery / Community 的功能语义、数据合同、页面信息架构、共享筛选语言和 Activity 卡片；不修改 SwiftData schema、Sync、认证、D1 migration 或 Production。

## 1. Step A｜Web 功能语义与数据来源

### Web Source of Truth

Discovery 的正式一级导航是：

1. `关注`
2. `为你推荐`
3. `同味之选`
4. `最新`
5. `趋势`

这些是同一页面的五个并列入口，不存在额外的“发现餐厅 / 社区动态”上层切换。城市、筛选、排序和距离是当前 Discovery projection 的上下文；Community Activity 继续通过 `关注` / `最新` 进入，而不是被拆成第二套产品。

功能语义审计确认：

- Discovery candidate 来自 Worker `/api/v1/discovery/*` 的公开 projection，包含 Restaurant、推荐原因、相似度/趋势上下文和 viewer state。
- Community card 来自公开 Visit / WantToGo activity；可见性仍由 Worker 鉴权和关系范围控制。
- 卡片上的“这次到访评分”必须来自产生该 Activity 的具体 Visit。
- Restaurant 聚合评分只属于餐厅级筛选、排序和 Restaurant Detail，不能冒充具体用户这一次到访的评分。
- `rating == null` 是合法状态，必须显示“未评分”，不能回退到餐厅聚合评分，也不能生成默认分。
- 点击餐厅仍进入共享 Restaurant Detail；记录、想吃、榜单、轮盘继续复用现有真实 flow。

关键代码：

- `src/components/CommunityPage.tsx`
- `src/contracts/discoveryContract.ts`
- `worker/discoveryV1.ts`
- `ios/TasteMap/TasteMap/Features/Discovery/DiscoveryView.swift`
- `ios/TasteMap/TasteMap/Features/Community/CommunityFeedView.swift`

### 找到的真实迁移错误

Worker 内部的 `DiscoveryVisitRow` 原本已经拥有 Visit ID、到访时间和 nullable rating，但 Web / iOS 共用的 Discovery JSON contract 在 projection 阶段丢弃了这些字段。结果是原生卡片只能读取 Restaurant aggregate ratings，造成“功能搬错”，而不只是视觉差异。

本轮修复：

- 新增 `DiscoveryActivityProjectionV1`：`visitId`、`visitedAt`、`rating: number | null`。
- `DiscoveryCardV1.activity` 为 nullable；没有具体 Visit 的 recommendation 可以为 `null`。
- Worker 由 source Visit 构建 activity，不由客户端猜测。
- Swift contract、持久化缓存、viewer-state reconciliation 和 Preview fixture 全部保留 activity。
- 旧缓存 / 旧 payload 缺少 `activity` 时仍可解码，避免升级后丢失已有离线内容。
- Web 与 iOS Activity card 都显示具体 Visit rating；nil 明确显示“未评分”。

## 2. Step B｜信息架构与布局还原

| 项目 | Web / 已确认 Source of Truth | iOS before | iOS after | 结论 |
| --- | --- | --- | --- | --- |
| Header | `发现` 是页面中心标题 | 视觉层级包含额外 DISCOVER / 图标表达 | 标题和说明居中，去掉多余上层视觉 | PASS |
| 一级导航 | 关注 / 为你推荐 / 同味之选 / 最新 / 趋势同级 | 曾被“发现餐厅 / 社区动态”重新分组 | 五个等宽、同级、可点击 Tab | PASS |
| Filter language | 与 Map 同一套紧凑筛选语义 | Discovery 自己维护另一套大控件 | 共用 `tasteMapFilterChipStyle`，横向单排滚动 | PASS |
| 城市 | 紧凑上下文 | 独立大块倾向 | 首个 active chip，保持当前城市语义 | PASS |
| 餐厅评分 | 明确为餐厅级筛选 | 容易与用户 Activity 评分混淆 | chip 文案明确为“餐厅评分” | PASS |
| Activity rating | 具体 Visit rating / 未评分 | Restaurant aggregate 冒充本次评分 | `这次到访 3.5` 或 `这次到访 · 未评分` | PASS |
| Card density | 内容流有较高信息密度 | 图片和卡片过高 | 缩短图片、内边距和卡片圆角，仍保留原因与真实操作 | PASS |
| Community | 与 Discovery 一级入口共存 | 实现存在但产品层级偏离 Web | 关注/最新直接呈现 Community，功能未删除 | PASS |
| Accessibility | 五个主入口可读可点 | 父容器 identifier 覆盖子按钮 | 每个 Tab 和 rating 拥有稳定独立 identifier | PASS |

## 3. Rating contract

```text
DiscoveryCardV1
├── restaurant             Restaurant identity / public projection
├── ratings                Restaurant aggregate context（筛选/详情）
└── activity?              产生当前卡片的具体 Visit
    ├── visitId            required
    ├── visitedAt          required
    └── rating             required but nullable
```

规则：

- `activity == null`：该 recommendation 没有具体 Visit，不渲染“本次到访”。
- `activity.rating == null`：有具体 Visit，但用户没有评分，渲染“未评分”。
- `activity.rating != null`：只显示该 Visit 的真实评分。
- `ratings.publicRating / friendRating / similarTasteRating` 不再用于 Activity card 的个人评分展示。

## 4. Evidence

### Web reference

- [Web Discovery reference](full-product-parity-assets/web-discovery-before.jpg)

### iOS before

- [iOS Discovery before](full-product-parity-assets/ios-discovery-before.png)

### iOS after

- [iOS Discovery after](full-product-parity-assets/ios-discovery-after-module-3.png)
- [iOS Community after](full-product-parity-assets/ios-community-after-module-3.png)
- [iOS Discovery dark](full-product-parity-assets/ios-discovery-after-module-3-dark.png)

After 截图来自通过的 iPhone 17 Pro UI tests；深色证据在 simulator appearance 设置为 Dark 后重新捕获，不使用浅色截图冒充深色验收。

## 5. Regression coverage

### Worker / Web

- Discovery、Community、Social collaboration、Social、Photo binary、Sync、Taste similarity：7 files / 78 tests，全部通过。
- TypeScript project build：PASS。
- Worker TypeScript no-emit：PASS。
- Vite production build：PASS。
- 唯一现存 Vite large-chunk warning 与本模块无关，本轮未扩大范围处理。

### iOS unit

通过：

- `P3CDiscoveryTests`
- `P3DCommunityTests`
- `P3ESocialHardeningTests`
- `Task06SocialCommunityTests`
- `Task07DiscoveryCommunityParityTests`
- `CoreProductLayoutParityTests`

覆盖 activity encode/decode、旧 payload 兼容、cache reopen、viewer isolation、relationship revocation、visibility、offline-first viewer action、nullable rating 与 provider-neutral Restaurant identity。

### iOS UI

iPhone 17 Pro：

- 五个一级 Tab、等宽布局、居中 Header：PASS。
- 城市 / 筛选 / 排序 / 距离 / 餐厅评分 chips：PASS。
- For You / Similar Taste / Trending / refresh：PASS。
- concrete Visit rating 与 un-rated activity：PASS。
- Community profile / Restaurant Detail / comments / want-to-go：PASS。
- Community offline cache：PASS。
- Light / Dark：PASS。

iPhone 17e：

- 五 Tab、横向 chips、卡片操作与 concrete Visit rating：PASS。
- 小屏没有导航或操作按钮重叠：PASS。

### Build

- Debug Simulator build：PASS。
- Release Simulator build：PASS。
- `AppIntents.framework` 未依赖的 metadata extraction warning 是现有工具链提示，不是本轮业务 warning。

## 6. Safety boundary

- SwiftData schema：未修改。
- Sync architecture / cursor / mutation queue：未修改。
- Sign in with Apple / Keychain / auth：未修改。
- Worker API 只做向后兼容的 response contract 扩展；没有 migration。
- D1：未修改。
- Production：未访问、未部署、未写入。
- 未生成假评分、假用户数据或客户端推断 Activity rating。

## 7. Result

Discovery 与 Community 已从“外观接近但 Activity 语义错误”收口为：五个正确一级入口、共享 compact filter language、真实 Visit-level rating、nullable 未评分状态、旧缓存兼容和完整跨层测试。Module 3 可以关闭。
