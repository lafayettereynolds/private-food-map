# Taste Map · 私人美食地图

Taste Map 是一个本地优先的私人美食足迹 Web App，用来记录去过和想去的餐厅、每次到访、评分、消费、排队时长、饭搭子、菜品、照片与个人感受。高德地图提供地图、定位、餐厅搜索和路线导航；私人记录默认只保存在当前浏览器中。

## 主要功能

- “我去过 / 我想去 / 推荐”三份清单与多维筛选；推荐会分析历史评分、口味标签与高分菜品，并排除已经记录的餐厅
- 通过高德搜索添加餐厅，也支持手动添加地图中没有的小店或摊位
- 每次到访可记录总价、人数、评分、排队时长、饭搭子、菜品、菜品星级、口味、照片和感受
- 自动汇总到访次数、10 分制评分、平均人均、平均排队时长和最近到访
- 地图使用餐厅图片或表情作为标记，外圈颜色根据 10 分制评分区间自动生成
- 设置中支持完整 JSON 数据导出和合并导入

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
VITE_AMAP_KEY=
VITE_AMAP_SECURITY_CODE=
```

如果以后需要分别使用不同的高德应用，可以改用：

```env
VITE_AMAP_DEV_KEY=
VITE_AMAP_DEV_SECURITY_CODE=
VITE_AMAP_PROD_KEY=
VITE_AMAP_PROD_SECURITY_CODE=
```

`.env`、`.env.local` 及其他本地环境文件已被 Git 忽略，不能提交到仓库。修改环境变量后需要重新启动对应服务。

没有配置 Key 时，应用仍可读取本地数据，但地图、定位和高德餐厅搜索不可用。

## 两个隔离环境

项目只维护一套代码，但使用两个不同端口和两个不同 IndexedDB 数据库：

| 用途 | 地址 | IndexedDB | 界面提示 |
| --- | --- | --- | --- |
| Codex 开发与测试 | `http://localhost:5173` | `food-map-dev` | 始终显示“🧪 测试环境” |
| 日常正式使用 | `http://localhost:4173` | `food-map-prod` | 不显示测试徽标 |

数据库名称集中定义在 `src/config/appEnvironment.ts`。`food-map-prod` 是稳定的正式数据库名，后续 Schema 调整只能通过 Dexie version migration 升级，不能通过清库或改名处理。

旧版使用的 `private-food-map` 数据库不会被自动删除，也不会自动复制进任何新环境。如需迁移旧数据，应先从旧版导出 JSON，再由用户明确选择要导入的环境。

## Windows 一键启动

- 双击 `启动美食地图-测试版.bat`：启动测试版并打开 `http://localhost:5173`。
- 双击 `启动美食地图-正式版.bat`：构建最新正式代码、启动正式版并打开 `http://localhost:4173`。

启动器会检查依赖和端口。对应 Taste Map 服务已经运行时只打开网页，不会重复启动；端口被其他程序占用时会给出提示。

如果需要手动运行，开发版可使用：

```bash
pnpm dev -- --host 127.0.0.1 --port 5173 --strictPort
```

手动构建正式版前应设置 `VITE_APP_ENV=production`，再在 4173 端口运行预览。日常使用不需要手动执行这些命令。

## 构建与预览

```bash
pnpm build
pnpm preview
```

构建产物生成在 `dist/`，该目录不提交到 Git。

## 数据存在哪里

餐厅、到访和照片保存在当前环境对应的 IndexedDB 数据库中：测试版为 `food-map-dev`，正式版为 `food-map-prod`。常用城市等少量界面偏好保存在各自端口隔离的 localStorage。

这些数据不会因为代码推送到 GitHub 而自动上传。不同浏览器、浏览器用户资料、设备和站点地址的数据彼此独立；清除站点数据会删除本地记录。

## 备份数据

1. 打开页面右上角的设置。
2. 选择“导出完整备份”。
3. 将下载的 JSON 文件保存在安全位置。

备份包含环境标识、数据库名称、餐厅、到访历史、评分、照片、菜品、标签和笔记。正式版文件名为 `food-map-backup-YYYY-MM-DD.json`，测试版为 `food-map-dev-backup-YYYY-MM-DD.json`。备份文件属于私人数据，不应加入 Git 仓库。

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
├── services/         高德地图加载、定位与 POI 搜索
├── styles/           全局界面样式与响应式适配
├── types/            领域数据类型
├── utils/            日期和图片处理工具
├── App.tsx           主流程、筛选与本地推荐
└── main.tsx          应用入口
```

## 隐私与仓库安全

仓库不应包含以下内容：

- `.env`、API Key、安全密钥、token 或密码
- `node_modules/`、`dist/` 等依赖和构建产物
- IndexedDB、本地数据库文件、导出的备份文件
- 用户餐厅数据和用户照片

提交前请检查 `git status`，确认只包含预期的源代码和文档。
