# Taste Map — Lafayette 正式视觉审批包执行记录

日期：2026-09-02

正式分支：`fix/product-ux-correction-8-tasks`

候选分支：`preview/fuse-visual-candidates`

## 1. 输入与边界

- 输入包：`TasteMap-Lafayette-Visual-Approval.zip`
- `approval.json` SHA-256：`0a36df17c34811abb7a46fbfe589c1b5d0c0237666705acbbdc78490a9772604`
- `README.md` SHA-256：`169b98b7af786ff9352295788b52477522de61ae568f101578705ed8311c75d4`
- 页面：14；区域：122。
- 明确冻结：103；需要重设计：18；machine choice 空白：1。
- 本轮没有把候选自动视为正式决定，也没有修改 Production、StoreKit 正式配置、Signing、Capability、App Icon、SwiftData schema 或 SyncEngine。

## 2. 正式分支执行

### My Map / My List

- Restaurant Marker 继续保持独立实体、自然重叠与稳定层级。
- 新增统一评分色政策；Marker 外圈按 Legacy 五段色语言显示评分，状态徽标仍单独表达去过/想吃/推荐。
- canonical Restaurant image pipeline 继续采用：用户真实照片 → 合法公共/缓存照片 → Provider 合法商户图 → Food/Dining fallback。
- DEBUG Rich Visual QA 生成图不再被标记成 Provider 商户图片；Provider-only fixture 必须走真实 Provider/failure/fallback 链。

证据：[Map approved rating rings](approval-execution/formal/map-approved-rating-rings.png)

### Profile

- 不再显示额外的顶层“我的”导航标题。
- 添加好友和设置位于冻结的左上/右上关系。
- 头像、名字、历史 Premium 汉堡、关注/粉丝、资料、编辑与分享采用居中身份骨架。
- `去过 / 想去 / 总消费`继续使用同一份正式统计数据。
- 核心入口仍是唯一允许继续重设计的区域，正式实现没有用未批准候选覆盖。

证据：[Profile approved regions](approval-execution/formal/profile-approved-regions.png)

### Public Profile / Social Hub

- 用户可见 follower 术语统一为“粉丝”。
- 身份内容按明确冻结备注居中。
- 顶层内容分类为“动态 / 食单”；动态内保留到访/想吃真实子状态，食单继续使用现有权限与 API。
- Follow、Friendship、Share、Report、Block、public cache、Restaurant Detail 与 Want-to-Go 语义未改变。
- Header 的 machine choice 仍为空白，本轮没有把它自动标成已批准。

证据：[Public Profile approved regions](approval-execution/formal/public-profile-approved-regions.png)、[Community preserved](approval-execution/formal/community-preserved-after.png)

## 3. 保持冻结、未重复重做

Discovery、Add Restaurant/Nearby、global Restaurant Detail、Roulette、Visit Editor、Dish/Photo、Lists 和 Settings 的已冻结结构保持不动。相关业务能力、数据来源和入口没有被候选实现替换。

## 4. 已生成真实候选、仍未正式批准

- Profile：核心入口 V4 已生成，等待 Lafayette 审批。
- Analytics × 4：V3 真实 SwiftUI 信息图已生成，八个区域继续等待 Lafayette 审批。
- 五类分享海报：V3 原生 9:16 renderer 已生成，所有构图区继续等待 Lafayette 审批。
- Premium Paywall：已恢复正式 approved hamburger asset 的 V3 候选，只等待 Hamburger Hero 审批。
- Public Profile：Header machine choice 为空白，等待 Lafayette 明确选择。

以上候选只能存在于独立 DEBUG 候选分支；正式 Release 不包含 Candidate Version、FUSE V1/V2/V3、Frozen/Pending 或 launch-argument 候选入口。

完整候选证据与 Clean Preview 见 [LAFAYETTE_VISUAL_APPROVAL_EXECUTION_05.md](LAFAYETTE_VISUAL_APPROVAL_EXECUTION_05.md)。

## 5. 自动验证

- 正式 `TasteMapTests`：631 tests / 64 suites，通过。
- Map/Profile/Social/Restaurant image targeted regression：46 tests / 5 suites，通过。
- Community → Public Profile → Restaurant Detail → Want-to-Go UI E2E：1/1，通过；同时断言“动态 / 食单 / 粉丝”。
- Debug Simulator build：通过（UI E2E 使用同一 Debug 产物）。
- Release Simulator build：通过。
- Generic iOS device Release build：通过（本机验证使用 `CODE_SIGNING_ALLOWED=NO`，未修改 Signing）。

视觉候选即使 Build/Test 通过也仍是“待 Lafayette 审批”，不会自动变为正式产品决定。
