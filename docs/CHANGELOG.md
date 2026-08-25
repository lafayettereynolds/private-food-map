# Taste Map 变更记录

## 2026-08-25 — 饭搭子与推荐来源分析 V1

- 在“我的数据”增加“饭搭子分析”和“推荐来源分析”两个入口，均支持从总览进入详情并查看真实餐厅证据。
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
