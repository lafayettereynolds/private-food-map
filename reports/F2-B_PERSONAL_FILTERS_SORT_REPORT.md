# Taste Map｜F2-B 个人地图 / 列表核心筛选与排序验收报告

日期：2026-08-29

分支：`main`

基线：`9107a3dc88d520092ae13a4505ef0634cd1b392d`

提交信息：`Restore personal restaurant filters and sorting`

## 1. Filter architecture

- 新增 `PersonalRestaurantFilterState`，集中保存个人 Restaurant 的状态、筛选组和排序方式。
- 新增 `PersonalRestaurantFilterEngine`，Map 与 List 都消费同一个解析结果，不存在两套筛选实现。
- `RestaurantBrowseBuilder` 在读取有效 Restaurant / Visit 后一次性建立 per-Restaurant aggregate 和轻量 `PersonalVisitFilterFacet`。
- Visit 级条件在聚合后的该餐厅 Visit facets 内匹配，避免每个筛选组再次全库扫描 Visit。
- 搜索文本也提升到 `MapHomeView` 共享状态，因此从 List 切回 Map 时仍使用同一个最终 Restaurant 集合。
- Discovery 的 For You / Similar Taste / Trending 与服务端排名均未接入或修改。

## 2. 实现的 filter groups

- 状态：去过、想吃，并在解析器层支持全部；当前产品顶部入口继续使用去过 / 想吃 / 适合你。
- 用餐方式：到店、外卖。
- 到访次数：沿用 Web 的阈值语义 `1+ / 2+ / 3+ / 5+ / 10+`。
- 评分区间：`9.0–10.0 / 7.0–8.9 / 5.0–6.9 / 3.0–4.9 / 1.0–2.9`，支持多选。
- 人均价格：`< 100 / 100–200 / > 200`。
- 排队：未记录、无需排队、15/30/60/90/120 分钟档和超过 120 分钟。
- 用餐场景：正式 `VisitDiningOccasion` 全部值，支持多选。
- 推荐来源：来自有效 Visit 的正式类型、自定义文字或当前用户 RecommendationSource 目录名。
- 到访时间：最近半年、最近一年。
- 饭搭子：来自当前用户私人的 Companion association / Visit companion name，不把姓名当社交用户 ID。
- 城市：仅列出当前有效个人 Restaurant 数据中实际存在的城市。
- 激活数量按 Web 的 filter group 计数：评分或场景选择多个值仍各算 1 组；排序不算筛选。

## 3. Distance

- 已实现 `1 / 3 / 5 / 10 km`。
- 复用现有 `LocationPermissionManager` 和 `currentLocation`，没有修改底层权限架构。
- 只有有限数值、合法经纬度且不是缺省 `(0, 0)` 的 Restaurant 才参与距离计算。
- 用户选择距离但尚无当前位置时，应用动作会请求一次当前位置；成功后才提交该筛选状态。
- 定位被拒绝时距离选项禁用并明确说明；如果请求失败，只移除距离条件，其他条件照常应用。
- 定位失败不会阻塞 App 启动或其他个人筛选。

## 4. Sorting

- 综合：精确移植 Web 个人列表顺序——实际 Visit 平均评分换算为 10 分制、到访次数、最近有效 Visit、Restaurant 创建时间，最后用名称和 UUID 稳定排序；没有发明推荐算法。
- 最近：按最近有效 Visit；没有 Visit 的想吃 Restaurant 使用既有 `createdAt`，不会制造 Visit。
- 评分：只使用非 nil Visit 评分的平均值；有评分排在无评分前，平分时回退到综合稳定顺序。

## 5. Map/List parity

- `MapHomeView` 只计算一次 `PersonalRestaurantFilterResult`。
- Map Marker 和 `RestaurantBrowseList` 接收相同的 `displayedItems`。
- 筛选 Sheet、激活数量、排序和查询在 Map/List 切换时保持。
- 单元测试断言两种展示消费相同 ID 序列；Simulator UI 测试验证 Map 筛选后显示 1 家，切到 List 仍只显示同一家。

## 6. Nil semantics

- `rating == nil` 不进入平均评分，也不属于最低评分区间。
- `pricePerPerson == nil` 不属于任何价格区间；不会借用 `myActualSpend`。
- `queueDuration == nil` 只匹配“未记录”；`.noWait` 只匹配“无需排队”。
- 缺失 Companion / Source / Scene 不会被伪造成任何筛选值。
- 价格严格沿用 Web 当前 Visit `pricePerPerson` 筛选语义，没有混合商家参考价和我的实际消费。

## 7. Tombstones

- `RestaurantBrowseBuilder` 继续统一排除 `Restaurant.deletedAt != nil`。
- 只聚合 `Visit.deletedAt == nil` 且仍关联有效 Restaurant 的 Visit。
- 被删除 Visit 不影响次数、平均评分、最近时间、筛选 facets 或选项列表。
- 被删除 Restaurant 及其 Visit 不会进入 Map、List 或筛选选项。

## 8. Zero-result state

- Map 和 List 都提供“当前无符合条件的餐厅”状态。
- 两处都有“一键清除全部筛选”。
- 如果基础集合本身为空，仍保留原有去过 / 想吃空状态，不把它误报为筛选归零。
- 本轮未实现非必要的自动放宽建议，避免引入推荐逻辑。

## 9. Performance

- 测试规模：1,000 Restaurant + 10,000 Visit。
- 覆盖聚合后同时启用城市、用餐方式、评分、价格、近一年和评分排序。
- 串行 Simulator 测试中的“聚合 + 多条件筛选”约 `0.393s`，低于测试上限 `5s`。
- 聚合阶段按 Restaurant ID 分组 Visit，筛选阶段只遍历每家已投影 facets；没有为每一筛选组重新扫描全库 Visit。

## 10. Unit tests

- 新增 25 项 F2-B 测试，逐项覆盖：status、dine-in、takeout、visit count、rating range、nil rating、price、nil price/spend、queue、nil queue、scene、source、companion、date、city、distance、combined filters、reset、active count、Map/List parity、recent/rating/comprehensive sort、tombstone、large dataset。
- 特别测试了多个 Visit 级筛选必须由同一条 Visit 同时满足，避免条件分别落在不同 Visit 时误命中 Restaurant。
- 同时回归 F2-A 5 项。
- 串行结果：`30 tests in 2 suites passed`，0 failure。

## 11. UI tests

- 新增最小完整路径：Map → Filter → 跨组多选评分和外卖 → Apply → Map 显示筛选后 1 家 → List 显示相同结果 → Reset → 恢复全部结果。
- 使用隔离的 in-memory F2-B fixture，不写正式数据库。
- 串行 Simulator 结果：1 test passed，0 failure，约 `20.8s`。

## 12. Build

- Debug iPhone Simulator build：成功。
- 命令目标：`TasteMap` scheme，`iPhone 17 Pro` Simulator，关闭 code signing。
- 最终结果：`BUILD SUCCEEDED`。
- 构建日志中的 AppIntents metadata skipped 属于既有无 AppIntents 依赖提示，不是本轮新增编译错误。

## 13. 修改文件

- `ios/TasteMap/TasteMap/Features/Map/PersonalRestaurantFilters.swift`（新增）
- `ios/TasteMap/TasteMap/Features/Map/PersonalRestaurantFilterView.swift`（新增）
- `ios/TasteMap/TasteMap/Features/Map/RestaurantBrowsePresentation.swift`
- `ios/TasteMap/TasteMap/Features/Map/RestaurantBrowseViews.swift`
- `ios/TasteMap/TasteMap/Features/Map/MapHomeView.swift`
- `ios/TasteMap/TasteMap/App/TasteMapUITestFixtures.swift`
- `ios/TasteMap/TasteMap/TasteMapApp.swift`
- `ios/TasteMap/TasteMapTests/F2BPersonalRestaurantFilterTests.swift`（新增）
- `ios/TasteMap/TasteMapUITests/TasteMapUITests.swift`
- `reports/F2-B_PERSONAL_FILTERS_SORT_REPORT.md`（本报告，新增）

## 14. 是否修改 schema

否。没有新增或修改 `@Model`、SwiftData Schema、MigrationPlan、字段或存储格式。

## 15. 是否修改 Worker/D1

否。Worker diff = 0，D1 diff = 0，migration diff = 0；没有部署 Development Worker，也没有执行数据库命令。

## 16. 是否访问 Production

否。未访问 Production Worker、Production D1、Production Cloudflare 或任何生产数据。

## 17. Git commit/push

- 基线时 `main == origin/main == 9107a3dc88d520092ae13a4505ef0634cd1b392d`。
- 计划提交信息：`Restore personal restaurant filters and sorting`。
- 精确 commit hash 与最终 push 结果见本任务交付消息。
- 既有未跟踪审计文档、历史报告和 `pnpm-workspace.yaml` 均未删除、覆盖或加入本提交。

## 18. 剩余问题

- 本轮只处理个人本地 Restaurant / Visit；Discovery 服务端筛选与排序按要求保持不变，未来应单独设计。
- “全部”状态已在底层解析器支持，但当前产品顶部仍维持“去过 / 想吃 / 适合你”，没有为了本轮增加新的顶栏入口。
- 未实现非必要的智能“放宽建议”；当前零结果已提供可靠的一键清除。
- iOS 本地 Restaurant 没有独立可选坐标字段，因此 `(0, 0)` 按缺省无坐标处理；若未来正式支持“无坐标 Restaurant”，应在单独 schema 任务中建模，不应在本轮更改 SwiftData。
