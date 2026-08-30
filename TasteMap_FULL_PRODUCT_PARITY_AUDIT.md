# Taste Map｜Full Product Parity Audit

审计日期：2026-08-30  
审计基线：`main@510f3b4e72fce785154ab5517e79a6f78d11092c`  
执行分支：`fix/full-product-parity-restoration`  
审计对象：当前 React/Web 移动端与当前原生 iOS / SwiftUI App  
审计标准：功能、交互、布局、页面结构、数据语义和组件复用必须同时成立；仅“能打开”或“已有类似功能”不算通过。

## 0. Source-of-truth amendment｜2026-08-30

Lafayette 在修复执行期确认了更晚的产品决定。以下决定覆盖本报告初版中冲突的局部结论，并直接进入对应模块的验收合同：

1. Map 顶部需要明确留白与标题「我的地图」；标题下使用紧凑的图标式「地图 / 列表」切换。旧结论中“只能使用右下浮动 Map/List 切换”的限制已废止。
2. Map 的去过 / 想吃 / 适合你状态、筛选结果与 Map/List 必须继续共享同一个 projection；横向 compact chips 保留。
3. Discovery 标题「发现」居中；关注 / 为你推荐 / 同味之选 / 最新 / 趋势等宽分布；筛选与 Map 使用同源视觉和交互 token。
4. Profile 身份区展示关注 / 被关注；顶部业务统计改为去过 / 想去 / 总消费。统计必须复用真实 Web 口径对应的数据来源，不允许只替换标题。
5. 自本修订起，每个页面先完成 Step A（Web 功能语义、数据来源、入口与状态审计），再完成 Step B（SwiftUI 布局/交互还原）。功能搬错按 parity bug 修复，不归为视觉差异。
6. Analytics 是独立完整模块：口味档案、饭搭子、推荐来源、本月回顾、年度回顾及各自竖版分享海报必须恢复已经确认的 Analysis Theme。仅有普通卡片、统计列表或图表不算通过；先检查 Git 历史/现有分支中的既有实现并优先复用，不得凭感觉设计第三套。
7. 全 App 建立统一 `Food & Dining Visual Language`：Food、Drink、Tableware、Receipt、Menu、Takeaway 与 Generic Dining 使用同一资产/组件系统。Core App 中只作为克制的辅助视觉；Analytics / Poster 中可以更突出。任何视觉必须标明是 Decorative 还是 Data-linked，后者只能来自真实数据。Premium 历史汉堡资产不受该系统覆盖。

该修订不会创建第二套 Map、Discovery 或 Profile；现有正式页面就地收口。

## 1. Executive conclusion

当前 iOS 已经具备很完整的数据和业务能力，Map、Discovery、Profile 也在前一轮修复中恢复了大部分顶层信息架构，但仍未达到本轮定义的 Product Parity。

最重要的结论：

1. **Map 数据与筛选结构基本正确，但顶部产品结构需按最新决定重排**：去过 / 想吃 / 适合你和横向 compact chips 已存在；需要新增「我的地图」标题与图标式 Map/List 切换，并移除旧右下模式切换。
2. **List 仍缺 Web 的高信息密度结构**：Web 有标题/数量、搜索、筛选、每行三类快捷动作；iOS 当前只有紧凑餐厅行，没有同级快捷动作与列表上下文摘要。
3. **Discovery 一级导航已恢复正确**：关注 / 为你推荐 / 同味之选 / 最新 / 趋势均为同一级；没有错误的“发现餐厅 / 社区动态”中间层。但城市/筛选控件和内容卡仍比 Web 更大、更卡片化。
4. **Profile 分组拓扑已恢复，但密度和统计语义仍不一致**：Web 头部统计是关注、粉丝、去过、想吃；iOS 当前头部统计是去过、到访、平均分、消费，社交统计被移出同级关系。iOS 头像头部、统计和入口卡高度也明显更大。
5. **Add Restaurant 的功能入口顺序已接近 Web，但 iOS 组件尺寸显著偏大**。Nearby 的 fresh-location 校验、3 km query、`CLLocation.distance` 排序已在代码中存在；真实 GPS 结果仍需用同一坐标做最终真机验收，不能只凭 fixture 宣称通过。
6. **Restaurant Detail 是当前唯一 S0 结构问题**：
   - 本地 Restaurant 使用 `RestaurantDetailView`；
   - Discovery / Community / Public Profile / Public List 在餐厅尚未成为本地记录时，使用 `DiscoveryRestaurantDestination` 内另一套手写详情主体；
   - 因此同一家餐厅会因入口和本地状态不同看到不同主体。
7. **本地 Restaurant Detail 自身顺序也不符合 Web 标准**：当前 iOS 是 Hero → Header → 评分参考 → Actions → Business Info；Web 和本轮锁定标准是 Hero → 城市/状态/名称/地址 → Actions → 人均/电话/营业时间/路线 → 评分参考 → 用户实拍 → 我的到访概览 → 到访历史。
8. Visit、Dish、Photo、Settings、Premium、分析页与回顾页的业务闭环基本存在；主要剩余工作是页面密度、入口一致性和统一 Restaurant Detail，而不是重做 P0–P4 数据架构。
9. 当前 Core App 仍缺少一套稳定、可识别且不制造假数据语义的 Food & Dining Visual Library。Map 远距离 cluster 需要由“纯数字圆点”升级为稳定 Food/Dining visual + count；近距离 Restaurant 仍优先独立 Marker。空态、Profile、Lists、Roulette 等只在合适位置使用 Decorative visual，Analytics 才优先使用真实数据驱动的 Food Hero。

## 2. Evidence and method

本报告不是沿用旧 Feature Parity 报告的状态结论，而是基于以下当前证据重新判断：

- 实际启动当前 Web Vite mobile view（430 × 932），Development seed 共 76 家餐厅；
- 实际读取 Web DOM 语义结构并操作 Map、List、Discovery、Profile、Add Restaurant、Restaurant Detail；
- 在 iPhone 17 Pro Max Simulator 上运行当前 `main` 的 UI fixtures；
- 当前 iOS UI test：`testCoreProductLayoutParityMapDiscoveryProfileEvidence` 通过；
- 当前 iOS UI test：`testRestaurantAcquisitionNearbyRequiresExplicitWantToGoAction` 通过；
- 当前 iOS UI test：`testTask04CoreLayoutParityEvidence` 通过；
- 逐项扫描 `src/`、`ios/TasteMap/TasteMap/Features/`、导航入口、sheet、NavigationLink 与所有 Restaurant Detail 入口。

代表性证据：

| 页面 | Web reference | iOS current / before |
| --- | --- | --- |
| Map | [web-map-before.jpg](reports/full-product-parity-assets/web-map-before.jpg) | [ios-map-before.png](reports/full-product-parity-assets/ios-map-before.png) |
| List | [web-list-before.jpg](reports/full-product-parity-assets/web-list-before.jpg) | [ios-list-before.png](reports/full-product-parity-assets/ios-list-before.png) |
| Add Restaurant / Nearby | [web-add-restaurant-before.jpg](reports/full-product-parity-assets/web-add-restaurant-before.jpg) | [ios-add-restaurant-before.png](reports/full-product-parity-assets/ios-add-restaurant-before.png) |
| Discovery | [web-discovery-before.jpg](reports/full-product-parity-assets/web-discovery-before.jpg) | [ios-discovery-before.png](reports/full-product-parity-assets/ios-discovery-before.png) |
| Profile | [web-profile-before.jpg](reports/full-product-parity-assets/web-profile-before.jpg) | [ios-profile-before.png](reports/full-product-parity-assets/ios-profile-before.png) |
| Restaurant Detail | [web-restaurant-detail-before.jpg](reports/full-product-parity-assets/web-restaurant-detail-before.jpg) | [ios-restaurant-detail-before.png](reports/full-product-parity-assets/ios-restaurant-detail-before.png) |

限制说明：本地 Web 没有注入高德 Key，因此 Web Map 背景显示配置态；这不影响页面层级、控件位置、List/Profile/Detail 结构的审计。Discovery 的真实 Development API 在本地 Web 返回 500，因此该页数据卡细节同时以当前组件源码和 iOS deterministic fixture 校验，不能把本地 500 误判成 iOS 缺失。

## 3. Severity definition

| Severity | 含义 |
| --- | --- |
| S0 | 入口导致不同业务主体、数据/身份语义或核心页面结构不一致；必须重构后才能关闭 parity |
| S1 | 页面核心信息架构、同级关系或关键交互形式错误；必须在本轮修复 |
| S2 | 核心功能存在，但密度、位置、卡片尺寸、空态或局部交互与 Web 不一致；本轮调整 |
| S3 | 平台允许差异或仅需补充验证；不应重写架构 |

## 4. Full page audit matrix

| 页面 / 模块 | Web structure | iOS current structure | Missing / misplaced / interaction gap | Reuse problem | Severity | Disposition |
| --- | --- | --- | --- | --- | --- | --- |
| Map | 品牌头；去过/想吃/推荐；地图主体；筛选；底部添加餐厅；最新产品决定要求「我的地图」与图标式模式切换 | 去过/想吃/适合你；单排 chips；地图主体；右下查看列表；底部添加餐厅 | 需加入顶部留白和「我的地图」，把模式切换迁到标题下的紧凑图标组；保证 chips、active count、安全区和小屏 | Map/List 已共用 filter state | S1 | 按执行期最新决定重排现有唯一 Map 页面，不创建第二套页面 |
| Personal List | MY TASTE MAP 标题、总数、分类计数、搜索、筛选、紧凑行、每行记录/想吃/抽签动作 | 顶部分类 + 搜索/chips + 紧凑餐厅行；浮动查看地图 | 缺列表上下文标题/数量；行内快捷动作缺失；地址/到访/评分虽有但层级不同 | 与 Map 共用数据，但行组件未复用 Web quick-action semantics | S1 | 重构 List header/row；使用标题下同一模式切换，不保留重复浮动切换 |
| Map filters | Web 入口打开完整筛选，当前产品决定要求单排 compact chips + More | 已有城市/评分/消费/到访次数/饭搭子等横向 chips 和完整 sheet | 需核对菜系/更多、active 文案、计数、横向可达性；当前视觉 pill 偏高 | `PersonalRestaurantFilterState` 为单一状态，正确 | S2 | 调整 chip token 和覆盖测试，不改筛选引擎 |
| Add Restaurant | 搜索餐厅 → 城市 → 搜索；粘贴链接；Nearby；Manual | 同一能力顺序，但以多个超大卡片/按钮纵向堆叠 | 首屏只能看到搜索、链接和一条 Nearby；信息密度低于 Web；确认页另起一步可接受 | 同一 `AddRestaurantView`，无第二套 acquisition | S2 | 压缩 section/header/row；保留显式确认 |
| Nearby / GPS | 当前 GPS → 3 km provider query → 距离排序 → 紧凑结果 | fresh CLLocation validator、精度/时间校验、3 km filter、`CLLocation.distance`、foreground refresh | fixture 147 m 通过，但真实同坐标 provider 结果尚无本轮证据；Reduced Accuracy 必须诚实显示 | query center 已集中在 ViewModel | S1 | 不重写定位；新增同坐标与 stale/reduced/foreground regression，最终真机一次验收 |
| Restaurant Search | Web 高德名称+城市；链接解析；无结果/错误 | Apple Maps 搜索 + AMap/link Worker；无结果/错误/重试 | provider 结果可不同；页面密度不同但功能语义完整 | acquisition flow 统一 | S3 | 仅布局收口与回归 |
| Restaurant Detail — local | Hero；城市/状态；名称；地址；动作；人均/电话/营业时间/路线；四类评分；用户实拍；我的概览；历史 | Hero；Header；评分；Actions；Business；Stats；Dish；Experience；Detailed Rating；Location；History | 顺序错误；首屏评分与动作卡过大；用户实拍没有作为固定独立段落；基础信息未在评分前完整呈现 | local 主体集中在 `RestaurantDetailView` | S0 | 重新编排唯一详情 shell 和 section 顺序 |
| Restaurant Detail — remote/public | 与 local 同一主体；无我的私有记录时显示安全空态；用户显式保存后才创建本地数据 | `DiscoveryRestaurantDestination` 另写图片/名称/地址/推荐理由/说明/快捷动作，省略标准主体 | 同餐厅因是否已本地保存而出现两套详情；缺标准基础信息、四类评分、用户实拍 | **严重重复主体**；Public List/Profile/Community 复用的是错误的 remote wrapper | S0 | 让 remote projection 进入同一个 `RestaurantDetailView`；entry source 只管关闭/analytics/返回 |
| Visit create/edit | Web modal：餐厅、日期、评分、丰富上下文、Dish/Photo、保存 | SwiftUI editor：同字段、local-first、nullable、分组/Disclosure | 字段闭环完整；部分 section 顺序与 Web 不完全一致；系统 keyboard/sheet 差异允许 | create/edit 共用 `VisitEditorView` | S2 | 调整 section order/labels；不改模型或保存语义 |
| Dish | Visit 内 Dish editor；可复用历史菜品、价格/评分/备注/图 | Dish manager sheet + reuse presentation | 功能完整；卡片密度和操作按钮层级需视觉核对 | 本地/详情统计共用 Dish model | S3 | 只做剩余布局与入口验证 |
| Photo | Visit 照片选择、排序、上传状态、实拍展示 | PhotosPicker/local-first/upload/retry/gallery | 业务完整；Restaurant Detail 中“用户实拍”的固定位置不正确 | Photo gallery 可复用，但 Detail section 编排不统一 | S1 | 详情中建立固定 User Photos section；不改上传架构 |
| Discovery shell | DISCOVER/发现/描述；城市；关注/为你推荐/同味之选/最新/趋势；筛选 | 同一五个一级 tab；城市和筛选下一行 | 顶层 parity 已恢复；iOS 城市/筛选 pill 过大，卡片起点更低 | `DiscoverHubView` 已统一入口 | S2 | 收紧 header、pill 高度和间距；保持五个一级 tab |
| For You / Same Taste / Trending | 推荐餐厅内容卡、理由、评分样本、动作、用户来源 | 大图大卡、理由/评分/动作完整 | 内容卡图片与卡高显著大于 Web mobile density；首屏仅一张卡 | Card 共用，但详情点击进入 remote duplicate | S1 | 卡片密度调整 + 唯一详情接入 |
| Community following/latest | 同一 Discovery 一级 tab 下的动态 feed；头像、餐厅、内容、照片、点赞/评论/分享/动作 | 同一一级 tab，`CommunityFeedView` feed card | 信息能力完整；卡片视觉与 Discovery cards 有割裂；点击餐厅仍走 remote duplicate | feed 与 discovery 各有卡组件，详情应共享 | S1 | 保持 feed card差异，但统一详情和共同 action tokens |
| Profile / My header | 头像、用户名、加入时间、编辑/Premium；关注、粉丝、去过、想吃同级横排 | 大导航标题；大头像卡；统计为去过、到访、平均分、消费 | 社交统计被移出同级；统计语义不一致；头部高度约为 Web 两倍 | profile summary 和 social stats 未合成 Web topology | S1 | 重构 compact header 和同级统计，不改变 auth/profile service |
| Profile primary actions | 今天吃什么 + 我的口味档案并排紧凑 | 两张大方卡并排 | 拓扑正确，尺寸/留白过大 | 已有统一 entry card | S2 | 收紧高度、icon和文案层级 |
| Profile memories | 回味：本月/年度/那年今日横向同组 | 三列同组大卡 | 拓扑正确，尺寸偏大；小屏/长文字需保证横向可读 | 共用 section | S2 | 收紧并测试 Dynamic Type |
| Profile lists / insights | 我的食单；发现与洞察；Settings 次级入口 | 我的食单/榜单/洞察/Settings 都存在，但当前截图首屏被大卡挤占 | 入口顺序基本正确；密度使发现与洞察下移过多 | 入口各自独立但无重复业务服务 | S2 | 收紧上半页并恢复 Web 一屏信息密度 |
| Public Profile | 紧凑身份头、关系动作、公开统计、公开记录/想吃、公开食单 | 大头像纵向居中、动作、2 个统计、segmented、feed/list | 信息存在但拓扑明显重新组织；restaurant click 走 remote duplicate | 使用 `SocialPublicProfileView`，与本人 Profile tokens 未共享 | S1 | 复用 compact identity/stat components；详情接唯一组件 |
| Social / Friends | 搜索、好友、请求、关注、隐私说明 | 原生 segmented destinations 与 API flow | 业务完整，NavigationStack/keyboard 为允许的平台差异 | 单一 social service | S3 | 仅核对顺序、空态、长用户名 |
| Lists | Web dashboard card/grid、封面、榜单顺序/备注/visibility | native inset grouped List + cover + item rows + sheets | 功能完整；公开/本人列表布局更系统化，信息密度和卡片结构不完全一致 | local/public 两套 list screen合理；餐厅详情不应重复 | S2 | 保留系统编辑交互；统一封面/row tokens与 Restaurant Detail 路由 |
| Roulette | 条件 → 候选 → 抽签 → 结果 → 餐厅详情 | native engine/view 同流程 | 平台动画差异允许；详情入口已 local unified | engine 单一 | S3 | 只补 cross-entry detail assertion |
| Settings | Account/Data/Sync/Privacy/Permissions/Storage/Premium/Help/About | 原生 Settings navigation | 原生 List/Form 是允许差异；真实能力与隐藏未实现入口符合要求 | services 均复用现有实现 | S3 | 不重构；做入口/返回一致性验证 |
| Premium / Paywall | Web membership presentation/paywall | StoreKit 2 abstraction + native paywall | 正式 Product ID 仍是 release gate；不是本轮 parity 代码缺口 | entitlement 单一 | S3 | 不触碰 App Store 配置；只验证 Profile/Settings入口一致 |
| On This Day | Profile 回味入口 → 记忆列表/详情/分享 | native analyzer/view/poster | 入口与能力存在 | 餐厅点击为 local detail | S3 | 增加统一详情标识断言 |
| Taste / Companion / Source / Monthly / Annual analytics | Web 统计语义与已确认的独立 Analysis Theme：中心食物、四周引导线/标签/卡片、代表餐厅图文、统一竖版海报 | native analyzers/views/posters 已存在，但必须重新确认页面和海报是否仍是已批准版本，而非普通纵向卡片/图表堆叠 | 入口存在不等于通过；需逐项验证偏好、价位、氛围、来源、饭搭子、评分、回头率、关键词、时间、消费和代表餐厅，且页面/海报共享数据语义 | 已有 Analysis design tokens、poster services 和五类 analyzer；应优先复用 Git 中正确实现，禁止创建第三套主题 | S1 | 独立 Analytics 模块完成历史实现审计、语义回归、页面/海报视觉证据；暖白食物主题不得扩散到 Core App |
| Monthly / Annual recap | 回味入口 → recap → 代表餐厅 → 海报 | native equivalent | 主要能力完整；入口/详情一致性需回归 | local detail 共用 | S3 | cross-entry contract tests |
| Share link landing | Web public route按 visibility返回公开投影 | native public landing | 外部公开 Restaurant 可能只有 remote projection；必须用统一详情主体 | 当前 landing 与 Discovery remote path边界需统一 | S1 | 接入统一 remote Restaurant Detail projection |
| Food & Dining visual language | 已确认的品牌覆盖范围包括 Map/cluster、空态、Profile、Lists、Roulette、Discovery、Community、Analytics/Poster 等；Core App 克制，Analysis 更大胆 | 目前各页面混用 SF Symbols、emoji 和局部插画，cluster 仍以纯数字为主，缺少统一分类、容器、深浅色和稳定 seed 规则 | 缺少 Decorative/Data-linked 边界；同场景图案稳定性没有合同；系统 emoji 不能作为正式资产；Premium 历史汉堡不得被覆盖 | 需要建立唯一 `FoodDiningVisualLibrary` / 等价组件，而不是页面各画一套 | S1 | 先审计现有资产与 Git 历史；建立统一 library，再以少量高价值场景接入并测试稳定性和数据真实性 |

## 5. Navigation and reusable component audit

### 5.1 Correctly shared today

- 本人 Map marker、Map list、Profile 去过/想吃、味觉足迹、Roulette、On This Day、月度/年度回顾、饭搭子与推荐来源分析中的**本地 Restaurant**，最终都调用 `RestaurantDetailView(restaurant:)`。
- `VisitEditorView` 同时负责新增和编辑，不存在第二套保存逻辑。
- Map/List 使用同一 `PersonalRestaurantFilterState` 和同一 browse snapshot。
- Auth、Sync、Backup、Premium 均使用单一 service，不应在 parity 修复中重做。

### 5.2 Duplicate or misleading reuse that must be removed

1. `DiscoveryRestaurantDestination`：local 分支调用 `RestaurantDetailView`，remote 分支自己维护另一套 Restaurant Detail 主体。
2. `CommunityFeedView`、`SocialPublicProfileView`、`RestaurantListDetailView`、`PublicRestaurantListDetailView` 都通过 `DiscoveryRestaurantDestination` 打开 remote Restaurant，因此继承上述差异。
3. `CompanionRestaurantDetailSheet` 与 `RecommendationSourceRestaurantDetailSheet` 是允许存在的**导航 wrapper**，但应只负责 close/back，不得拥有详情主体。
4. Restaurant Detail 的 section order 当前由 `RestaurantDetailView` 直接堆叠，缺少一份可测试的固定 Layout Contract。

### 5.3 Target architecture

目标不是把 remote Restaurant 偷偷保存为本地记录，而是建立一个全局唯一详情容器：

```swift
RestaurantDetailView(
    restaurant: RestaurantDetailSource,
    entrySource: RestaurantDetailEntrySource
)
```

- `RestaurantDetailSource.local(Restaurant)`：显示标准主体 + 本人的到访概览/历史/编辑能力。
- `RestaurantDetailSource.remote(RestaurantDetailRemoteProjection)`：显示同一标准主体；私有“我的记录”段落显示安全空态；只有用户点击“想吃”或“记录到访”才创建自己的本地 Restaurant。
- `entrySource` 只能影响 dismiss/back、analytics、恢复滚动/来源，不得决定 section 顺序、Hero、标题、业务信息或评分组件。

## 6. Locked Restaurant Detail layout contract

所有入口必须按以下稳定顺序渲染；可选字段没有值时隐藏该字段或显示诚实空态，但不能改变剩余 section 的相对顺序：

1. Restaurant Cover / Hero
2. 城市 / 去过或想吃状态
3. Restaurant Name
4. 地址
5. Restaurant Actions
6. 参考人均
7. 电话
8. 营业时间
9. 到这里去
10. 评分参考
11. 我的评分
12. 全部用户评分
13. 好友评分
14. 同味评分
15. 用户实拍
16. 我的到访概览
17. 到访历史
18. 菜品、体验标签、多维评分等扩展信息在基础合同之后按固定位置展示

评分视觉合同继续保持：大圆 = 评分；小圆 = 样本数。`nil` / 无样本不得显示假 0 分。

## 7. Repair plan by complete module

| 顺序 | Module | Type | Required result | Independent commit |
| ---: | --- | --- | --- | --- |
| 1 | Map + Filter + Map/List | 调整 + List重构 | 保持最新 Map topology；补 List header/数量/行快捷动作；收紧 chips；Map/List状态同源 | `Restore Map and List product parity` |
| 2 | Add Restaurant + Nearby + GPS | 调整 + regression | 压缩 IA；保持 search/link/Nearby/manual顺序；验证 fresh/stale/reduced/3km/distance/foreground | `Restore restaurant acquisition parity` |
| 3 | Discovery + Community | 调整 | 五个一级 tab不变；收紧 header/filter/card；Community仍在相同一级结构；餐厅动作统一 | `Restore Discovery and Community parity` |
| 4 | Profile / My + Public Profile | 重构布局 | compact header；关注/粉丝/去过/想吃同级；主入口/回味/食单/洞察恢复 Web密度 | `Restore Profile product parity` |
| 5 | Global Restaurant Detail | **核心重构** | local/remote使用同一主体；固定 section contract；entrySource只管导航；全部入口验证 | `Unify global Restaurant Detail` |
| 6 | Remaining core pages | 调整 | Visit section order、Lists tokens、Social/Share landing cross-entry consistency | `Close remaining core product parity gaps` |
| 7 | Food & Dining Visual Language | 视觉系统 + 有限接入 | 复用既有正确资产；统一 food/drink/tableware/receipt/menu/takeaway/generic dining；稳定 seed；Map 远距离 Food/Dining cluster；空态/Profile/Lists/Roulette 的克制 Decorative 示例 | `Establish Food and Dining visual language` |
| 8 | Analytics + Share Posters | **独立完整模块** | 先核对五类 analyzer 的统计口径，再复用已确认 Analysis Theme；动态中心 Food Hero、四周分析、代表餐厅图文、五类统一竖版海报；所有 Data-linked visual 有真实证据 | `Restore Analytics and poster product parity` |
| 9 | Closure | 验收 | 全量 tests/build；Web/iOS after screenshots；全入口 Detail contract；Food/Dining Decorative/Data-linked证据；Analytics 页面/海报证据；剩余 gap诚实列出 | `Document full product parity closure` |

## 8. Pages requiring refactor vs adjustment

### Must refactor

- Restaurant Detail local/remote source architecture and section order.
- Profile compact identity/stat topology.
- Public Profile identity/stat topology.
- Personal List header and row action structure.

### Adjust without business refactor

- Map chips height/spacing/small-screen overflow.
- Add Restaurant card/row density.
- Discovery header, city/filter controls and result card density.
- Community card tokens and actions.
- Visit section ordering、Lists rows/covers。

### Must restore as a separate visual/data module

- Taste Profile、Companion、Recommendation Source、Monthly、Annual 的统计语义、页面和分享海报。
- Food Hero 必须由高频菜系/代表餐厅/真实分析结论驱动；数据不足时才使用明确的 Decorative composition，不得伪装成用户偏好。
- 页面阅读布局与竖版海报共享 Design Tokens 和 presentation model，但不强行共享完全相同的布局。
- Core App 的 Food/Dining 装饰与 Analysis Theme 分层：前者低强度，后者可以更具故事感。

### Verify only; do not rewrite

- Auth / Sign in with Apple / Keychain.
- SyncEngine / cursor / queue / user isolation.
- SwiftData schema and current ownership model.
- Backup/Import architecture.
- StoreKit/Premium entitlement architecture.
- Worker/D1/Production.

## 9. Test contract for closure

### Map / List

- visited / wantToGo / suitable；compact horizontal chips；active count；small iPhone；dark mode；Map→List→Map；filter/sort preservation；Add Restaurant不重叠；row quick actions不误触详情。

### Add / Nearby

- fresh precise location；stale rejection；reduced accuracy honest state；future timestamp；invalid horizontal accuracy；foreground/movement refresh；same query center；3 km bound；distance ascending；provider error/empty/retry；explicit want/visit confirmation。

### Discovery / Community / Profile

- 五个一级 tab；city/filter；loading/empty/error/cache；community interaction；logged-in/logged-out；long username；missing avatar；Free/Premium；compact stats；全部入口顺序；light/dark/Dynamic Type。

### Restaurant Detail global entry matrix

必须自动验证下列入口都出现同一组 section identifiers，顺序相同：Map、List、Search/Nearby saved result、Discovery local、Discovery remote、Community、Public Profile、Companion、Recommendation Source、Monthly、Annual、Lists、Visited、WantToGo、On This Day、Roulette、Public Share。

remote detail 必须验证：浏览不会创建本地 Restaurant；显式 WantToGo/Visit 后才创建；随后重开显示同一主体且状态更新。

### Food & Dining visual language

- 近距离每家 Restaurant 优先独立 Marker；远距离 cluster 使用 Food/Dining visual + count，不能只剩纯数字圆点。
- cluster visual 根据稳定 cluster coordinate/identifier seed 选择，轻微拖动或 rerender 不应无意义跳变。
- Decorative visual 不附会数据；Data-linked visual 必须有明确 analyzer/provider 证据，并覆盖无数据/多元偏好降级。
- Light/Dark、Dynamic Type、Reduce Motion、small iPhone 下不遮挡内容、不成为无标签交互控件。
- 覆盖 Map、空态、Profile/Lists/Roulette 的代表性 Core 场景以及全部 Analytics/Poster；验收目标不是“每页都有图标”。

### Analytics and posters

- 五类 analyzer 的日期区间、nullable rating、消费、饭搭子、推荐来源、回头率、代表餐厅口径与 Web/已锁定合同一致。
- 口味档案覆盖偏好排行、价位、氛围、推荐来源、饭搭子、评分风格、回头率、关键词、用餐时间、消费和代表餐厅图文。
- Taste / Companion / Recommendation Source / Monthly / Annual 页面均有独立竖版 poster renderer，不是页面截图；共享同一 Analysis token 和 Food/Dining asset language。
- “最坑推荐来源”等已锁定产品文案不得改名；无真实数据时显示诚实空态，不生成假结论。

## 10. Safety boundary

- 本轮不修改 Production Worker、Production D1、Production R2、Production secrets 或 App Store Connect。
- 本轮不改变 Bundle ID、Team、Signing、Capabilities、SwiftData schema、Auth、Sync 或现有 ownership。
- Development Web seed 只存在于本地浏览器 IndexedDB；没有写入 Production。
- 当前已知 F1-C4 duplicate Visit Import bug 仍是独立已知问题，不在本轮借 parity 名义扩大处理。

## 11. Audit disposition

Audit 结论：**FAIL — implementation required**。

不能以当前 Map/Discovery/Profile UI tests 已通过为由关闭 Product Parity；这些测试只证明上一轮指定结构存在，无法证明全页面 Web topology、remote/local Restaurant Detail 单一主体和跨入口一致性。本报告完成后将直接进入上述模块化修复，并为每个大模块独立 commit/push。
