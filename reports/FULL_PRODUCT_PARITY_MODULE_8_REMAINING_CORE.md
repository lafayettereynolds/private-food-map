# Taste Map｜Full Product Parity Module 8：Remaining Core + Food & Dining

验收日期：2026-08-31

执行分支：`fix/full-product-parity-restoration`

模块目标：关闭剩余 Core App 产品一致性缺口，落实最新版「我的地图」层级、远近缩放 Marker 合同、公开 Restaurant 分享入口的一致详情主体，以及克制、稳定、不会制造假数据语义的 Food & Dining Visual Language。

## 1. Step A｜功能语义与数据来源审计

本模块先核对 Web 原功能和当前 iOS 数据路径，再决定是否改 UI。结论如下：

| 页面 / 能力 | Web 语义与数据来源 | iOS 审计结果 | Module 8 处理 |
| --- | --- | --- | --- |
| Map / List | 同一 Restaurant/Visit 投影、同一 scope 与 filter；模式变化不能改变业务集合 | 已共用 `RestaurantBrowseBuilder`、`PersonalRestaurantFilterState` 与查询结果；功能语义正确，最新标题/控件层级尚未落实 | 保留同一 projection，只重排成最新版四层 header，并为同级 filter 补齐一致语义 icon |
| Visit | Restaurant 上下文必填；日期、评分、备注、消费、人数、场景、排队、菜品、照片等按已确认顺序逐步记录；nullable 不伪造成默认值 | `VisitEditorView` 与 `VisitDraft` 已是一条新增/编辑保存链路，section 顺序与 Web `AddVisitModal` 对齐 | 不重排、不复制保存逻辑；由既有 Visit/Dish/Photo 回归覆盖 |
| Dish / Photo | 都属于 Visit 记录图；照片传输失败不应让 Visit 保存失败 | 单一 `VisitDraft`、Dish relation、PhotoAsset 与 local-first transfer 已存在 | 不改 schema/同步；只把缺图 fallback 接入统一视觉库 |
| Public Profile / Social | 公开范围、好友关系和 owner isolation 决定可见数据；餐厅点击应进入同一 Restaurant 主体 | Module 4/5 已修复公开资料拓扑与统一详情路由；业务服务单一 | 只统一共享用餐/内容图片的餐饮 fallback，不改社交权限或 API |
| Lists | visibility、排序、备注和列表项来自同一 list domain；餐厅点击进入统一详情 | 本人/公开列表分别保留合理权限边界，详情已进入全局标准主体 | 空封面和无图 item 使用统一餐饮 visual，不改 list model |
| Settings | 原生系统设置导航；只展示真实已实现/已配置能力 | Account/Data/Sync/Permissions/Storage/Premium/Help/About 已由单一服务提供 | 不重构，不添加假入口 |
| Premium | entitlement 与 StoreKit provider 决定状态；未配置产品不得显示假价格 | 架构和已认可 Hamburger asset 已在 Module 4 固定 | 明确排除于通用 Food & Dining 重绘之外 |
| On This Day / Analytics entries | owner-scoped Visit/Restaurant 生成回忆和分析；餐厅入口进入统一主体 | 路由、统计和海报均已存在，Module 5/7 已完成详情与 Analysis 收口 | 回归验证，不改 analyzer |
| Public Restaurant share | 匿名公开 payload 只能显示 allowlisted public projection，不得暗中创建本地 Restaurant | 原先 landing 仅用通用分享卡片，未呈现全局标准 Restaurant Detail 主体 | 改为 `RestaurantDetailStandardBody` 的 remote/read-only projection；复制名称/地址可用，私人到访/评分为空态，浏览不写 SwiftData |

## 2. Step B｜最新版 Map Layout Contract

最新版 Source of Truth 覆盖早期「右下角 Map/List 浮动按钮」决定。最终合同为：

| 项目 | Web / 最新确认 | iOS before | 修改 | iOS after | 结果 |
| --- | --- | --- | --- | --- | --- |
| Top offset | 顶部保留明显呼吸空间 | 控件密集贴顶，标题与模式/范围层级曾混在一起 | 顶部 18 pt 视觉留白；标题独立居中 | 标题上方留白清楚 | PASS |
| Title | 「我的地图」居中 | 无正式标题或标题不在独立层 | 新增居中标题与 header trait | 独立第一层 | PASS |
| Map / List | 标题下 icon-only，两项独立一组 | 与 scope 同层或旧浮动切换 | 地图/列表 icon-only control，提供 VoiceOver label/value | 独立第二层 | PASS |
| Restaurant scope | 去过 / 想吃 / 适合你等权、独立 | 与模式控制混合 | 继续使用真实同源 selection，单独一行 | 独立第三层 | PASS |
| Filters | 单排横向 compact chips；同组 icon 策略一致 | 城市有 icon、其他维度不一致 | 城市/评分/消费/到访次数/饭搭子/来源/排序全部使用短文本 + 真实语义 icon；城市使用 `building.2`，不冒充 GPS | 独立第四层，可横向滚动 | PASS |
| Map body | 仍是首页主视觉 | 顶部控制侵占感明显 | Map 继续 full-bleed；完整 header 被限制在屏幕上方 30% 内 | 地图可视内容从 header 下连续延伸到 Tab Bar | PASS |
| Add Restaurant | 底部偏中间、不遮挡 Tab Bar | 已正确 | 保留现有正式入口 | PASS | PASS |

证据：

- Web reference：[web-map-before.jpg](full-product-parity-assets/web-map-before.jpg)
- iOS before：[ios-map-before.png](full-product-parity-assets/ios-map-before.png)
- iOS Module 1 中间状态：[ios-map-after-module-1.png](full-product-parity-assets/ios-map-after-module-1.png)
- iOS Module 8 final：[ios-map-after-module-8.png](full-product-parity-assets/ios-map-after-module-8.png)
- List final：[ios-list-after-module-8.png](full-product-parity-assets/ios-list-after-module-8.png)

## 3. Map Marker / Cluster 最终合同

### 3.1 正常与近距离

- Restaurant 优先独立 Marker；
- status、照片/餐饮 fallback、到访数量和评分 accessibility 保持 Restaurant 自己的数据；
- 不因本轮视觉处理改变 Restaurant identity、选择或导航。

### 3.2 极远距离

- 只有地图 region span 达到明确 far threshold 时，annotation 才获得 clustering identifier；
- cluster 主体为 Food/Dining vector visual，数字只作为辅助 count badge；
- 不再使用纯数字圆点作为主要视觉；
- 默认 visual 是 **Decorative**，不会暗示 cluster 内存在某个特定菜系；
- visual 由排序后的稳定 Restaurant UUID seed 通过固定 FNV-1a 映射生成，重新 render 或成员顺序变化不会随机跳图；
- `NaN`/无效 span 默认关闭聚合，避免错误状态吞并 Marker。

证据：[ios-map-far-cluster-after-module-8.png](full-product-parity-assets/ios-map-far-cluster-after-module-8.png)

## 4. Food & Dining Visual Language

唯一视觉入口继续是 `FoodDiningVisualLibrary` / `FoodDiningVisualIcon`，没有按页面再创造新画风。

### 4.1 Decorative / 装饰型

| 场景 | Visual | 为什么是 Decorative |
| --- | --- | --- |
| Map 极远 cluster | generic dining / drink / tableware / menu / takeaway / receipt | 默认不把某个食物谎称为 cluster 的真实菜系 |
| Map 空状态 | generic dining | 只强化餐饮产品识别，不表达用户偏好 |
| Profile、Lists 无图封面 | stable dining visual | 代替散落 emoji，不声称真实照片或统计结论 |
| Discovery、Community 缺图 | dining fallback | 只作为内容占位，Activity 数据仍来自真实 feed |

### 4.2 Data-linked / 数据型

| 场景 | Visual | 真实语义依据 |
| --- | --- | --- |
| 评分 chip / 模块 | star | 当前控件确实表示评分条件或评分值 |
| 消费 chip / 分析 | receipt | 当前字段确实来自实际消费/价位 |
| 到访次数 | tableware / repeat visit | 真实 Visit count |
| 饭搭子 | shared meal | 真实 Companion relation |
| Restaurant 图片 fallback | Restaurant 的稳定 cuisine/marker symbol（若有） | 只在已有明确 Restaurant 语义时映射 |
| Analytics / Poster | Food Hero 与辅助 icon | 由 Module 7 analyzer 的真实 cuisine/dish/spend/companion/source evidence 决定 |

同一层级 Filter Chips 现在全部有 icon；熟悉的地图/列表系统操作使用 icon-only，但补齐 accessibility label，不重复冗余长文案。

## 5. Core App 接入范围

本模块把统一 visual 接入以下高价值场景：

- Map individual-marker fallback、empty state、far cluster；
- Profile dashboard tile / row；
- Lists empty cover / no-photo item；
- Roulette result no-photo fallback；
- Discovery card / Community feed 缺图；
- Social shared-meal row；
- Restaurant Detail hero 无图状态；
- Public Restaurant share landing。

这不是要求“每页都有食物图标”。设置、认证、权限等系统工具场景继续优先使用清晰系统语义，不为装饰强塞餐饮图案。

Premium Hamburger 没有被修改、替换或重新设计。

## 6. Public Restaurant Share 收口

公开 Restaurant share 现在从 `PublicRestaurantShareV1` 投影为 `RestaurantDetailIdentityPresentation`，并渲染全局 `RestaurantDetailStandardBody`：

1. Hero；
2. 城市/状态/名称/地址；
3. read-only 合理 actions；
4. 可公开的参考人均；
5. 评分/用户实拍/个人记录/到访历史的诚实无数据状态；
6. privacy notice。

`RestaurantDetailEntrySource.share` 只影响入口语义，不改变主体 section contract。打开分享不会创建 Restaurant、Visit 或任何本地 mutation。

详情回归截图：[ios-restaurant-detail-regression-module-8.png](full-product-parity-assets/ios-restaurant-detail-regression-module-8.png)

## 7. 自动化与构建

### Unit / integration regression

17 个相关 suites、151 tests：**PASS**。

覆盖：

- `CoreProductLayoutParityTests`
- `MapBrowsingParityTests`
- `VisitCoreFlowTests`
- `VisitDishPhotoRecordingParityTests`
- `P2ADishPhotoTests`
- `P2BPhotoFlowTests`
- `P2CDishFlowTests`
- `P2EVisitContextTests`
- `P3AProfileTests`
- `P3BSocialTests`
- `P3ESocialHardeningTests`
- `P4FRestaurantListTests`
- `SettingsFoundationTests`
- `P4HPremiumEntitlementTests`
- `OnThisDayTests`
- `Task09PublicSharingTests`
- `RestaurantDetailTests`

新增回归明确验证：

- Map header 层级顺序；
- filter icon consistency 和 City 非 GPS；
- Decorative visual 稳定 seed；
- 近距不聚合 / 远距才聚合；
- 成员顺序变化不改变 cluster visual；
- public Restaurant share 进入标准详情 projection。

### UI evidence

- `testTask04CoreLayoutParityEvidence`：PASS（iPhone 17 Pro Max）；
- `testModule8FarMapUsesFoodDiningCluster`：PASS（iPhone 17 Pro Max）；
- `testTask04DarkLayoutKeepsCompactMapControls`：PASS（小屏 iPhone 17e，Dark Mode）。

### Build

- Debug Simulator：PASS；
- Release Simulator：PASS；
- `git diff --check`：在提交前再次执行。

## 8. 安全边界

- SwiftData schema：未修改；
- Visit / Dish / Photo 数据合同：未修改；
- Worker / D1 / migration：未修改；
- Auth / SyncEngine：未修改；
- Production：未访问；
- App Icon：未修改；
- Premium Hamburger：未修改；
- Google Drive、Restore、Legacy Claim、六个废弃 Visit 字段：未恢复。

## 9. Module 8 结论

**PASS**。剩余 Core parity 已在既有页面就地收口：最新版「我的地图」四层 hierarchy 落地，所有主要 filter 使用一致语义 icon，近距独立 Marker 与极远 Food/Dining cluster 合同具备真实 UI 证据；Core App 的餐饮 fallback 进入唯一视觉库，public Restaurant share 进入全局标准详情主体。Visit/Dish/Photo/Settings/Premium 等已正确迁移的业务路径保持原实现，没有为“视觉完整”重写数据架构。
