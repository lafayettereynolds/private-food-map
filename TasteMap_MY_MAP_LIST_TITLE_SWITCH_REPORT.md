# Taste Map｜“我的地图 / 我的列表”标题与视图切换修正报告

日期：2026-08-31

仓库：`/Users/lafayette/Projects/private-food-map-product-ux`

分支：`fix/product-ux-correction-8-tasks`

Production：未访问、未修改

## 1. 结果

本次 New Design Override 已完成。修改范围严格限制在“我的地图 / 我的列表”顶部标题组合、Map/List 唯一切换入口及其对应测试，没有修改地图数据、筛选业务、Restaurant、SwiftData、Sync、Worker、D1、Production、App Icon 或其他页面。

最终行为：

- Map 状态显示 `我的地图` + 当前视图的 `map` icon。
- List 状态显示 `我的列表` + 当前视图的 `list.bullet` icon。
- title + icon 是一个固定内容宽度的 `HStack`，外层再以页面宽度整体居中。
- icon 是唯一正式 Map/List switch；没有增加 segmented control 或第二套入口。
- 44 × 44 pt 实际点击区域，带按压 scale/opacity 与轻量底色反馈。
- 使用系统 selection sensory feedback。
- VoiceOver 文案为 `切换到我的列表` / `切换到我的地图`，不会只读“地图图标”。
- Map/List 切换继续复用同一份 `selectedSegment`、`filterState`、`browseQuery` 和 projection，不重置 scope、筛选或排序。

## 2. 根因与修正

### 原实现

- title 与 icon 虽位于同一个 `HStack`，但 accessibility identifier 加在扩展至整屏宽度后的容器上。
- 旧测试只证明“整屏宽容器”的 `midX` 与页面一致，不能证明实际可见 title+icon group 居中。
- Map 状态显示 `list.bullet`，表达的是目标视图；视觉上更像一个漂在标题右侧的独立操作。
- 可访问名称是较宽泛的“切换到列表 / 切换到地图”。

### 新实现

- 新增可复用的 `MapBrowseTitleSwitch`。
- 内部 title+icon group 使用 `.fixedSize(horizontal: true, vertical: false)`。
- accessibility identifier 直接归属实际固定宽度视觉 group。
- 外层只负责把完整 group 放在页面正中。
- icon 表达当前视图：Map 使用 `map`，List 使用 `list.bullet`。
- `MapBrowseMode` 集中维护页面标题、icon、切换可访问文案与 identifier，避免 View 中分散猜测。
- 新增轻量 `MapBrowseTitleIconButtonStyle`，不引入大型按钮或卡片。

## 3. 未改变的共享状态

以下状态仍由原 `MapHomeView` 的同一实例持有，Map/List 没有建立第二份 query 或 filter：

- `selectedSegment`：去过 / 想吃 / 推荐
- `filterState`：城市、评分、消费、到访次数、饭搭子、菜系、推荐来源、sort
- `browseQuery`
- `RestaurantBrowseBuilder` projection
- `PersonalRestaurantFilterEngine` 结果
- Restaurant selection/detail route

定向 UI regression 实际设置了 `想吃` + `9.0–10.0 分`，然后执行 Map → List → Map；两次切换后 scope 与评分筛选均保持 selected，没有被重置。

## 4. Accessibility 与交互

| 状态 | 标题 | 当前视图 icon | Button label | Button value |
|---|---|---|---|---|
| Map | 我的地图 | `map` | 切换到我的列表 | 当前显示我的地图 |
| List | 我的列表 | `list.bullet` | 切换到我的地图 | 当前显示我的列表 |

- Button hit target：至少 44 × 44 pt
- Button trait：原生 Button
- Hint：切换地图和列表视图
- Pressed feedback：scale、opacity、轻量背景 tint
- Haptic/sensory feedback：selection
- title 保留 header trait

## 5. 尺寸与主题验收

- 主要 iPhone 宽度：402pt，实际 UI E2E 通过。
- 实际 title group `midX` 与 App `midX` 误差要求：不超过 2pt，测试通过。
- title group 宽度小于页面宽度 52%，测试通过。
- 小尺寸：以 320pt 约束执行 `UIHostingController.sizeThatFits`，完整 title+icon group 未溢出，测试通过。
- Light Mode：通过。
- Dark Mode：通过。
- 顶部整体仍受原 compact header 高度约束，地图有效面积没有回退。

## 6. 截图证据

截图目录：

[`reports/product-ux-correction-assets/my-map-title-switch/`](reports/product-ux-correction-assets/my-map-title-switch/)

必需证据：

- [Map before](reports/product-ux-correction-assets/my-map-title-switch/map-before.png)
- [Map after](reports/product-ux-correction-assets/my-map-title-switch/map-after.png)
- [List after](reports/product-ux-correction-assets/my-map-title-switch/list-after.png)

补充证据：

- [Map after — scope/filter state preserved](reports/product-ux-correction-assets/my-map-title-switch/map-after-state-preserved.png)
- [List after — scope/filter state preserved](reports/product-ux-correction-assets/my-map-title-switch/list-after-state-preserved.png)
- [Map dark after](reports/product-ux-correction-assets/my-map-title-switch/map-dark-after.png)

## 7. 测试

### Unit / layout contract

新增/更新覆盖：

- Map title = 我的地图
- List title = 我的列表
- Map current icon = `map`
- List current icon = `list.bullet`
- 精确 Accessibility labels
- 320pt compact group size fitting
- 正式一级 scope 仍为 去过 / 想吃 / 推荐

结果：`TEST SUCCEEDED`

- Log：`/tmp/tastemap-my-map-title-unit.log`
- Result bundle：`/tmp/TasteMap-MyMapTitle-Unit-20260831.xcresult`

### UI E2E（固定 Simulator，禁止并行 Clone）

运行：

- `testTask04CoreLayoutParityEvidence`
- `testMyMapListTitleSwitchKeepsScopeAndFilters`
- `testTask04DarkLayoutKeepsCompactMapControls`

结果：3 tests，0 failures，`TEST SUCCEEDED`。

最终有效测试明确使用：

- `-parallel-testing-enabled NO`
- `-maximum-parallel-testing-workers 1`
- 固定 UDID：`E4F3EED9-89D8-405C-B4CB-7CA816CE3405`

- Log：`/tmp/tastemap-my-map-title-ui-fixed-simulator.log`
- Result bundle：`/tmp/TasteMap-MyMapTitle-UI-FixedSimulator-20260831.xcresult`

## 8. Build 与 Simulator checkpoint

| 项目 | 结果 |
|---|---|
| Debug iPhone Simulator build | BUILD SUCCEEDED |
| Release iPhone Simulator build | BUILD SUCCEEDED |
| 安装到固定 Simulator | 成功 |
| 启动 Taste Map | 成功 |

Logs：

- `/tmp/tastemap-my-map-title-debug-build.log`
- `/tmp/tastemap-my-map-title-release-build.log`

固定开发 Simulator：

- iPhone 17 Pro
- iOS 26.5
- UDID `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`
- 当前 Booted
- 当前运行最新 Debug Taste Map
- 当前停留在“我的地图”页面

第一次 UI 命令未显式关闭 Xcode parallel runner，因此结果日志曾出现一次瞬时 `Clone 1` runner 标签；`simctl` 中没有留下 Clone 设备。发现后立即改为 `-parallel-testing-enabled NO` 并在固定 UDID 上重新执行，最终正式验收结果来自无 Clone 的第二次运行。没有 erase，也没有切换到其他设备或旧 worktree。

## 9. 修改文件

- `ios/TasteMap/TasteMap/Features/Map/MapHomeView.swift`
- `ios/TasteMap/TasteMapTests/CoreProductLayoutParityTests.swift`
- `ios/TasteMap/TasteMapUITests/TasteMapUITests.swift`
- `TasteMap_MY_MAP_LIST_TITLE_SWITCH_REPORT.md`
- `reports/product-ux-correction-assets/my-map-title-switch/*.png`

## 10. 明确未修改

- Map Marker 逻辑
- Nearby / GPS
- Restaurant Detail
- Discovery
- Profile
- Filter 业务逻辑
- Restaurant / Visit / SwiftData schema
- SyncEngine / APIClient
- Worker / D1 / migration
- Production
- App Icon

建议独立 commit message：`Fix My Map list title switch`
