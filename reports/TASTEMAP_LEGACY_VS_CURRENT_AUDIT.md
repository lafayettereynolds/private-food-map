# Taste Map Legacy Windows/Web vs Current Mac/iOS Audit

> 类型：READ + COMPARE + DOCUMENT
> Current baseline：`fix/product-ux-correction-8-tasks@648be229878d7358c9381d5153580a130f32d8c3`
> Legacy baseline：`main@fb127e9ea20498c0db450872deb9c9dc346ef34f`
> 日期：2026-09-01
> 是否修改业务代码：**NO**

## Executive Summary

### 1. 旧 Windows/Web 项目实际路径

正式 Legacy 证据源是：

- 原始 ZIP：`/Users/lafayette/Desktop/Taste-Map-完整项目备份-2026-09-01.zip`
- ZIP SHA-256：`18f5ad1d64bc6c5447cccfa4e1cae1f6edb4888ee2f7897a5f73789316cc37c0`
- 审计只读解压：`/tmp/tastemap-legacy-reference-20260901-648be22`

它包含 React/Web、Worker/D1、assets、tests、docs、migrations `0001–0014` 和 `.git`。解压目录已设为只读，原 ZIP 没有被修改。

### 2. 找到几个历史版本

找到 **2 个候选目录、1 个实质历史版本**：

| Candidate | Git | Conclusion |
| --- | --- | --- |
| `/Users/lafayette/Desktop/Taste-Map-完整项目备份-2026-09-01.zip` | `main@fb127e9`，完整 25-commit 历史 | Windows 最终正式版本，主证据源 |
| `/Users/lafayette/Projects/private-food-map-connector-backup-20260827` | 无 `.git` | 核心源码副本，不是独立产品版本 |

Legacy `fb127e9` 是 Current `648be22` 的精确祖先；当前有 113 个 post-Legacy commits。不存在需要直接 merge 的“另一套最终 Web 分支”。

### 3. Decision totals

完整矩阵位于 [`docs/TASTEMAP_LEGACY_FUSION_DECISIONS.md`](../docs/TASTEMAP_LEGACY_FUSION_DECISIONS.md)：

| Decision | Count |
| --- | ---: |
| RESTORE | 1 |
| KEEP CURRENT | 39 |
| FUSE | 46 |
| RETIRE | 10 |
| NEEDS LAFAYETTE APPROVAL | 2 |
| **Total** | **98** |

### 4. 最严重的 10 个迁移偏差

这里区分“当前仍开放”与“历史上曾偏离、目前已修复”。不能因为旧报告写过 PASS 就默认通过，也不能把已经修复的项继续误报为 blocker。

| Rank | Deviation | Current status | Conclusion |
| ---: | --- | --- | --- |
| 1 | Legacy Marker 明确按评分优先、到访次数次级设置 z-index；当前 iOS 虽携带两项数据，却没有用于 annotation 层级 | **OPEN** | 本次唯一明确的 RESTORE；应先修 |
| 2 | Restaurant 图片优先级在多个页面仍有表层 resolver 分散，统一 policy 没有完全成为唯一 renderer | **OPEN consistency risk** | FUSE：全局收口，真实图永远优先于 Food fallback |
| 3 | Legacy `preferenceLevel` 汇总曾出现在 Profile；当前合同保留但不再作为核心 UI | **USER DECISION** | 不是字段丢失；是否恢复 UI 需 Lafayette 决定 |
| 4 | Legacy Web icon 最大只有 512px；当前 AppIcon 没有可确认的正式 1024px source | **ASSET GATE** | 不能自动复制/放大；需 Lafayette 提供或确认 |
| 5 | iOS 曾把 Discovery 拆成“发现餐厅/社区动态”额外层级 | **RESOLVED** | 当前五个一级 tab 已恢复 |
| 6 | iOS 曾在 activity contract/UI 中丢失具体 Visit rating 语义 | **RESOLVED** | 当前 nullable Visit rating 已恢复；须回归保护 |
| 7 | Profile 曾变成纵向大卡片流，偏离 Web compact dashboard | **RESOLVED** | 当前 compact topology 已恢复并保留新 Social/Premium |
| 8 | Restaurant Detail 曾按入口维护相似页面 | **RESOLVED** | 当前 `RestaurantDetailStandardBody` 是全局主体 |
| 9 | Roulette 曾偏离 Legacy pointer/center/empty-slot/wheel geometry | **RESOLVED** | 当前恢复几何并改用稳定真实 Restaurant ID |
| 10 | Analytics 曾退化为普通卡片/报表，分享只验证“能 share” | **RESOLVED** | 当前独立 Analysis Theme、Food Hero、五类 9:16 poster 已恢复 |

### 5. 绝对不能被 Legacy 覆盖的新版能力

- Taste Map `tm_...` 用户 ID 与 Apple identity 分离；
- global Restaurant UUID + provider-neutral `placeIdentities[]`；
- Apple Maps-only Restaurant 的完整 CRUD/sync；
- SwiftData local-first、persistent mutation queue、incremental cursor、idempotency、tombstone、per-user checkpoint；
- local multi-account isolation、current-user cache ownership、cross-user protection；
- Backup v1、Legacy v4 strict decoder、Import preflight/plan/transaction flow；
- F1-C4 exact duplicate Import regression（已关闭 blocker）；
- separate Dish / VisitDish / PhotoAsset、图片上传失败不阻塞 Visit；
- Worker-backed Like/Comment、Report/Block/Delete-own、公开内容可见性；
- canonical global Restaurant Detail；
- StoreKit 2 + server entitlement/reconciliation；
- 原生 Analytics analyzers、五类海报和分享生命周期；
- Settings、Account Delete boundary、Release Binary Purity、Visual QA Release 排除；
- 当前三层 Design System 和 Food & Dining data/decorative semantics。

### 6. 最值得恢复的 Legacy 设计

1. **Marker rating/visit z-order**：代码证据明确且当前确实缺失。
2. Map Marker selected 置顶语义，与上述 z-order 一并融合验证。
3. Legacy 页面中已经证明有效的 compact hierarchy，应继续作为当前 canonical templates 的产品证据，而不是复制 CSS。
4. Restaurant Detail 的基础信息顺序和四圆评分语义，当前已经恢复，应作为 regression contract 长期保护。
5. Roulette 的 pointer/center/empty-slot/5–10 slot 几何，当前已经恢复，应保护。
6. Analytics 的真实 Restaurant/Visit/Companion/Source 语义、隐私 redaction 和 poster-specific render 思路，当前原生实现应继续保留。

### 7. Current Design Rules 与 Legacy 证据是否冲突

有明确冲突，但都能按 Source of Truth 解决，没有架构 blocker：

- Legacy 远景数字 cluster vs 最新“任何缩放层级独立 Marker”：**最新规则胜出，Legacy cluster RETIRE**。
- Legacy 旧 Map/List switch 位置 vs 最新“居中 title + icon”：**最新规则胜出**。
- Legacy raw emoji marker vs `FoodDiningVisualLibrary`：**保留兼容解码，正式视觉 RETIRE raw emoji**。
- Legacy Profile 统计组合 vs 最新“去过/想去/总消费”：**最新规则胜出**。
- Legacy 旧分析名称 vs “最佳饭搭子/谁最会种草”：**最新名称胜出**。
- 历史 `FULL_PRODUCT_PARITY_MODULE_8_CLOSURE_REPORT.md` 曾描述 Food/Dining far clusters；它已被后续规则和当前代码 supersede，不能再作为当前验收依据。

没有发现需要推翻当前三层 Design System 的 Legacy 证据。Legacy 只能输入到 Canonical Page Template / shared components，不能建立平行 CSS-style SwiftUI 层。

### 8. 是否修改业务代码

**NO。** 本轮只新增两份 Markdown 审计文件。

---

## Audit Method and Provenance

本次同时检查：

- Legacy React/Web source、assets、tests、docs、Worker/D1 migrations 和 Git history；
- Current iOS SwiftUI、SwiftData models、services、tests、assets；
- Current Web/Worker contracts；
- `AGENTS.md`；
- `docs/TASTEMAP_PRODUCT_DESIGN_RULES.md`；
- Product parity、Product UX、Release Fix 与 closure reports；
- `fb127e9..648be22` 的 113 个 current-only commits。

关键 Legacy Git 轨迹：

```text
fb127e9 Update Taste Map premium and product experience
d3491aa Complete discovery interactions and profile updates
42a76d6 Redesign profile dashboard
0a4489a Improve social profiles and companion insights
7002076 Complete Taste Map insights and experience updates
095300a Improve discovery, profiles, roulette, and nearby search
db7a50d Fix nearby restaurant lookup
0e6bd4e Refine map navigation and restaurant discovery
bdb0bee Improve map, visit details, and taste footprints
9685ec2 Add social visits and mobile map refinements
7380d53 Add Google Drive photo sync
b6e3cba Add Cloudflare D1 cross-device sync
4a86caa Protect local backup exports
1ef5689 Initial commit
```

重要 Current 迁移/修复里程碑：

```text
2c5ec6f Add native TasteMap iOS project
c46281e Implement P0-A restaurant identity contract
a02d04f Implement P0-B1 versioned sync foundation
41aa952 Configure P0-B2-C native Sign in with Apple
8ce1c0e Complete P1 offline and sync hardening
3f7ad9b Complete P2 rich visit recording
a542c77 Complete P3 social system hardening
bc6b817 Complete P4 product hardening
204c899 Implement backup import merge engine
6aaf4fc Complete backup data import flow
ce24c38 Close final Web iOS feature parity
0eafe9f Fix local multi-account data isolation
2b7ffa8 Fix real-device sync pull timeout
4ca5ca9 Unify global Restaurant Detail
4b1ae8b Restore Analytics and poster product parity
d9f5acd Close duplicate import release blocker
7e67c65 Remove test support from release binary
9ee14d7 Close final Taste Map product UX corrections
648be22 Enforce Taste Map design system architecture
```

---

# A. MIGRATION REGRESSIONS

## A1. Open: Map Marker layer priority

Legacy `src/components/MapView.tsx` 的实际实现：

```text
ratingPriority = round((scoreOutOfTen ?? 0) * 10)
priority = ratingPriority * 10 + min(visitCount, 99)
marker.setzIndex(priority)
selected marker.setTop(true)
```

Current `RestaurantMapMarkerPresentation` 仍携带 `averageRating` 和 `visitCount`，但 `ClusteredRestaurantMapView.swift` 对所有 annotation 设置相同 `.required` display priority，没有产生“评分优先、到访次数次级”的层级。这是可由源码直接证明的当前 regression。

**Severity：P1 Product/Visual。** 不涉及数据丢失，但密集地图中会改变用户看到哪个 Restaurant 在上层。

**Future fusion contract：**

- selected > score > visit count > stable ID；
- 每店保持独立 Marker；
- 不恢复 numeric cluster；
- 与稳定 collision/overlap/spiderfy 策略共存；
- 不改 scope/filter/query；
- 用共享 presentation/view 一次解决，不按页面 patch。

## A2. Open consistency risk: Restaurant image policy 未完全成为唯一 renderer

Current 已有正确 `RestaurantImagePriorityPolicy`：

```text
local user photo
→ public/cached photo
→ safe HTTPS provider merchant image
→ Food & Dining fallback
```

但部分 Discovery、Community、List、Roulette、Detail、Analytics surface 仍各自做 resolver/URL/PhotoAsset 映射。多数路径目前遵循正确顺序，但并非所有地方都只依赖一个 canonical renderer，因此存在未来漂移或某类 source 被漏接的风险。

这不是“把 Legacy `RestaurantAvatar` 复制回来”。Legacy 的 `markerType` 分支甚至可能让 emoji 覆盖本可用 merchant image。正确做法是把 Current policy 提升为唯一跨表面决策源。

**Severity：P1 consistency / P2 implementation。** 需要用 provider/public/local/missing-photo contract tests 判断是否已造成实际用户可见错误。

## A3. Previously regressed, now closed

- Discovery 五 tab IA：已恢复。
- Activity nullable Visit rating：已恢复。
- Profile compact dashboard：已恢复。
- global Restaurant Detail：已统一。
- Roulette geometry：已恢复。
- Analytics/Posters：已恢复。
- F1-C4 duplicate Visit：`d9f5acd` 已加入 exact regression，当前不再是 Release blocker。

这些内容应保留 regression tests，但本轮没有理由重新实现。

---

# B. LOST FEATURES

## B1. Confirmed fully lost product features

在当前 baseline 上，**没有确认到一个 Legacy 正式产品模块整体丢失且需要直接恢复**。Map、Discovery、Add Restaurant、Detail、Profile、Roulette、Analytics、Lists、Visit、Social、Premium 的主能力都已经存在，很多能力比 Legacy 更完整。

唯一明确未闭环的是 **Marker z-order 行为**，它属于产品行为 regression，而不是整页 feature missing。

## B2. Unresolved historical surface: `preferenceLevel` summary

Legacy 有 `favorite/like/normal/avoid` 字段及 Profile 四格 summary，但数据库逻辑表明该值多数由平均 rating 推导，不一定是独立用户意图。Current 并未丢失字段：Restaurant JSON、Backup v1、Legacy Import 和部分 Analytics 都保留它。

因此不能报为“数据字段丢失”，也不能自动恢复成正式 Profile 模块。是否需要让用户直接设置/看到四级偏好，必须由 Lafayette 决定，避免与评分、想吃、回头率重复。

## B3. Asset gap, not lost feature

Legacy 只包含 32/180/192/512 Web icons，没有正式 1024px iOS AppIcon source。Current AppIcon catalog 也没有可确认的正式图片文件。它是发布资产 Gate，不是可以从 Legacy 自动恢复的 feature。

---

# C. CURRENT-ONLY FEATURES

下列能力在 Legacy 不存在或不够成熟，必须保护：

## Identity, data and sync

- Taste Map user ID 与 Apple sub 分离；
- auth identities / sessions / refresh rotation / reuse detection；
- global Restaurant UUID + multiple provider identities；
- Apple Maps-only Restaurant 完整 CRUD；
- SwiftData local-first、offline mutation persistence；
- versioned `/api/v1/sync`、incremental cursor、server version；
- mutation idempotency、tombstone、防复活；
- current-user checkpoint 和 local multi-account isolation；
- real-device sync timeout diagnosis/fix；
- Worker identity 覆盖客户端 userId。

## Backup and Import

- Backup v1 locked contract；
- current-user isolated export；
- strict Legacy Web v4 decoder；
- preflight/dry run；
- merge plan/transaction writer；
- exact duplicate Visit regression；
- Import UI 和取消/确认边界。

## Native content and social

- separate Dish / VisitDish；
- PhotoAsset metadata/local file/upload retry/provider abstraction；
- real backend social caches and activity contracts；
- worker-backed Like/Comment；
- Report/Block/Delete own content/comment；
- visibility and public sharing controls；
- canonical cross-entry Restaurant Detail。

## Premium, Analytics and release

- StoreKit 2 purchase/restore/transaction updates；
- server entitlement and expiry/revoke/refund handling；
- native owner-scoped analyzers；
- five 9:16 native posters + image renderer/temp cleanup；
- Settings foundation、Account Delete boundary；
- Share Extension and public links；
- Release Binary Purity；
- Accessibility/Dark Mode/locale/performance hardening；
- DEBUG-only Visual QA that is excluded from Release；
- three-layer Design System Architecture。

---

# D. VISUAL REGRESSIONS

## D1. Current open

### Map marker layer hierarchy

视觉上最重要的开放项是密集 Marker 的层级：Legacy 有明确 score/visit z-order，Current 没有。它会在相同/相近位置改变用户首先看到的 Restaurant。

### Cross-surface Restaurant imagery

Current 视觉规则正确，但 resolver 分散。视觉验收必须覆盖：

- local user photo；
- public/cached photo；
- AMap lawful provider photo；
- Apple/MapKit 无图；
- deleted/revoked photo；
- FoodDining honest fallback。

Food visual 不能因为“更统一”而遮盖真实图。

## D2. Historical deviations now resolved

- Map 顶部多层 segmented/filter 堆叠；
- Discovery 多出一层“发现餐厅/社区动态”；
- Profile 巨型纵向 card dashboard；
- multiple Restaurant Detail bodies；
- Roulette wheel 几何偏差；
- ordinary analytics report/card stack；
- poster 只验证 Share Sheet 而不验证内容；
- Premium hamburger 被非认可 asset 替代。

Current source和最近 Product UX commits 表明这些已修复。未来融合不能把它们重新带回来。

## D3. Historical report conflict

旧 closure report 中的 Food/Dining far cluster 描述与最新“所有缩放层级独立 Marker”冲突。Current source 使用 `clusteringIdentifier = nil`，应以最新 Design Rules 与代码为准。该旧报告只能作为历史记录，不能作为当前 PASS contract。

---

# E. INTERACTION REGRESSIONS

## E1. Map

- Legacy selected Marker 强制置顶；Current 使用 MapKit selection，但需与未来 z-order 一起做重叠场景验收。
- Current centered title+icon switch 是最新决定，不能恢复 Legacy 浮动/顶部二次切换。
- Filter/scope state 已共享，不能因 z-order 修复重置。

## E2. Add Restaurant

Legacy 正确产品路径是 Search / Share Link / Nearby / Manual → Restaurant preview → WantToGo or Visit。Current 已恢复并改善 GPS freshness/provider identity。没有证据支持重做 flow。

## E3. Restaurant Detail navigation

Legacy 证明“基础摘要应共享”，Current 将其提升为全局 canonical body。未来任何新入口都只能传 `restaurantId + entrySource`，不得出现 Discover/Map/Friend 专用 Detail。

## E4. Roulette

Legacy 临时自定义候选虽然方便，但会生成非持久、身份不稳定的候选。Current 通过 Manual Add 获得真实 Restaurant 是更安全的交互决定，不应恢复 fake candidate。

## E5. Social

Legacy local Like/Comment 表面可操作，但不构成跨端 authoritative state。Current backend interactions 是正确升级，不能为了视觉 parity 退回 local-only feedback。

---

# F. DATA / SEMANTIC REGRESSIONS

## F1. No loss: Restaurant preference

`preferenceLevel` 在 Current 中存在：

- `RestaurantJSONContractV1`；
- Backup v1 contract；
- Legacy v4 normalizer；
- Import transaction writer；
- 部分 Analytics/companion recommendation logic。

它不是丢失字段。开放问题只是是否显示为正式 UI。

## F2. Correct current semantics to protect

- Restaurant 和 Visit 分离；
- 一店多次 Visit；
- rating untouched = `nil`；
- Dish/Photo 分离；
- Visit 保存不依赖图片上传；
- owner 从 verified server identity 得出；
- Apple/AMap IDs 是 external identities，不是 primary key；
- delete 使用 tombstone；
- StoreKit entitlement 不能由客户端 flag 决定。

## F3. Deprecated fields

Legacy 中以下内容即便仍能被 decoder 识别，也必须 RETIRE，不回到正式 UI/model：

- 是否愿意再来；
- 推荐菜；
- 避雷菜；
- 座位情况；
- 等位之外订位情况；
- 最佳到访时间。

兼容 decoder 读取/报告/丢弃不等于恢复产品字段。

## F4. Duplicate Import

Current `d9f5acd` 已覆盖：

```text
Legacy v4 first import
→ second identical source
→ cross-provider Restaurant candidate
→ manual merge
→ dependent Visit re-resolve
→ exactDuplicate
→ no second Visit
→ no extra mutation
```

因此 F1-C4 duplicate Visit 应保持 **CLOSED**，不要求对真实用户数据做危险的第二次 Import。

---

# G. LEGACY RETIRED CONTENT

| Legacy content | Why retired |
| --- | --- |
| Far-zoom numeric clusters | 最新规则要求所有缩放层级独立 Marker |
| Old Map/List switch placement | 最新 centered title+icon 是正式入口 |
| `amapPoiId` as unique primary key | 与 global Restaurant identity 冲突 |
| Synthetic AMap ID for manual Restaurant | 会制造 provider identity 假数据 |
| Raw emoji marker/customizer as formal visual | 与 FoodDiningVisualLibrary 和一致性规则冲突；仅兼容解码 |
| Google Drive photo sync | Lafayette 已明确取消 |
| IndexedDB as cross-platform truth | Current Worker/D1 + platform local caches 已取代 |
| Local/fake engagement state | Current Worker-backed UGC 已取代 |
| Local/admin Premium bypass | Release 安全禁止 |
| Six deprecated Visit fields | 已明确废弃 |

此外，Legacy 的 Web DOM/CSS poster 和页面 magic numbers 不能逐字翻译成 SwiftUI。可恢复的是产品语义和视觉证据，不是平行组件库。

---

# H. ASSETS WORTH RECOVERING

## H1. Asset inventory

Legacy repo 中实际找到的 raster/icon assets 只有：

```text
public/icons/taste-map-icon-32.png
public/icons/taste-map-icon-180.png
public/icons/taste-map-icon-192.png
public/icons/taste-map-icon-512.png
public/icons/taste-map.ico
public/taste-map-avatar-presets.png
```

没有找到可直接恢复的历史 Restaurant 商户照片图库、poster 照片库或 marker bitmap library。Legacy Restaurant/photo imagery 主要来自数据、URL 或用户记录，不能在审计报告中虚构为 repo asset。

## H2. Fusion asset matrix

| Legacy asset | Current asset | Final recommendation |
| --- | --- | --- |
| `taste-map-avatar-presets.png` | `TasteMapAvatarPresets.imageset/taste-map-avatar-presets.png` | **KEEP CURRENT**；SHA-256 完全相同：`85ae2852...94fa8` |
| 32/180/192/512 Web icons | `AppIcon.appiconset/Contents.json`，无正式图片 source | **NEEDS APPROVAL**；不能把 512px 自动放大为 1024px |
| Legacy approved Premium hamburger SVG/code | `PremiumViews.swift` Canvas，`web-approved-hamburger-v1` | **KEEP CURRENT**；当前是认可视觉的 code-native port |
| Legacy raw emoji marker | `FoodDiningVisualLibrary.swift` | **RETIRE raw asset UI**；只保留 compatibility mapping |
| Legacy merchant/user image URLs | PhotoAsset + provider/public image pipeline | **FUSE semantics**；真实合法图片优先，不能直接复制缓存 |
| Legacy 无 Food Hero bitmaps | Current FoodHero Japanese/Chinese/HotpotGrill/Western/Cafe/Mixed | **KEEP CURRENT**；属于后来确认的 Analysis system |

## H3. No automatic copy list

下列动作都不应执行：

- 从 ZIP 覆盖 Assets.xcassets；
- 复制 Web 512 icon 当 App Store icon；
- 把旧 URL cache 当拥有版权的商户原图；
- 用 raw system emoji 替代正式 Food/Dining assets；
- 覆盖 current approved hamburger；
- 将 Legacy manifest/favicon 当 iOS signing/app metadata。

---

# I. NEEDS USER DECISION

## I1. Restaurant `preferenceLevel` 是否需要正式 UI

证据同时支持两种解释：

- Legacy Profile 有 favorite/like/normal/avoid summary，说明它曾经是可见产品概念；
- Legacy database 多处根据平均 rating 自动推导该字段，说明它可能只是派生兼容数据，而不是独立用户输入；
- Current 保留合同与分析用途，但最新 Profile 决定没有把它列入主统计。

建议 Lafayette 决定以下其一：

1. 保持隐藏兼容字段（推荐，最少重复语义）；
2. 作为 secondary insight 展示，但不成为独立输入；
3. 明确升格为用户可编辑偏好，并先定义它与 rating/想吃/回头率的差异。

本轮不自动选择。

## I2. App Icon source

Legacy 最高清晰度只有 512×512，不能证明它是正式 1024×1024 App Store source。Current AppIcon 也没有可确认图片。

需要 Lafayette：

- 提供或确认正式 1024×1024 source；
- 明确是否沿用 Legacy 品牌造型；
- 再由独立 App Icon 任务导入和真机验收。

用户已明确本轮不得修改 App Icon，因此这里只记录 Gate。

---

## Full page and capability cross-check

### 1. My Map / My List

**Legacy structure**

- 地图/列表、visited/want/recommend scopes；
- city/filter/sort；
- numeric clusters at far zoom；
- individual restaurant markers at closer zoom；
- exact-coordinate stable offset；
- score/visit z-index；
- selected marker top；
- user avatar top layer；
- merchant/user image or fallback marker。

**Current structure**

- centered “我的地图/我的列表 + switch icon”；
- 去过/想吃/推荐；
- compact horizontal chips + filter sheet；
- independent MapKit markers, no cluster；
- stable exact-coordinate dispersion；
- real image policy；
- shared Map/List state。

**Decision**

FUSE only z-order/selection evidence into Current. Keep current title, scopes, chips, no-cluster, identity, image priority, user avatar, query state. Do not recreate Legacy Map component.

### 2. Discovery / Community

**Legacy semantics**

- five primary tabs；
- city/distance/rating/trend filters；
- user + restaurant + visit rating + image + recommendation reason；
- like/comment/share and navigation；
- loading/empty/error。

**Current semantics**

- same five tabs；
- real Worker APIs, cache, pagination, offline；
- nullable Visit rating restored；
- canonical user/restaurant navigation；
- backend Like/Comment and safety controls。

**Decision**

FUSE historical IA/card semantics with Current backend/security. No open full-page regression found in current source.

### 3. Add Restaurant / Nearby

**Legacy semantics**

- Search / AMap or Apple/share link / Nearby / Manual；
- GPS-centered 3km results；
- preview then WantToGo or Visit；
- dedupe/re-record existing restaurant。

**Current semantics**

- same product sources；
- fresh CLLocation, horizontalAccuracy/timestamp checks, Reduced Accuracy honest state；
- MapKit/AMap/manual identities；
- real CLLocation distance/sorting；
- canonical preview and local-first save。

**Decision**

FUSE IA, KEEP CURRENT location and identity implementation. RETIRE synthetic AMap manual IDs.

### 4. Restaurant Detail

Legacy proved the correct information ordering and shared summary concept. Current has the correct global abstraction and expands it safely. Preserve:

1. Hero
2. city/status/name/actions
3. address/price/phone/hours/directions
4. my/all/friend/same-taste ratings with samples
5. user photos
6. personal overview
7. Visit history
8. current dishes/context/detailed ratings

Every entry source must continue using the same `RestaurantDetailStandardBody`.

### 5. Profile / My and Public Profile

Legacy compact dashboard is useful historical evidence. Current correctly fuses it with:

- followers/following near identity；
- current business stats 去过/想去/总消费；
- paired Roulette/Taste Profile；
- memories；
- lists；
- 最佳饭搭子/谁最会种草；
- Settings/Backup/Sync；
- real Social visibility and safety。

Do not restore old statistic labels or old analytics names verbatim.

### 6. Roulette

Keep Legacy geometry/story topology and Current stable Restaurant identity/source filters. Do not restore ephemeral custom fake candidates. Continue max 10, min 2, empty slots, images, city, rating, pointer and result.

### 7. Analytics / Poster

Legacy is semantic evidence; Current native implementation is the visual/technical source. Preserve:

- 我的口味档案；
- 最佳饭搭子；
- 谁最会种草；
- 本月回顾；
- 年度回顾；
- 那年今日；
- owner-scoped real data；
- Food Hero driven only by real evidence when semantic；
- representative Restaurant image/text；
- five native 9:16 posters；
- privacy redaction and temp cleanup。

Do not collapse back into ordinary statistics cards or DOM screenshot sharing.

### 8. Lists

Legacy CRUD/ranked/collection/visibility/reorder/cover/share are present in Current. Current ownership, sync, public cache and canonical Detail are stronger. Joining a list must not implicitly mutate personal want/visited status.

### 9. Visit / Dish / Photo

Current preserves Legacy rich recording semantics while improving model separation and local-first safety. Explicitly retired fields remain decoder-only compatibility. Do not reintroduce them into UI/schema.

### 10. Social

Current is a strict superset: follow/friend/public profile/activity plus real Like/Comment/Report/Block/Delete-own. Legacy is useful for IA, not for authoritative state or safety architecture.

### 11. Premium

Keep current StoreKit/server entitlement. Preserve approved hamburger port. Do not restore Legacy local/admin membership controls.

### 12. Images / Assets

No Legacy restaurant photo library exists. Use only lawful data sources. A Food/Dining visual is an honest final fallback, never a fabricated merchant image and never a replacement for an available real image.

### 13. Data model and business architecture

Current architecture is strictly newer and safer. Legacy types inform decoder/semantic compatibility only. No proposal in this report requires a SwiftData/Worker/D1 migration.

---

## Risk-ranked future work

| Priority | Work | Why first | Scope boundary |
| --- | --- | --- | --- |
| P1 | Map Marker score/visit/selected layer fusion | Only clear open migration regression with exact Legacy evidence | Map presentation/view + tests only; no query/model change |
| P1/P2 | Canonical Restaurant image renderer | Prevent cross-surface fallback drift and real-photo masking | Reuse current policy; no provider secret or image fabrication |
| Decision | `preferenceLevel` visible UI | Product semantics ambiguous | Wait for Lafayette; no automatic code |
| Release gate | Formal 1024 App Icon source | Legacy asset insufficient | Separate approved asset task only |

## Final conclusion

这次审计的结论不是“恢复 Windows 版”，而是：

```text
Legacy strengths
+ Current identity/data/sync/social/premium capabilities
+ Current Design System
+ Latest Lafayette decisions
= Final Taste Map
```

**下一步应先融合：My Map 的 Restaurant Marker overlap/layer priority 模块。**

理由：它是本次唯一有明确 Legacy 代码证据、Current 数据已具备、但渲染语义仍未闭环的 migration regression；范围可控，不需要改数据模型、Worker、Production 或其他页面。完成后再收口 canonical Restaurant image renderer。

本轮没有自行开始上述融合代码。
