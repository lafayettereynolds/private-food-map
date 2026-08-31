# Taste Map｜Full Product Parity Closure Report

验收日期：2026-08-31  
执行分支：`fix/full-product-parity-restoration`  
审计基线：`main@510f3b4e72fce785154ab5517e79a6f78d11092c`  
最终功能基线：`facdbe4cba1637f8cd13c567fe56254207c2c3a4`（Module 8）  
Module 9：本报告与最终 UI regression 修订所在的 `Document full product parity closure` commit  
Production：未访问、未部署、未迁移、未写入  

## 1. 最终结论

**Product Parity：PASS。**

本结论同时要求并已经验证：

- Web 正式功能语义没有被 SwiftUI 页面布局重新解释；
- Map、List、Add Restaurant、Nearby、Discovery、Community、Profile、Public Profile、Restaurant Detail、Roulette、Analytics 与 Share Poster 的核心结构按最新 Source of Truth 收口；
- Activity rating、Restaurant aggregate rating、Profile 统计、Nearby query center、Roulette candidate pool、Analytics nullable 数据等关键口径没有只改文案或换皮；
- 本地与远程 Restaurant 详情使用同一个标准主体，不再按入口维护相似页面；
- Food & Dining Visual Language 有统一组件、稳定映射和 Decorative / Data-linked 边界；
- 五类 Analytics 页面和五类独立 9:16 海报恢复已认可的 Analysis Theme，不是普通报表或页面截图；
- 全量 Web/Worker 与 iOS unit、关键 UI E2E、Debug/Release/device build 均通过。

本报告的 PASS **不等同于 App Store 发布完成**。真实 StoreKit 商品、Production 部署和最终硬件 smoke 仍在第 15 节单独列出。F1-C4 重复 Visit 风险已经由 Release Candidate 阶段的精确 fixture regression 覆盖，并在最终组合代码上再次通过，现已正式关闭。

## 2. Module 与 Git 追溯

| 阶段 | Commit | 内容 | 状态 |
| --- | --- | --- | --- |
| Audit | `0327b2a` | Audit full Web iOS product parity | PASS / historical baseline |
| Module 1 | `fc9442e` | Restore Map List filter product parity | PASS / pushed |
| Visual contracts | `105f0d9` | Expand product parity visual contracts | PASS / pushed |
| Module 2 | `b92b6cb` | Restore restaurant acquisition parity | PASS / pushed |
| Overrides | `608fd8d` | Integrate final product parity overrides | PASS / pushed |
| Module 3 | `ad83c7d` | Restore Discovery and Community parity | PASS / pushed |
| Naming | `ca5db8e` | Update analytics feature names | PASS / pushed |
| Module 4 | `80b20a2` | Restore Profile and Public Profile parity | PASS / pushed |
| Module 5 | `4ca5ca9` | Unify global Restaurant Detail | PASS / pushed |
| Module 6 | `26add07` | Restore approved Roulette experience | PASS / pushed |
| Module 7 | `4b1ae8b` | Restore Analytics and poster product parity | PASS / pushed |
| Module 8 | `facdbe4` | Close remaining product parity gaps | PASS / pushed |
| Module 9 | 本报告所在 commit | Document full product parity closure | PASS；最终 SHA 见交付回执 / `git log -1` |

各模块独立报告：

1. [Module 1｜Map / List / Filters](reports/FULL_PRODUCT_PARITY_MODULE_1_MAP_LIST.md)
2. [Module 2｜Add Restaurant / Nearby / GPS](reports/FULL_PRODUCT_PARITY_MODULE_2_ADD_RESTAURANT_NEARBY.md)
3. [Module 3｜Discovery / Community](reports/FULL_PRODUCT_PARITY_MODULE_3_DISCOVERY_COMMUNITY.md)
4. [Module 4｜Profile / Public Profile / Premium badge](reports/FULL_PRODUCT_PARITY_MODULE_4_PROFILE_PUBLIC_PROFILE.md)
5. [Module 5｜Global Restaurant Detail](reports/FULL_PRODUCT_PARITY_MODULE_5_GLOBAL_RESTAURANT_DETAIL.md)
6. [Module 6｜Roulette / 今天吃什么](reports/FULL_PRODUCT_PARITY_MODULE_6_ROULETTE.md)
7. [Module 7｜Analytics / Share Posters](reports/FULL_PRODUCT_PARITY_MODULE_7_ANALYTICS.md)
8. [Module 8｜Remaining Core / Food & Dining](reports/FULL_PRODUCT_PARITY_MODULE_8_REMAINING_CORE.md)

## 3. 最终页面 Closure Matrix

| 页面 / 能力 | 功能语义 | 布局 / 交互 | 复用 / 数据边界 | 最终状态 |
| --- | --- | --- | --- | --- |
| Map | 当前用户 Restaurant + Visit 投影；去过/想吃/适合你共用同一 browse state | 顶部留白、居中「我的地图」、icon-only 地图/列表、独立 scope、单排横滑 compact chips | Map/List 共用 snapshot、filter、sort、query | PASS |
| List | 与 Map 同一结果集合；搜索/筛选不会重建业务数据 | 高密度标题、数量、搜索、compact rows、独立快捷动作 | 行点击详情；再次记录/想吃/抽签不误触详情 | PASS |
| Map Marker / Cluster | 近距 Restaurant 独立；极远才聚合 | Restaurant marker 或 Food/Dining visual + auxiliary count；不再纯数字气泡 | stable seed；默认 Decorative，不伪造菜系 | PASS |
| Add Restaurant | Search、City、Apple Maps、AMap、URL/分享文本、Nearby、Manual | 入口顺序和密度按 Web 收口；显式 WantToGo / Visited 确认 | 同一 acquisition flow、provider-neutral identity、dedupe | PASS |
| Nearby / GPS | fresh CLLocation、时间/精度校验、Reduced Accuracy 诚实状态、3 km、距离排序 | 当前定位状态与结果距离可读；失败/空态/重试不无限 loading | 不使用 city center / stale camera center 冒充 GPS | PASS（最终真机同坐标 smoke 见 Gate） |
| Visit | Restaurant context 必填，其余可选；rating 未操作保持 `nil` | 新增/编辑共用分组编辑器；保存始终 local-first | 单一 `VisitEditorView` / `VisitDraft`；照片失败不阻塞核心记录 | PASS |
| Dish | Visit 独立菜品、复用历史、nullable 数据 | 管理与展示层级保留 | Visit/Dish/VisitDish 单一 domain | PASS |
| Photo | local-first、上传重试、公开范围与用户实拍 | picker、状态、gallery、缺图诚实 fallback | PhotoAsset / transfer coordinator 单一链路 | PASS |
| Discovery | 关注/为你推荐/同味之选/最新/趋势五个一级 Tab | 居中标题、五项等宽、城市/筛选 compact | 每 Tab 使用正式数据源；无错误中间层 | PASS |
| Community | Activity 自己的 optional rating、互动与公开边界 | 与 Discovery 同层，卡片密度和 action token 统一 | Activity rating 不再用 Restaurant aggregate 冒充 | PASS |
| Profile / My | 当前用户身份、关注/被关注、去过/想去/总消费真实口径 | compact header、横排统计、主入口并排、回味/食单/洞察分组 | owner-scoped projection；Settings 是次级入口 | PASS |
| Public Profile | 可见性与关系决定公开内容 | compact identity/stat topology、关系动作、公开记录/食单 | 不读取私有 Visit/消费；Restaurant 进入统一详情 | PASS |
| Lists / Rankings | 本人和公开食单的排序、visibility、备注与 Restaurant identity | 紧凑列表和餐饮 fallback | local/public 权限分离，详情主体共享 | PASS |
| Social | 搜索、好友/关注、请求与隐私边界 | 原生导航差异保留，正式入口顺序不重组产品 | 单一 social services / viewer-scoped cache | PASS |
| Settings | Account、Data & Backup、Sync、Privacy、Permissions、Storage、Premium、Help、About | 原生设置 IA；不暴露假死按钮 | 不复制 Auth/Sync/Backup/StoreKit service | PASS |
| Premium | Entitlement 决定 Free/Premium；无产品不显示假价格 | 已认可 Hamburger badge 统一复用 | 不由 FoodDiningVisualLibrary 重绘；StoreKit 真实配置仍是 Release Gate | PASS（Development-safe） |
| Roulette | 候选集合、Wheel segments、抽取结果为同一真实 Restaurant pool | 已认可 Wheel、固定指针、中心 CTA、结果/重抽/详情 | 不复制 Restaurant、不 placeholder、不按评分暗中加权 | PASS |
| On This Day | 当前用户历史日期范围内的真实 Visit/Restaurant | 回忆分组、详情、独立海报 | owner-scoped，餐厅进入统一详情 | PASS |
| Analytics | 五类 analyzer 使用真实 owner-scoped domain 数据 | 独立 Analysis Theme、Food Hero、四周故事模块、代表餐厅图文 | 页面与海报共享 model/token，不复制业务计算 | PASS |
| Public Share | 只读 allowlisted projection、visibility fail closed | Restaurant share 进入标准详情主体 | 浏览不会静默创建本地 Restaurant/Visit | PASS（Production domain 仍是 Gate） |

## 4. Map / List Before → After

### Web reference

![Web Map reference](reports/full-product-parity-assets/web-map-before.jpg)

![Web List reference](reports/full-product-parity-assets/web-list-before.jpg)

### iOS before

![iOS Map before](reports/full-product-parity-assets/ios-map-before.png)

![iOS List before](reports/full-product-parity-assets/ios-list-before.png)

### iOS final

![iOS Map after](reports/full-product-parity-assets/ios-map-after-module-8.png)

![iOS List after](reports/full-product-parity-assets/ios-list-after-module-8.png)

![iOS far-map Food Dining cluster](reports/full-product-parity-assets/ios-map-far-cluster-after-module-8.png)

最终合同：

- 顶部保留明确呼吸空间，标题为「我的地图」；
- 地图 / 列表是同层 icon-only 模式控制，并有 VoiceOver label/value；
- 去过 / 想吃 / 适合你独立成层；
- 所有主要 Filter Chips 统一使用真实语义 icon + 短文字/当前值；城市使用城市/建筑语义，不使用 GPS；
- 正常和近距离 Restaurant 优先独立 Marker；只有极远距离使用餐饮 visual + count；
- 添加餐厅、定位、Tab Bar、Marker 与模式控制没有互相遮挡；
- 最终 header 处于 App 高度上方 30% 以内，Map 仍是第一屏主视觉。

## 5. Add Restaurant / Nearby Before → After

![Web Add Restaurant reference](reports/full-product-parity-assets/web-add-restaurant-before.jpg)

![iOS Add Restaurant before](reports/full-product-parity-assets/ios-add-restaurant-before.png)

![iOS Add Restaurant after](reports/full-product-parity-assets/ios-add-restaurant-after-module-2.png)

功能链路没有只改 UI：

`CLLocationManager → permission / accuracy → fresh CLLocation → provider query center → 3 km results → CLLocation.distance → ascending sort → explicit selection`。

Apple Maps-only Restaurant 继续使用 Taste Map UUID + provider identity，不依赖 `amapPoiId`。Nearby 选择后必须显式确认“我想去”或“我去过”；浏览和搜索不会静默写入记录。

## 6. Discovery / Community Before → After

![Web Discovery reference](reports/full-product-parity-assets/web-discovery-before.jpg)

![iOS Discovery before](reports/full-product-parity-assets/ios-discovery-before.png)

![iOS Discovery after](reports/full-product-parity-assets/ios-discovery-after-module-3.png)

![iOS Discovery dark](reports/full-product-parity-assets/ios-discovery-after-module-3-dark.png)

![iOS Community after](reports/full-product-parity-assets/ios-community-after-module-3.png)

最终一级导航固定为：

1. 关注
2. 为你推荐
3. 同味之选
4. 最新
5. 趋势

没有恢复“发现餐厅 / 社区动态”中间层。每条 Activity 卡片只显示自己的 optional Visit rating；Restaurant-level 我的/全部/好友/同味评分只在统一 Restaurant Detail 中按真实样本显示。

## 7. Profile / Public Profile Before → After

![Web Profile reference](reports/full-product-parity-assets/web-profile-before.jpg)

![iOS Profile before](reports/full-product-parity-assets/ios-profile-before.png)

![iOS Profile after](reports/full-product-parity-assets/ios-profile-after-module-4.png)

![iOS Profile dark](reports/full-product-parity-assets/ios-profile-after-module-4-dark.png)

![iOS Public Profile after](reports/full-product-parity-assets/ios-public-profile-after-module-4.png)

本人 Profile 最终拓扑：

- compact avatar / identity / join information / edit / Premium；
- 关注 / 被关注；
- 去过 / 想去 / 总消费；
- 今天吃什么 + 我的口味档案并排；
- 回味：本月回顾 / 年度回顾 / 那年今日；
- 我的食单；
- 发现与洞察：最佳饭搭子 / 谁最会种草等正式入口；
- Settings 保持次级工具入口。

Public Profile 继续只展示 viewer 有权读取的公开投影，不因复用本人视觉组件而泄露私有消费、备注或未公开到访。

Premium 历史 Hamburger 证据：

![Approved Premium hamburger](reports/full-product-parity-assets/ios-premium-approved-hamburger-module-4.png)

![Premium paywall](reports/full-product-parity-assets/ios-premium-paywall-module-4.png)

## 8. Global Restaurant Detail Single Source

### Before / reference / after

![Web Restaurant Detail reference](reports/full-product-parity-assets/web-restaurant-detail-before.jpg)

![iOS Restaurant Detail before](reports/full-product-parity-assets/ios-restaurant-detail-before.png)

![iOS local Restaurant Detail top after](reports/full-product-parity-assets/ios-restaurant-detail-local-top-after-module-5.png)

![iOS local Restaurant Detail after](reports/full-product-parity-assets/ios-restaurant-detail-local-after-module-5.png)

![iOS remote Restaurant Detail after](reports/full-product-parity-assets/ios-restaurant-detail-remote-after-module-5.png)

![iOS Restaurant Detail final regression](reports/full-product-parity-assets/ios-restaurant-detail-regression-module-8.png)

### 唯一主体

所有本地和远程入口最终进入 `RestaurantDetailStandardBody`。`RestaurantDetailEntrySource` 只影响 navigation / dismiss / analytics / back behavior，不决定主体 UI。

标准 section 顺序：

1. Cover / Hero
2. 城市 / 状态 / 名称 / 地址
3. Actions
4. 参考人均 / 电话 / 营业时间
5. 到这里去
6. 我的 / 全部用户 / 好友 / 同味评分（仅真实值与正样本）
7. 用户实拍
8. 我的到访概览
9. 到访历史
10. 菜品、体验、多维评分等扩展记录

评分规则继续是：大圆表示评分，小圆表示样本数；`nil` / 无样本不显示假 0 分。

### 跨入口验证矩阵

| 入口 | Source | Standard Body | 结果 |
| --- | --- | --- | --- |
| Map | `.map` | `RestaurantDetailStandardBody` | PASS |
| List / 去过 / 想吃 | `.list` | 同一主体 | PASS |
| Search / Nearby saved result | `.search` / `.nearby` | 同一主体 | PASS |
| Discovery local | `.discovery` | 同一主体 | PASS |
| Discovery remote | `.discovery` | 同一主体 + remote projection | PASS |
| Community | `.community` | 同一主体 | PASS |
| Other User / Public Profile | `.publicProfile` | 同一主体 | PASS |
| 最佳饭搭子 | `.analysis` | 同一主体 | PASS |
| 谁最会种草 | `.analysis` | 同一主体 | PASS |
| 本月 / 年度回顾 | `.analysis` | 同一主体 | PASS |
| Lists / Rankings | `.restaurantList` | 同一主体 | PASS |
| On This Day | `.onThisDay` | 同一主体 | PASS |
| Roulette | `.roulette` | 同一主体 | PASS |
| Public share link | `.share` | 同一主体 + public allowlist | PASS |

远程详情打开本身不会创建本地 Restaurant；只有用户显式选择想吃、到访、食单或抽签操作才进入已有 action/acquisition flow。

## 9. Roulette / 今天吃什么

![Web Roulette reference](reports/full-product-parity-assets/web-roulette-reference-module-6.png)

![iOS Roulette before](reports/full-product-parity-assets/ios-roulette-before-module-6.png)

![iOS Roulette after](reports/full-product-parity-assets/ios-roulette-after-module-6.png)

![iOS Roulette large dataset](reports/full-product-parity-assets/ios-roulette-large-after-module-6.png)

最终 active pool 最多显示 10 家真实 Restaurant；每家在 Wheel 中恰好一个具名 segment，抽取结果来自相同集合。120/1000 家源数据会先形成可解释候选池，而不是复制餐厅、增加 placeholder 或让 Wheel 与结果集合分离。评分不参与隐藏加权。

## 10. Analytics｜独立 Analysis Theme 与真实数据

Analytics 是本次完整模块，不以“有数字、有图表、能 Share”判定通过。

### 10.1 数据维度

| 分析 | 真实输入与核心维度 | 空值 / 门槛 |
| --- | --- | --- |
| 我的口味档案 | 菜系偏好、价位、氛围、来源、饭搭子、评分风格、回头率、关键词、时间、消费、代表餐厅图文 | `nil` rating/spend 不当作 0；证据不足显示形成中 |
| 最佳饭搭子 | companion identity、共同到访、餐厅、食物、最近时间、关系关键词、代表餐厅、下次建议 | 重名不合并；私人备注不出海报 |
| 谁最会种草 | 来源使用次数、distinct Restaurant、平均分、最靠谱、最坑推荐来源、证据餐厅 | 达不到样本门槛不生成“最坑”假结论 |
| 本月回顾 | 自然月 Visit、餐厅、新店、消费、最爱/最常去、饭搭子、来源、口味变化、代表餐厅 | 跨月数据不混入；无值诚实省略 |
| 年度回顾 | 自然年统计、月度高光、味觉轨迹、关键词、代表餐厅 | 只用选定年度 owner-scoped 数据 |

### 10.2 视觉合同

- Analysis Theme 与 Core App Theme 分离；
- 暖白 canvas、灰蓝品牌色与少量食材色只用于分析/海报，不把整个 Core App 变暖黄；
- 中心 Food Hero 优先来自真实照片、高频菜系或代表 Dish；
- 四周使用 connector、callout、标签和故事模块；
- 有数据关系时才 Data-linked；证据不足的组合餐桌明确属于 Decorative；
- 页面用于阅读和交互，9:16 Poster 是独立 `ImageRenderer` 内容，不是当前屏幕截图；
- 五类页面和五类海报共享 analysis model、tokens 与 visual library，但各自保留适合内容的排版。

### 10.3 页面与海报 Before → After

| 类型 | Before | After |
| --- | --- | --- |
| 我的口味档案 | [before](reports/full-product-parity-assets/ios-taste-profile-before-module-7.png) | [after](reports/full-product-parity-assets/ios-taste-profile-after-module-7.png) |
| 我的口味档案海报 | [before](reports/full-product-parity-assets/ios-taste-profile-poster-before-module-7.png) | [after](reports/full-product-parity-assets/ios-taste-profile-poster-after-module-7.png) |
| 最佳饭搭子 | [before](reports/full-product-parity-assets/ios-companion-before-module-7.png) | [after](reports/full-product-parity-assets/ios-companion-after-module-7.png) |
| 最佳饭搭子海报 | [before](reports/full-product-parity-assets/ios-companion-poster-before-module-7.png) | [after](reports/full-product-parity-assets/ios-companion-poster-after-module-7.png) |
| 谁最会种草 | [before](reports/full-product-parity-assets/ios-source-before-module-7.png) | [after](reports/full-product-parity-assets/ios-source-after-module-7.png) |
| 谁最会种草海报 | [before](reports/full-product-parity-assets/ios-source-poster-before-module-7.png) | [after](reports/full-product-parity-assets/ios-source-poster-after-module-7.png) |
| 本月回顾 | [before](reports/full-product-parity-assets/ios-monthly-before-module-7.png) | [after](reports/full-product-parity-assets/ios-monthly-after-module-7.png) |
| 本月回顾海报 | [before](reports/full-product-parity-assets/ios-monthly-poster-before-module-7.png) | [after](reports/full-product-parity-assets/ios-monthly-poster-after-module-7.png) |
| 年度回顾 | [before](reports/full-product-parity-assets/ios-annual-before-module-7.png) | [after](reports/full-product-parity-assets/ios-annual-after-module-7.png) |
| 年度回顾海报 | [before](reports/full-product-parity-assets/ios-annual-poster-before-module-7.png) | [after](reports/full-product-parity-assets/ios-annual-poster-after-module-7.png) |

历史恢复依据为 `codex/taste-analysis-visuals@e855f6f`，包括六组已认可 Food Hero assets；本轮优先复用，没有凭感觉设计第三套。

## 11. Food & Dining Visual Language

唯一入口为 `FoodDiningVisualLibrary` / `FoodDiningVisualIcon`，统一 size、stroke、container、padding、light/dark 和 accessibility 行为。

### Decorative 示例

| 场景 | 视觉 | 语义边界 |
| --- | --- | --- |
| 极远地图 cluster | dining / drink / tableware / menu / takeaway / receipt + count | 默认只强化美食地图识别，不声称 cluster 菜系 |
| Map / Lists / Profile 空态或无图 | stable generic dining visual | 不冒充真实照片或用户偏好 |
| Discovery / Community 缺图 | dining fallback | Activity 文案和评分仍来自真实 feed |
| 数据不足的分享海报 | mixed dining composition | 明确为视觉故事，不伪造用户结论 |

### Data-linked 示例

| 场景 | 视觉 | 真实依据 |
| --- | --- | --- |
| 高频日料口味档案 | sushi Food Hero | analyzer 的高频 cuisine / dish / representative Restaurant |
| 高频火锅烧烤 | hotpot / grill Hero | 同上 |
| 消费分析 | receipt | owner-scoped non-nil spend aggregation |
| 最佳饭搭子 | shared meal / tableware | Visit 的真实 companion relation |
| 谁最会种草 | menu / receipt / source flow | Visit 的真实 recommendation source identity |
| 月/年 Food Hero | photo 或 cuisine-aware hero | 当期真实 Photo / Dish / Restaurant evidence |

同一场景使用 stable semantic ID / stable seed，不会因 View re-render 随机跳图。Decorative visual 对 VoiceOver 隐藏；Data-linked visual 提供实际语义 label。Premium Hamburger 是独立历史 asset，不被该 library 覆盖。

## 12. Icon / Label 一致性

- 同级 Map Filter Chips 全部使用语义 icon + 短文字/当前值，没有只给“城市”加 icon；
- 城市使用 `building.2` 等城市语义；真实 current location 才使用定位 icon；
- 评分、消费、到访次数、饭搭子、来源、排序分别使用稳定语义；
- 返回、搜索、分享、定位、地图/列表等高度熟悉系统操作可 icon-only，但有 accessibility label；
- 没有为了装饰把随机 Food icon 放进交互控件，也没有用 icon 冒充数据结论。

## 13. 自动化与 Build

### Web / Worker

| 验收 | 结果 |
| --- | --- |
| Full Vitest | **49 files / 342 tests passed** |
| App TypeScript `tsc -b` | PASS |
| Worker TypeScript `tsc -p tsconfig.worker.json --noEmit` | PASS |
| Vite production build | **1691 modules transformed; PASS in 1.18 s** |

Vite 保留既有 `733.77 kB` minified chunk-size提示；它不是本轮引入的编译错误，也没有为了 Closure 擅自重构 bundle architecture。

### iOS unit / integration

| 验收 | 结果 |
| --- | --- |
| Full `TasteMapTests` | **581 tests / 57 suites passed in 55.204 s** |
| Module 8 focused suite | **151 tests / 17 suites passed** |
| Map/List, identity, acquisition, location, Activity rating, Restaurant Detail, Analytics, public share, ownership and sync regressions | PASS |

### 关键 Simulator UI E2E

最终八条路径全部 PASS：

1. `testCoreProductLayoutParityMapDiscoveryProfileEvidence`
2. `testRestaurantAcquisitionNearbyRequiresExplicitWantToGoAction`
3. `testDiscoveryAndCommunityCardsUseConcreteVisitRating`
4. `testF3ARestaurantDetailMetadataEditAndVisitRefresh`
5. `testP4GRouletteFilterSpinResultDetailRerollAndOfflineRestart`
6. `testP4ATasteProfilePageAndIndependentPoster`
7. `testF1B3SettingsFoundationNavigationAndBackupPrivacyFlow`
8. `testF7AProfileOnThisDayHistoricalRestaurantAndBack`

首轮综合执行中 6 条直接通过；两条历史测试断言与最终 UI contract/lazy accessibility 行为冲突。修订后定向复验通过：

- Map 综合断言从废止的 24% header 上限改为最终已锁定、同文件 light/dark tests 共用的 30% 上限；实测约 26.5%，仍保留 Map 第一屏面积约束；
- Restaurant Detail 对地址/电话改为重新打开 editor 读取持久化值，并分别向顶部/底部滚动验证 lazy body 的“去过”Badge与到访次数；业务断言没有删除或改成只检查提示文案。

额外视觉回归：

- iPhone 17 Pro Max light：PASS；
- iPhone 17 Pro Max dark：PASS；
- iPhone 17e small screen dark：PASS；
- 极远 Food/Dining cluster：PASS；
- 近距独立 marker：PASS。

### Build

| Build | 结果 |
| --- | --- |
| Debug / iPhone 17 Pro Max Simulator | PASS |
| Release / iPhone 17 Pro Max Simulator | PASS |
| Release / generic iOS device / `CODE_SIGNING_ALLOWED=NO` | PASS |

generic device build 只验证 device SDK 编译，没有修改 Team、Bundle ID、Automatic Signing 或 Capability，也没有伪报真机安装。

## 14. 安全边界与未改内容

- Bundle Identifier：未修改；
- Apple Developer Team / Signing / Capabilities：未修改；
- App Icon：未修改；
- SwiftData schema：未修改；
- Auth / Sign in with Apple / Keychain：未修改；
- SyncEngine / cursor / mutation queue / conflict policy：未修改；
- Worker / D1 / migration / R2：本分支无业务修改；
- Production Worker / D1 / R2 / secrets / migration：未访问；
- Google Drive：未恢复；
- 六个已废弃 Visit 字段：未恢复；
- Restore / Legacy Claim：未实现或伪装完成；
- 未跟踪 `pnpm-workspace.yaml`：保留原状，未提交。

## 15. Remaining Gaps / Release Gates

以下项目不会把本轮 Product Parity 判回 FAIL，但在正式发布前必须继续管理，且本报告没有伪报完成。

### 15.1 F1-C4 repeated-import integrity（CLOSED）

- 精确自动化用例 `repeatedLegacyManualMergeIsIdempotent()` 已存在于 `BackupImportMergeEngineTests`，覆盖 Legacy v4 首次导入、第二次相同来源、cross-provider Restaurant candidate、manual merge、dependent Visit re-resolve、`exactDuplicate`、第二次写入为 0、额外 mutation 为 0。
- 最终组合代码上已分别通过该 targeted regression 和 581-test 串行 iOS unit/integration 全集。
- 因此不再把 duplicate Visit 列为 known blocker，也不要求用真实用户备份进行危险的第二次 Import；未来仍由隔离 fixture regression 持续防回归。

### 15.2 App Store Connect / StoreKit gate

- 正式 Product IDs；
- Subscription Group；
- App Store Connect IAP API key / Issuer ID / Key ID / `.p8` 的安全注入；
- Sandbox / TestFlight purchase、restore、expiry、refund、revoke 与服务端 entitlement 验收；
- 真实本地化价格和周期。

当前 StoreKit architecture、local configuration、purchase/restore/transaction/entitlement tests 已存在；没有假正式 Product ID 或硬编码价格。

### 15.3 Production gate

- Production Worker / D1 / R2 只读 preflight、备份、migration 与部署必须另行获得明确授权；
- Production API base URL / public share origin；
- AASA / Associated Domain / Universal Link；
- 正式 Privacy / Terms / Support URLs 与 App Review metadata；
- Production secrets 不得进入客户端或 Git。

本轮完全未触碰 Production。

### 15.4 Final real-device smoke

建议在最新分支合并/安装后做一次最小人工验收：

1. 同一真实 GPS 坐标下 Nearby query center、最近餐厅和距离排序；
2. Map/List/Filter chips/cluster 的真机 safe area 与触摸；
3. Roulette 动画、触觉、Reduce Motion；
4. 五类海报真实保存与系统 Share Sheet；
5. Dark Mode、Dynamic Type、长用户名、无头像；
6. Public Universal Link（仅正式 domain 配置完成后）；
7. StoreKit Sandbox/TestFlight（仅正式商品配置完成后）。

### 15.5 Account deletion说明

当前主线的 Release Readiness 报告记录账户删除后端闭环已经实现；本 Product Parity 分支没有修改它，也没有执行不可逆真实账户删除。最终发布验收仍应按照专用 release checklist 做 re-auth、session revoke、retention 与真实账号人工 smoke，不能由本报告代替。

## 16. 最终判定

| 判定范围 | 结论 |
| --- | --- |
| Web → iOS 功能语义 | PASS |
| 核心页面结构 / 层级 / 交互 | PASS |
| Map / Discovery / Profile latest overrides | PASS |
| Global Restaurant Detail single source | PASS |
| Food & Dining Visual Language | PASS |
| Analytics pages + five independent share posters | PASS |
| Automated tests and builds | PASS |
| Production readiness | PENDING EXPLICIT RELEASE GATES |
| App Store sale readiness | PENDING APP STORE CONNECT / SANDBOX / TESTFLIGHT |
| F1-C4 repeated-import integrity | PASS / CLOSED BY EXACT AUTOMATED REGRESSION |

**结论：Full Product Parity Restoration 可以正式关闭；F1-C4 duplicate Visit 已关闭。不要自动开始 Production 或 App Store 发布。**
