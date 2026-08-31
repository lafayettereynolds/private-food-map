# Taste Map｜Full Product Parity Module 5

## Global Restaurant Detail Single Source 验收报告

验收日期：2026-08-31

执行分支：`fix/full-product-parity-restoration`

模块结论：**PASS**

Production：**未访问、未修改**

## 1. Step A｜原功能与数据语义确认

Web Source of Truth 中，Restaurant Detail 是同一个餐厅主体：入口只影响返回路径，不应该因为餐厅来自地图、发现、社区、公开主页或食单而切换成另一种详情结构。

修复前 iOS 存在两条主体实现：

- 已经保存到本地的 Restaurant 使用 `RestaurantDetailView`；
- Discovery / Community / Public Profile / Public List 中尚未保存的 Restaurant 使用 `DiscoveryRestaurantDestination` 内手写的另一套详情。

这导致同一家餐厅因入口和本地保存状态不同而出现不同的 Hero、基础信息、评分、用户实拍、我的记录与到访历史结构。它是功能迁移和组件复用错误，不只是视觉差异。

本轮锁定以下数据边界：

- 本地 Restaurant 继续读取 SwiftData 中属于当前用户的 Restaurant / Visit / Dish / Photo 数据；
- 远程 Restaurant 只读取 Worker 返回的公开 `DiscoveryRestaurantProjectionV1`；
- 打开远程详情不会静默创建本地 Restaurant；
- 只有用户显式点击“想吃”“记录到访”“加入食单”或“加入抽签”时，才进入既有 acquisition / action 流程；
- 远程 projection 没有电话、营业时间、公开照片或评分样本时，隐藏对应可选信息或显示诚实空态，不生成假数据。

## 2. Step B｜唯一详情架构

本轮建立并复用同一个有序详情主体：

- `RestaurantDetailStandardBody`
- `RestaurantDetailIdentityPresentation`
- `RestaurantDetailEntrySource`
- `RestaurantDetailSectionOrderContract`

`RestaurantDetailEntrySource` 已覆盖：

- Map
- List
- Search / Nearby 预留
- Discovery
- Community
- Public Profile
- Restaurant List
- Analytics
- Roulette
- On This Day
- Share 预留

它只表达入口来源，供 navigation / analytics / back behavior 使用；不决定 Hero、标题、Section 顺序、评分或用户实拍布局。

本地与远程 wrapper 只负责提供真实数据和允许的 actions，不再分别维护相似详情页面。`DiscoveryRestaurantDestination` 现在是数据与导航适配器，不再拥有第二套 Restaurant Detail 主体。

## 3. 固定 Layout Contract

标准主体保持以下相对顺序；可选字段缺失不会改变其他 Section 的相对顺序：

1. Restaurant Cover / Hero
2. 城市 / 去过或想吃状态
3. Restaurant Name
4. 地址
5. Restaurant Actions
6. 参考人均
7. 电话
8. 营业时间
9. 到这里去
10. 评分参考
11. 我的评分
12. 全部用户评分
13. 好友评分
14. 同味评分
15. 用户实拍
16. 我的到访概览
17. 到访历史

对应的可测试 accessibility identifiers 为：

- `restaurant-photo-gallery`
- `restaurant-detail-header`
- `restaurant-detail-quick-actions`
- `restaurant-business-information`
- `restaurant-detail-location`
- `restaurant-rating-references`
- `restaurant-user-photos`
- `restaurant-detail-statistics`
- `restaurant-visit-history`

Restaurant 的扩展记录（菜品、用餐体验、多维评分等）继续保留在上述标准主体之后，没有删除既有能力。

## 4. 评分和用户实拍语义

- 大圆继续表示评分值；小圆继续表示样本数。
- 正式 aggregate 文案统一为“全部用户评分”。
- `nil`、无有效评分或样本数为 0 时不显示假 0 分。
- 本地详情使用当前用户私有数据和已有公开汇总。
- 远程详情只展示公开 projection 中真实存在的“我的 / 全部用户 / 好友 / 同味”评分及正样本数。
- 本地照片与远程公开照片共用 `RestaurantUserPhotosSection` 容器；无图片时显示诚实空态。

## 5. 显式操作安全

- 仅打开远程详情不会写入 SwiftData。
- 已经是“去过”的 Restaurant 不会被“想吃”动作降级。
- 远程“想吃 / 记录到访 / 食单 / 抽签”继续复用原有 service 和 action 语义。
- 为避免 UI 路径回归，保留了跨页面既有稳定 accessibility identifiers，而不是复制业务流程。

## 6. 跨入口验证矩阵

| 入口 | 主体 | 入口来源 | 结果 |
| --- | --- | --- | --- |
| Map | `RestaurantDetailStandardBody` | `.map` | PASS |
| List | `RestaurantDetailStandardBody` | `.list` | PASS |
| Discovery | `RestaurantDetailStandardBody` | `.discovery` | PASS |
| Community | `RestaurantDetailStandardBody` | `.community` | PASS |
| Public Profile | `RestaurantDetailStandardBody` | `.publicProfile` | PASS |
| Restaurant List | `RestaurantDetailStandardBody` | `.restaurantList` | PASS |
| Analytics / Footprints / Recaps | `RestaurantDetailStandardBody` | `.analysis` | PASS |
| Roulette | `RestaurantDetailStandardBody` | `.roulette` | PASS |
| On This Day | `RestaurantDetailStandardBody` | `.onThisDay` | PASS |

## 7. 截图证据

### Web reference

![Web Restaurant Detail reference](full-product-parity-assets/web-restaurant-detail-before.jpg)

### iOS before

![iOS Restaurant Detail before](full-product-parity-assets/ios-restaurant-detail-before.png)

### iOS local after｜首屏

![iOS local Restaurant Detail top after](full-product-parity-assets/ios-restaurant-detail-local-top-after-module-5.png)

### iOS local after｜用户实拍、我的概览、到访历史

![iOS local Restaurant Detail after](full-product-parity-assets/ios-restaurant-detail-local-after-module-5.png)

### iOS remote after｜同一主体与诚实私有空态

![iOS remote Restaurant Detail after](full-product-parity-assets/ios-restaurant-detail-remote-after-module-5.png)

## 8. 自动化测试

最终通过：

- `RestaurantDetailCompletionTests`
- `RestaurantDetailTests`
- `P3DCommunityTests`
- `P4FRestaurantListTests`
- `CoreProductLayoutParityTests`
- `testTask04CoreLayoutParityEvidence`
- `testF3ARestaurantDetailMetadataEditAndVisitRefresh`
- `testP3DCommunityFeedOpensPublicProfileRestaurantAndSupportsExplicitWantToGo`
- `testP4FPublicProfileListRestaurantWantToGoAndVisibilityRevocation`
- `testP4GRouletteFilterSpinResultDetailRerollAndOfflineRestart`
- `testF7AProfileOnThisDayHistoricalRestaurantAndBack`

回归中修复了两项测试可观测性问题：

1. 只读结构 Section 不再错误使用 `isHittable` 判断可见性，改为可滚动读取；
2. 公共食单详情恢复已有稳定 action identifier，保持跨入口 UI contract。

没有通过修改业务期待值掩盖布局或功能错误。

## 9. Build

- iOS Debug generic Simulator build：PASS
- iOS Release generic Simulator build：PASS
- Release log：`/tmp/tastemap-module5-release.log`
- 仅保留既有非阻塞 AppIntents metadata extraction warning；本轮没有新增明显 warning。

## 10. 修改文件

核心详情：

- `ios/TasteMap/TasteMap/Features/Restaurant/RestaurantDetailComponents.swift`
- `ios/TasteMap/TasteMap/Features/Restaurant/RestaurantDetailPresentation.swift`
- `ios/TasteMap/TasteMap/Features/Restaurant/RestaurantDetailView.swift`
- `ios/TasteMap/TasteMap/Features/Restaurant/RestaurantQuickActionsSection.swift`
- `ios/TasteMap/TasteMap/Features/Discovery/DiscoveryView.swift`

入口来源接线：

- `ios/TasteMap/TasteMap/Features/Map/MapHomeView.swift`
- `ios/TasteMap/TasteMap/Features/Map/RestaurantBrowseViews.swift`
- `ios/TasteMap/TasteMap/Features/Community/CommunityFeedView.swift`
- `ios/TasteMap/TasteMap/Features/Profile/SocialViews.swift`
- `ios/TasteMap/TasteMap/Features/Lists/RestaurantListsView.swift`
- `ios/TasteMap/TasteMap/Features/Roulette/RestaurantRouletteView.swift`
- `ios/TasteMap/TasteMap/Features/Visit/TasteFootprintsView.swift`
- `ios/TasteMap/TasteMap/Features/Analysis/DiningCompanionAnalysisView.swift`
- `ios/TasteMap/TasteMap/Features/Analysis/RecommendationSourceAnalysisView.swift`
- `ios/TasteMap/TasteMap/Features/Analysis/MonthlyRecapAnalysisView.swift`
- `ios/TasteMap/TasteMap/Features/Analysis/AnnualRecapAnalysisView.swift`
- `ios/TasteMap/TasteMap/Features/Analysis/OnThisDayView.swift`

测试：

- `ios/TasteMap/TasteMapTests/RestaurantDetailCompletionTests.swift`
- `ios/TasteMap/TasteMapUITests/TasteMapUITests.swift`

## 11. 安全边界

- SwiftData schema：未修改
- Worker：未修改
- D1 / migration：未修改
- Auth / Keychain：未修改
- Sync：未修改
- Production：未访问、未修改
- `pnpm-workspace.yaml`：未纳入修改或提交

## 12. Remaining gaps

1. 当前公开 projection 不保证包含电话、营业时间和完整公开照片；缺少时按 optional contract 隐藏，不生成假字段。后续如产品需要，应扩展公开 API contract，而不是在客户端猜测。
2. 远程 Restaurant 没有可验证 public share entity 时不伪造分享链接。
3. 当前 Hero fallback 仍属于历史 Core App 表达；统一 `FoodDiningVisualLibrary` 将在后续独立模块中替换合适的 fallback，本模块不提前创建另一套视觉系统。
4. 真正线上公开 projection 的完整度取决于现有 Development API 数据；本轮已覆盖本地 fixture、公共列表、公共主页与社区路径。

## 13. 结论

Module 5 的 S0 问题已经关闭：Restaurant Detail 不再因入口或本地/远程状态维护两套主体。统一 section contract、诚实数据边界、显式保存和跨入口路由均有测试与截图证据。可以继续 Module 6 Roulette 历史体验恢复。
