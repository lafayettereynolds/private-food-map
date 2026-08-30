# Taste Map｜Full Product Parity Module 2

## Add Restaurant + Nearby + GPS

日期：2026-08-30  
分支：`fix/full-product-parity-restoration`  
范围：Restaurant Acquisition 页面、Nearby provider coverage、GPS query center 与距离排序；不修改 SwiftData schema、Sync、Worker、D1 或 Production。

## 1. Step A｜Web 功能语义与数据来源

### Web Source of Truth

Web `AddRestaurantModal` 的正式 acquisition 语义是：

1. 自动申请/读取当前高精度位置；定位 watchdog 为 12 秒。
2. 用该 GPS coordinate 作为 Nearby query center，半径 3 km。
3. AMap provider 对「餐厅 / 美食 / 饭店」三类 query 并发检索。
4. 合并 provider results、去重，再使用当前 GPS 到每个 POI 的实际距离升序排序。
5. Nearby 只展示前 8 个；搜索、城市、Apple/AMap/普通链接、手动添加是同一 acquisition flow 的其他入口。
6. 用户必须先显式选择餐厅，再选择「去过 / 想去」并确认；仅浏览/检索不会写入 Restaurant。
7. 已存在餐厅进入再次记录流程，不能建立重复 Restaurant。

关键代码：

- `src/components/AddRestaurantModal.tsx`
- `src/services/amap.ts`
- `src/services/mapService.ts`
- `src/services/externalRestaurantLink.ts`

### iOS before semantic audit

iOS 已有的正确能力保留：

- `LocationPermissionManager` 检查 freshness、future timestamp、horizontal accuracy 与 Reduced Accuracy。
- 正常 full accuracy 只接受 15 秒内且精度合理的 `CLLocation`；不把 stale/city center/map camera 当作 GPS。
- foreground 与明显 movement 会刷新位置。
- `RestaurantAcquisitionViewModel` 使用同一个 accepted coordinate 做 query center、3 km bound 和 `CLLocation.distance` 排序。
- Apple Maps、AMap、普通链接/分享文字、manual entry、provider-neutral identity、dedupe、WantToGo/Visited 显式确认已存在。

发现的真实功能 parity bug：

- iOS MapKit Nearby 过去只发起一次自然语言「餐厅」搜索；Web 使用「餐厅 / 美食 / 饭店」三类检索。单一 query 会漏掉 provider 分类为“美食”或“饭店”的真实近距离结果，这能解释“GPS center 正确但 Nearby 仍不完整”的现象。

## 2. Step B｜修复

### Nearby provider coverage

新增 `RestaurantNearbySearchPolicy`：

- 稳定 query vocabulary：`餐厅`、`美食`、`饭店`。
- 三个 `MKLocalSearch` 并发执行，共用同一 accepted GPS coordinate 和 3 km region。
- 至少一个 batch 成功即可合并结果；全部失败才返回 provider error。
- 优先按 provider identity 去重；没有 identity 时使用规范化名称 + 坐标键。
- 用 `CLLocation.distance(from:)` 重新计算，而不是相信 provider 返回顺序。
- 严格过滤 3 km 之外结果并按距离升序。

Web 与 iOS 使用不同 provider，因此不要求 POI 名称逐条完全一致；验收合同是 query center、radius、实际距离与排序语义一致。

### Layout restoration

| 项目 | Web | iOS before | iOS after | 结论 |
| --- | --- | --- | --- | --- |
| Acquisition hierarchy | Search → link → Nearby → manual 同页 | 同顺序但超大纵向卡/按钮 | 保持同顺序并缩小 section/header/input | PASS |
| Link import | 输入与识别动作紧凑组合 | 输入和整行大按钮分两层 | 输入 + 42pt「识别」按钮同一行 | PASS |
| Nearby candidate | 紧凑 POI row + 可见「选择」 | 58pt 图 + 多行信息 + 整行大 CTA | 44pt 图、单行地址、GPS 距离、可见紧凑「选择」 | PASS |
| Manual entry | Nearby 后的补充入口 | 大卡片 | 紧凑 section，仍不伪装为默认路径 | PASS |
| Explicit confirmation | 选择后再确认状态 | 已存在 | 保持不变 | PASS |

证据：

- Web reference：[web-add-restaurant-before.jpg](full-product-parity-assets/web-add-restaurant-before.jpg)
- iOS before：[ios-add-restaurant-before.png](full-product-parity-assets/ios-add-restaurant-before.png)
- iOS after：[ios-add-restaurant-after-module-2.png](full-product-parity-assets/ios-add-restaurant-after-module-2.png)

## 3. Safety and honesty

- 定位被拒绝时仍可 Search / link / Manual，不阻止 App 使用。
- Reduced Accuracy 明确显示，不能假装精确到几十米。
- Nearby 空结果和 provider error 是有限状态，不会无限 loading。
- 只浏览、搜索或解析链接不会写数据；WantToGo / Visited 仍需显式确认。
- 本轮没有使用 city center、map camera 或 stale coordinate 作为 Nearby center。
- 没有修改 Apple Developer、Bundle ID、Signing、Capabilities、SwiftData schema、Worker、D1 或 Production。

## 4. Regression coverage

### Unit

`RestaurantAcquisitionTests` 覆盖：

- query vocabulary 与三批 merge；
- provider identity 去重；
- GPS distance ascending；
- 3 km bound；
- fresh/stale/future/invalid horizontal accuracy；
- Reduced Accuracy；
- foreground/movement refresh；
- denied/error/empty；
- city search、Apple/AMap/generic link、manual；
- provider-neutral identity、dedupe 与 sync contract。

结果：22 项通过。

### UI

- Nearby 必须显式选择并确认 WantToGo：PASS（iPhone 17 Pro Max）。
- City search → no result → retry/result → Visit：PASS。
- Link import 先确认后创建：PASS。
- Location denied 仍可 manual：PASS。
- Nearby compact layout 与完整确认路径：PASS（small iPhone 17e）。
- 一次 simulator accessibility infrastructure failure（`kAXError -25218`）在同一测试独立重跑后通过，不是产品断言失败。

### Remaining verification boundary

自动化已经证明 coordinate、freshness、radius、dedupe 和 sorting 算法。不同 Map provider 的实时 POI catalog 会变化，因此最终在真实 iPhone 上还需要一次非诊断性的人工视觉确认：首批 Nearby 确实围绕当前真实位置；这不应再要求用户反复 Retry 或提供日志。

### Build

- Debug Simulator build：由 unit/UI tests 完成，PASS。
- Release Simulator universal build（arm64 + x86_64）：PASS。

## 5. Result

功能语义、布局、当前尺寸、小屏回归与 Release build 均已通过。Module 2 可以关闭。
