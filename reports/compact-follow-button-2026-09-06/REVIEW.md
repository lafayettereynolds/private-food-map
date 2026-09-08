# work — 关注按钮居中与紧凑化

日期：2026-09-06

## 结果与范围

“好友与关注 → 推荐”中的蓝色关注按钮改为文字居中的紧凑胶囊；默认字体下宽 64 点、可见高 30 点、实际点击高度至少 44 点。推荐与用户搜索结果共用一个 Native 组件。加载时保留文字占位、仅显示居中转圈，避免宽度跳变；无障碍大字体可自然扩展。关注请求、待处理禁用、用户身份与推荐依据未改变。

旧实现是 List 中的系统 Label（关注 + person.badge.plus）配 borderedProminent/controlSize.small，系统布局保留了图标列空间，造成截图中仅可见文字偏右及按钮过长。现使用明确居中的 Text 与既有品牌 token，不再依赖系统 Label 布局。

本次只处理这一项样式请求，没有顺带修改此前“记录后显示启动页”的业务链路。

## 同类消费者清查

| 消费者 | 处理与证据 |
| --- | --- |
| Hybrid → Native Social Hub 推荐列表 | 共享 TasteMapCompactFollowButton；最终 QA UI 验证 64 × 44 点、截图人工确认文字居中 |
| 同一 Social Hub 用户搜索 | 同一 row/同一按钮；最终 QA 缓存搜索 UI 与截图验证 |
| Native 回退个人页 → Social Hub | 复用正式组件；额外 UI 验证结果见下 |
| Native 公开主页关注/已关注 | 已有文字型 intrinsic 按钮，属于关系操作组，不是截图的列表 Label；本次不改 |
| Browser FriendsPage | 图标型关注动作已居中，不是长文字胶囊；不擅自改成新模板 |
| Browser 公开主页、加好友/已申请 | 关系操作组或不同业务语义，保留既有居中结构与文案 |
| Preview / Share extension | Preview 复用 Social Hub；Share extension 无相关消费者 |

截图使用明确隔离的 QA 资料，不代表真实推荐服务或线上用户。搜索截图明确显示“网络不可用，显示已有缓存”，因此只证明缓存搜索行的样式，不宣称真实搜索 API 验收通过。测试不点击关注，不新增真实社交关系。

## 验证记录

- 最终 Vitest：HybridGlobalProductContract 与 HybridMapProductContract 两个文件、72 项通过，覆盖新增共享按钮契约与既有全局/地图回归。
- Swift Testing：8 项通过；包含浅色/深色 ready/pending 尺寸一致、44 点目标及 accessibility3 自然扩展。
- 最终 QA UI：推荐 → 搜索测试通过，25.578 秒，保留两张运行截图；本次没有以源码断言替代真实截图。
- 最终 Debug 测试目标、DebugQA、Release 构建成功；Release 纯净扫描通过：39 app 文件、17 signed Web 文件。
- 正式暂存、QA 构建和已安装包中的 17 个 Hybrid 文件逐字节匹配；完整安装包与构建目录 diff 无差异。
- 首轮测试错误地查找被 VoiceOver 合并的子 Text，实际按钮已通过 64/44 几何断言。删除不存在的子元素查询，保留真实按钮几何要求，文字居中由最终截图检查。
- 额外 Native 首轮路径测试点击“我的”后仍在地图，未进入按钮页面；不将该失败计为按钮通过，也不宣称修复导航。样式测试后续改为使用已有的 DEBUG 初始个人页参数，范围明确限定到个人页的真实 Social Hub 入口。地图启动/切换问题仍需独立复核。

- 原生与 Hybrid 额外 UI 测试最终通过：32.310 秒。原生使用现有 DEBUG 初始个人页参数，进入实际 Social Hub 并搜索；Hybrid 使用添加好友入口。两条路径均验证可点击性与 64 × 44 点目标。
- 深色复测：`-AppleInterfaceStyle Dark` 在这次环境中未实际改变外观，不能把命名为 Dark 的浅色截图当作证据。明确启动隔离模拟器并通过 `simctl ui … appearance dark` 设置系统外观后，额外 UI 测试再次通过，31.685 秒；最终真实深色截图人工确认文字居中、深色文字/浅蓝底清晰。完成后恢复模拟器浅色。
- 最终相关跟踪文件 `git diff --check` 通过。

最终截图（隔离测试资料）：

- [推荐列表](/Users/lafayette/Projects/private-food-map-hybrid-final-integration/reports/compact-follow-button-2026-09-06/recommendations.png)
- [QA 搜索结果](/Users/lafayette/Projects/private-food-map-hybrid-final-integration/reports/compact-follow-button-2026-09-06/search.png)
- [原生回退搜索](/Users/lafayette/Projects/private-food-map-hybrid-final-integration/reports/compact-follow-button-2026-09-06/native-search.png)
- [系统深色搜索](/Users/lafayette/Projects/private-food-map-hybrid-final-integration/reports/compact-follow-button-2026-09-06/dark-search.png)

## Design System Compliance

- Core UI：抽取唯一共享关注原语，使用 Typography.control、FollowAction 与 minimumHitTarget；新增语义 onBrand 色保证深色对比度；未新增第二套字号/间距体系。
- Food & Dining：未修改头像资产、餐厅图片或品牌食物视觉。
- Canonical Templates：保留页头、四个分栏、搜索、用户身份和推荐依据；只调整用户明确要求的关注按钮。
- Default SwiftUI：使用 plain style 避免系统 List Label 图标列干预，未改成新的默认表单、列表模板或另一路由。
- 边界：模拟器验证，不是 iPhone 真机验收；没有线上部署、购买或社交关系写入。未修改 Hybrid/Native 所有权或正式运行模式。

## 运行身份

- 仓库：/Users/lafayette/Projects/private-food-map-hybrid-final-integration
- 分支：feature/hybrid-final-integration；基准 HEAD：58bd556b8382734aeae1f08937ba649563682140；保留所有既有脏工作区改动，未提交。
- QA：com.lafayette.tastemap.qa / DebugQA / iPhone 17 Pro / iOS 26.5。
- QA 模拟器：E4F3EED9-89D8-405C-B4CB-7CA816CE3405。
- 构建：/tmp/tastemap-map-anchor-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app。
- 安装：/Users/lafayette/Library/Developer/CoreSimulator/Devices/E4F3EED9-89D8-405C-B4CB-7CA816CE3405/data/Containers/Bundle/Application/DDD96A46-E4AC-4D4A-B2E2-57819560AD01/TasteMap.app。
- QA 参数：--tastemap-hybrid-development -AppleInterfaceStyle Light；TASTEMAP_VISUAL_QA_MODE=rich。
- 原生回退：com.lafayette.tastemap / Debug；模拟器 5C24CBC2-5E24-4D82-B7DD-FB815DD7A60A；既有参数 TASTEMAP_CORE_PARITY_INITIAL_TAB=profile（仅原生启动），TASTEMAP_VISUAL_QA_MODE=rich。额外深色通过系统 appearance 设置，未改变产品配置。
- 测试结果：/tmp/tastemap-follow-compact-final-qa.xcresult；/tmp/tastemap-follow-compact-final-native.xcresult（Swift 8 项通过、首次 UI 入口失败）；/tmp/tastemap-follow-compact-final3-native.xcresult（最终两入口通过）；/tmp/tastemap-follow-compact-dark-system.xcresult（真实深色通过）。
