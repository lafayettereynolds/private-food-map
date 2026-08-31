# Taste Map Product / UX Correction — Task 02 验收报告

## 范围

本任务只处理 `My Map + Discovery + Activity + Same Taste + User Location`。未修改 Add Restaurant、Restaurant Detail、SyncEngine、数据模型、Worker、D1、Production 或 App Icon。

## Source of Truth 与功能语义

- My Map 一级范围固定为 `去过 / 想吃 / 推荐`；已移除该范围中的“适合你”用户可见文案。
- `去过`、`想吃`继续读取当前账户隔离后的本地 Restaurant / Visit；`推荐`不生成假餐厅，真实推荐内容继续由 Discovery API 提供。
- Discovery 五个一级入口仍分别路由到正式数据源：`关注`、`最新`读取 Community feed；`为你推荐`、`同味之选`、`趋势`读取版本化 Discovery API。
- Activity 卡片评分只使用该条 Activity / Visit 的 `rating`。`nil` 明确显示“未评分”，不回退到 Restaurant aggregate rating。
- Same Taste 保留并验证正式的登录、Premium access、loading、insufficient / empty、error、内容、分页和 Restaurant Detail 路径。

## 产品与布局修复

### My Map / My List

- 标题组居中，地图态显示“我的地图”，列表态显示“我的列表”。
- 视图切换 icon 紧邻标题，单一 44pt 命中区域；VoiceOver 分别为“切换到列表 / 切换到地图”。
- 删除独立的 Map / List segmented control；切换不会重置 scope、filter、sort、city 或 search。
- `去过 / 想吃 / 推荐`改用与 Discovery 相同的 `TasteMapPrimaryTabBar`。
- FilterBar 改用 Task 01 的共享组件，并统一 `icon + 短文字 / 当前值`：筛选、城市、评分、消费、到访次数、饭搭子、菜系、推荐来源、排序、清除。
- City 使用 building 语义，不使用 GPS / location 图标。
- 每个 chip 只进入自己的筛选维度；“筛选”才进入完整筛选面板。
- Map 与 List 继续共享同一份 `PersonalRestaurantFilterState` 与排序结果。

### Restaurant Marker / User Location

- 移除所有 zoom level 的 `MKClusterAnnotation` 与 clustering identifier。
- 同坐标 Restaurant 通过基于 UUID 的稳定轻量位移分散；数量与 Restaurant ID 均不丢失，每家仍可独立选择。
- Marker 继续按正式顺序选择视觉：Restaurant marker photo → HTTPS merchant image → 本地照片 → legacy food semantic → natural-color Food/Dining fallback。
- 当前用户位置改为圆形用户头像；有自定义头像时读取缩略图，无头像时使用正式 preset avatar，并带轻量 location halo。
- Restaurant Marker 和 User Location Marker 的形状、badge 与可访问名称保持明确区分。

### Discovery / Activity

- “发现”继续居中；五个一级入口等宽平均分布，并复用 My Map 的一级 Tab 视觉。
- 城市、筛选、排序、距离、评分、趋势时间窗口统一使用共享 FilterBar / FilterChip。
- Discovery 与 Community Activity 卡片共享 `TasteMapActivityCard` surface、`TasteMapActivityRatingBadge` 与同一组 Restaurant quick actions。
- Community 仍保留授权后的 like / comment / more、安全操作和独立“分享动态”；Discovery 不伪造其 API 尚未提供的 engagement 数据。

## 截图证据

- My Map after：`reports/product-ux-correction-assets/task-02-map-discovery/B82F2F2B-7D28-4292-B08A-C2C803D401CC.png`
- My List after：`reports/product-ux-correction-assets/task-02-map-discovery/541A4341-3540-4FFE-9C9B-E9E2793D6F98.png`
- Discovery / Activity after：`reports/product-ux-correction-assets/task-02-map-discovery/C583CC15-225B-4BCE-A13A-994A898A500E.png`
- Same Taste content after：`reports/product-ux-correction-assets/task-02-same-taste/942705CE-E6F7-410F-BD97-717F0BDCC290.png`
- User Location avatar after：`reports/product-ux-correction-assets/task-02-map-discovery/map-user-avatar-after.png`
- Far map independent markers after：`reports/product-ux-correction-assets/task-02-map-discovery/087EB42B-9476-4D3D-8855-EB3F0A212F9B.png`
- Specific city filter after：`reports/product-ux-correction-assets/task-02-map-discovery-extra/E9311C74-E62D-4DDA-80EF-F56F6A3A6A37.png`
- Task 01 before reference：`reports/product-ux-correction-assets/task-01-canonical-baseline-before.png`

## 自动化验收

通过：

- `CoreProductLayoutParityTests`
- `MapBrowsingParityTests`
- `F2BPersonalRestaurantFilterTests`
- `P3CDiscoveryTests`
- `P3DCommunityTests`
- `testTask04CoreLayoutParityEvidence`
- `testFarMapKeepsIndependentRestaurantMarkers`
- `testCoreProductLayoutParityMapDiscoveryProfileEvidence`
- `testProductUXMapFilterChipsOpenTheirOwnDimension`
- `testDiscoveryAndCommunityCardsUseConcreteVisitRating`
- `testP3CDiscoveryNativeFlowRestaurantWantSimilarProfileTrendingAndRefresh`

覆盖：Map/List 状态保持、specific filter sheet、横向 FilterBar、无 cluster、Marker 碰撞分散、Activity nil / non-nil rating、Discovery 五入口、Same Taste 内容与理由、趋势窗口和统一 Restaurant Detail 路径。

## Build

- Debug iPhone Simulator：PASS
- Release iPhone Simulator：PASS
- 本次只出现项目原有的 AppIntents metadata extraction warning；没有新增编译错误。

## 人工真机项

- 真实 GPS 更新时的头像 marker 移动流畅度与 Reduced Accuracy 系统状态仍应在最终 Task 08 真机验收。
- Same Taste 的 Development fixture 已通过；真实账户的内容量、分页和网络错误恢复留到最终真机验收，不将 fixture 结果冒充真实 Production 数据。

## 结论

Task 02 自动化与模拟器验收通过，可以进入 Task 03。Production 未访问。
