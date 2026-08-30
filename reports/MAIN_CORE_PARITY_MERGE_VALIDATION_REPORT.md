# Taste Map｜Nearby + Core Product Layout 合并验收报告

日期：2026-08-30  
目标分支：`main`  
合并前基线：`2b7ffa8c8ac6d7c83099c3f45a4eed16bee0d620`（Fix real-device sync pull timeout）

## 1. Nearby branch merge

- 来源分支：`fix/add-restaurant-nearby-parity`
- 来源 commit：`aa5ec5682f933f08ac8e9f5f28a2a1c0e16c4625`
- merge commit：`0e79e34ebe3925b7692c8b485f8ae89ee3912e05`
- 合并方式：正常 `--no-ff` merge；未 squash、未 rebase、未重写历史。
- 合并结果：成功，无文本冲突。
- 已保留：fresh `CLLocation`、过期位置拒绝、时间戳与水平精度校验、Reduced Accuracy 诚实状态、前台/移动刷新、Nearby 查询中心、`CLLocation` 距离排序，以及 Web 对齐的搜索、城市、Apple Maps、高德、URL/分享文字、Nearby、手动添加、想吃/去过、显式确认和去重流程。

## 2. Core Product Layout branch merge

- 来源分支：`fix/core-product-layout-parity`
- 来源 commit：`78e8e8c42ef3329b96c64b14cc834ada7eb0d558`
- merge commit：`a037f7929561ff1804990c0cf0675d4b27fe203d`
- 合并方式：正常 `--no-ff` merge；未 squash、未 rebase、未重写历史。
- 合并结果：成功，无文本冲突。
- Map 已保留紧凑的“去过 / 想吃 / 适合你”、单排横向筛选 chips、地图/列表右下悬浮切换、底部居中的“添加餐厅”，以及 Map/List 共享筛选状态。
- Discovery 已保留“关注 / 为你推荐 / 同味之选 / 最新 / 趋势”五个一级导航，没有恢复“发现餐厅 / 社区动态”额外层级。
- Profile 已保留 compact header、横向统计、并排核心入口、回味、我的食单、发现与洞察及次级 Settings 入口。

## 3. 冲突与用户工作保护

- 两次 Git merge 均未产生需要人工选择 ours/theirs 的冲突。
- `TasteMapUITestFixtures.swift` 与 `TasteMapUITests.swift` 由 Git 自动合并；合并后逐项检查，Nearby fixture/test 与 Core Layout fixture/test 均保留。
- 主工作目录原有 `project.pbxproj` 用户修改、未跟踪审计文档、`reports/` 内容、`pnpm-workspace.yaml` 和既有 stash 均未删除、覆盖、reset、clean、pop 或误提交。
- 未合并、未修改 `audit/full-product-parity`。
- 未修改 Production、StoreKit/App Store 配置或 Sync 实现。

## 4. 自动化测试

### Web / Worker

- Vitest 全套：49 files / 342 tests，全部通过。
- TypeScript project typecheck：通过。
- Worker TypeScript typecheck：通过。
- Vite production build：通过；仅保留既有大 chunk advisory，无新增构建失败。

### iOS unit / integration

- 合并后相关 suite：92 tests，全部通过，0 failure，0 skipped。
- 覆盖：`RestaurantAcquisitionTests`、`CoreProductLayoutParityTests`、F2-A Map/List、F2-B filters、P3-A Profile、P3-C Discovery、P3-D Community、`SyncCoordinatorTests`。
- `SyncCoordinatorTests` 独立回归：16 tests，全部通过；覆盖 per-user incremental cursor、空队列 pull、超时边界、有界 retry、single-flight 和网络恢复。

### iOS UI E2E

- iPhone 17 Pro Max：10 条关键 UI E2E 全部通过。
- 覆盖：Map、List、共享筛选、Restaurant Detail、Nearby 想吃显式确认、城市搜索后去过、链接导入确认、拒绝定位后手动添加、Discovery、Community、Settings/Sync。
- iPhone 17e 深色模式：2 条布局测试全部通过；覆盖 compact Map controls、Discovery 与 Profile。

## 5. Build

- Debug / generic iOS Simulator：通过。
- Release / generic iOS Simulator：通过。
- Release / generic iOS Device：通过。
- Device 产物已使用现有 Automatic Signing 正常签名：Team `7G5J9MJX88`，Bundle ID `com.lafayette.tastemap`。
- `codesign --verify --deep --strict`：通过。

## 6. 合并后截图

- [Map](main-core-parity-merge-assets/map.png)
- [List](main-core-parity-merge-assets/list.png)
- [Add Restaurant / Nearby](main-core-parity-merge-assets/add-restaurant-nearby.png)
- [Discovery](main-core-parity-merge-assets/discovery.png)
- [Profile](main-core-parity-merge-assets/profile.png)

截图来自合并后 `main` 的关键 UI E2E `xcresult`，不是合并前分支截图。

## 7. 真机安装状态

Release generic iOS Device 构建和签名已通过，因此可以在真实 iPhone 上安装最新 `main` build。仍建议在保留两个 feature branch/worktree 的前提下完成最小人工 smoke 后再删除任何分支或 worktree。

## 8. 最小真机人工检查

1. Map 首屏：顶部无 Map/List segmented control，chips 可横滑，地图面积与底部按钮无遮挡。
2. Map ↔ List：右下悬浮按钮双向切换，筛选状态保持。
3. 添加餐厅：Nearby 能取得真实当前定位，选择后可明确记录“想吃”与“去过”。
4. Discovery：五个一级 Tab 均可切换，城市/筛选位置紧凑。
5. Profile：登录态 dashboard 保持紧凑横向统计、并排核心入口与正确 section 顺序。
6. Restaurant Detail 与 Settings → Sync 可正常进入；确认此前真机 sync timeout 修复没有回归。

