# Taste Map｜Full Product Parity Module 4 验收报告

日期：2026-08-31

分支：`fix/full-product-parity-restoration`

模块：Profile / My、Public Profile、Premium 历史汉堡资产

结论：**PASS（Restaurant Detail 跨入口统一仍归 Module 5）**

## 1. Scope

本模块只处理：

- 本人 Profile 的信息架构、真实统计口径与页面密度；
- Public Profile 的身份区、关系动作、公开统计和内容入口拓扑；
- 已经确认过的 Premium hamburger 资产恢复；
- 与上述界面直接相关的 Accessibility 与 UI regression。

没有修改 SwiftData schema、认证、Sync、Worker、D1、StoreKit 交易语义或 Production。

## 2. Step A｜功能与数据语义

在布局修改前，先核对了现有数据来源，最终采用以下合同：

| 用户可见项 | 数据来源 | 口径 |
| --- | --- | --- |
| 关注 | `ProfileSocialStatisticsLoader` → 当前 Taste Map user 隔离的 Social API / cache | 当前用户正在关注的人数 |
| 被关注 | 同上 | 正在关注当前用户的人数 |
| 去过 | 当前用户拥有、未删除、状态为 `visited` 的 `Restaurant` | Restaurant 维度，不用 Visit 次数冒充餐厅数 |
| 想去 | 当前用户拥有、未删除、状态为 `wantToGo` 的 `Restaurant` | Restaurant 维度 |
| 总消费 | 当前用户拥有且未删除的 `Visit.myActualSpend` | 只累计非 `nil` 实际消费；没有数据时显示 `—`，不生成假金额 |
| Public Profile 去过 / 公开记录 | Social profile context 的公开统计 projection | 只展示服务端允许公开的聚合，不读取对方私有 SwiftData |

结论：本轮不需要新增 API、数据库字段或同步 mutation；问题是 presentation topology 与数据标签错位，不是数据模型缺失。

## 3. Step B｜布局与交互还原

### 3.1 本人 Profile

Web / 已确认方向：头像、用户名、加入时间、编辑资料和 Premium 同属紧凑身份区；关注 / 被关注紧邻身份信息；业务统计为去过 / 想去 / 总消费；今天吃什么与我的口味档案并排；回味为三项同组；我的食单和发现与洞察保持后续层级。

iOS before：身份卡和统计卡较高；社交统计在独立大卡；顶部业务统计仍包含到访次数和平均评分；主要入口、回味卡高度偏大，首屏密度低。

iOS after：

- 身份区收紧为 64pt 头像 + 两行以内用户名 + 单行 bio + 城市 / 加入时间；
- 编辑资料与 Premium 保持身份区操作；
- 关注 / 被关注进入身份区底部同一级，好友和找人使用语义清楚的 icon-only action，并提供完整 VoiceOver label；
- 顶部业务统计固定为去过 / 想去 / 总消费，并分别使用同组语义 icon；
- 今天吃什么 / 我的口味档案恢复横向紧凑主入口关系；
- 本月回顾 / 年度回顾 / 那年今日保持同一「回味」组；
- 我的食单继续使用紧凑行，Settings 仍是次级入口；
- 页面继续复用现有 Auth、Profile、Premium、Social 和 Navigation flow，没有复制 service。

### 3.2 Public Profile

Web / 已确认方向：紧凑头像和个人信息、关系动作、横向公开统计、公开记录 / 想吃、公开食单。

iOS before：头像和文字纵向居中；好友 / 关注 / 粉丝被拆成大统计卡；内容起点较低。

iOS after：

- 改为 80pt 头像与名称 / 城市 / bio 的紧凑横排 header；
- 好友与关注动作紧接身份区；
- 关注 / 被关注 / 去过 / 公开记录形成等宽横向 metric strip；
- 数据尚未返回时固定保留结构并诚实显示 `—`，避免异步加载造成页面跳动，也不伪造数字；
- 公开记录 / 想吃和公开食单继续复用原有 API、缓存、visibility 与用户隔离逻辑。

Public Profile 内点击 remote Restaurant 仍会在 Module 5 接入全局唯一 Restaurant Detail 主体；本模块没有提前复制或重写详情页。

## 4. Premium hamburger 恢复

Premium badge 使用仓库 Web 正式历史资产的同一几何与配色重新落为 SwiftUI `Canvas`：

- 24 × 24 viewBox；
- 上层面包、绿色夹层、肉饼、底层面包和三颗芝麻；
- 使用 Web 来源的 bun / green / patty fill 与 stroke；
- `PremiumBurgerAssetContract.semanticVersion = web-approved-hamburger-v1`；
- Profile Premium 状态入口仍复用唯一 `PremiumBurgerBadge`。

它没有被纳入或覆盖未来的 `FoodDiningVisualLibrary`，符合“Premium 历史汉堡是单独锁定资产”的 Design Override。

## 5. Icon / Label 规则

- 城市元数据使用 `building.2`，没有错误使用 GPS / current-location 图标；
- 去过 / 想去 / 总消费作为同一统计组全部带语义 icon；
- 关注 / 被关注作为同一连接组全部带语义 icon；
- 好友 / 找人属于高频、紧凑系统动作，使用 icon-only，但有完整 VoiceOver label 和 36pt 可点击区域；
- 没有用无业务语义的 Food 图案冒充统计结论。

## 6. Visual evidence

| 状态 | 证据 |
| --- | --- |
| Web reference | [web-profile-before.jpg](full-product-parity-assets/web-profile-before.jpg) |
| iOS before | [ios-profile-before.png](full-product-parity-assets/ios-profile-before.png) |
| iOS after — Light | [ios-profile-after-module-4.png](full-product-parity-assets/ios-profile-after-module-4.png) |
| iOS after — Dark | [ios-profile-after-module-4-dark.png](full-product-parity-assets/ios-profile-after-module-4-dark.png) |
| Public Profile after | [ios-public-profile-after-module-4.png](full-product-parity-assets/ios-public-profile-after-module-4.png) |
| Premium historical hamburger in Profile | [ios-premium-approved-hamburger-module-4.png](full-product-parity-assets/ios-premium-approved-hamburger-module-4.png) |
| Premium paywall regression | [ios-premium-paywall-module-4.png](full-product-parity-assets/ios-premium-paywall-module-4.png) |

## 7. Layout contract result

| Check | Web / locked contract | iOS before | iOS after | Result |
| --- | --- | --- | --- | --- |
| Identity topology | 横向头像与资料 | 大卡、信息与社交分散 | compact identity + connections | PASS |
| Social metrics | 关注 / 被关注靠近身份 | 独立完整社交管理卡 | 身份区同级 metric/action | PASS |
| Business statistics | 去过 / 想去 / 总消费 | 去过 / 到访 / 平均分 / 消费 | 三列同级真实口径 | PASS |
| Primary actions | 两项并排 | 并排但卡片过高 | 74pt 紧凑横向卡 | PASS |
| Memories | 三项同组 | 同组但过高 | 78pt 紧凑三列 | PASS |
| Lists hierarchy | 主要内容之后、Settings 次级 | 首屏被大卡挤压 | 高密度 row hierarchy | PASS |
| Public Profile | compact header + metrics | 纵向大头像和拆散统计 | 横排 header + 4-column metrics | PASS |
| Accessibility | 独立可读 action | 父 identifier 会覆盖子 action | 子按钮独立 identifier / label | PASS |
| Light / Dark | 两种外观可读 | 未形成本轮证据 | 两种 Simulator 截图通过 | PASS |

## 8. Tests

### Unit / integration

以下定向 suites 全部通过：

- `P3AProfileTests`
- `ProfileListsMemoriesParityTests`
- `CoreProductLayoutParityTests`
- `P3DCommunityTests`
- `P3ESocialHardeningTests`
- `P4HPremiumEntitlementTests`

### UI E2E

以下路径全部通过：

- `testCoreProductLayoutParityMapDiscoveryProfileEvidence`
- `testCoreProductLayoutParityDarkDiscoveryAndProfile`
- `testP3AProfileEditAndRestartPersistence`
- `testP3DCommunityFeedOpensPublicProfileRestaurantAndSupportsExplicitWantToGo`
- `testP4HFreeProfilePaywallFeatureGateAndDevelopmentUpgrade`
- `testCoreProductParityPremiumProfileUsesApprovedHamburgerBadge`
- iPhone 17e 小屏上的 `testCoreProductLayoutParityMapDiscoveryProfileEvidence`

首次 UI run 暴露并修复了父 accessibility identifier 覆盖内部按钮的问题；失败没有通过删除业务断言或放宽布局要求解决。公开统计的异步空缺也改为稳定、诚实的 `—`。

## 9. Builds

- Debug iOS Simulator build：PASS
- Release iOS Simulator build：PASS
- 唯一 warning：既有 AppIntents metadata extraction skipped；本模块未引入新 warning。

## 10. Files changed

- `ios/TasteMap/TasteMap/Features/Profile/ProfileView.swift`
- `ios/TasteMap/TasteMap/Features/Profile/SocialViews.swift`
- `ios/TasteMap/TasteMap/Features/Premium/PremiumViews.swift`
- `ios/TasteMap/TasteMapTests/P4HPremiumEntitlementTests.swift`
- `ios/TasteMap/TasteMapUITests/TasteMapUITests.swift`
- `TasteMap_FULL_PRODUCT_PARITY_AUDIT.md`
- 本报告与 `reports/full-product-parity-assets/` 中的 Module 4 截图证据

## 11. Safety boundaries

- SwiftData schema：未修改
- Worker / D1 / migration：未修改
- Sync / Auth：未修改
- StoreKit transaction / entitlement state machine：未修改
- Production：未访问
- `pnpm-workspace.yaml`：未纳入提交

## 12. Remaining gaps

1. Public Profile / Community 中的 remote Restaurant 仍需在 Module 5 接入全局唯一 Restaurant Detail；这不是 Profile layout 的遗留副本。
2. Public fixture 无在线统计响应时截图显示 `—`，这是诚实的缓存/网络状态；真实服务返回后会更新正式计数。
3. `FoodDiningVisualLibrary` 与 Core App 装饰系统仍属于后续独立模块；本轮没有为了填满页面擅自引入新图案。
4. App Store Connect 的真实 Premium 产品配置仍是 Release Gate，本轮没有伪造 Product ID 或价格。
