# Taste Map｜Full Product Parity Module 6：Roulette / 今天吃什么

验收日期：2026-08-31  
执行分支：`fix/full-product-parity-restoration`  
模块目标：恢复已经认可的「今天吃什么」产品语义与 Wheel 视觉；候选池、可见扇区和最终结果必须使用同一组真实 Restaurant。

## 1. Step A｜Web 功能与数据语义

当前 Web 移动端实际结构为：

1. 私人餐厅库中的候选餐厅 chips，可逐家移除或清空；
2. 候选上限为 10 家；
3. Wheel 顶部为固定 Map Pin 指针；
4. Wheel 的每个扇区显示一家具名 Restaurant，优先显示真实照片，并补充城市与真实评分；
5. 中央 CTA 直接开始/再次抽取；
6. 候选管理与搜索位于 Wheel 之后；
7. 抽取只基于用户自己的 Restaurant，不依赖网络，也不改变 Restaurant 数据。

Web reference：

- [Web Roulette reference（首屏）](full-product-parity-assets/web-roulette-reference-top-module-6.png)
- [Web Roulette reference（完整页）](full-product-parity-assets/web-roulette-reference-module-6.png)

### 修复前发现的功能迁移错误

旧 iOS 的 `RestaurantRouletteEngine` 在候选数较大时把可见 Wheel 压缩成最多 12 个抽象扇区，但随机结果仍从全部 120/1000 家候选中产生。这样会造成：

- 用户看到的扇区集合和真实可抽取集合不一致；
- 结果可能不是用户在 Wheel 上看到的 Restaurant；
- Wheel 无法证明每家具名 Restaurant 的机会一致；
- 可见扇区只有文字，没有照片、城市和评分上下文；
- 候选不是 Web 已确认的最多 10 家主动池。

因此这不是单纯视觉问题，而是 candidate projection 的 parity bug。

## 2. Step B｜iOS 修复

### 2.1 一一对应的真实候选池

- Active candidate pool 上限锁定为 10 家，与当前 Web 合同一致；
- 默认从当前筛选结果中稳定选择前 10 家；
- 从 Restaurant Detail / 其他入口传入的首选 Restaurant 会被优先放入 active pool，且只出现一次；
- 用户可清空、逐家移除或在候选管理中重新选择；
- 120/1000 家私人餐厅库仍可搜索和筛选，但不会用 placeholder 或复制 Restaurant 填满 Wheel；
- Wheel 扇区数始终等于 active candidate 数；
- 每个扇区、抽取引擎与结果卡使用同一个 `RouletteCandidate.globalKey` 集合；
- 抽取继续保持 active pool 内均匀随机，并保留立即重复保护；
- 只有一家具名 Restaurant 时明确显示“今天就它了”，不播放伪随机动画。

### 2.2 已认可 Wheel 视觉恢复

- 恢复 10 色低饱和餐饮海报式扇区 palette；
- 固定白底/品牌深蓝 Map Pin 指针；
- 双层圆形描边、轻阴影和中央主 CTA；
- 每个扇区优先显示真实 Restaurant thumbnail；
- 无照片时使用统一 generic dining 餐具符号，不使用系统 Emoji 冒充真实食物；
- 扇区补充真实城市；存在真实平均评分时才显示评分，`nil` 不显示假分数；
- 候选 chips、筛选摘要与 Wheel 使用同一 active pool；
- 结果卡仍进入全局唯一 `RestaurantDetailView(..., entrySource: .roulette)`。

### 2.3 Food & Dining Visual Language 边界

| 元素 | 类型 | 语义 |
| --- | --- | --- |
| Restaurant photo | Data-linked | 来自该候选 Restaurant 的真实 `PhotoAsset` |
| Restaurant name / city / rating | Data-linked | 来自该具名候选；评分仅在真实存在时显示 |
| 无照片餐具 fallback | Decorative / generic dining | 只表达餐饮场景，不暗示菜系或用户偏好 |
| Map Pin pointer | System semantic | 只表达 Wheel 当前命中位置，不表达 City/GPS filter |
| City condition chip 的建筑图标 | System semantic | 表达城市筛选；不再错误使用 GPS 图标 |

## 3. Before / After

| 证据 | 截图 |
| --- | --- |
| iOS before：巨大宣传 Hero、抽象文字扇区、候选和可见结果集合不完整对应 | [ios-roulette-before-module-6.png](full-product-parity-assets/ios-roulette-before-module-6.png) |
| iOS after：4 家真实候选、每家一个扇区、固定指针、结果/重抽状态 | [ios-roulette-after-module-6.png](full-product-parity-assets/ios-roulette-after-module-6.png) |
| iOS after：120 家私人库中主动选择 10 家，10 个真实一一对应扇区 | [ios-roulette-large-after-module-6.png](full-product-parity-assets/ios-roulette-large-after-module-6.png) |

## 4. 自动化验收

### Unit tests

`P4GRestaurantRouletteTests`：11/11 PASS。

覆盖：

- 2/3/8/12/30/100/1000 候选时可见扇区数严格等于 active pool 数；
- 1000 家库仍完整可搜索，但 Wheel active pool 最多 10 家；
- active candidate global identity 唯一；
- preferred Restaurant 被稳定加入且不重复；
- 筛选、默认城市、均匀选择入口、立即重复保护、旋转落点与 global identity 保持。

### UI tests

以下 4 条核心路径全部 PASS：

1. `testP4GRouletteFilterSpinResultDetailRerollAndOfflineRestart`
2. `testP4GRouletteEmptyState`
3. `testP4GRouletteSingleCandidateSkipsFakeSpin`
4. `testP4GRouletteLargeLibraryUsesTenRealOneToOneSegments`

验证了筛选、抽取、结果、统一 Restaurant Detail、重抽、离线重启、空状态、单候选、120 家库与 10 个真实可见候选。

### Build

- Debug Simulator build：PASS
- Release Simulator build：PASS
- Swift compiler / App target / Share Extension：PASS
- `git diff --check`：PASS

## 5. 安全边界

- SwiftData schema：未修改
- API / Worker / D1 / migration：未修改
- Auth / SyncEngine：未修改
- Restaurant 数据：抽取过程中不写入、不伪造、不复制
- Production：未访问
- App Icon：未修改

## 6. 剩余人工项

自动化已覆盖功能、候选一致性和 Simulator 视觉证据。仍建议最终真机总体验收时只做一次短 smoke：确认 3 秒惯性动画、触觉反馈和滚动手感符合预期；这不是当前代码 blocker。

## 7. Module 6 结论

**PASS**。Roulette 已从“抽象可用转盘”恢复为真实 Restaurant 候选驱动、视觉与结果一一对应、可离线使用且符合已确认 Web 产品语义的「今天吃什么」。
