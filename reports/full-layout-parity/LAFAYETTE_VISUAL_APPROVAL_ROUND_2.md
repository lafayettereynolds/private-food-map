# Taste Map — Lafayette Visual Approval Round 2

日期：2026-09-01

正式实现分支：`fix/product-ux-correction-8-tasks`

视觉候选分支：`preview/fuse-visual-candidates`

Legacy 证据版本：`fb127e9ea20498c0db450872deb9c9dc346ef34f`

## 1. 本轮边界

本轮执行 Lafayette 第一轮视觉审批记录，不重新开展全 App 审计，不把 Pending 区域自动标记为 Approved，也不把候选实现合入正式产品分支。

- 正式方向落地：Dish / Photo、Public Profile、Lists、Analytics × 4、Premium。
- 正式冻结：Settings / Data 保持 Current，不重做。
- 独立候选：Profile FUSE V2、Visit Editor FUSE V1、五类 Poster Candidate A / B。
- 未修改：Production、Worker、D1/R2、Signing、Capability、App Icon、SwiftData schema、SyncEngine、StoreKit 正式交易架构。

## 2. 已按明确 Direction 实现

### 2.1 Dish / Photo Manager — LEGACY

正式页面改为以一次用餐故事为主线：Restaurant / Visit 上下文连续，菜品与照片采用图文优先构图，保留 Dish、VisitDish、PhotoAsset、复用、删除、上传下载与图片安全边界。

- Legacy reference：[legacy-fb127e9-visit-dish-photo-manager-1280x720.png](legacy-reference-screenshots/legacy-fb127e9-visit-dish-photo-manager-1280x720.png)
- Final candidate：[dish-photo-legacy-final-candidate.png](visual-approval/round-2/formal/dish-photo-legacy-final-candidate.png)

状态：`LAFAYETTE DIRECTION: LEGACY`；仍需 Lafayette 对最终截图做视觉确认。

### 2.2 Public Profile / Social Hub — LEGACY

正式页面使用“公开身份 → 关系 → Restaurant / Activity / List evidence”的 Legacy 骨架，并保留 Current 的 visibility、public cache、Report、Block、public Lists、sharing、Worker-backed follow、likes、comments、isolation 与权限边界。

- Legacy reference：[legacy-fb127e9-public-profile-social-1280x720.png](legacy-reference-screenshots/legacy-fb127e9-public-profile-social-1280x720.png)
- Final candidate：[public-profile-legacy-final-candidate.png](visual-approval/round-2/formal/public-profile-legacy-final-candidate.png)

状态：`LAFAYETTE DIRECTION: LEGACY`；最终视觉区域仍待确认。

### 2.3 Lists / Public Lists — LEGACY

正式页面恢复 collection / ranked 区分、cover、visibility、Restaurant ordering、ranking/member-management priority 与紧凑卡片密度；Current 的 SwiftData/Worker、owner isolation、public cache、link sharing、visibility contract、canonical Restaurant image、stable Restaurant ID 均保留。

- Legacy reference：[legacy-fb127e9-lists-public-list-1280x720.png](legacy-reference-screenshots/legacy-fb127e9-lists-public-list-1280x720.png)
- Final candidate：[lists-legacy-final-candidate.png](visual-approval/round-2/formal/lists-legacy-final-candidate.png)

状态：`LAFAYETTE DIRECTION: LEGACY`；最终视觉区域仍待确认。

### 2.4 Analytics × 4 — LEGACY

最佳饭搭子、谁最会种草、本月回顾、年度回顾统一恢复已批准历史 Analytics visual family：central Food Hero、周边 callouts/nodes、连接线、留白、代表 Restaurant image 与 infographic composition。正式 owner-scoped analyzer、sample sufficiency、nil/empty、消费、月/年轨迹、隐私、Food/Dining semantic rules 与 Poster Preview 保持不变。

| 页面 | Legacy reference | Final candidate |
| --- | --- | --- |
| 最佳饭搭子 | [Legacy](legacy-reference-screenshots/legacy-fb127e9-companion-analysis-1280x720.png) | [Final](visual-approval/round-2/formal/analytics-companion-legacy-final-candidate.png) |
| 谁最会种草 | [Legacy](legacy-reference-screenshots/legacy-fb127e9-recommendation-source-analysis-1280x720.png) | [Final](visual-approval/round-2/formal/analytics-source-legacy-final-candidate.png) |
| 本月回顾 | [Legacy](legacy-reference-screenshots/legacy-fb127e9-monthly-review-analysis-1280x720.png) | [Final](visual-approval/round-2/formal/analytics-monthly-legacy-final-candidate.png) |
| 年度回顾 | [Legacy](legacy-reference-screenshots/legacy-fb127e9-annual-review-analysis-1280x720.png) | [Final](visual-approval/round-2/formal/analytics-annual-legacy-final-candidate.png) |

状态：`LAFAYETTE DIRECTION: LEGACY`；算法没有回滚，四页最终视觉区域仍待 Lafayette 确认。

### 2.5 Premium Paywall — LEGACY

正式页面恢复 Legacy 紧凑层级和已批准 Hamburger 视觉核心；StoreKit 2、server entitlement、restore、transaction updates、expiry/refund/revoke、Feature Registry 和真实 Product facts 均未改变，不含假价格或假交易。

- Legacy reference：[legacy-fb127e9-premium-paywall-1280x720.png](legacy-reference-screenshots/legacy-fb127e9-premium-paywall-1280x720.png)
- Final candidate：[premium-legacy-final-candidate.png](visual-approval/round-2/formal/premium-legacy-final-candidate.png)

状态：`LAFAYETTE DIRECTION: LEGACY`；最终视觉区域仍待确认。

### 2.6 Settings / Data — CURRENT FROZEN

Settings 正式代码未重做。当前布局只允许后续因 bug、Accessibility、Dynamic Type、localization overflow 或安全/发布问题调整。

- Current frozen：[settings-current-frozen.png](visual-approval/round-2/formal/settings-current-frozen.png)

状态：`CURRENT APPROVED / FROZEN`。

## 3. 仍是 Candidate，不是正式产品决定

### 3.1 Profile — FUSE Candidate V2

候选采用 Legacy compact dashboard topology，并完整保留 Premium、关注/粉丝、去过/想去/总消费、今天吃什么、我的口味档案、三类回味、食单、最佳饭搭子、谁最会种草、Social、Sharing 和 Settings。

- Candidate：[profile-fuse-v2.png](visual-approval/round-2/candidates/profile-fuse-v2.png)
- 已冻结：Header、Settings，均为 `KEEP LEGACY / Frozen YES`。
- Pending：Social Metrics、Main Statistics、Core Entries、Memory / 回味、Lists、Insights。

状态：`FUSE V2 — NOT YET APPROVED`。后续 V3 不得修改已冻结区域，除非 Lafayette 明确解除冻结。

### 3.2 Visit Editor — FUSE Candidate V1

候选以 Legacy 紧凑连续的单次到访日记叙事为骨架，保留 Current optional/nil、多维评分、消费、饭搭子、推荐来源、Dining Context、Dish/Photo 和正式数据架构。六个废弃字段未恢复。

- Legacy reference：[legacy-fb127e9-visit-editor-1280x720.png](legacy-reference-screenshots/legacy-fb127e9-visit-editor-1280x720.png)
- Candidate：[visit-editor-fuse-v1.png](visual-approval/round-2/candidates/visit-editor-fuse-v1.png)
- Frozen：0。
- Pending：全部区域。

状态：`FUSE V1 — NOT YET APPROVED`。

### 3.3 五类分享海报 — Redesign Candidate A / B

正式 Poster visual contract 未被候选覆盖。A 为 radial infographic family，B 为 editorial receipt family；两套均由真实 SwiftUI 9:16 renderer 产生，并使用相同 Rich Demo 语义数据。

| 海报 | Candidate A | Candidate B |
| --- | --- | --- |
| 我的口味档案 | [A](visual-approval/round-2/candidates/poster-taste-a.png) | [B](visual-approval/round-2/candidates/poster-taste-b.png) |
| 最佳饭搭子 | [A](visual-approval/round-2/candidates/poster-companion-a.png) | [B](visual-approval/round-2/candidates/poster-companion-b.png) |
| 谁最会种草 | [A](visual-approval/round-2/candidates/poster-source-a.png) | [B](visual-approval/round-2/candidates/poster-source-b.png) |
| 本月回顾 | [A](visual-approval/round-2/candidates/poster-monthly-a.png) | [B](visual-approval/round-2/candidates/poster-monthly-b.png) |
| 年度回顾 | [A](visual-approval/round-2/candidates/poster-annual-a.png) | [B](visual-approval/round-2/candidates/poster-annual-b.png) |

状态：`NEEDS REDESIGN`；等待 Lafayette 选择 A、B、继续 redesign 或按区域给出修改意见。候选不会自动写入正式 Design Rules 或正式 Poster renderer。

## 4. Round 2 视觉审批台

本地入口：`http://127.0.0.1:8765/full-layout-parity/visual-approval/index.html#top`

文件入口：[visual-approval/index.html](visual-approval/index.html)

审批台已验证：

- 9 个独立审批项目均正常渲染。
- 真实 Reference / Current / Final / Candidate 图片可横向比较和全屏放大。
- Profile 正确显示 FUSE V2、2 个冻结区域与 6 个 Pending 区域。
- Visit 正确显示 FUSE V1，全部区域 Pending。
- Dish/Public/Lists/Analytics/Premium 顶层 Direction 锁定为 Legacy，但没有自动批准区域。
- Settings 顶层 Direction 锁定为 Current，10 个区域 Frozen，显示 `APPROVED FINAL`。
- Poster 仍为 `Needs redesign`，允许 Lafayette 选择 A/B，不预先代选。
- “复制审批摘要”会输出页面级方向、Candidate Version、区域来源、冻结状态与 Notes。

## 5. 自动化与构建证据

### 正式分支

- iOS full unit/integration：`629 tests / 64 suites / 0 failures`。
- 包含 F1-C4 exact duplicate Visit regression：通过。
- 相关 UI E2E：9 条关键路径通过，包括 Dish/Photo、Public Profile/Community、Lists、Analytics × 4、Premium 与 Settings。
- Debug Simulator build：通过。
- Release Simulator build：通过。

### Candidate 分支

- Debug Simulator build：通过；候选已在固定 Simulator 真实渲染并截图。
- Release Simulator build：通过。
- Release 主 App 与 Share Extension binary scan：未发现 `FuseVisualCandidate`、`fuse-candidate`、`FUSE V2`、候选 gallery 或 poster candidate 标识。
- Candidate gallery 与启动入口均受严格 `#if DEBUG` 保护；Release 产品行为仍进入正式 `ContentView`。

## 6. 下一轮只需 Lafayette 做的视觉选择

1. Profile：只审批 6 个 Pending 区域；Header 与 Settings 已冻结。
2. Visit Editor：逐区选择 KEEP CURRENT / KEEP LEGACY / KEEP FUSE / CHANGE / NEEDS REDESIGN。
3. Dish / Photo、Public Profile、Lists、Analytics × 4、Premium：查看 Legacy vs Final screenshot，确认各区域是否可冻结。
4. Posters：分别比较五类 A/B，选择方向或标记需要继续 redesign。
5. Settings：无需重新审批，保持 Current Frozen。

任何 `PENDING / Frozen NO` 都未被本报告视为 Lafayette 最终批准。
