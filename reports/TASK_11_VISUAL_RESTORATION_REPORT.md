# Taste Map Task 11 验收报告

## 1. 任务

- 任务：Global Visual Restoration
- 基线分支：`main`
- 基线提交：`ce24c389568092d13b23c452e901dc4387cc181f`
- 基线提交说明：`Close final Web iOS feature parity`
- 实施范围：原生 iOS / SwiftUI 视觉恢复，不改变现有业务能力
- 视觉基准：现有 Web 正式产品与用户已经确认的 Taste Map 设计方向

## 2. 结论

Task 11 已完成代码、视觉抽查、相关单元测试、核心 UI 路径测试、Debug 构建和 Release Simulator 构建。

原生 App 的 Core App Theme 已统一为低饱和灰蓝、冷白/极浅冷灰蓝表面、深蓝灰文字、轻边框与克制阴影；不再依赖系统默认亮蓝色作为产品视觉。Analysis / Poster Theme 与 Core App Theme 继续分层，既有分析海报的暖色美食视觉没有被错误套成设置页或地图页风格，已经确认的 Restaurant Roulette 方向也保持不变。

## 3. Design Token

新增 `TasteMapCoreTheme` 作为 Core App 唯一语义视觉入口，包含动态 Light / Dark Mode token：

| 语义 | Web 基准值 | 用途 |
| --- | --- | --- |
| Brand | `#506C8C` | 主按钮、选中态、重点图标、全局 tint |
| Brand Deep | `#344F69` | 深强调、深色层级 |
| Background | `#F7F7F5` | Core App 页面背景 |
| Surface | `#FFFFFF` | 卡片和主表面 |
| Text Primary | `#172A3A` | 标题和主要正文 |
| Divider | `#E3E6E8` | 轻边框和分隔 |

Dark Mode 使用独立语义色值，不以简单反色代替设计；AccentColor asset 同步提供 Light / Dark 变体。

## 4. 可复用 Core App 组件

- `tasteMapCorePage()`：统一页面背景与前景层级。
- `tasteMapCoreCard(...)`：统一表面、圆角、边框和可选轻阴影。
- `TasteMapSectionHeader`：统一模块标题、说明与生活化图标层级。
- `TasteMapSegmentedControl`：恢复品牌化分段控制，保留明确选中态、触控目标、VoiceOver label 与稳定 UI test identifier。
- `TasteMapEmptyState`：统一空状态的品牌图标、说明和可选行动入口。

## 5. 页面覆盖

| 页面/模块 | 本轮处理 |
| --- | --- |
| App Root / 全局 tint | 采用 Taste Map brand token |
| 底部导航 / 添加餐厅主操作 | 恢复灰蓝选中态、冷白表面、轻分隔与主操作按钮 |
| 地图 / 列表 / 去过 / 想吃 / 适合你 | 恢复品牌分段控件、页面背景、筛选层级、空状态和餐厅卡片 |
| 添加餐厅 | 页面、搜索结果与输入表面接入 Core Theme，保留原有 Acquisition 业务能力 |
| Restaurant Detail / Edit | 基础信息、我的记录、评分、菜品、快捷操作和编辑页统一表面语言 |
| Visit / Dish / Footprints | 编辑 Form、菜品管理和足迹页面接入 Core Theme；字段和保存逻辑未改 |
| Profile / Social / Lists | 页面背景、摘要卡片、社交与榜单表面统一 |
| Settings / Import presentation | 统一设置页与导入计划页面表面，不改变 Backup/Import 语义 |
| Discovery / Community | 恢复 Discover Hub 品牌分段控件、Feed 背景和内容卡片 |
| Premium | 保留 StoreKit 行为，统一 Paywall 和权益页面 Core 表面 |
| Public Sharing | 统一原生分享入口与落地页 Core 表面 |
| Analysis / Poster / On This Day | 保留独立 Analysis Theme，不把 Core Theme 强行覆盖到海报视觉 |
| Restaurant Roulette | 保留已经确认的轮盘视觉与交互方向 |

## 6. 可访问性与自动化稳定性

- 所有新增 icon-only 或自定义分段操作保留可读 accessibility label。
- 自定义分段控件使用真实 Button、选中 traits、动态文字布局和不小于 44pt 的交互高度。
- UI 测试增加兼容 helper，同时识别系统 segmented picker 与恢复后的 Taste Map segmented buttons；业务测试不再耦合具体渲染器。
- 主题单测验证基准色值以及关键文字/按钮组合达到 WCAG AA 4.5:1 对比度要求。
- SwiftUI 原生字体样式继续支持 Dynamic Type；未引入固定像素正文。

## 7. 视觉验收

在 iPhone 17 Pro / iOS 26.5 Simulator 上对下列核心页面进行了自动化启动与截图抽查：

- Map Home
- Restaurant Acquisition
- Restaurant Detail / Edit / Visit refresh
- Profile / Lists / Footprints
- Settings / Backup
- Discovery
- Community
- Premium
- Restaurant Roulette
- On This Day / Analysis entry

保留的本地测试截图位于 `/tmp/tastemap-task11-shots.8oAA4f/`，用于本次验收，不提交临时图片到 Git。

## 8. 测试和构建

### Theme unit tests

- Suite：`TasteMapCoreThemeTests`
- Tests：2
- Passed：2
- Failed：0
- Result bundle：`/tmp/TasteMapTask11ThemeTests.xcresult`

覆盖：

1. Web Visual Source of Truth 的六项核心色值合同。
2. Primary text / surface 与 white / brand 的 WCAG contrast。

### Core visual UI suite

- Device：iPhone 17 Pro Simulator
- iOS：26.5
- Tests：10
- Passed：10
- Failed：0
- Skipped：0
- Result bundle：`/tmp/TasteMapTask11VisualTests/Logs/Test/Test-TasteMap-2026.08.30_08-48-59-+0800.xcresult`

### Builds

- Debug Simulator build：通过。
- Release Simulator build：通过。
- Release product：`/tmp/TasteMapTask11Release/Build/Products/Release-iphonesimulator/TasteMap.app`

Release 构建仅报告项目已有的 Swift actor-isolation warnings；本轮没有引入新的编译错误或明显视觉相关 warning。

## 9. 修改文件

### 新增

- `ios/TasteMap/TasteMap/Components/TasteMapCoreTheme.swift`
- `ios/TasteMap/TasteMapTests/TasteMapCoreThemeTests.swift`
- `reports/TASK_11_VISUAL_RESTORATION_REPORT.md`

### 修改

- `ios/TasteMap/TasteMap/App/RootTabView.swift`
- `ios/TasteMap/TasteMap/Assets.xcassets/AccentColor.colorset/Contents.json`
- `ios/TasteMap/TasteMap/Components/PublicSharingViews.swift`
- `ios/TasteMap/TasteMap/Components/TasteMapBottomNavigation.swift`
- `ios/TasteMap/TasteMap/ContentView.swift`
- `ios/TasteMap/TasteMap/Features/Community/CommunityFeedView.swift`
- `ios/TasteMap/TasteMap/Features/Community/CommunityPreviews.swift`
- `ios/TasteMap/TasteMap/Features/Discovery/DiscoveryPreviews.swift`
- `ios/TasteMap/TasteMap/Features/Discovery/DiscoveryView.swift`
- `ios/TasteMap/TasteMap/Features/Lists/RestaurantListsView.swift`
- `ios/TasteMap/TasteMap/Features/Map/MapHomeView.swift`
- `ios/TasteMap/TasteMap/Features/Map/RestaurantBrowseViews.swift`
- `ios/TasteMap/TasteMap/Features/Premium/PremiumViews.swift`
- `ios/TasteMap/TasteMap/Features/Profile/ProfileView.swift`
- `ios/TasteMap/TasteMap/Features/Profile/SocialViews.swift`
- `ios/TasteMap/TasteMap/Features/Restaurant/AddRestaurantView.swift`
- `ios/TasteMap/TasteMap/Features/Restaurant/RestaurantDetailComponents.swift`
- `ios/TasteMap/TasteMap/Features/Restaurant/RestaurantDetailView.swift`
- `ios/TasteMap/TasteMap/Features/Restaurant/RestaurantDetailedRatingsSection.swift`
- `ios/TasteMap/TasteMap/Features/Restaurant/RestaurantDishSection.swift`
- `ios/TasteMap/TasteMap/Features/Restaurant/RestaurantEditView.swift`
- `ios/TasteMap/TasteMap/Features/Restaurant/RestaurantQuickActionsSection.swift`
- `ios/TasteMap/TasteMap/Features/Settings/Import/BackupImportPlanView.swift`
- `ios/TasteMap/TasteMap/Features/Settings/SettingsSystemViews.swift`
- `ios/TasteMap/TasteMap/Features/Settings/TasteMapSettingsView.swift`
- `ios/TasteMap/TasteMap/Features/Visit/DishManagerSheet.swift`
- `ios/TasteMap/TasteMap/Features/Visit/TasteFootprintsView.swift`
- `ios/TasteMap/TasteMap/Features/Visit/VisitEditorView.swift`
- `ios/TasteMap/TasteMapUITests/TasteMapUITests.swift`

## 10. 明确未修改

- Restaurant / Visit / Dish / Photo / Profile / Social 等业务数据模型未改。
- SwiftData schema 未改。
- Sync / Auth / Keychain / Sign in with Apple 未改。
- Worker、D1、R2、migration 未改。
- Production 未访问、未部署、未写入。
- Bundle Identifier、Team、Signing、Capabilities 未改。
- App Icon 未改。
- Analysis / Poster 的独立设计语言未重做。
- Web 产品代码未改。

## 11. 已知后续 Release Gates

这些项目来自 Task 10 parity closure，不由 Task 11 视觉恢复伪装为已完成：

- Account Delete 正式闭环仍暂缓。
- F1-C4 第二次导入导致 duplicate Visit 的已知问题仍需在 Release closure 中修复；本轮未执行第二次真实 Import。
- UGC report / block 能力尚未形成完整闭环。
- StoreKit 正式 Product / Subscription / Sandbox / TestFlight 配置仍需 App Store Connect。
- Share Extension 真机、Universal Link / AASA 与 Production 部署仍需发布环境验收。
- Privacy Policy / Terms / Support 正式 URL 尚待发布配置锁定。

## 12. Git

- 计划提交说明：`Complete Taste Map visual restoration`
- 本报告将在提交后补充最终 commit hash 与 push 结果。
