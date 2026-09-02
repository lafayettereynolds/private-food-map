# Taste Map — Lafayette 最新视觉审批执行结果

日期：2026-09-02

输入：`TasteMap-Lafayette-Visual-Approval.zip`

正式产品分支：`fix/product-ux-correction-8-tasks`

候选预览分支：`preview/fuse-visual-candidates`

## 1. 输入完整性

- `approval.json` SHA-256：`0a36df17c34811abb7a46fbfe589c1b5d0c0237666705acbbdc78490a9772604`
- `README.md` SHA-256：`169b98b7af786ff9352295788b52477522de61ae568f101578705ed8311c75d4`
- 审批范围：14 个页面、122 个区域。
- 审批状态：103 个已冻结、18 个待重设计、1 个 machine choice 空白。
- 空白项是 Public Profile 的 Header；本轮没有根据备注替 Lafayette 自动选择。

## 2. 正式产品执行

正式分支只落实了已经冻结且具有明确执行语义的调整：

- My Map：餐厅评分外圈使用统一五段评分色；Restaurant 状态继续由独立状态徽标表达。
- Restaurant image：DEBUG Visual QA 生成图不再冒充 Provider 商户图片；正式优先级仍是用户真实照片 → 合法公共/缓存照片 → Provider 合法图片 → Food/Dining fallback。
- Profile：移除多余“我的”标题；添加好友/设置维持左上/右上；身份、历史 Premium 汉堡、关注/粉丝、去过/想去/总消费按冻结关系呈现。
- Public Profile：用户可见术语统一为“粉丝”；顶层内容分类为“动态 / 食单”；Social、权限、举报/拉黑与 Restaurant navigation 能力保留。

正式分支 commit：`3beab169782bef76210b61042d45720e829f1aa6`（已 push）。

正式截图：

- [我的地图评分色](approval-execution/formal/map-approved-rating-rings.png)
- [我的页面已批准区域](approval-execution/formal/profile-approved-regions.png)
- [公开主页已批准区域](approval-execution/formal/public-profile-approved-regions.png)
- [Community 能力保留](approval-execution/formal/community-preserved-after.png)

## 3. 候选边界

以下内容只存在于 `preview/fuse-visual-candidates` 的 `#if DEBUG` 候选画廊：

- Profile Core Entries V4。
- Analytics × 4 V3。
- 五类 9:16 Poster V3。
- Premium Paywall 汉堡 V3。
- `-fuse-candidate` 与 `-fuse-clean-preview` 入口。

这些候选没有进入正式产品分支、没有修改正式业务模型、没有修改 Production、StoreKit、Signing、Capabilities、App Icon、SwiftData schema、SyncEngine 或正式 renderer。

## 4. Profile Core Entries V4

Lafayette 已冻结的七个区域保持不变；只重做“核心入口”。

- 今天吃什么与我的口味档案使用等宽、等高、同构的两个主入口。
- 图标容器、标题基线、说明文字、箭头和卡片边界使用相同节奏。
- 不再使用一侧紧、一侧松或不同几何结构造成视觉失衡。

证据：

- [候选标识版](approval-execution/candidates/profile-fuse-v4.png)
- [无候选标识 Clean Preview](approval-execution/clean/profile-fuse-v4-clean.png)

## 5. Analytics × 4 V3

共同视觉家族来自 Lafayette 高保真参考，但四页的数据语义分别实现：

- 中心真实 Food Hero。
- 周边节点、细连接线和非对称平衡。
- 左侧 TOP 3。
- 右侧数据总览与近期洞察。
- 中下部偏好、消费、人均、城市、饭搭子和用餐时间信息图。
- 暖白编辑式画布；不是普通 `VStack + Card`。

Lafayette 参考：[高保真构图 Source of Truth](approval-execution/reference/lafayette-taste-profile-source-of-truth.png)

| 页面 | 候选标识版 | Clean Preview |
| --- | --- | --- |
| 最佳饭搭子 | [V3](approval-execution/candidates/analytics-companion-v3.png) | [Clean](approval-execution/clean/analytics-companion-v3-clean.png) |
| 谁最会种草 | [V3](approval-execution/candidates/analytics-source-v3.png) | [Clean](approval-execution/clean/analytics-source-v3-clean.png) |
| 本月回顾 | [V3](approval-execution/candidates/analytics-monthly-v3.png) | [Clean](approval-execution/clean/analytics-monthly-v3-clean.png) |
| 年度回顾 | [V3](approval-execution/candidates/analytics-annual-v3.png) | [Clean](approval-execution/clean/analytics-annual-v3-clean.png) |

## 6. 五类分享海报 V3

五张均由实际 SwiftUI 9:16 renderer 输出，不是 HTML mockup、Photoshop 拼接或 AI 效果图：

- 我的口味档案：Food Hero 轨道 + 四项核心指标 + 代表餐厅。
- 最佳饭搭子：双人餐桌 + 共同到访身份 + 代表餐厅。
- 谁最会种草：推荐来源小票 + 核心 Food Hero + 来源/踩坑结论。
- 本月回顾：月度主图 + 周节奏 + 到访/餐厅/消费。
- 年度回顾：年度轨迹 + 四季节点 + 城市/到访/餐厅。

| 海报 | 候选标识版 | Clean Preview |
| --- | --- | --- |
| 我的口味档案 | [V3](approval-execution/candidates/poster-taste-v3.png) | [Clean](approval-execution/clean/poster-taste-v3-clean.png) |
| 最佳饭搭子 | [V3](approval-execution/candidates/poster-companion-v3.png) | [Clean](approval-execution/clean/poster-companion-v3-clean.png) |
| 谁最会种草 | [V3](approval-execution/candidates/poster-source-v3.png) | [Clean](approval-execution/clean/poster-source-v3-clean.png) |
| 本月回顾 | [V3](approval-execution/candidates/poster-monthly-v3.png) | [Clean](approval-execution/clean/poster-monthly-v3-clean.png) |
| 年度回顾 | [V3](approval-execution/candidates/poster-annual-v3.png) | [Clean](approval-execution/clean/poster-annual-v3-clean.png) |

## 7. Premium Paywall 汉堡 V3

- 只替换待重设计的汉堡 Hero。
- 直接复用正式 `PremiumBurgerBadge` 已认可资产，不另建第三套汉堡。
- Header、权益、商品事实、购买、恢复、法律和 Free/Premium 状态保持冻结。
- StoreKit 与 server entitlement 没有变化。

证据：

- [候选标识版](approval-execution/candidates/premium-paywall-v3.png)
- [无候选标识 Clean Preview](approval-execution/clean/premium-paywall-v3-clean.png)

## 8. 审批台更新

审批台已接入：

- Profile V4、Analytics V3、Poster V3、Premium V3 真实截图。
- 每个新候选对应的独立 Clean Preview。
- Lafayette 高保真 Analytics / Poster Reference。
- 原有 `tastemap.visualApproval.round3` 存储键继续使用；已有页面选择、区域选择、Frozen 状态、Notes 与 IndexedDB Reference 不清空。
- Candidate 仍显示为待审批，未自动设置 `KEEP FUSE`、`APPROVED` 或 `APPROVED FINAL`。

本地入口：`http://127.0.0.1:8765/full-layout-parity/visual-approval/index.html?lang=zh-cn-final&scope=approval-workspace-3#profile-density`

## 9. 自动验证

正式产品回归：

- `TasteMapTests`：631 tests / 64 suites，通过。
- Map/Profile/Social/Restaurant image targeted：46 tests / 5 suites，通过。
- Community → Public Profile → Restaurant Detail → Want-to-Go UI E2E：1/1，通过。
- 正式 Debug、Release Simulator 和 Generic iOS device Release build：通过。

候选分支验证：

- Debug Simulator build：通过。
- 固定 iPhone 17 Pro Simulator install / launch：通过。
- Release Simulator build：通过。
- 主 App + Share Extension Release executable scan：2 个 executable，候选入口、候选类型、候选标签与 Premium 预览 bypass 匹配数为 0。
- 审批台 JavaScript 语法检查：通过。
- 审批台浏览器检查：14 个项目正常显示；原冻结状态保留；Profile V4、Analytics V3、Poster V3、Premium V3 与 Lafayette Reference 可见；Clean Preview 可切换。

## 10. 仍待 Lafayette 决定

- Profile：只审批 Core Entries V4。
- Analytics × 4：八个区域全部重新审批。
- 五类海报：八个区域全部重新审批，并逐张判断传播价值。
- Premium：只审批汉堡 Hero V3。
- Public Profile：Header 仍保持空白，等待 Lafayette 明确选择。

本报告和自动化结果不构成 Lafayette 视觉批准。
