# Taste Map 变更记录

## 2026-08-27 — P0-B2-A Development Worker / D1 真实接通

- 创建并隔离 `food-map-db-development`，在空库只读 preflight 后顺序应用 `0001`—`0016`；`0015`、`0016` 已登记且无待执行 migration，Production D1 未查询或修改。
- 部署独立 Worker `private-food-map-development`，使用 `https://api-dev.tastemap.cn` 与 Development-only test identity；缺少身份返回 401，Production 配置不能启用测试身份。
- iOS 通过打包的 `APIEnvironment.plist` 集中读取 Development URL；Production URL 仍为空，不修改 Bundle Identifier、Team、Signing 或 Capability。
- 新增真实远程验收脚本与 iOS `URLSessionSyncAPIClient` 集成测试，验证 Restaurant、Visit、Apple Maps-only identity、增量 cursor、幂等、用户隔离和 tombstone。
- 修复 Swift Visit JSON 编码：required-but-nullable 字段现在显式输出 `null`，解码时缺少这些键会失败，保持与 TypeScript 合同一致。
- 验证：Web/Worker 30 个测试文件共 175 项、P0-A/P0-B1 migration、Web/Worker typecheck、Vite build、21 项 iOS 单元测试、Simulator build 和真实 iOS → Worker → D1 → iOS 往返全部通过。

## 2026-08-27 — P0-B1 Sync API 与 iOS 离线同步基础层

- 新增 `/api/v1/sync/push`、`/api/v1/sync/pull` 和共享 Sync V1 contract；pull 使用服务端 revision cursor，push 使用 base version 和 mutation receipt。
- iOS Restaurant/Visit 增加 remote ID、soft delete、server version、last sync 与同步状态；新增持久化 `SyncMutation`、`SyncCheckpoint`、API client、queue 和 SyncEngine，所有本地写入先成功再异步上传。
- Apple Maps-only Restaurant 使用 `placeIdentities` 完整同步，不要求 `amapPoiId`；旧 Web `/api/sync` 的实际 Restaurant/Visit 更新会桥接到同一 change log。
- 新增 D1 `0016_sync_v1.sql`，只增量增加版本字段、change log、idempotency receipt 和既有记录 bootstrap；不重写 Restaurant/Visit ID 或外键。
- V1 route 的认证用户覆盖客户端 `userId`；本地测试身份仅允许 loopback，生产未显式配置认证模式时关闭，不回退为 owner。
- Production URL、Production D1 和 Apple Signing/Capability 均未修改。
- 验证：Web/Worker 30 个测试文件共 174 项测试、P0-A/P0-B1 两套 SQLite migration、Web/Worker typecheck、Vite build、iOS Simulator build 与 18 项 iOS 单元测试通过。

## 2026-08-27 — P0-A Restaurant 跨平台合同与 Provider Identity

- 新增 Restaurant JSON Contract V1、共享 JSON Schema 和 Web/iOS 共用 fixtures，明确 required、optional 与 required-but-nullable 字段；旧 Web `amapPoiId` payload 会兼容升级为显式 `amap` identity。
- 新增 Provider-neutral `placeIdentities`，支持 `amap / apple_maps / manual / other`；Taste Map `Restaurant.id` 保持独立，重复 Provider 映射不再静默选中。
- Worker 同步读写映射元数据，外部链接识别改用 Provider 映射查找；现有 `/api/sync` 继续兼容旧 Web，Apple Maps-only 写入保留到 P0-B。
- Web 与 iOS 新增集中式 Development/Production API Base URL 配置；仓库未可靠记录正式 Worker URL时保持未配置，不猜测、不在 Swift 文件散落硬编码。
- Migration：新增 `0015_restaurant_place_identities.sql`，只创建映射表/索引并回填非空高德标识；不更改 Restaurant/Visit 主键、不修改 Visit 外键、不删除或合并现有行。远程 D1 尚未应用，部署前使用只读 preflight SQL 检查空 ID、重复映射与孤立 Visit。
- 验证：Web/Worker 28 个测试文件共 158 项测试、真实 SQLite migration 测试、Web/Worker TypeScript 检查、Vite production build、iOS Simulator build 和 13 项 iOS 单元测试全部通过。

## 2026-08-26 — Premium 入口与会员状态页简化

- 免费用户的本人资料只保留轻量“开通 Premium”；会员用户移除“管理会员”，改为点击用户名旁 Burger 进入同一 Premium 页面。设置继续稳定保留“会员与订阅”。
- 同一 Premium 页面按服务端 Entitlement 切换免费销售态和已开通状态态。会员状态页只展示当前方案、来源、适用日期、可展开权益和恢复购买；仅 App Store 月度/年度订阅显示订阅管理，永久、赠送、活动和兑换码使用各自状态分支。
- 免费销售页继续只显示 StoreKit 本地化价格，年度节省比例动态计算；购买、恢复或会员状态变化后通过统一事件即时刷新，不需要重新加载页面。
- 关键文件：`src/components/ProfilePage.tsx`、`src/components/PremiumPaywall.tsx`、`src/components/SettingsModal.tsx`、`src/services/membershipPresentation.ts`、`src/services/membershipPresentation.test.ts`、`src/styles/global.css`、`docs/PREMIUM_PRODUCT.md`。
- Migration：无；本次只调整会员入口、状态呈现与前端权限刷新，没有修改字段、数据库结构或同步协议，未检查或重复执行 migration。
- 验证：会员来源分支、Profile 会员入口、StoreKit 价格/年度节省逻辑共 18 项自动测试通过；TypeScript 检查与正式构建通过。构建仅保留项目原有的大分包提示。

## 2026-08-26 — 推荐来源“最坑”结论与分享规则

- 推荐来源分析顶部扩展为“最懂我 / 最容易种草 / 最稳定 / 最坑”；“最坑”综合低分率、高分命中、复购和相对个人基线动态计算，至少需要 6 家独立有评分餐厅，10 家起进入稳定样本。没有来源达到门槛时整项隐藏。
- 同一家餐厅的多次 Visit 先汇总为一个餐厅评分样本，重复到访只提供次级信号；来源详情补充个人基线差、近期表现、真实低分餐厅与不适合菜系，支持全年、当年、当月和自定义时间范围的服务层计算。
- 分享海报同步加入符合门槛的“最坑”来源，使用轻微暖色强调；人物来源保留当前真实姓名并随改名更新，不分享账号 ID、对方私密资料、笔记或消费。新增查看、打开详情和分享事件。
- 关键文件：`src/services/recommendationSourceInsights.ts`、`src/components/ProfileAnalyticsPanels.tsx`、`src/services/analysisShare.ts`、`src/services/analysisPosterRenderer.ts`、`src/components/AnalysisShareSheet.tsx`、`src/styles/global.css`、`src/services/recommendationSourceInsights.test.ts`、`src/services/analysisShare.test.ts`。
- Migration：无；本次仅增加由现有 Restaurant / Visit / 推荐来源动态计算的派生分析与展示，没有修改字段、数据库结构或同步协议，`docs/DATA_SCHEMA.md` 未修改。
- 验证：推荐来源服务与分享共 26 项定向测试、TypeScript/Worker 类型检查和正式构建通过。

## 2026-08-26 — 移动端半星评分命中修复

- 修复手机端左右半星点击不稳定：根因是两个绝对定位半区按钮被移动端通用按钮尺寸规则放大后发生重叠；现改为每颗星一个独立 44px Pointer Events 命中区，并用当前星的边界与 `clientX` 判定左半/右半。
- 新增/编辑到访、餐厅记录与菜品星级统一复用 `StarRating`；支持 0.5—5 星、即时半星填充、键盘半星步进、清除评分与纵向页面滚动，菜品不再只支持整数星。
- 关键文件：`src/components/StarRating.tsx`、`src/components/DishEditor.tsx`、`src/utils/starRatingInteraction.ts`、`src/components/StarRating.test.tsx`、`src/styles/global.css`。
- Migration：无；本次没有修改评分字段、数据库结构或同步协议，半星仍以既有数值类型原样保存，未检查或重复执行 migration，`docs/DATA_SCHEMA.md` 未修改。
- 验证：半星坐标、键盘交互与 10 分制换算共 10 项测试、TypeScript/Worker 类型检查、ESLint 与正式构建均通过；390×844 手机视口实测点击第 4 颗星左半边得到 3.5 星 / 7.0 分，半星填充正确且评分区域纵向滑动正常。Lint 仅保留 `CommunityPage.tsx` 的既有 Hook 依赖警告，构建仅保留既有包体积提示；真实 iPhone 触控仍建议在下一次设备验收时复核一次手感。

## 2026-08-26 — “我的”页居中布局与添加好友整合

- 将本人身份区改为居中结构：添加好友与设置位于顶部两侧，头像、昵称、Premium 标识、简介或加入时间和编辑资料形成单一视觉中心；头像在桌面端适度放大，移动端保持紧凑。
- 顶部统计统一为带品牌色图标的“我关注的 / 关注我的 / 去过 / 想吃”四项等宽入口；去过和想吃继续按唯一餐厅统计，四项均可点击，极窄屏自动调整为 2×2。
- 好友推荐从“我的”首页移除，完整保留在“添加好友”统一弹层；该弹层同时提供昵称、用户名或城市搜索与好友推荐，不再需要首页折叠或“查看更多”入口。“今天吃什么 / 我的口味档案”仍保持同一行。
- 关键文件：`src/components/ProfilePage.tsx`、`src/components/FriendsPage.tsx`、`src/services/profileTopStats.ts`、`src/services/profileTopStats.test.ts`、`src/styles/global.css`。
- Migration：无；本次仅调整 UI、文案与现有入口组合，没有修改数据字段、数据库结构或同步协议。
- 验证：TypeScript 检查、22 个测试文件共 119 项测试和正式构建均通过；Development 页面实测首页布局、统一添加好友弹层与四项统计入口正常。Lint 无错误，仍只有 `CommunityPage.tsx` 的既有 Hook 依赖警告；构建保留既有大包体积提示。

## 2026-08-26 — 添加与记录餐厅统一 Plus 图标

- 新增可复用 `PlusAction`，将全局添加餐厅与已知餐厅记录到访拆成 `ADD_RESTAURANT` / `ADD_VISIT` 两个明确动作；去过的餐厅继续显示 `+`，辅助文案改为“再次记录到访”，不把按钮做成状态切换或次数徽标。
- 地图底栏、餐厅列表、发现信息流、搜索已有餐厅结果和餐厅详情统一使用相同入口；发现页餐厅快捷操作继续固定为 `+ / 想吃 / 抽签`，分享、点赞、评论和添加好友不受影响。餐厅卡片内操作会阻止事件冒泡，避免误开其他页面。
- 关键文件：`src/components/PlusAction.tsx`、`src/components/RestaurantQuickActions.tsx`、`src/components/RestaurantList.tsx`、`src/components/AddRestaurantModal.tsx`、`src/App.tsx`、`src/styles/global.css`、`src/components/RestaurantQuickActions.test.tsx`。
- Migration：无；本次仅统一 UI、入口语义和点击行为，没有修改字段、数据库结构或本地/云端同步协议，未检查或重复执行 migration，`docs/DATA_SCHEMA.md` 未修改。
- 验证：完整测试 22 个文件共 119 项、TypeScript/Worker 类型检查及正式构建全部通过；ESLint 无错误，仅保留 `CommunityPage.tsx` 既有 Hook 依赖提示和既有构建包体积提示。

## 2026-08-26 — Premium 统一会员入口与价格页

- 新增统一的 Taste Map Premium 会员页，覆盖六项核心权益、免费/Premium 对比、恢复购买、订阅管理、数据保留说明、服务条款和隐私政策；本人资料、设置及全部受限功能统一进入该页面。免费账号展示月度/年度方案；已开通账号只展示当前权益、管理订阅和恢复购买，不重复显示价格或购买按钮。
- 新增平台无关的 Membership Store Bridge：原生端从 StoreKit 返回本地化 `displayPrice`，年度节省比例只在同币种数值价格可用时计算；Web 显示“暂时无法获取订阅信息”、重试和 iPhone App 提示，不硬编码或伪造价格。
- 购买、恢复和管理订阅后统一刷新服务端 Entitlement；自定义头像、深度推荐、同味能力、高级筛选、完整口味档案、饭搭子/推荐来源分析与照片上限均复用现有会员策略。免费版每次到访最多 3 张照片，点击第 4 张的“继续添加”会直接打开统一会员页；Premium 最多 20 张，到期不会删除既有数据或历史照片。
- 关键文件：`src/components/PremiumPaywall.tsx`、`src/services/premiumPaywall.ts`、`src/services/membershipStore.ts`、`src/services/membershipService.ts`、`src/services/featurePolicy.ts`、`src/components/ProfilePage.tsx`、`src/components/SettingsModal.tsx`、`src/components/CommunityPage.tsx`、`src/components/VisitPhotoPicker.tsx`、`src/App.tsx`、`src/styles/global.css`、`docs/PREMIUM_PRODUCT.md`。
- Migration：无；本次只增加会员入口、平台购买抽象、权限接线与 UI，没有修改 IndexedDB/D1 字段、数据库结构或同步协议，未检查或重复执行 migration，`docs/DATA_SCHEMA.md` 未修改。
- 验证：TypeScript 与 Worker 类型检查、22 个测试文件共 119 项测试、正式构建全部通过；会员与非会员页面已在 Development 浏览器中分别验证，构建仅保留既有主包体积提示。
- 已知限制：iOS 端真实 StoreKit 商品、收据校验、续期和 App Store 沙盒/正式购买仍需在 Mac/Xcode 与服务端环境中完成；Web 只展示会员信息与当前资格，不提供购买。

## 2026-08-26 — Profile 信息架构去重与文案精简

- 本人主页移除固定品牌口号，改为优先显示真实个人简介；无简介时显示加入 Taste Map 的时间。顶部数据固定为“我关注的 / 关注我的 / 去过餐厅 / 想去餐厅”，不再显示“公开记录”。
- 他人主页的顶部统计统一为“关注 / 粉丝 / 去过餐厅 / 想去餐厅”，四项均可进入权限过滤后的列表；移除重复的“动态 / 想吃 / 食单 / 地图”快捷宫格，只保留一组“动态 / 口味 / 食单”导航。想去从顶部统计进入，地图收敛为“TA 去过的餐厅 · N 家”轻量入口。
- 公开内容语义明确区分：代表餐厅按 Restaurant 聚合，最近动态按 Visit 展示；共同想吃为 0 时隐藏。Worker 同时返回可见想吃、关注和粉丝摘要，陌生人、好友与本人继续使用既有可见性规则。
- 关键文件：`src/components/ProfilePage.tsx`、`src/services/profileTopStats.ts`、`src/services/publicProfile.ts`、`src/services/socialApi.ts`、`src/App.tsx`、`worker/index.ts`、`src/styles/global.css`。
- Migration：无；本次只调整 Profile 信息架构、动态选择器与现有接口响应，没有修改 IndexedDB/D1 字段、数据库结构或同步协议，未检查或重复执行 migration，`docs/DATA_SCHEMA.md` 未修改。
- 验证：完整测试 19 个文件共 112 项全部通过；TypeScript、Worker 类型检查和正式构建通过；测试环境实测本人四项统计、关注列表、公开用户单一导航、代表餐厅、轻量足迹及 Visit 动态。ESLint 无错误，仅保留 `CommunityPage.tsx` 既有依赖提示。

## 2026-08-26 — 分析页与分享海报系统

- 为完整口味档案、饭搭子分析、推荐来源分析、本月回味、年度回味和那年今日建立统一 `AnalysisShareData` 与分享入口；六类分析均可生成独立海报预览、在真实图片候选池内换图、保存 PNG 或调用系统分享。
- 新增 `AnalysisShareService`、隐私过滤、`FoodVisualResolver` 和 `AnalysisPosterRenderer`：海报固定 1080 × 1440，主图优先到访实拍与匹配的餐厅封面，同一报告稳定选图，代表餐厅的图片、名称和说明按 `restaurantId` 一一对应。
- 海报使用 Taste Map 官方北极熊汉堡图标、品牌 Token 和简洁编辑式布局，只保留 5–8 条可验证结论；不直接截取分析页，不分享邮箱、内部账号 ID、精确私人位置、未授权消费或饭搭子私密身份。
- 关键文件：`src/types/analysisShare.ts`、`src/services/analysisShare.ts`、`src/services/foodVisualResolver.ts`、`src/services/analysisPosterRenderer.ts`、`src/components/AnalysisShareSheet.tsx`、`src/components/ProfilePage.tsx`、`src/styles/global.css`、`src/services/analysisShare.test.ts`、`docs/ANALYSIS_SHARE_SYSTEM.md`。
- Migration：无；本次运行时生成分享数据和海报，没有修改 IndexedDB、D1 Schema 或同步协议，未检查或重复执行既有 migration，`docs/DATA_SCHEMA.md` 未修改。
- 验证：TypeScript 检查通过；19 个测试文件共 105 项全部通过；测试环境实测六类入口、海报预览、换图、保存图片和系统分享按钮均正常。
- 已知限制：V1 不含二维码和持久化海报缓存；浏览器不支持文件型 Web Share API 时降级为保存 PNG；iOS 原生 Renderer 与分享面板留给后续客户端实现。

## 2026-08-26 — 饭搭子头像与筛选排序修复

- 将饭搭子头像优先级、类别识别、稳定文字头像、置信度和四种列表模式统一收拢到 `companionInsights` 服务；已绑定账号使用真实头像，普通名字由稳定 companionId 生成可读头像，家人/同事/朋友等类别不再伪装成真实用户。
- “全部 / 最近 / 常一起 / 历史饭搭子”现在分别按真实共同次数、最近共同到访、频次与“至少 3 次且 90 天未共同到访”工作；搜索与当前模式组合，列表显示当前结果数量、明确选中态和对应空状态。
- 摘要、列表和详情复用同一头像与排序结果，点击不同饭搭子会重建详情，避免沿用上一个对象的数据。
- 未绑定真实账号的私人饭搭子新增轻量编辑：可修改名称、私人头像和关系备注；改名会保留原 companionId，并同步兼容已有 Visit 中的历史名称。
- Development 免费测试种子升级为 8 位饭搭子，固定覆盖高频、最近、历史、低频、已绑定账号、私人头像、稳定文字头像和类别型记录；仅重建 `food-map-dev-free` 的测试账号数据。
- 关键文件：`src/services/companionInsights.ts`、`src/services/companionInsights.test.ts`、`src/components/ProfileAnalyticsPanels.tsx`、`src/components/ProfilePage.tsx`、`src/styles/global.css`。
- Migration：无；本次没有修改字段、数据库结构或本地/云端同步协议，未重复检查或执行既有 migration，`docs/DATA_SCHEMA.md` 未修改。
- 验证：完整自动测试 18 个文件、90 项全部通过；TypeScript 与正式构建通过。Development 浏览器实测 6 位饭搭子的全部/最近/常一起/历史、搜索、头像和详情切换均正常。
- 数据：`DiningCompanion` 增加可选的 `privateAvatarData` 与 `relationshipLabel`；两者均为非索引可选属性，旧记录保持兼容，Dexie 无需升版或重建，未执行数据库迁移。类别型饭搭子仍按稳定名称词典识别。

## 2026-08-26 — “我的”页顶部信息架构优化

- 顶部四项统计统一为“我关注的 / 关注我的 / 去过餐厅 / 想去餐厅”，移除“公开记录”；去过和想去按稳定餐厅身份去重，并为四项补齐可点击列表。
- 好友推荐移动到统计下方并改为默认折叠的轻量入口，展开首屏最多显示 3 位候选并保留“查看更多”；“今天吃什么 / 我的口味档案”改为同一行等宽等高紧凑卡片，极窄屏才纵向排列。
- 新增 `profileTopStats` 统一计算个人页去过/想去的唯一餐厅，避免同一 POI 或重复本地记录造成数量虚高。
- 关键文件：`src/components/ProfilePage.tsx`、`src/services/profileTopStats.ts`、`src/services/profileTopStats.test.ts`、`src/styles/global.css`。
- Migration：无；本次仅调整 UI、统计选择器和页面交互，没有修改字段、数据库结构或同步协议，`docs/DATA_SCHEMA.md` 未修改。
- 验证：完整测试套件 18 个文件、82 项测试通过；TypeScript 与正式构建通过。构建仅保留既有主包体积提示。

## 2026-08-26 — “写下这家餐厅”页面结构强制纠错

- 将选中餐厅后的组件树固定为“返回搜索 → 餐厅摘要 → 评分参考 → 用户实拍 → 我去过/我想去 → 状态表单 → 整理与显示 → 固定底部操作栏”；餐厅摘要改为无条件渲染，模式选择器只替换其下方表单。
- 将共用摘要组件显式命名为 `RestaurantSummarySection`，保留旧名兼容导出；新增/编辑到访、餐厅编辑和地图/发现/搜索详情继续复用同一摘要。参考人均、电话和营业时间缺失时保留明确占位，不再导致两个模式顶部结构不一致。
- 关键文件：`src/components/RestaurantRecordSummary.tsx`、`src/components/RestaurantSocialStatsPanel.tsx`、`src/components/AddRestaurantModal.tsx`、`src/components/AddVisitModal.tsx`、`src/components/RestaurantEditorModal.tsx`、`src/components/RestaurantPreviewCard.tsx`。
- Migration：无；本次只纠正 UI/DOM 结构和共用组件，没有修改字段、数据库、同步协议或算法，`docs/DATA_SCHEMA.md` 未修改。
- 验证：TypeScript 与正式构建通过，17 个测试文件共 79 项测试通过；Development 实测同一肯德基 POI 在“我去过 / 我想去”之间切换，摘要、评分参考、用户实拍与固定保存栏顺序保持一致。
- 已知问题：个别 POI 源本身没有参考人均、营业时间或公开实拍时显示真实空状态；全库 lint 仍有与本次无关的既有未使用导入/参数以及 Hook 依赖警告。

## 2026-08-26 — 发现页 Restaurant 交互统一

- 将关注、为你推荐、同味之选、最新和趋势五个分栏统一为同一套餐厅交互：餐厅卡右侧固定显示“记录去过 / 想吃 / 加入抽签”，社交互动继续独立位于左侧；移除原有分栏之间不一致的详情按钮和含义模糊的加号操作。
- 新增可复用 `RestaurantQuickActions`；三项操作都阻止卡片点击冒泡，想吃与抽签即时切换状态，记录去过在当前发现上下文打开到访表单，不再强制切换地图或自动打开轮盘。
- 餐厅正文、图片和名称在当前分栏打开完整餐厅详情，用户头像和昵称只进入用户主页；关闭详情会恢复原分栏和滚动位置。公开用户的 Visit 不再被详情误显示成当前用户自己的到访历史，公开详情也不会出现当前用户专属的编辑与删除入口。
- 关键文件：`src/components/RestaurantQuickActions.tsx`、`src/components/RestaurantRecordSummary.tsx`、`src/components/RestaurantPreviewCard.tsx`、`src/components/CommunityPage.tsx`、`src/App.tsx`、`src/styles/global.css`。
- Migration：无；本次只调整 UI、交互和当前查看者状态映射，没有修改字段、数据库结构或本地/云端同步协议，`docs/DATA_SCHEMA.md` 未修改。
- 验证：17 个测试文件、79 项测试全部通过；TypeScript、Worker 类型检查与正式构建通过。构建仅保留既有主包体积提示。

## 2026-08-26 — 好友推荐折叠与会员标识优化

- 将“我的”页好友推荐从横向卡片改为可折叠纵向列表：首次默认展开，之后用 `localStorage` 记忆用户选择；展开时先显示 3 位候选并提供“查看更多”，移除原生横向滚动条。
- 推荐卡只保留头像、昵称、城市、一个真实理由、独立的“优先认识 / 推荐认识 / 可以认识”强度，以及轻量添加和隐藏操作；共同好友、已绑定饭搭子、同味相似度、共同餐厅与同城由服务层统一计算，会员身份不参与排序加权。
- Premium Burger Badge 从头像角标移到用户名右侧，改为无圆底、无外框、无文字的小型彩色 SVG；免费用户不显示标识，显示状态继续由服务端 Entitlement 决定。
- 本人和其他用户主页均显示既有账号创建月份；Development 测试种子补充 2024—2026 年稳定加入日期、免费/会员混合身份、互相关系和已绑定饭搭子场景。
- 关键文件：`worker/friendRecommendation.ts`、`worker/friendRecommendation.test.ts`、`src/services/socialApi.ts`、`src/components/PremiumBurgerBadge.tsx`、`src/components/UserAvatar.tsx`、`src/components/ProfilePage.tsx`、`src/components/CommunityPage.tsx`、`src/components/FriendsPage.tsx`、`src/components/TasteFootprints.tsx`、`src/styles/global.css`。
- Migration：无；本次复用现有 User、Friendship、Visit、DiningCompanion 和 Taste Similarity 数据，没有修改数据库字段、结构或同步协议，`docs/DATA_SCHEMA.md` 未修改。
- 验证：完整测试套件 17 个文件、79 项测试通过，TypeScript、Worker 类型检查与正式构建通过；浏览器实测会员与免费用户名标识、默认展开、折叠状态刷新保留、首屏 3 人及 390px 手机宽度无横向溢出。
- 已知限制：当前数据结构没有单独的用户屏蔽表，推荐暂以既有地图可见性作为可发现性边界；想吃记录尚无可复用的公开可见性口径，因此本轮不把共同想吃作为推荐理由。

## 2026-08-26 — 外部餐厅链接识别与 iOS 分享导入基础

- 新增统一 `ExternalRestaurantLinkResolver`，支持高德、Apple Maps、普通餐厅网页和分享文本；外部链接只产生候选和来源建议，唯一候选仍需确认，多候选必须选择，低置信度回落到现有 POI 搜索，不会自动创建、标记去过或加入想吃。
- Worker 新增受登录保护的 `/api/external-place/resolve`，加入 HTTPS、回环/内网/云元数据拦截、逐跳重定向校验、超时、响应大小和内容类型限制；查询候选时只使用当前查看者有权读取的餐厅数据。
- Web“添加餐厅”增加“粘贴餐厅链接”，识别成功后复用现有餐厅确认和记录流程；无结果、失败和不安全地址都会结束加载并给出明确提示。
- 新增 iOS Share Extension、App Group 待处理导入、不可预测 `importId` 深链、主 App 确认页与授权请求注入的 Swift 源码；Xcode Target、签名、Capability 和真机分享面板留到 Mac 按 `docs/IOS_MAC_RELEASE_CHECKLIST.md` 完成。
- 关键文件：`worker/externalRestaurantLinkResolver.ts`、`worker/externalRestaurantLinkResolver.test.ts`、`worker/index.ts`、`src/services/externalRestaurantLink.ts`、`src/components/AddRestaurantModal.tsx`、`src/styles/global.css`、`ios/`、`docs/IOS_MAC_RELEASE_CHECKLIST.md`。
- Migration：无；本次使用短期 App Group 文件和运行时解析结果，没有修改 Restaurant、Visit、IndexedDB、D1 字段或同步协议，`docs/DATA_SCHEMA.md` 未修改。
- 验证：TypeScript、6 项解析器定向测试、现有全部 76 项测试和正式构建通过；浏览器实测不安全链接即时失败、高德链接生成可确认候选且不自动保存、390px 手机视口无横向溢出。Windows 无法验证 Xcode 签名和系统分享面板，已单独列入 Mac 清单。

## 2026-08-26 — 其他用户主页与公开地图优化

- 将其他用户主页整理为身份与关系操作、公开统计、快捷入口、共同想吃、代表餐厅和公开内容分栏；零条共同想吃时不占位，口味分栏仅在样本足够时显示。
- 公开地图替换静态示意图，按可见 Visit 聚合为一店一标，支持城市数量切换并默认进入可见餐厅最多的城市；Marker 可打开带封面、菜系、价格、城市和可见到访次数的餐厅预览。
- Worker 在返回公开主页数据前执行隐私过滤：本人可见全部有效记录，已接受好友可见 `public + friends`，陌生人只可见 `public`；地图关闭、`private` 和仅好友范围均不会被前端绕过。
- 关键文件：`src/services/publicProfile.ts`、`src/services/publicProfile.test.ts`、`src/components/ProfilePage.tsx`、`src/styles/global.css`、`worker/index.ts`。
- Migration：无；本次复用现有用户、好友、Visit 和地图隐私字段，没有修改数据库结构或同步协议，`docs/DATA_SCHEMA.md` 未修改。
- 验证：全部 15 个测试文件共 70 项测试通过，TypeScript 与正式构建通过；Development 实际打开 TestUser17 主页与公开地图，验证杭州/上海城市切换、真实 Marker 和餐厅预览正常。

## 2026-08-26 — 发现页餐厅分享与公开落地页

- 将发现五栏的“转发”统一为餐厅分享：点击后优先使用系统分享，不支持时打开轻量分享弹层，提供系统分享、复制链接和公开预览；取消分享保持静默，失败时给出明确提示。
- 分享模型仅允许餐厅名称、稳定商家图、白名单菜系、可靠价格、城市/地址和达到 5 位独立用户阈值的公开评分；不会携带 Visit、用户、饭搭子、推荐证据、实际消费、Provider 标识、内部 ID 或令牌。
- 新增稳定公开地址 `/restaurant/<publicRestaurantId>?ref=discover_share` 与最小公开餐厅页；Worker 公开接口按不可预测的稳定 ID 查找餐厅，只返回安全字段，并按独立用户等权聚合公开评分。
- 移除公开分享计数；本地分析事件只记录安全的餐厅标识、发现分栏、推荐层级和分享方式，不新增持久化字段。
- 关键文件：`src/services/restaurantShare.ts`、`src/components/RestaurantShareSheet.tsx`、`src/components/PublicRestaurantPage.tsx`、`src/components/CommunityPage.tsx`、`src/main.tsx`、`worker/index.ts`、`src/styles/global.css`、`src/services/restaurantShare.test.ts`。
- Migration：无；本次没有修改数据库字段、数据结构或同步协议，`docs/DATA_SCHEMA.md` 未修改。
- 验证：全部 14 个测试文件共 62 项测试通过，TypeScript 检查和正式构建通过；正式构建仅保留既有主包体积提示。

## 2026-08-26 — 非会员完整测试数据与 Premium 汉堡 Badge

- 为独立的非会员 Development 账号加入固定种子 `TASTE_MAP_TEST_SEED = 20260826`：50 家餐厅、68 条到访、15 家想吃、10 家重复到访餐厅、6 位饭搭子、8 类推荐来源、4 个食单与 24 条食单餐厅，覆盖杭州、上海、北京和东京及约 18 个月时间范围。
- 修正免费测试数据的归属：所有餐厅、Visit、饭搭子和食单都写入 `free-tester` 对应的 `food-map-dev-free`，不再误写到会员测试账号；种子版本不变时不会重复生成，也不会触碰 Production。
- 新增统一 Premium 汉堡矢量 Badge，并接入 `UserAvatar` 与 Development 账号切换提示；免费账号不显示负向身份标签。Badge 由服务端 Entitlement 对应的 `membershipTier` 决定，会员授予、更新和撤销会触发界面立即刷新。
- 修复免费用户已拥有自定义头像或同步照片时被错误替换成预设头像的问题。
- 关键文件：`src/db/seedRestaurants.ts`、`src/db/social.ts`、`src/components/PremiumBurgerBadge.tsx`、`src/components/UserAvatar.tsx`、`src/services/membershipService.ts`、`src/App.tsx`、`src/styles/global.css`、`docs/TEST_DISCOVERY_DATA.md`。
- Migration：无；本次复用既有 Restaurant、Visit、DiningCompanion、RestaurantList、User 与 Membership 字段，没有修改数据库结构或同步协议，`docs/DATA_SCHEMA.md` 未修改。
- 验证：TypeScript、Worker 类型检查与正式构建通过。当前运行服务可正常返回；Codex 内置浏览器本轮没有可附加标签页，因此未完成自动化点击验收，需在已打开的测试版刷新后确认最终视觉。

## 2026-08-26 — 餐厅记录页统一信息摘要

- 完成：新增可复用 `RestaurantRecordSummary`，并接入餐厅详情、添加餐厅、想吃计划、新增/编辑到访和编辑餐厅；表单前统一显示商家大图、城市/状态、名称、地址、参考价格、可用联系方式、路线、评分参考与用户实拍，适用入口继续显示去过/想吃/抽签快捷操作。
- 完成：同店历史记录会合并补齐商家信息和到访实拍；没有实拍时使用正式空状态，移除“这里只需要补充”和“记录到访后会显示”等开发说明文案。
- 关键文件：`src/components/RestaurantRecordSummary.tsx`、`src/components/RestaurantPreviewCard.tsx`、`src/components/AddRestaurantModal.tsx`、`src/components/AddVisitModal.tsx`、`src/components/RestaurantEditorModal.tsx`、`src/components/RestaurantSocialStatsPanel.tsx`、`src/styles/global.css`。
- Migration：无。本次只统一展示与布局，不修改数据字段、数据库结构或同步协议。
- 验证：`pnpm run build` 通过；Development 实际打开新增到访弹层，确认统一摘要顺序和固定底部保存栏正常。
- 已知问题：构建仍有既有的 Vite 大块体积警告，不影响本次功能。

## 2026-08-26 — 回顾系统重构

- 将原有通用回顾详情拆为“本月回顾”、年度“食味年鉴”和免费的“那年今日”三种独立体验；新增照片优先的回忆卡、月度高光、年度关键餐厅、口味变化、城市足迹、饭搭子/来源洞察和有意义时才展示的同比/环比。
- 消费口径统一为 `myActualSpend`，并按记录覆盖率区分隐藏、“已记录实际消费”和“总计”；单样本、空时段与缺少图片/笔记/来源/饭搭子时均使用真实降级，不生成虚假结论。
- 权限：本月回顾和年度食味年鉴纳入 Premium，那年今日保持免费。
- 关键文件：`src/services/reviewService.ts`、`src/services/reviewService.test.ts`、`src/services/featurePolicy.ts`、`src/components/ProfilePage.tsx`、`src/styles/global.css`。
- Migration：无；本次仅重构由现有 Restaurant / Visit 动态计算的派生内容，未修改字段、数据库结构或同步协议。
- 验证：TypeScript 检查通过；15 项回顾边界测试通过，并与全部现有测试共 52 项一起通过。
- 已知限制：餐厅无实拍、稳定封面和 Provider 图时使用占位图；无可比历史时不展示同比/环比。

## 2026-08-25 — 长表单固定保存栏统一

- 新增可复用 `StickyFormActionBar`，统一提供取消、保存/保存修改、禁用、保存中和错误提示状态；操作栏固定在当前弹层或页面底部，表单内容独立滚动并预留底部安全空间。
- 已接入新增/编辑到访、添加/编辑餐厅、手动添加小店、编辑个人资料与隐私、创建食单等长表单；短搜索、评论、轮盘临时输入和即时保存字段保持原交互。
- Modal 使用可视视口高度与偏移响应手机键盘变化，底部操作栏使用安全区内边距；新增到访的可选字段不再阻止初始保存。
- 关键文件：`index.html`、`src/components/StickyFormActionBar.tsx`、`src/components/ModalShell.tsx`、`src/components/AddVisitModal.tsx`、`src/components/AddRestaurantModal.tsx`、`src/components/RestaurantEditorModal.tsx`、`src/components/ProfilePage.tsx`、`src/components/RestaurantListsPanel.tsx`、`src/styles/global.css`。
- Migration：无；本次仅调整表单交互与布局，没有修改字段、数据库结构或同步协议，`docs/DATA_SCHEMA.md` 未修改。
- 验证：37 项自动测试和正式构建通过；浏览器实测桌面长表单滚动、手机尺寸及模拟键盘压缩高度下保存栏均持续可见，表单末项不被遮挡。
- 已知限制：浏览器是否自动弹出系统输入法由设备决定；页面已跟随 `visualViewport` 更新高度，未引入平台专属键盘 API。

## 2026-08-25 — Premium“为你推荐”核心理由与操作区优化

- 将推荐适配度改为由 Recommendation Service 统一返回 `STRONG_MATCH / GOOD_MATCH / MODERATE_MATCH / EXPLORATION`，前端只展示“优先推荐 / 推荐给你 / 可以试试 / 换个口味”，匹配等级与证据置信度独立。
- 推荐理由改为默认展开的结构化证据：Premium 主卡展示 2–3 条最高价值个性依据和最多一条注意项，免费版展示 1 条基础依据；完整分析仅补充次级证据。当前城市、附近、地址和泛化高分等低价值信息不再进入主理由。
- “大家评分”与推荐适配完全分离，按独立评分用户等权聚合并显示样本置信度；1–4 人隐藏分数，5–9 人标记样本较少，10 人以上正常显示。
- 推荐卡继续按稳定优先级展示 1–3 张真实可用图片；右下操作区精简为详情、想吃、抽签三枚 44px 纯图标按钮，补齐 tooltip、可访问名称和选中状态，不再保留大号文字详情按钮。
- 关键文件：`src/types/recommendation.ts`、`src/types/domain.ts`、`src/services/recommendationService.ts`、`src/services/recommendationService.test.ts`、`src/services/recommendationAnalytics.ts`、`src/services/socialApi.ts`、`src/components/CommunityPage.tsx`、`src/styles/global.css`、`worker/index.ts`。
- Migration：无；本次只调整运行时推荐响应、服务逻辑和 UI，没有修改持久化字段、数据库结构或同步协议，`docs/DATA_SCHEMA.md` 未修改。
- 验证：Recommendation Service 的 3 项定向测试通过，TypeScript、Worker 类型检查与正式构建通过；浏览器已在桌面与 390px 手机宽度验证核心理由默认可见、至少两条会员依据以及恰好三枚图标操作。
- 已知限制：当真实数据只有 1 张可用图片时卡片只显示 1 张，不使用重复图或演示图凑满三张；正式构建仍有既有主包体积提示。

## 2026-08-25 — 餐厅详情一致性与分析页可读性修复

- 统一地图、列表、想吃、推荐、发现和食单使用的餐厅详情数据：同一家餐厅存在多份精简/完整记录时会合并全部匹配记录，不再因先命中精简记录而丢失电话、营业时间、详细地址或图片。
- 餐厅联系方式固定为“电话 / 营业时间 / 路线”三格；来源没有电话或营业时间时明确显示“暂无”，不再让整格消失，避免不同入口产生两套详情布局。
- 饭搭子分析调整为可读的宽版“关系摘要 → 搜索筛选 → 饭搭子列表”结构；推荐来源分析保持“本页结论 → 分组来源列表 → Taste Map 推荐表现 → 最近成功案例”，并提高字号、留白和桌面弹窗宽度。
- 关键文件：`src/components/RestaurantPreviewCard.tsx`、`src/components/ProfileAnalyticsPanels.tsx`、`src/components/CommunityPage.tsx`、`src/App.tsx`、`src/services/recommendations.ts`、`src/services/socialApi.ts`、`src/types/domain.ts`、`src/styles/global.css`、`worker/index.ts`。
- Migration：无；本次未修改字段、数据库结构或同步协议，未检查或重复执行 migration，`docs/DATA_SCHEMA.md` 未修改。
- 验证：TypeScript 与正式构建通过；Development 浏览器实测去过与想吃餐厅均保留三格联系方式，饭搭子分析与推荐来源分析均能打开并显示真实测试数据。
- 已知限制：POI 来源本身缺少电话或营业时间时只能显示“暂无”，不会伪造商家资料。

## 2026-08-25 — 会员与非会员双账号测试环境

- 将默认 Development 测试账号设为终身会员，开放完整推荐理由、同味之选、高级推荐筛选、完整口味档案、饭搭子分析、推荐来源分析、自定义头像及每次到访最多 20 张照片。
- 新增严格非会员测试账号与桌面一键启动文件；该账号使用独立的 `food-map-dev-free`，免费版保留基础个性化推荐，每次到访最多 3 张照片，会员专属分析使用明确权益提示。
- Worker 在 localhost 下识别受控测试身份并返回真实会员权限，线上环境不接受本地测试身份；当前会员测试版继续使用原 `food-map-dev`，Production `food-map-prod` 未修改。
- 关键文件：`src/config/appEnvironment.ts`、`src/db/social.ts`、`src/services/membershipService.ts`、`src/services/featurePolicy.ts`、`src/services/socialApi.ts`、`src/components/CommunityPage.tsx`、`src/components/ProfilePage.tsx`、`src/components/VisitPhotoPicker.tsx`、`worker/index.ts`、`scripts/start-food-map.ps1`、`启动美食地图-测试版.bat`、`启动美食地图-非会员测试版.bat`。
- Migration：无；本次复用既有会员字段与接口，只增加运行时测试身份、权限策略和独立数据库名，没有修改字段、数据库结构或同步协议，`docs/DATA_SCHEMA.md` 未修改。
- 验证：TypeScript、Worker 类型检查和正式构建通过；会员/非会员接口、推荐分层、两套启动入口及两个 URL 均通过本地测试。构建仅保留既有主包体积提示。
- 已知限制：真实订阅购买、续期和支付校验尚未接入；本轮非会员账号只用于本机 Development 权限测试。

## 2026-08-25 — 发现动态互动与食单添加收口

- 为“关注 / 为你推荐 / 同味之选 / 最新 / 趋势”的每条餐厅动态补齐点赞、评论和转发，支持点赞切换与计数、评论列表与新增；分享入口已在后续版本统一为餐厅分享，不再展示公开分享计数。刷新后本地互动状态仍会保留。
- 动态卡片保持左侧社交互动、右侧“去过 / 想吃 / 抽签”的简洁布局，没有移除原有餐厅操作。
- 食单详情补充“添加餐厅”入口，可搜索现有餐厅、排除重复项并直接加入当前食单；公开用户 ID 改为稳定的纯数字展示编码，头像在信息流与主页中保持圆形裁切。
- 关键文件：`src/components/CommunityPage.tsx`、`src/components/RestaurantListsPanel.tsx`、`src/components/ProfilePage.tsx`、`src/components/UserAvatar.tsx`、`src/utils/publicUserId.ts`、`src/styles/global.css`。
- Migration：无；本次未修改字段、数据库结构或同步协议，未检查或执行 migration，`docs/DATA_SCHEMA.md` 未修改。
- 验证：TypeScript 与正式构建通过；浏览器实测“最新”和“趋势”所有动态均显示点赞、评论、转发，点赞/评论计数可变化并在刷新后保留，控制台无错误或警告。
- 已知限制：点赞与评论状态当前只保存在本浏览器，尚未通过社交后端跨账号或跨设备同步。

## 2026-08-25 — 完整口味档案、分析页与跨城市测试数据

- 按最终参考图重构“完整口味档案”，补齐档案结论、成熟度、菜系排名、预算分布、体验加减分项、用餐场景、到店/外卖、复购、常回餐厅、近期变化、打分风格、推荐来源和更多数据入口，并完成桌面三栏、平板双栏和手机单栏适配。
- 饭搭子分析完善为关系摘要、筛选列表和单人洞察；推荐来源分析完善为本页结论、按人/平台/Taste Map/自己发现分组的来源列表、系统推荐表现和最近成功案例，均继续使用现有真实统计服务与餐厅证据。
- Development 本地种子新增上海、北京、广州、深圳、成都、南京、苏州和香港 8 个城市共 16 家已到访测试餐厅；浏览器实测当前测试账号“去过”由杭州 61 家扩展为 77 家，Production 数据未写入、清理或重命名。
- “写下这家餐厅”的去过与想吃状态统一复用完整商家信息区，补齐参考价格、路线、去过/想吃/抽签、四项评分参考和用户实拍；想吃分支仅保留精简计划，去过分支继续使用完整 Visit 表单，上传本次照片后会立即回显到实拍区。
- 关键文件：`src/db/seedRestaurants.ts`、`src/components/ProfileAnalyticsPanels.tsx`、`src/components/ProfilePage.tsx`、`src/components/AddRestaurantModal.tsx`、`src/styles/global.css`。
- Migration：无；本次未修改字段、数据库结构或同步协议，未执行或重复检查既有 migration，`docs/DATA_SCHEMA.md` 未修改。
- 验证：正式构建通过；浏览器实测地图 77 家跨城市数据、完整口味档案、饭搭子总览与详情、推荐来源分析，以及添加餐厅的去过/想吃公共信息区、四列评分和各自分支表单均正常。构建仅保留既有主包体积提示。

## 2026-08-25 — 公开用户主页重构与发现返回定位

- 按参考结构重构他人公开主页，补齐身份资料、关注与加好友、四项公开统计、动态/想吃/食单/地图快捷入口、共同想吃、代表餐厅，以及动态/食单/口味三个公开模块。
- 他人主页只展示允许公开的内容，不复用本人页面中的月度回顾、年度回顾和私有分析。
- 修复从“发现”各分栏进入用户主页后的定位问题：主页总是从顶部打开，返回时恢复原分栏及进入前的滚动位置。
- 关键文件：`src/App.tsx`、`src/components/ProfilePage.tsx`、`src/services/socialApi.ts`、`src/styles/global.css`。
- Migration：无；本次仅调整 UI、关系操作与页面导航状态，未修改字段、数据库结构或同步协议，`docs/DATA_SCHEMA.md` 未修改。
- 验证：正式构建通过；浏览器实测从“同味之选”滚动位置进入公开主页后返回，仍停留在“同味之选”并恢复原位置。

## 2026-08-25 — 测试个人数据隔离与添加餐厅详情头部统一

- 将 Development 的个人 D1 同步与公开 Social API 拆分：测试版不再自动把云端公共/模拟餐厅拉进当前用户的个人清单，同时“发现”仍可正常读取公开测试内容。
- 个人餐厅和 Visit 查询统一限定当前用户；对测试环境中遗留的“外地、标记去过但没有当前用户 Visit”的旧模拟行仅从个人去过视图排除，不删除本地数据、不影响杭州真实/测试记录，也不影响外地想吃。
- “写下这家餐厅”的 POI 头部改为与餐厅详情一致的大图信息结构，集中显示商家图片、城市/状态、店名、详细地址、电话与营业时间，原有去过/想吃及完整记录表单保持不变。
- 关键文件：`src/config/appEnvironment.ts`、`src/services/socialApi.ts`、`src/services/restaurantStats.ts`、`src/services/recommendationAnalytics.ts`、`src/App.tsx`、`src/components/AddRestaurantModal.tsx`、`src/styles/global.css`、`scripts/start-food-map.ps1`。
- Migration：无；未修改字段或数据库结构，未清空、重建或迁移 Production 数据库。
- 验证：正式构建通过；浏览器实测个人去过为杭州 61 家，发现页公开推荐卡正常加载；添加餐厅选中 POI 后已显示统一详情式头部。

## 2026-08-25 — “我的”页面视觉与信息架构重构

- 按确认的个人主页参考重构“我的”页：顶部集中添加好友、设置、头像、资料、ID、编辑入口和四项可点击统计。
- 将“今天吃什么”升级为首屏主入口，口味档案改为暖色重点卡片；回味改为三张紧凑主题卡，并重新组织“我的食单”“发现与洞察”和分组设置。
- 食单卡片改为标题与数量在上、餐厅封面在下；饭搭子分析与推荐来源分析改为两张带图标的低饱和入口卡。
- 补充桌面端与手机端响应式布局，保持现有主色、导航与所有原有点击能力。
- 关键文件：`src/components/ProfilePage.tsx`、`src/components/RestaurantListsPanel.tsx`、`src/styles/global.css`。
- Migration：无；本次仅调整 UI、样式与页面信息结构，未检查或执行数据迁移，`docs/DATA_SCHEMA.md` 未修改。
- 验证：TypeScript、正式构建与本地测试环境页面检查通过；构建仅保留既有主包体积提示。

## 2026-08-25 — 饭搭子与推荐来源分析 V1

- 在“我的数据”增加“饭搭子分析”和“推荐来源分析”两个入口，均支持从总览进入详情并查看真实餐厅证据。
- 饭搭子分析界面补充关系摘要、搜索、分层列表和完整详情视图，并加入共同次数、餐厅数、最近记录、菜系、消费、城市与共同记忆等图标化信息。
- 个人头像与饭搭子头像外圈统一为固定圆形细黑线，不再按用户分配不同颜色；同时修复列表头像被弹性布局拉伸成椭圆的问题。
- 饭搭子分析只聚合当前用户自己的有效 Visit，覆盖一起记录次数、不同餐厅、复购、跨度、我的实际消费、我的评分、菜系、常去餐厅、用餐方式、城市和共同记忆；3/6 次阈值统一控制基础与完整洞察，不伪造对方评分、消费或口味。
- 推荐来源分析按餐厅首次有效来源归因，同一餐厅只计算一次推荐样本，多次 Visit 先汇总为该餐厅的个人结果，再用于高分命中、低分、重复到访、消费和菜系表现；标准平台按来源类型合并，好友来源可显示已知昵称。
- 来源亲和度增加样本置信度与收缩处理，仅作为未来 Recommendation 的弱信号，继续服从预算、距离、场景和长期口味等明确限制。
- 同步修正月报/年报底层聚合对推荐来源和饭搭子的统计口径，使推荐来源按独立餐厅计数、饭搭子摘要同时记录共同餐厅数。
- 关键文件：`src/services/companionInsights.ts`、`src/services/recommendationSourceInsights.ts`、`src/services/reviewService.ts`、`src/components/ProfileAnalyticsPanels.tsx`、`src/components/ProfilePage.tsx`、`src/App.tsx`、`src/styles/global.css`。
- Migration：无；复用现有 Visit、DiningCompanion、Restaurant 和推荐来源字段，未修改字段、数据库结构或同步协议，未重复执行既有 migration。
- 验证：饭搭子与来源服务单元测试、完整测试、ESLint、正式构建及本地浏览器交互均通过；浏览器控制台无错误或警告。
- 已知问题：现有历史数据缺少可靠的来源获得时间，暂不展示“收录 → 想吃 → 到访”转化率；跨用户双人评分、对方口味和共同想吃需等权限完备的数据接口后再开放。

## 2026-08-24 — 餐厅详情空状态、实拍与上下文返回收口

- 评分参考空状态改为圆内统一图案和单一“暂无数据”，移除圆外重复说明；小圆只显示数字样本量，评分大圆继续使用既有五档颜色。
- 从餐厅详情移除“重复到访”展示；三枚“去过 / 想吃 / 抽签”按钮移至店名右侧，并将评分参考排在用户实拍之前。
- “我的到访概览”增加适合场景、服务、环境、性价比、上餐时长、菜量、用餐环境和交通等历史汇总；不新增数据字段。
- 发现信息流的公开到访实拍会传入同一餐厅详情并与本地照片去重，不再出现卡片有图、详情却显示暂无实拍。
- 食单打开餐厅详情时保留原食单作为来源层，关闭详情后回到该食单。
- 关键文件：`src/components/RestaurantPreviewCard.tsx`、`src/components/RestaurantSocialStatsPanel.tsx`、`src/components/CommunityPage.tsx`、`src/components/RestaurantListsPanel.tsx`、`src/components/ModalShell.tsx`、`src/styles/global.css`。
- Migration：无；本次为 UI 与现有数据映射调整，未修改字段、数据库结构或同步协议。
- 验证：ESLint、21 项自动测试与正式构建通过；仅保留既有的主包体积提示。

## 2026-08-24 — 遗漏功能收口、详情修复与线上同步准备

- 修复关注用户资料来源返回：从趋势、最新等发现分栏进入资料后会回到原分栏；昵称首次绑定 Cloudflare Access 时不再因无关时间戳刷新被旧云端资料覆盖。
- 食单餐厅现可点击并在当前页面打开完整餐厅详情；地图列表补齐城市、详细地址和“去过 / 想吃 / 抽签”快捷操作。
- 去过餐厅顶部直接显示“我的评价 X.X / 10”；详情卡修复弹性收缩导致的评分、历史和按钮重叠，保留四项评分参考、到访编辑、电话、营业时间、图片和三枚快捷按钮。
- “我想去”录入补充已选 POI 的详细地址、电话和营业时间说明，这些信息会与名称和图片一起保存。
- 修复开发启动流程：每次启动只增量应用未记录的本地 migration；重新生成 Development 测试数据，使当前账号拥有 10 个关注、9 个粉丝，并让共享餐厅能展示全部用户、好友及同味评分。
- 正式 D1 增量应用并确认 `0010`—`0014` 全部完成；未清空、覆盖或重命名正式数据库。
- 关键文件：`src/App.tsx`、`src/components/CommunityPage.tsx`、`src/components/ProfilePage.tsx`、`src/components/RestaurantListsPanel.tsx`、`src/components/RestaurantList.tsx`、`src/components/RestaurantPreviewCard.tsx`、`src/components/AddRestaurantModal.tsx`、`src/styles/global.css`、`scripts/seed-test-users.mjs`、`scripts/start-food-map.ps1`、`worker/index.ts`。
- Migration：本次没有新增 migration 文件；仅按用户已确认的现有结构增量应用待执行的 `0010`—`0014`，远端再次检查显示无待执行项。
- 验证：桌面测试版启动流程返回成功；21 项自动测试通过；TypeScript 和正式构建通过；浏览器实测列表地址/快捷操作、完整餐厅详情、四项评分参考及到访历史。
- 已知问题：附近餐厅依赖浏览器授予精确定位；拒绝权限时会结束 Loading 并明确提示开启权限，不会用城市级结果冒充附近餐厅。

## 2026-08-24 — 餐厅详情评分、快捷动作与推荐筛选

- 餐厅详情新增动态“历史预测”，并与全部用户、好友评分、同味评分统一为大圆分数 + 小圆样本数；窄卡片也会一次显示四项，不再只露出前两项。
- 到访历史移动到评分参考后方并保留展开、编辑和内部滚动；恢复并固定“去过 / 想吃 / 抽签”三枚快捷按钮。图片区缩小并固定为一半商家图片、一半用户实拍。
- 发现卡片改为图片优先的信息流样式；“为你推荐”与地图“推荐”均可直接筛选距离和评分并切换综合/最近/高分排序，地图另支持城市，评分区间可多选；删除已废弃的标签筛选。
- 开发环境的测试用户公开到访补充稳定的 2–3 张演示餐图，用于直接检查双图、三图信息流布局；不写入 Production，也不伪装成真实用户上传。
- 新增统一 Filter Result Resolution：真实 0 结果会识别距离、评分、城市或数据不足，并从同一候选池计算最小有效放宽；用户点击后才更新筛选。跨城市不再错误使用设备 GPS，界面会明确显示设备位置或浏览城市中心锚点。
- 关键文件：`src/components/RestaurantPreviewCard.tsx`、`src/components/RestaurantSocialStatsPanel.tsx`、`src/components/CommunityPage.tsx`、`src/services/personalTasteScore.ts`、`src/styles/global.css`。
- Migration：无；本次只增加动态计算和界面筛选，没有修改字段、数据库结构或同步协议，未检查或重复执行 migration。
- 验证：TypeScript、21 项自动测试和正式构建通过；本地页面实测地图推荐筛选入口、评分多选、距离、排序、城市与标签移除。

## 2026-08-24 — “今天吃什么”转盘视觉重构

- 按最终参考图重构转盘：候选餐厅改为图片标签，轮盘使用低饱和圆形分区、定位指针、声音开关和双层中央开始按钮；空分区直接提供“添加更多餐厅”。
- 保留统一候选池、最多 10 家、最少 2 家、等概率抽取、删除、清空、筛选、临时添加和结果详情；空分区不会参与随机，抽中位置与指针保持一致。
- 开发环境 60 家餐厅补充餐饮图片，便于实际测试候选标签和轮盘图片效果；正式数据未写入或改动。
- 关键文件：`src/components/RestaurantRoulette.tsx`、`src/db/seedRestaurants.ts`、`src/styles/global.css`。
- Migration：无；本次未修改数据结构或同步协议，未检查或重复执行 migration。
- 验证：桌面端与 390×844 手机尺寸实测通过；声音、转动、结果卡及候选增删正常；ESLint、TypeScript、15 项自动测试与正式构建通过。构建仅保留既有主包体积提示。

## 2026-08-24 — 跨平台基础、推荐、食单与食味年鉴

- 完成地图 Provider 与餐厅身份解耦、local-first 增量同步、图片存储抽象、服务端会员权益、可选半星评分、价格可信度和口味档案 2.0。
- 完成推荐 V1 的个性化/同味/趋势分流、冷启动与低样本降级、推荐反馈事件；修正同味阈值，明显相反的评分习惯不会再进入同味集合。
- 重组餐厅详情的信息层级，补充社交评分样本量；新增普通/排名食单、排序、笔记、封面、详情加入和带权限校验的稳定公开地址。
- 新增月度回顾与年度食味年鉴，并按会员等级展示完整故事；分享模型默认移除个人消费、饭搭子、来源和私人照片。
- 修复关注用户资料：点击后立即进入独立公开主页，加载对方公开记录，只显示对方的记录/餐厅统计并提供返回入口。
- 关键文件：`src/services/maps/*`、`src/services/syncQueue.ts`、`src/services/photoStorage/*`、`src/services/membershipService.ts`、`src/services/priceIntelligence.ts`、`src/services/recommendationService.ts`、`src/services/reviewService.ts`、`src/components/RestaurantListsPanel.tsx`、`src/components/RestaurantPreviewCard.tsx`、`src/components/ProfilePage.tsx`、`worker/index.ts`。
- Migration：新增 `0010_membership_entitlements.sql`、`0011_photo_storage_metadata.sql`、`0012_recommendation_events.sql`、`0013_restaurant_lists.sql`；未重复执行既有 migration，未应用远端 D1。
- 验证：ESLint 通过；6 个测试文件共 15 项测试通过；TypeScript 和正式构建通过。构建仅保留 Vite 对主包大于 500 kB 的性能提示。
- 已知问题：真实订阅支付尚未接入；远端启用新实体前必须依次应用 `0010`—`0013`；主包仍可在后续用按页面动态加载继续瘦身。

## 2026-08-24 — 品牌色与应用图标统一

- 建立全局品牌色、文字、背景、卡片、分割线、未选中与暖色强调 Token，并将主要导航、按钮和选中状态改为统一变量。
- 将北极熊汉堡图标应用到页内顶部品牌标识、favicon、Apple Touch Icon、PWA manifest 及 Windows 快捷启动方式，取消顶部旧餐具组件。
- 修复测试版 Windows 启动脚本的旧 PowerShell 兼容与服务检测问题；端口已有服务时直接打开，不重复启动。
- 关键文件：`src/App.tsx`、`src/styles/global.css`、`index.html`、`public/manifest.webmanifest`、`public/icons/*`、`scripts/start-food-map.ps1`。
- Migration：无；本次仅涉及 UI、静态资源与启动脚本，未检查或重复执行数据迁移。
- 验证：测试版启动返回 200；页面实际读取的顶部图标为 192×192 北极熊资源；TypeScript 检查通过。
- 已知问题：已安装到手机桌面的旧 PWA 图标可能被系统缓存，需删除旧捷径后重新“添加到主屏幕”。

## 2026-08-23 — 发现、社交评分、测试用户与餐厅详情

- 完成发现五栏及各自独立的数据逻辑；为你推荐改为“与曾吃餐厅相似 XX%”，同味之选继续呈现相似用户，餐厅卡增加图片及想吃/抽签图标。
- 增加 40 个可重复生成的开发测试用户、66 家测试餐厅、1326 条到访和关注/好友/想吃/共同饭局关系；关注数字、用户列表和公开资料均可点击查看。
- 餐厅详情增加全部用户、好友、口味相似用户评分与重复到访率；发现页和地图列表均在当前上下文打开完整详情，手机端不再露出后方地图。
- 轮盘完成统一候选池、等分扇区、删除/清空、结果卡及贯穿旋转过程的可静音提示音；附近餐厅修复高德照片字段类型异常造成的无限 Loading，并按精确 GPS 距离排序 3 组关键词结果。
- 关键文件：`worker/index.ts`、`worker/restaurantStats.ts`、`scripts/seed-test-users.mjs`、`src/App.tsx`、`src/components/CommunityPage.tsx`、`src/components/ProfilePage.tsx`、`src/components/FriendsPage.tsx`、`src/components/RestaurantPreviewCard.tsx`、`src/components/RestaurantRoulette.tsx`、`src/services/amap.ts`。
- Migration：新增并各执行一次本地 `0008_dining_companion_links.sql`、`0009_discovery_follows_and_test_markers.sql`；远端既有 `0008`，本轮仅增量应用待执行的 `0009`，未清空或重命名正式数据库。
- 已知问题：正式发现页不会自动生成模拟用户；真实内容数量取决于公开用户、关注关系与到访数据。

## 2026-08-23 — 当前位置与附近餐厅修复

- 当前位置头像标记改为圆形定位气泡，外圈和尖角统一使用 App 主色 `#4F6F8C`。
- 附近餐厅改用浏览器高精度 GPS，坐标转换为高德坐标后按餐饮类别检索 3 公里范围，避免把“餐厅”误当成必须出现在店名里的关键词。
- 定位、坐标转换和 POI 查询均有明确超时；失败、拒绝权限和无结果都会结束 Loading 并显示重试或说明。
- 关键文件：`src/styles/global.css`、`src/services/amap.ts`、`src/components/AddRestaurantModal.tsx`。
- Migration：无；本次没有新增、删除或修改数据字段、数据库结构或同步协议。
- 验证：ESLint、13 项自动测试和正式构建通过；本地页面确认拒绝定位权限后 Loading 会结束并显示“重新定位”。
- 已知问题：附近结果依赖浏览器获得精确位置权限；拒绝权限时只提示重新定位，不使用城市级近似结果。

## 2026-08-22 — 地图交互、转盘与个人页细化

- 地图与列表分类栏统一为带图标且居中的“去过 / 想吃 / 推荐”；底栏保留“地图 / 社区 / 我的”，添加餐厅改为悬在社区正上方的小型快捷按钮。
- “附近餐厅”改为只使用设备高精度 GPS 的 1.5 公里检索，失败或超时会停止 Loading 并允许重新定位，不再混入城市级结果。
- 餐厅详情增加“添加到转盘”；候选餐厅在当前会话累计，转盘从空状态开始始终可见，候选每增加一家就立即增加一个分区。
- 味觉足迹调整为头像在左、笔记和照片优先的连续动态流；个人页修复预设头像显示，移除头像相机角标，并将头像、资料和地图隐私合并到同一折叠面板。
- 用户查找从关注管理中拆出为独立“发现好友”入口；App 主要蓝色统一为 `#4F6F8C`。
- 关键文件：`src/App.tsx`、`src/components/AddRestaurantModal.tsx`、`src/components/FriendsPage.tsx`、`src/components/ProfilePage.tsx`、`src/components/RestaurantPreviewCard.tsx`、`src/components/RestaurantRoulette.tsx`、`src/components/TasteFootprints.tsx`、`src/services/amap.ts`、`src/styles/global.css`。
- Migration：无；本次没有新增、删除或修改数据字段、数据库结构或同步协议，因此未重复执行既有 migration。
- 已知问题：真实附近结果依赖设备授予精确定位权限；拒绝权限时只显示重试提示，不展示近似城市结果。

## 2026-08-22

- 完成：桌面/手机完整地图与列表双模式、地图常驻分类栏和列表入口、蓝色底部导航、个人页整合、头像预设与会员上传限制、饭搭子复用、到访编辑和体验字段、价格语义、转盘工具、地图分享权限、测试数据恢复及当前位置头像定位气泡。
- 界面：列表标题改为 `MY TASTE MAP` 并移除冗余说明；新增仅在列表模式显示的“味觉足迹”动态流，支持连续滚动并展示到访照片或菜品图片；选中餐厅后“查看列表”仍保持可见。
- 表单：用餐人数、饭搭子和排队时长改为整齐的整行卡片与等宽网格；饭搭子限量展示并支持添加/展开；菜品改为直接“添加”；适合场景支持多选和自定义；历史摘要移除重复的单次可见性。
- 搜索：附近餐厅改为城市兜底与 GPS 附近检索并行，成功结果优先结束 Loading，并保留失败和超时提示。
- 关键文件：`src/App.tsx`、`src/components/TasteFootprints.tsx`、`src/components/MapView.tsx`、`src/components/ProfilePage.tsx`、`src/components/AddVisitModal.tsx`、`src/components/AddRestaurantModal.tsx`、`src/components/VisitExtraFields.tsx`、`src/components/UserAvatar.tsx`、`src/styles/global.css`、`worker/index.ts`。
- Migration：新增 `0005_visit_tags_and_map_privacy.sql`、`0006_avatar_presets_and_membership.sql`、`0007_multi_dining_occasions.sql`；本地 D1 均已各验证一次，本次后续 UI 调整未重复执行 migration，远端未在本轮执行。
- 验证：ESLint、TypeScript、13 项自动测试和正式构建通过；桌面与手机尺寸验证地图/列表切换、味觉足迹动态流、常驻分类栏、价格切换、表单布局、自定义场景与上餐时长选项。
- 已知问题：远端部署前仍需确认 D1 migration 状态；真实会员订阅尚未接入。
