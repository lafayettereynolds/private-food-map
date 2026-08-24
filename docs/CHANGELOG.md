# Taste Map 变更记录

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
