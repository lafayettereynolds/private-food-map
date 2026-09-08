# Taste Map Legacy Fusion Decisions

> 状态：已归并的 Legacy 决策登记；`NEEDS LAFAYETTE APPROVAL` 项仍未批准，任何代码实施仍需独立授权。
> 审计基线：`fix/product-ux-correction-8-tasks@648be229878d7358c9381d5153580a130f32d8c3`
> Legacy 基线：`main@fb127e9ea20498c0db450872deb9c9dc346ef34f`
> 审计日期：2026-09-01
> 业务代码修改：**NO**

## 1. 审计边界与安全结论

本文件把 Windows/Web 旧版作为只读历史证据库，与当前正式 Mac/iOS 项目逐项比较。它不是恢复脚本、迁移脚本或 merge 计划。本轮没有复制 Legacy `src/`、没有修改 SwiftData、Worker、D1、R2、StoreKit、Signing、Capability、App Icon，也没有访问 Production。

当前正式项目仍是唯一开发源：

- 路径：`/Users/lafayette/Projects/private-food-map-product-ux`
- 分支：`fix/product-ux-correction-8-tasks`
- HEAD：`648be229878d7358c9381d5153580a130f32d8c3`
- `origin/fix/product-ux-correction-8-tasks`：同一 commit
- 开始审计时唯一工作区例外：未跟踪的 `pnpm-workspace.yaml`；本轮未读取为配置依据、未修改、未暂存。

Legacy 原始归档：

- `/Users/lafayette/Desktop/Taste-Map-完整项目备份-2026-09-01.zip`
- SHA-256：`18f5ad1d64bc6c5447cccfa4e1cae1f6edb4888ee2f7897a5f73789316cc37c0`
- 审计时只读解压位置：`/tmp/tastemap-legacy-reference-20260901-648be22`
- 解压目录已去除写权限；原 ZIP 未修改。

找到两个 Legacy 候选：

1. 上述 ZIP：包含 React/Web、Worker/D1、旧 assets、tests、docs、migrations `0001–0014` 和完整 `.git`，是最终 Windows 正式版本。
2. `/Users/lafayette/Projects/private-food-map-connector-backup-20260827`：无 `.git`；核心源码与 ZIP 一致，仅缺少部分同步元数据和生成文件，应视为副本，不是第二条产品版本。

其他 `private-food-map*` 目录均为当前项目的分支/worktree，不是 Windows Legacy 候选。

## 2. Git 关系：不是两套无关代码

Legacy `fb127e9` 是当前 `648be22` 的**精确祖先**。当前项目不是需要跨仓库 cherry-pick 的另一条历史，而是在 Legacy 之后连续增加原生 iOS、同步、认证、备份导入、Social、Premium、Product Parity、Design System 和 Release Safety 的后继版本。

关键证据：

```text
merge-base(fb127e9, 648be22) = fb127e9
Legacy HEAD = fb127e9 Update Taste Map premium and product experience
Current HEAD = 648be22 Enforce Taste Map design system architecture
Current-only commits since Legacy = 113
```

因此未来融合应从“产品语义和历史正确行为”中恢复证据，不能 merge/cherry-pick Legacy，也不能把当前架构倒退成 IndexedDB + `amapPoiId` 中心模型。

## 3. Source of Truth 与判断词

冲突优先级固定为：

1. Lafayette 当前任务中的最新明确决定
2. `docs/TASTEMAP_PRODUCT_DESIGN_RULES.md`
3. 本文件中已经记录并确认的 Legacy Fusion Decision
4. 当前新版已确认的新功能与新产品决定
5. 用户历史确认过的 Web 设计、页面与交互
6. Windows/Web Legacy 实现证据
7. 当前 iOS 中尚未人工确认的视觉实现

本文只使用以下判断：

- **RESTORE**：Legacy 做对且当前仍确实缺失，应恢复产品行为。
- **KEEP CURRENT**：当前能力更强、更新或已经锁定，应保护。
- **FUSE**：恢复 Legacy 的结构/语义，同时保留当前新增能力与架构。
- **RETIRE**：Legacy 内容已废弃或与最新决定冲突，不恢复。
- **NEEDS LAFAYETTE APPROVAL**：不能由代码证据自动决定，未来实施前必须确认。

Legacy 默认没有权限删除或降级当前正式 feature、data field、interaction、Premium、Social、Sharing、Analytics 或当前架构。任何这类删除建议都必须改判为 **NEEDS LAFAYETTE APPROVAL**，并在实现前停止等待确认。

证据列缩写：

- `L:`：Legacy commit 证据，可用 `git show fb127e9:<path>` 复现。
- `C:`：当前 `648be22` 工作树证据。
- `R:`：`docs/TASTEMAP_PRODUCT_DESIGN_RULES.md` 或当前正式报告中的规则证据。

## 4. Executive decision count

下表共 **98** 项决策：

| Decision | Count |
| --- | ---: |
| RESTORE | 1 |
| KEEP CURRENT | 39 |
| FUSE | 46 |
| RETIRE | 10 |
| NEEDS LAFAYETTE APPROVAL | 2 |

> 数量只用于说明审计覆盖范围，不表示实施工作量。一个 `FUSE` 可能比多个 `KEEP CURRENT` 更复杂。

## 5. Legacy Fusion Matrix

| # | Area | Legacy Web | Current | Evidence | Decision | Risk | Needs Approval |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 01 | My Map 标题/切换 | 移动端曾使用页面内或浮动 Map/List 切换 | 最新为“我的地图/我的列表 + 小图标”整体居中并作为唯一切换入口 | L:`src/components/MapView.tsx`; C:`ios/TasteMap/TasteMap/Features/Map/MapHomeView.swift`; R:最新 My Map override | KEEP CURRENT | 低 | 否 |
| 02 | My Map 一级范围 | Legacy 有去过、想吃与推荐/发现语义 | 当前固定“去过 / 想吃 / 推荐”并共享查询状态 | L:`src/components/AppShell.tsx`; C:`MapHomeView.swift` | FUSE | 低 | 否 |
| 03 | Map Filter/Sort/City | Legacy 有城市、筛选、排序和状态保留 | 当前 compact horizontal chips、filter sheet、共享 projection | L:`src/components/FilterPanel.tsx`; C:`PersonalRestaurantFilters.swift`,`MapHomeView.swift` | FUSE | 中 | 否 |
| 04 | 远距离数字 cluster | Legacy `CLUSTER_MAX_ZOOM = 9`，远景数字聚合 | 最新明确任何缩放层级均不使用数字 cluster | L:`src/components/MapView.tsx`; C:`ClusteredRestaurantMapView.swift`; R:Marker override | RETIRE | 高：恢复会直接违反最新规则 | 否 |
| 05 | 独立 Restaurant Marker | Legacy 城市级开始展开独立商户 | 当前 `clusteringIdentifier = nil`、独立 UUID Marker | C:`ClusteredRestaurantMapView.swift` | KEEP CURRENT | 低 | 否 |
| 06 | Marker 重叠/同坐标处理 | Legacy AMap 图层允许 Marker 自然重叠；历史代码也曾对完全同坐标做轻微散开 | 当前会对同坐标默认强制 dispersion | L:`MapView.tsx`; C:`RestaurantMapPresentation.swift`; R:最新 Marker override | FUSE | 中：最终规则是自然重叠；普通状态不默认 offset/spiderfy，只允许用户主动展开 | 否 |
| 07 | Marker 评分层级 | Legacy 明确 `scoreOutOfTen` 优先、`visitCount` 次级，并设置 z-index | 当前 Marker 有 `averageRating`/`visitCount`，但 annotation `displayPriority` 全部相同，未形成评分层级 | L:`MapView.tsx#markerLayerPriority`; C:`RestaurantMapPresentation.swift`,`ClusteredRestaurantMapView.swift` | RESTORE | **高：当前最明确的未闭环迁移回归** | 否 |
| 08 | 选中 Marker 置顶 | Legacy `setTop(selected)` | 当前用 MapKit select/deselect，主体选择正确，但应与未来评分 z-order 一起验证视觉置顶 | L:`MapView.tsx`; C:`ClusteredRestaurantMapView.swift` | FUSE | 中 | 否 |
| 09 | 用户位置/头像 | Legacy 用户头像在最高图层 | 当前真实用户位置 + Profile avatar annotation，并保留权限诚实状态 | L:`MapView.tsx`; C:`ClusteredRestaurantMapView.swift`,`LocationPermissionManager.swift` | KEEP CURRENT | 低 | 否 |
| 10 | Restaurant 图片优先级 | Legacy 图片/emoji 受 `markerType` 分支影响，可能先走装饰 emoji | 当前正式合同为本地用户图 > 公共/缓存图 > 合法 provider HTTPS > Food fallback | L:`src/components/RestaurantAvatar.tsx`; C:`RestaurantImagePriorityPolicy.swift` | KEEP CURRENT | 中 | 否 |
| 11 | 跨页面 Restaurant 图片 renderer | Legacy 多处分别取 merchant/photo/emoji | 当前已有统一 policy，但 Discovery/Community/List/Roulette/Detail 仍有部分表层 resolver 分散 | L:多组件；C:`RestaurantImagePriorityPolicy.swift` 及各 Feature image view | FUSE | **高：策略漂移可能让 fallback 遮盖真实图** | 否 |
| 12 | Map/List state preservation | Legacy 切换时保留 scope/filter | 当前 Map/List 共享 browse state、sort/filter/projection | L:`MapView.tsx`; C:`MapHomeView.swift`,`PersonalRestaurantFilters.swift` | FUSE | 低 | 否 |
| 13 | Discovery 一级 IA | Legacy 五个一级入口：关注/为你推荐/同味之选/最新/趋势 | 当前已恢复相同五入口，不再套“发现餐厅/社区动态”二级壳 | L:`src/components/CommunityPage.tsx`; C:`DiscoveryView.swift`,`RootTabView.swift` | FUSE | 低 | 否 |
| 14 | Discovery 城市与筛选 | Legacy 按 tab 暴露城市、距离、评分、趋势周期 | 当前使用共享 compact chip 语言和当前能力 registry | L:`CommunityPage.tsx`; C:`DiscoveryBrowsePresentation.swift` | FUSE | 中 | 否 |
| 15 | Discovery Restaurant Card | Legacy 显示商户图、原因、评分、来源用户与动作 | 当前保留并连接真实 contract/caches | L:`CommunityPage.tsx`; C:`DiscoveryView.swift` | FUSE | 中 | 否 |
| 16 | Activity Visit rating | Legacy activity 有具体 Visit rating，并允许 nil | 当前在迁移中曾丢失，后续合同和 UI 已恢复 nullable Visit rating | L:`CommunityPage.tsx`; C:`CommunityV1Contracts.swift`,`CommunityFeedView.swift`; Git:`ad83c7d` | FUSE | 低：当前已修复，须回归保护 | 否 |
| 17 | Like/Comment/Share | Legacy 交互存在，但部分状态只在客户端/local storage | 当前是 Worker-backed、幂等、owner-isolated，并含 Share | L:`CommunityPage.tsx`; C:`CommunityInteractionViews.swift`,`CommunityAPIClient.swift` | KEEP CURRENT | 高：不得退回本地假互动 | 否 |
| 18 | Loading/Empty/Error/Offline | Legacy 有基本状态 | 当前增加缓存、offline、retry、分页和 auth 恢复 | L:`CommunityPage.tsx`; C:`DiscoveryView.swift`,`CommunityFeedView.swift` | KEEP CURRENT | 低 | 否 |
| 19 | 社区到用户/餐厅导航 | Legacy 可进 public profile/restaurant | 当前入口进入 canonical Public Profile 与 Restaurant Detail | L:`CommunityPage.tsx`; C:`CommunityFeedView.swift` | FUSE | 中 | 否 |
| 20 | Add Restaurant 信息架构 | Legacy Search/Link/Nearby/Manual 并列流程 | 当前已恢复同一产品语义，并使用原生 Navigation | L:`src/components/AddRestaurantModal.tsx`; C:`AddRestaurantView.swift` | FUSE | 中 | 否 |
| 21 | Nearby GPS 正确性 | Legacy 使用 browser fresh geolocation + 3km AMap query | 当前增加 timestamp/accuracy/stale/reduced-accuracy/foreground/movement 校验 | L:`AddRestaurantModal.tsx`; C:`LocationPermissionManager.swift`,`NearbyRestaurantSearchService.swift` | KEEP CURRENT | 高：不得倒退成 city/camera center | 否 |
| 22 | Provider Search | Legacy 高德为主并支持 URL/share text | 当前 MapKit + AMap/url ingestion + provider-neutral identity | L:`src/services/amap.ts`,`AddRestaurantModal.tsx`; C:`RestaurantAcquisitionService.swift`,`PlaceIdentity.swift` | FUSE | 中 | 否 |
| 23 | Nearby 距离与排序 | Legacy 3km/top 8，按 provider/坐标距离 | 当前 CLLocation 真实距离、3km、fresh center、结果去重 | L:`AddRestaurantModal.tsx`; C:`NearbyRestaurantSearchService.swift` | FUSE | 中 | 否 |
| 24 | Manual Add synthetic AMap ID | Legacy 手动餐厅生成伪 `amapPoiId` | 当前 global Restaurant UUID + optional place identities | L:`AddRestaurantModal.tsx`; C:`RestaurantJSONContract.swift` | RETIRE | 高：恢复会破坏 global identity | 否 |
| 25 | Add dedupe/existing Restaurant | Legacy 发现同店后复用/再次记录 | 当前跨 provider identity + 名称/地址/坐标候选，显式确认 | L:`src/db/restaurants.ts`; C:`RestaurantDeduplicationService.swift` | FUSE | 高 | 否 |
| 26 | Add 选中预览 | Legacy 预览商户基本信息与操作 | 当前用 `RestaurantDetailStandardBody` 子集，避免第二套 Detail | L:`AddRestaurantModal.tsx`; C:`AddRestaurantView.swift` | KEEP CURRENT | 中 | 否 |
| 27 | WantToGo / Record Visit | Legacy 显式选择想吃或去过/新增 Visit | 当前 local-first，同店再次到访生成独立 Visit | L:`AddRestaurantModal.tsx`; C:`AddRestaurantView.swift`,`VisitEditorView.swift` | FUSE | 高 | 否 |
| 28 | 全局唯一 Restaurant Detail | Legacy 已抽出共享 Restaurant summary，但仍有 Web route context | 当前 `RestaurantDetailStandardBody` + `RestaurantDetailEntrySource` 是全局唯一主体 | L:`src/components/RestaurantSummarySection.tsx`; C:`RestaurantDetailComponents.swift`,`RestaurantDetailView.swift` | KEEP CURRENT | **高：禁止再分叉页面** | 否 |
| 29 | Detail Hero/header 顺序 | Legacy Hero→city/status→name→actions | 当前同一 canonical body，并增加真实图片 policy | L:`RestaurantSummarySection.tsx`; C:`RestaurantDetailComponents.swift` | FUSE | 中 | 否 |
| 30 | Detail 商户基础信息 | Legacy 地址→参考人均→电话→营业时间→导航 | 当前在 canonical business/location sections 中统一 | L:`RestaurantSummarySection.tsx`; C:`RestaurantDetailComponents.swift` | FUSE | 中 | 否 |
| 31 | 四圆评分 | Legacy 我的/全部/好友/同味，大圆分数、小圆样本 | 当前保留同一语义与 nil/sample honest state | L:`RestaurantSummarySection.tsx`; C:`RestaurantDetailComponents.swift` | FUSE | 高：不得生成假评分 | 否 |
| 32 | 用户实拍 | Legacy 位于基础信息之后、个人记录之前 | 当前位置和 Gallery 语义统一，并支持本地/远程 PhotoAsset | L:`RestaurantSummarySection.tsx`; C:`RestaurantDetailComponents.swift`,`PhotoGalleryComponents.swift` | FUSE | 中 | 否 |
| 33 | 我的到访概览/历史 | Legacy 到访次数、平均分、最近、消费、每次独立 Visit | 当前 owner-scoped、可编辑/删除单条、上下文更完整 | L:`RestaurantPreviewCard.tsx`; C:`RestaurantDetailPresentation.swift`,`RestaurantDetailComponents.swift` | FUSE | 高 | 否 |
| 34 | Dishes/context/detailed ratings | Legacy 有嵌入式菜品和丰富 Visit context | 当前分离 Dish/VisitDish、独立照片与详细评分 | C:`Dish.swift`,`VisitDish.swift`,`RestaurantDetailedRatingsSection.swift` | KEEP CURRENT | 高：不得退回嵌入式模型 | 否 |
| 35 | Cross-entry Detail | Legacy 入口较少且共享程度有限 | 当前 Map/Search/Nearby/Discovery/Community/Public Profile/List/Analytics/Roulette/On This Day/Share 都传 entrySource 进入同一主体 | C:`RestaurantDetailEntrySource` 全局引用 | KEEP CURRENT | 高 | 否 |
| 36 | Profile compact dashboard | Legacy 是高密度 dashboard，而非纵向大卡片流 | 当前已恢复 compact header、分组和双列入口 | L:`src/components/ProfilePage.tsx`; C:`ProfileView.swift` | FUSE | 中 | 否 |
| 37 | Profile followers/following | 显示关注/粉丝并可导航 | 当前与身份区相邻，连接真实 Social contract | L:`ProfilePage.tsx`; C:`ProfileView.swift`,`SocialViews.swift` | FUSE | 中 | 否 |
| 38 | Profile 主统计 | Legacy 统计组合曾包含社交与餐厅数据 | 最新决定固定去过/想去/总消费，当前已按真实口径实现 | L:`ProfilePage.tsx`; C:`ProfileSocialStatistics.swift`,`ProfileView.swift`; R:Profile override | KEEP CURRENT | 中 | 否 |
| 39 | 今天吃什么 + 我的口味档案 | Legacy 并排主入口 | 当前恢复同级双入口并连接原生功能 | L:`ProfilePage.tsx`; C:`ProfileView.swift` | FUSE | 低 | 否 |
| 40 | 回味 | Legacy 本月/年度/那年今日同一 section | 当前恢复同一 hierarchy | L:`ProfilePage.tsx`; C:`ProfileView.swift` | FUSE | 低 | 否 |
| 41 | 我的食单 | Legacy dashboard 中独立 section | 当前 Lists 集成并保留 owner/public/ranked 能力 | L:`ProfilePage.tsx`; C:`ProfileView.swift`,`RestaurantListsView.swift` | FUSE | 中 | 否 |
| 42 | 洞察入口 | Legacy 饭搭子/推荐来源分析等 | 当前用正式新名称“最佳饭搭子”“谁最会种草”并保留分析能力 | L:`ProfilePage.tsx`; C:`ProfileView.swift` | KEEP CURRENT | 低 | 否 |
| 43 | Settings/Data/Backup/Sync | Legacy settings/data 入口有限 | 当前正式 Settings IA、Backup v1、Import、Sync diagnostics | C:`TasteMapSettingsView.swift`,`BackupExportService.swift` | KEEP CURRENT | 高 | 否 |
| 44 | Public Profile | Legacy 动态/口味/食单、共同想吃、代表店和 follow/friend | 当前保留结构并增加 visibility、cache、report/block、安全删除 | L:`src/components/PublicProfilePage.tsx`; C:`SocialViews.swift`,`ProfileOwnedContentScope.swift` | FUSE | 高 | 否 |
| 45 | Roulette 轮盘几何 | Legacy pointer、center、5–10 segment、空 slot | 当前原生 Wheel 恢复相同几何和视觉关系 | L:`src/components/RestaurantRoulette.tsx`; C:`RestaurantRouletteView.swift` | FUSE | 中 | 否 |
| 46 | Roulette max 10/至少 2 | Legacy max 10、至少 2 才转 | 当前 engine 同样约束并提供 honest empty state | L:`RestaurantRoulette.tsx`; C:`RestaurantRouletteEngine.swift` | FUSE | 低 | 否 |
| 47 | Roulette 候选信息 | Legacy image/name/city，结果卡 | 当前增加 rating、real image priority，并保持信息密度 | L:`RestaurantRoulette.tsx`; C:`RestaurantRouletteView.swift` | FUSE | 中 | 否 |
| 48 | Roulette 候选管理 | Legacy chip/管理面板/来源选择 | 当前正式 sheet、filter、stable IDs | L:`RestaurantRoulette.tsx`; C:`RestaurantRouletteView.swift` | FUSE | 中 | 否 |
| 49 | Roulette identity/selection | Legacy 以名称去重并允许临时条目 | 当前以 global Restaurant ID 稳定去重并保持均匀随机 | C:`RestaurantRouletteEngine.swift` | KEEP CURRENT | 高 | 否 |
| 50 | 临时虚构 Roulette candidate | Legacy 可加不持久的自定义候选 | 当前要求通过 Manual Add 成为真实 Restaurant | L:`RestaurantRoulette.tsx`; C:`RestaurantRouletteView.swift` | RETIRE | 中：避免假 Restaurant | 否 |
| 51 | 五类 Analytics 产品范围 | Legacy 已有口味、饭搭子、来源、月度、年度及回忆 | 当前保留并扩展真实原生分析 | L:`src/components/*Analysis*`,`ProfilePage.tsx`; C:`Features/Analysis/` | FUSE | 中 | 否 |
| 52 | Analytics 统计语义 | Legacy 从真实 Restaurant/Visit/companion/source 聚合 | 当前 owner-scoped analyzer、样本充足度、nil/empty 诚实表达 | L:`src/services/profileInsights.ts`; C:`*Analyzer.swift` | FUSE | 高 | 否 |
| 53 | Analysis Theme | Legacy Web 有分享布局但 Core/Analysis 边界不完全稳定 | 当前独立 `TasteMapAnalysisTheme`，不污染 Core App | C:`Components/Analysis/TasteMapAnalysisTheme.swift` | KEEP CURRENT | 中 | 否 |
| 54 | Food Hero/代表餐厅 | Legacy 使用菜系/餐厅证据和图片候选 | 当前动态 Food Hero + 代表 Restaurant 图文 + FoodDining semantics | L:`src/services/analysisShare.ts`; C:`TasteProfileAnalyzer.swift`,`FoodHero*.imageset` | FUSE | 高：数据型视觉不得伪造 | 否 |
| 55 | 五类分享海报 | Legacy 有专门分享 render，不是纯页面截图 | 当前五类 9:16 SwiftUI poster + `ImageRenderer` + temp cleanup | L:`src/services/analysisShare.ts`; C:`*PosterView.swift`,`AnalysisPosterServices.swift` | KEEP CURRENT | 中 | 否 |
| 56 | Analytics 隐私/照片替换 | Legacy 有隐私 redaction 和 hero photo 选择 | 当前保留并结合 PhotoAsset、分享权限和 temp lifecycle | L:`analysisShare.ts`; C:`AnalysisPosterServices.swift` | FUSE | 高 | 否 |
| 57 | Analytics 正式名称 | Legacy 使用“饭搭子分析/推荐来源分析” | 最新正式名称为“最佳饭搭子/谁最会种草” | C:`DiningCompanionAnalysisView.swift`,`RecommendationSourceAnalysisView.swift` | KEEP CURRENT | 低 | 否 |
| 58 | 普通卡片/DOM 截图式分析 | Legacy 页面仍有 Web card/dashboard 呈现 | 当前已确认中心主视觉、留白、故事卡、独立 poster | R:Analysis override; C:`Features/Analysis/` | RETIRE | 中 | 否 |
| 59 | 那年今日 | Legacy 有回忆服务/页面 | 当前 native analyzer/view/poster 与 Profile 回味入口 | L:`src/services/reviewService.ts`; C:`OnThisDay*.swift` | FUSE | 中 | 否 |
| 60 | List model/CRUD | Legacy collection/ranked、create/edit/delete/reorder | 当前保留并用 SwiftData/Worker 同步 | L:`RestaurantListsPanel.tsx`; C:`RestaurantListsView.swift`,`RestaurantList.swift` | FUSE | 高 | 否 |
| 61 | List visibility/public share | Legacy private/friends/public 和 public route | 当前 visibility、public API/cache、link sharing 更完整 | L:`RestaurantListsPanel.tsx`; C:`RestaurantListV1Contracts.swift`,`PublicSharingViews.swift` | FUSE | 高 | 否 |
| 62 | List images/covers | Legacy custom/auto cover、Restaurant image | 当前 cover ownership + canonical image fallback | L:`RestaurantListsPanel.tsx`; C:`RestaurantListsView.swift` | FUSE | 中 | 否 |
| 63 | List ownership/sync | Legacy IndexedDB + older Worker owner | 当前 per-user SwiftData + mutation queue + public cache isolation | C:`LocalRestaurantListStore.swift`,`RestaurantListAPIClient.swift` | KEEP CURRENT | 高 | 否 |
| 64 | List 添加时隐式改 WantToGo | Legacy 某些路径会把 public Restaurant 合成为 wantToGo | 当前加入食单不隐式改变个人去过/想吃状态 | L:`RestaurantListsPanel.tsx`; C:`RestaurantListsView.swift` | KEEP CURRENT | 高：状态语义不得耦合 | 否 |
| 65 | Restaurant/Visit 分离 | Legacy 已正确分离，一店多次 Visit | 当前继续并增加 global identity/sync metadata | L:`src/types/domain.ts`; C:`Restaurant.swift`,`Visit.swift` | KEEP CURRENT | 高 | 否 |
| 66 | Optional rating | Legacy rating 可空且半星 | 当前未触碰时 `nil`，0.5–5.0 半星 | L:`domain.ts`; C:`VisitDraft.swift`,`VisitEditorView.swift` | FUSE | 高 | 否 |
| 67 | Rich Visit context | Legacy 消费、人数、排队、场景、模式、饭搭子、来源等 | 当前以正式字段/enum/optional 语义恢复 | L:`domain.ts`; C:`VisitDraft.swift`,`VisitContext.swift` | FUSE | 高 | 否 |
| 68 | Local-first Visit save | Legacy 本地 IndexedDB 先写 | 当前 SwiftData 先写 + persistent mutation queue，图片失败不阻塞 | C:`LocalVisitRecordingStore.swift`,`SwiftDataSyncQueue.swift` | KEEP CURRENT | 高 | 否 |
| 69 | Dish 模型 | Legacy Dish 主要嵌在 Visit | 当前独立 Dish + VisitDish，支持复用与同步 | C:`Dish.swift`,`VisitDish.swift` | KEEP CURRENT | 高 | 否 |
| 70 | Photo 模型/传输 | Legacy data URL/Google Drive/older provider path | 当前 PhotoAsset metadata、local original、upload retry、provider abstraction | C:`PhotoAsset.swift`,`PhotoTransferCoordinator.swift` | KEEP CURRENT | 高 | 否 |
| 71 | 六个废弃 Visit 字段 | Legacy 仍有愿意再来/推荐菜/避雷菜/座位/订位/最佳到访时间 | 当前 decoder 只为兼容读取并丢弃，不进入正式模型/UI | L:`domain.ts`; C:`LegacyWebBackupV4Normalizer.swift` | RETIRE | 高：不得恢复 | 否 |
| 72 | `preferenceLevel` 数据合同 | Legacy favorite/like/normal/avoid，多数由平均 rating 推导 | 当前 Restaurant JSON、Backup、Import 和部分分析仍保留该字段 | L:`src/db/restaurants.ts`,`domain.ts`; C:`RestaurantJSONContract.swift`,`BackupV1Contracts.swift` | KEEP CURRENT | 中：字段没有丢失 | 否 |
| 73 | Follow/friend/public profile | Legacy 有 follow、friendship、public user | 当前正式 Worker API + cache + owner isolation | L:`PublicProfilePage.tsx`; C:`SocialViews.swift`,`ProfileAPIClient.swift` | FUSE | 高 | 否 |
| 74 | Community activity | Legacy 有 Visit/Restaurant activity、图片、评分与动作 | 当前保留语义并支持真实分页/缓存/offline | L:`CommunityPage.tsx`; C:`CommunityFeedView.swift` | FUSE | 高 | 否 |
| 75 | Like/comment authoritative state | Legacy 部分是客户端状态 | 当前 Worker-backed、幂等、delete-own、user isolation | C:`CommunityAPIClient.swift`,`CommunityInteractionViews.swift` | KEEP CURRENT | 高 | 否 |
| 76 | Report/block/moderation hooks | Legacy 不完整 | 当前已有 report、block、delete own content/comment 和可配置 moderation | C:`CommunitySafetyViews.swift` | KEEP CURRENT | 高 | 否 |
| 77 | Legacy local fake engagement | Legacy 可在 local UI 形成赞/评论感知 | 当前不能回退为本地假数据 | L:`CommunityPage.tsx` | RETIRE | 高 | 否 |
| 78 | Google Drive photo sync | Legacy commit `7380d53` 曾增加 | Lafayette 已明确取消；当前 provider abstraction 不恢复 Drive | Git:`7380d53`; R:当前禁止规则 | RETIRE | 高 | 否 |
| 79 | Apple/Taste Map auth | Legacy Web auth/Cloudflare Access/local account 语义 | 当前 Apple identity→Taste Map User→session→Keychain | C:`AuthSessionManager.swift`, Worker auth migrations | KEEP CURRENT | 高 | 否 |
| 80 | Premium presentation/paywall | Legacy 有 badge、paywall、tier 说明 | 当前恢复已认可 hamburger，并使用当前 feature registry | L:`ProfilePage.tsx`; C:`PremiumViews.swift`,`PremiumFeatureRegistry.swift` | FUSE | 中 | 否 |
| 81 | StoreKit/entitlement | Legacy local/admin membership 能力有限 | 当前 StoreKit 2、server reconciliation、restore、transaction updates、expiry/refund/revoke | C:`PremiumEntitlementService.swift`,`PremiumCommerceAPIClient.swift` | KEEP CURRENT | 高 | 否 |
| 82 | Legacy fake/admin membership | Legacy admin/dev 可改会员状态 | Release 不允许 fake entitlement 或 admin bypass | L:Legacy membership/admin components; C:Release purity rules | RETIRE | 高 | 否 |
| 83 | Approved Premium hamburger | Legacy SVG 是已认可视觉来源 | 当前 Canvas 为精确 code-native port，semantic version `web-approved-hamburger-v1` | L:Premium SVG; C:`PremiumViews.swift` | KEEP CURRENT | 低 | 否 |
| 84 | Avatar preset sprite | Legacy 有 `public/taste-map-avatar-presets.png` | 当前 iOS sprite SHA-256 与 Legacy 完全相同 | L:asset; C:`Assets.xcassets/AvatarPresets.imageset` | KEEP CURRENT | 低 | 否 |
| 85 | Legacy Web App icon → iOS AppIcon | Legacy 最大 512px Web icon；当前 AppIcon 未含可确认的正式 1024px 原图 | 不能自动复制或放大；用户本轮明确禁止改 App Icon | L:`public/icons`; C:`Assets.xcassets/AppIcon.appiconset` | NEEDS LAFAYETTE APPROVAL | 高：发布资产质量与品牌确认 | 是 |
| 86 | Legacy Restaurant photo assets | Legacy repo 没有历史商户照片图库；图片来自数据/URL | 当前不能伪称可从 ZIP 恢复真实商户图 | L:`public/` asset inventory; C:Photo pipeline | KEEP CURRENT | 中 | 否 |
| 87 | Current Food Hero assets | Legacy 没有 current native Food Hero bitmap 组 | 当前 Japanese/Chinese/HotpotGrill/Western/Cafe/Mixed 是已确认 Analysis 资产 | C:`Assets.xcassets/FoodHero*` | KEEP CURRENT | 低 | 否 |
| 88 | Raw marker emoji selector | Legacy raw emoji 是 marker fallback/customization | 当前正式视觉要求统一 FoodDiningVisualLibrary；只为兼容解码旧值 | L:`RestaurantAvatar.tsx`; C:`FoodDiningVisualLibrary.swift`,`LegacyWebBackupV4Normalizer.swift` | RETIRE | 中 | 否 |
| 89 | Food/Dining map visual | Legacy emoji/图像证明地图需要餐饮识别度 | 当前必须通过统一 library、真实图片优先、无假数据语义 | L:`RestaurantAvatar.tsx`; C:`FoodDiningVisualLibrary.swift` | FUSE | 中 | 否 |
| 90 | Legacy placeholders/empty state | Legacy 有餐饮图形与占位语气 | 当前可吸收故事/语气，但必须用 shared canonical empty state | L:Legacy components/styles; C:`FoodDiningVisualLibrary.swift` | FUSE | 低 | 否 |
| 91 | Restaurant preference summary UI | Legacy Profile 有 favorite/like/normal/avoid 汇总，但字段本质多由 rating 推导 | 当前保留数据合同，却没有把四级偏好作为正式核心统计；最新规则也未锁定该入口 | L:`global.css .preference-summary`,`db/restaurants.ts`; C:Profile/Restaurant contract | NEEDS LAFAYETTE APPROVAL | 中：可能重复评分语义 | 是 |
| 92 | Global Restaurant Identity | Legacy 以 `amapPoiId` 为强身份 | 当前 Taste Map UUID + `placeIdentities[]`，Apple-only 可完整同步 | L:`appDb.ts`; C:`RestaurantJSONContract.swift`,`PlaceIdentity.swift` | KEEP CURRENT | 高 | 否 |
| 93 | Taste Map User identity | Legacy `owner/userId` 与 Web identity 紧耦合 | 当前 `tm_...` 用户与 Apple sub 分离，可扩展多 identity | C:auth migrations/contracts | KEEP CURRENT | 高 | 否 |
| 94 | Sync architecture | Legacy older whole-data/owner sync | 当前 versioned delta cursor、idempotent mutation、tombstone、per-user checkpoint、offline queue | C:`SyncEngine.swift`,`SyncV1Contracts.swift`,`SwiftDataSyncQueue.swift` | KEEP CURRENT | 高 | 否 |
| 95 | Backup/Import | Legacy 本地 export 和 Web v4 数据 | 当前 locked Backup v1、strict legacy decoder、preflight/plan/transaction UI | C:`Services/Backup/` | KEEP CURRENT | 高 | 否 |
| 96 | F1-C4 exact duplicate Import | Legacy 不包含最终回归 | 当前 `d9f5acd` 已覆盖第二次相同来源+manual merge+Visit exactDuplicate+no extra mutation | Git:`d9f5acd`; C:Import regression tests | KEEP CURRENT | 高：已关闭，不再做真实破坏性复测 | 否 |
| 97 | IndexedDB 作为主数据源 | Legacy Web 以 IndexedDB 为本地真相 | 当前 iOS SwiftData local-first + Worker/D1 共享后端；IndexedDB 仅 Web cache/legacy input | L:`src/db/appDb.ts`; C:Persistence/Sync | RETIRE | 高 | 否 |
| 98 | 当前 Design System Architecture | Legacy CSS/React 局部样式，没有三层正式架构 | 当前 Canonical Templates → Core Components/Tokens + Food & Dining → SwiftUI | C:`AGENTS.md`,`docs/TASTEMAP_PRODUCT_DESIGN_RULES.md` | KEEP CURRENT | 高：禁止 CSS→magic numbers 直译 | 否 |

## 6. 最重要的融合结论

### 6.1 应先恢复：Map Marker 层级，而不是重做整个 Map

Legacy 的 `markerLayerPriority` 是明确、可复现的正确行为：

```text
ratingPriority = round(scoreOutOfTen * 10)
zIndex = ratingPriority * 10 + min(visitCount, 99)
selected marker = setTop(true)
```

当前 iOS 已经拥有 `averageRating` 和 `visitCount`，但所有 annotation 都设置为同一个 `.required` display priority，没有把历史规则映射到 MapKit 层级。这不是“视觉感觉不同”，而是产品排序语义在渲染层丢失。

未来修复应在现有 `RestaurantMapMarkerPresentation` / `RestaurantMarkerAnnotationView` 共享层一次完成：

- 评分高者在重叠时优先显示在上层；
- 到访次数只作为次级 tie-break；
- selected Restaurant 永远在最上层；
- stable Restaurant ID 是最终 deterministic tie-break；
- 每家 Restaurant 仍是独立 Marker；
- 不恢复数字 cluster；
- 允许 Marker 自然重叠，不要求全部露出；
- 普通状态不默认强制 offset、spiderfy、collision dispersion 或 zoom-driven separation；
- expand/spiderfy 只可作为用户主动检查高度重叠区域的辅助交互；
- 保留用户头像、最新 scope/filter 与真实图片优先级。

### 6.2 应统一：Restaurant image renderer，而不是复制 Legacy 图片组件

当前 `RestaurantImagePriorityPolicy` 的顺序比 Legacy 正确：

1. 用户本地真实照片
2. 合法 public/cache photo
3. 合法 provider HTTPS merchant image
4. Food & Dining honest fallback

问题在于部分页面仍各自解析 URL/PhotoAsset/fallback。未来应建立一个 canonical Restaurant image renderer/source resolver，让 Nearby/Search/Map/List/Discovery/Restaurant Detail/Lists/Roulette/Analytics 都消费同一决策结果；Legacy `RestaurantAvatar` 只能提供“曾有真实图和 fallback”这一历史证据，不能被原样移植。

### 6.3 不应恢复的 Legacy 主线

- 远距离数字 cluster；
- `amapPoiId` 作为系统唯一主键；
- 手动餐厅伪造 provider ID；
- 原始 emoji 作为正式品牌资产；
- Google Drive 照片同步；
- IndexedDB 作为跨端唯一真相；
- 本地假 Like/Comment；
- local/admin Premium bypass；
- 六个已废弃 Visit 字段；
- 旧认证替代 Taste Map User/session；
- DOM/CSS 页面或 Web screenshot 直接当原生分享海报。

### 6.4 必须保护的 Current-only 能力

- Apple identity 与 Taste Map User ID 分离；
- global Restaurant UUID + provider identities；
- SwiftData local-first、mutation queue、cursor、idempotency、tombstone；
- current-user isolation 与 multi-account safety；
- Backup v1、Legacy v4 strict decoder、preflight/merge/transaction import；
- F1-C4 exact duplicate regression；
- canonical global Restaurant Detail；
- real backend Like/Comment/Report/Block/Delete-own；
- StoreKit 2 + server entitlement；
- native 9:16 Analytics posters；
- Settings、Account Delete boundary、Release Binary Purity；
- 当前三层 Design System 和 Food/Dining visual semantics。

## 7. 建议实施顺序（本轮未执行）

1. **Map Marker natural-overlap/z-order fusion**：移除普通状态默认强制散开，补齐 `selected → rating → visit count → stable ID` 层级，并用密集 Marker regression + 真机/Simulator 视觉验证。
2. **Canonical Restaurant image renderer**：把真实照片优先级在所有 Restaurant-facing surfaces 一次收口。
3. **Lafayette 决定 `preferenceLevel` 是否需要正式 UI**：保留合同已无风险，是否展示四级偏好必须先决定，不能自动恢复。
4. **App Icon 资产决策**：仅在 Lafayette 提供/确认正式 1024px source 后处理，不能从 512px Web icon 自动放大。
5. 再做一次只针对上述两项开放回归的 cross-surface acceptance；不要重新搭建 Map、Detail、Analytics 或 Social。

## 8. 审计可复现命令

```bash
git merge-base fb127e9 648be22
git log --oneline fb127e9..648be22
git show fb127e9:src/components/MapView.tsx
git show fb127e9:src/components/CommunityPage.tsx
git show fb127e9:src/components/AddRestaurantModal.tsx
git show fb127e9:src/components/ProfilePage.tsx
git grep -n "preferenceLevel" fb127e9 -- src
rg -n "RestaurantDetailStandardBody|RestaurantImagePriorityPolicy|clusteringIdentifier" ios/TasteMap/TasteMap
```

## 9. 本轮变更声明

本轮只新增审计 Markdown。未执行任何 RESTORE/FUSE/RETIRE 决策，未修改正式业务代码、测试期待值、数据库、配置、资产或签名。
