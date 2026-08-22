# Taste Map · 私人美食地图

Taste Map 是一个本地优先的私人美食足迹 Web App，用来记录去过和想去的餐厅、每次到访、评分、消费、排队时长、饭搭子、菜品、照片与个人感受。高德地图提供地图、定位、餐厅搜索和路线导航；正式网站通过 Cloudflare Worker + D1 同步结构化记录，实际照片保存在每位用户自己授权的私有 Google Drive，IndexedDB 负责离线数据和图片缓存。

## 主要功能

- “我去过 / 我想去 / 推荐”三份清单与多维筛选；推荐会分析历史评分、口味标签与高分菜品，并排除已经记录的餐厅
- 添加餐厅时先展示 GPS 附近餐厅；高德 POI 搜索支持 KFC、星巴克等品牌关键词，也支持手动添加地图中没有的小店或摊位
- 每次到访可记录到店/外卖、三级可见范围、总价、本人实付、消费方式、人数、评分、排队与用餐时长、饭搭子、菜品、照片、感受和更多可选维度
- 自动汇总到访次数、10 分制评分、平均人均、平均排队时长和最近到访
- 地图使用餐厅图片或表情作为标记，外圈颜色根据 10 分制评分区间自动生成
- 设置中支持完整 JSON 数据导出和合并导入
- 正式网站支持 D1 跨设备同步、离线修改重试、软删除和首次本地数据安全迁移
- Google Drive 采用 BYOS（自带存储）模式，使用最小 `drive.file` 权限同步餐厅、到访和菜品照片
- 用户资料、好友请求、独立 Visit 的共同饭局邀请、个人饮食时间线和仅由公开 Visit 生成的社区 Feed
- 地图默认只显示私人足迹；“社区足迹”图层可随时打开或关闭，并且只读取允许公开的记录

## 环境要求

- Node.js 18 或更高版本
- pnpm（推荐）或 npm
- 高德开放平台 Web 端（JS API）Key 与安全密钥

## 安装依赖

```bash
pnpm install
```

也可以使用：

```bash
npm install
```

## 配置环境变量

将 `.env.example` 复制为 `.env.local`。开发版和正式版可以先共用一套高德配置：

```env
VITE_CLOUD_SYNC_ENABLED=false
VITE_AMAP_KEY=
VITE_AMAP_SECURITY_KEY=
VITE_GOOGLE_CLIENT_ID=
```

如果以后需要分别使用不同的高德应用，可以改用：

```env
VITE_AMAP_DEV_KEY=
VITE_AMAP_DEV_SECURITY_KEY=
VITE_AMAP_PROD_KEY=
VITE_AMAP_PROD_SECURITY_KEY=
```

旧配置名 `VITE_AMAP_SECURITY_CODE`（以及对应的 DEV / PROD 形式）仍然兼容，无需修改已有本地配置。

`.env`、`.env.local` 及其他本地环境文件已被 Git 忽略，不能提交到仓库。修改环境变量后需要重新启动对应服务。

没有配置 Key 时，应用仍可读取本地数据，但地图、定位和高德餐厅搜索不可用。

`VITE_GOOGLE_CLIENT_ID` 是 Google OAuth Web Client ID，本身不是密钥，可以进入浏览器构建；Access Token 只保存在当前标签页的 sessionStorage，不写入 GitHub、D1、URL 或备份。Google Client Secret 不应使用 `VITE_` 变量，也不需要放入当前纯浏览器 OAuth 流程。

`VITE_CLOUD_SYNC_ENABLED` 在本地开发和本地预览中应保持 `false`，避免测试数据连接正式 D1。部署到 HTTPS 的正式 Cloudflare Worker 时，云端同步会自动启用。

## 两个隔离环境

项目只维护一套代码，但使用两个不同端口和两个不同 IndexedDB 数据库：

| 用途 | 地址 | IndexedDB | 界面提示 |
| --- | --- | --- | --- |
| Codex 开发与测试 | `http://localhost:5173` | `food-map-dev` | 始终显示“🧪 测试环境” |
| 日常正式使用 | `http://localhost:4173` | `food-map-prod` | 不显示测试徽标 |

数据库名称集中定义在 `src/config/appEnvironment.ts`。`food-map-prod` 是稳定的正式数据库名，后续 Schema 调整只能通过 Dexie version migration 升级，不能通过清库或改名处理。

旧版使用的 `private-food-map` 数据库不会被自动删除，也不会自动复制进任何新环境。如需迁移旧数据，应先从旧版导出 JSON，再由用户明确选择要导入的环境。

本地 4173 预览仍是隔离的本机版本，不会连接正式 D1。跨设备使用时，电脑和 iPhone 应打开同一个 HTTPS Cloudflare 网站。

## Windows 一键启动

- 双击 `启动美食地图-测试版.bat`：启动测试版并打开 `http://localhost:5173`。
- 双击 `启动美食地图-正式版.bat`：构建最新正式代码、启动正式版并打开 `http://localhost:4173`。

启动器会检查依赖和端口。对应 Taste Map 服务已经运行时只打开网页，不会重复启动；端口被其他程序占用时会给出提示。

如果需要手动运行，开发版可使用：

```bash
pnpm exec vite --host 127.0.0.1 --port 5173 --strictPort
```

手动构建正式版前应设置 `VITE_APP_ENV=production`，再在 4173 端口运行预览。日常使用不需要手动执行这些命令。

## 构建与预览

```bash
pnpm build
pnpm preview
```

构建产物生成在 `dist/`，该目录不提交到 Git。

## Cloudflare D1 云端同步

Cloudflare 配置保存在 `wrangler.jsonc`：

- D1 database：`food-map-db`
- Worker binding：`DB`
- Worker API：`/api/sync`、`/api/community`、`/api/profiles/:id`、`/api/users/search`、`/api/friendships`、`/api/shared-meals`
- Schema migrations：`migrations/0001_initial.sql` 至 `migrations/0004_user_avatar_thumbnail.sql`

同步顺序始终是：先读 IndexedDB 并立即显示，再在后台连接 Worker；新增、编辑和删除也会先写本地，再异步同步 D1。网络失败时本地记录和同步队列都会保留，可通过顶部“同步失败”或设置中的“立即同步”重试。

Restaurant 和 Visit 使用原有稳定 ID，通过 `updatedAt` 执行 Last Write Wins。删除写入 `deletedAt` 软删除标记，防止旧设备把已删除记录重新上传。旧 Visit 在迁移和读取时自动使用 `visibility=private`、`diningMode=dine_in`；其他新增字段允许为空，不会要求清库或重建数据。

照片采用三层存储：

- Cloudflare D1：保存结构化记录、Photo metadata、`driveFileId` 及 Restaurant / Visit / Dish 引用；另保存压缩至 256px 的用户头像缩略图，供好友和社区跨账号显示
- Google Drive：保存实际私有图片文件，不创建公开链接或共享权限
- IndexedDB：保存待上传原图和最近使用的 Blob 缓存；缓存上限约 300 MB，可在设置中单独清除

第一次连接会创建 `Taste Map/Photos`。测试环境使用 `Taste Map/Development Photos`，避免测试图片混入正式目录。新设备需要重新授权同一个 Google 账号；OAuth Token 不通过 D1 跨设备同步。

本地 D1 开发与测试：

```bash
pnpm run d1:migrate:local
pnpm run cloudflare:dev
```

应用远端 migration：

```bash
pnpm run d1:migrate:remote
```

正式部署：

```bash
pnpm run deploy
```

远端 migration 必须先在本地 D1 验证。禁止通过删库、清表或重建正式数据库解决 Schema 变更。

### 首次迁移

当 D1 为空而浏览器 IndexedDB 已有记录时，App 不会自动上传或覆盖，而是在设置中显示本地和云端数量。只有用户点击“上传到云端”后才会：

1. 自动下载完整 JSON 备份。
2. 将本地 Restaurants 和 Visits 上传 D1。
3. 重新读取 D1。
4. 校验本地与云端有效记录数量。

当新设备 IndexedDB 为空、D1 已有数据时，App 会自动下载并写入该设备的 IndexedDB。

### 用户身份与访问保护

D1 只能通过 Worker binding 访问，前端不会获得 D1 credential 或 Cloudflare API Token。Worker 使用 Cloudflare Access 注入的已认证邮箱识别用户，并把每个浏览器内的本地 `owner` 安全映射到云端真实账号；第二个账号不会读到第一个账号的私人同步快照。未经过 Access 的本地开发请求只使用单机 `owner` 兼容模式。

由于数据包含私人笔记，正式 Worker 路由必须在 Cloudflare Zero Trust 中由 Access Application 保护。Access 未配置时，Worker 无法获得真实多用户身份，不应把该 URL 当作开放公共服务。社区接口只返回 `visibility=public`；好友个人页额外返回 `friends`，`private` 永远只返回给记录本人。

### 平台无关的数据契约

`Restaurant`、`Visit`、`User`、`Friendship`、`SharedMeal` 与同步 JSON 都不依赖 React 组件或浏览器 DOM。高德品牌关键词归一化、隐私枚举、用餐方式和 Worker API 也位于独立类型/服务层。后续 iOS 客户端可复用同一套 D1 表和 HTTP JSON API；本轮没有创建 iOS UI。

## 数据存在哪里

餐厅、到访和待上传照片保存在当前环境对应的 IndexedDB 数据库中：测试版为 `food-map-dev`，正式版为 `food-map-prod`。正式 Cloudflare 网站把餐厅、到访、评分、标签、笔记及图片索引同步到 D1；实际图片进入用户自己的 Google Drive。本地图片 Blob 缓存可以清除，不会删除 Drive 原图。

GitHub 只保存代码和 D1 Schema，不包含实际餐厅数据。不同站点地址仍有各自的 IndexedDB；只有同一个正式 Cloudflare 网站会通过 D1 共享文字记录。清除单个设备的站点数据会删除该设备缓存，但下次打开正式网站时可重新从 D1 下载。

## 备份数据

1. 打开页面右上角的设置。
2. 选择“导出完整备份”。
3. 将下载的 JSON 文件保存在安全位置。

备份包含环境标识、数据库名称、餐厅、到访历史、评分、菜品、标签、笔记和 Google Drive 图片索引。已同步的 Drive 图片二进制不会塞进 JSON；尚未上传的本地照片会继续留在浏览器中，失败时不会删除。正式版文件名为 `food-map-backup-YYYY-MM-DD.json`，测试版为 `food-map-dev-backup-YYYY-MM-DD.json`。首次迁移到空 D1 前也会自动下载同样的备份。备份文件属于私人数据，不应加入 Git 仓库。

## 恢复数据

1. 打开设置。
2. 选择“导入 Taste Map 备份”。
3. 选择此前导出的 JSON 文件。

导入会与当前数据合并，不会先清空已有餐厅和到访记录。建议在导入前先导出一份当前数据备份。

## 项目结构

```text
src/
├── components/       页面组件、地图、弹窗与表单
├── db/               IndexedDB 数据库、数据操作与备份恢复
├── services/         高德服务与 IndexedDB ↔ Worker ↔ D1 同步
├── styles/           全局界面样式与响应式适配
├── types/            领域数据类型
├── utils/            日期和图片处理工具
├── App.tsx           主流程、筛选与本地推荐
└── main.tsx          应用入口
worker/               Cloudflare Worker API
migrations/           D1 Schema migration 历史
wrangler.jsonc        Worker、静态资源和 D1 binding 配置
```

## 隐私与仓库安全

仓库不应包含以下内容：

- `.env`、API Key、安全密钥、token 或密码
- `node_modules/`、`dist/` 等依赖和构建产物
- IndexedDB、本地数据库文件、导出的备份文件
- 用户餐厅数据和用户照片
- Google OAuth Access Token、Refresh Token 或 Client Secret

提交前请检查 `git status`，确认只包含预期的源代码和文档。
