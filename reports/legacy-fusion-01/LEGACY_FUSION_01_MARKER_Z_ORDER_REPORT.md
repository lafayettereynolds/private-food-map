# Taste Map — Legacy Fusion 01 验收报告

## 结论

Restaurant Marker 的自然重叠与确定性图层顺序已经恢复。每家 Restaurant 仍是独立 annotation；任何缩放层级都不生成数字 cluster 或 Food/Dining count cluster；默认路径不再修改原始坐标来摊开重叠 Marker。

## 根因

当前 presentation 已经携带 `averageRating` 和 `visitCount`，但 MapKit annotation view 没有统一消费这些字段来设置最终视觉层级。与此同时，`RestaurantMapMarkerCollisionPolicy` 会对同坐标 Restaurant 自动施加径向坐标偏移，导致普通地图状态被强制摊开，并掩盖了真正需要的重叠层级关系。

## 共享实现

- `RestaurantMapMarkerBuilder` 现在保留 Restaurant 的原始经纬度，不再调用默认 dispersion。
- `RestaurantMapMarkerLayerPolicy` 是唯一的 Restaurant marker 排序合同，生成稳定的 back-to-front ranks。
- `RestaurantMapView.Coordinator` 在 annotation 更新、selection 更新和 annotation view 复用时统一应用 ranks。
- 用户实时位置 annotation 使用独立层级路径，不进入 Restaurant rating comparator；其视觉没有修改。

最终顺序（从最上层优先级到最低）：

1. selected Restaurant
2. 有效 aggregate `averageRating`
3. `visitCount`
4. stable Restaurant UUID

`nil` / 非有限 rating 是明确的“未评分”状态，稳定排在任何真实有限评分之后；真实 `0` 分不会被当成 `nil`。

## 默认重叠策略

- 数字 cluster：无
- Food/Dining count cluster：无
- same-coordinate automatic offset：已清除
- default spiderfy：无
- collision dispersion：已清除
- zoom-driven forced separation：无
- 用户主动展开高度重叠区域的未来辅助交互：本次未新增、未阻塞

## 自动化验收

- `MapBrowsingParityTests` + `Task10LargeDatasetPerformanceTests`：18 tests / 2 suites PASS。
- 最终 `MapBrowsingParityTests` + `Task09AccessibilityVisualQATests`：20 tests / 2 suites PASS。
- UI regression `testLegacyFusionRichMapKeepsIndependentNaturalMarkers`：PASS。
- 既有 UI regression `testFarMapKeepsIndependentRestaurantMarkers`：PASS。
- Debug Simulator build：PASS。
- Release Simulator build：PASS。

覆盖内容包括：4.8 > 4.2、三层以上重叠、同评分 visitCount、stable UUID、nil 与真实 0 的区别、selected/deselect、反转输入顺序模拟 viewport refresh、90 家 Rich Demo 独立 marker、无 count cluster、自然重叠 fixture。

## 固定 Simulator

- Device：iPhone 17 Pro
- iOS：26.5
- UDID：`E4F3EED9-89D8-405C-B4CB-7CA816CE3405`
- 状态：保持 booted；已安装最新 Debug build；以 `TASTEMAP_VISUAL_QA_MODE=rich` 启动；当前停留在“我的地图”去过页。
- Rich Demo：仍为 90 家去过 Restaurant，没有为截图减少数据量。坐标 fixture 改为确定性的自然城市锚点，包含真实同坐标与近重叠数据，不再使用人工均匀网格制造“硬币墙”。

## 截图证据

- [修复前 dense map](dense-map-before.png)
- [自然重叠 dense map](dense-map-overlap.png)
- [放大后的重叠状态](zoomed-overlap.png)
- [Marker 选择手势状态](selected-marker-top.png)
- [稀疏想吃地图](sparse-map.png)

选中 Marker 后产品既有行为会立即进入全局 Restaurant Detail；因此 selected 的置顶/取消选择恢复主要由确定性排序测试验证，截图保留点击时的地图状态，没有为截图增加另一套 UI 或测试专用业务路径。

## 范围确认

本次没有修改 Restaurant image policy、Map/List title switch、FilterBar、Nearby/GPS、Restaurant Detail、Discovery、Profile、Roulette、Analytics、SwiftData schema、Sync、Worker、D1、R2、Production、StoreKit 或 App Icon。`docs/TASTEMAP_PRODUCT_DESIGN_RULES.md` 已有正确合同，本次没有重复改写。
