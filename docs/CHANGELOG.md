# Taste Map 变更记录

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
