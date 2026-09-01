# Taste Map｜Lafayette 用户参考图工具验收报告

日期：2026-09-02

范围：仅 `reports/full-layout-parity/visual-approval/`

正式 Taste Map SwiftUI / 业务代码修改：**NO**

## 1. 完成能力

- 每个视觉审批项目均新增「我的参考图」区域；当前完整核心页面审批范围为 14 项。
- 支持点击文件选择器选择 PNG、JPG/JPEG、WEBP。
- 支持一次选择多张图片。
- 支持把图片拖入对应审批项目。
- 支持聚焦上传区后按 `Command + V` 粘贴图片。
- 支持点击「粘贴剪贴板图片」读取浏览器剪贴板中的图片。
- 上传后直接显示大图预览，并复用审批台已有的放大、缩放、全屏和左右浏览能力。
- 每张图均可独立设置：
  - 参考名称
  - 用途：整页、区域、构图、风格、组件
  - 参考强度：灵感参考、视觉方向、高度复刻、几何 / 构图 Source of Truth
  - Lafayette 最终视觉参考
  - 一个或多个页面区域
  - 自由备注
- 支持替换图片，替换后继续保留用途、强度、区域和备注。
- 支持两步确认删除，避免误删。
- 顶部统计新增「我的参考图」和「最终视觉参考」。

## 2. 本机持久化

参考图使用独立 IndexedDB 保存：

- Database：`tastemap-lafayette-visual-approval`
- Object Store：`references`
- 保存内容：图片 Blob、原文件名、审批项目、用途、强度、绑定区域、最终视觉标记、备注、创建时间和更新时间。

没有把大图存入 localStorage；原有页面决定、区域决定、Frozen 状态、Round 1 / Round 2 / Round 3 记录仍使用原有存储键，未迁移、未清空、未覆盖。

图片不会上传到 Taste Map、Production、Cloud、Worker 或其他远程服务器。

## 3. 导出视觉审批包

新增「导出视觉审批包」按钮，生成：

`TasteMap-Lafayette-Visual-Approval.zip`

ZIP 包包含：

```text
approval.json
README.md
references/
  <page-id>/
    01-<reference-title>.png|jpg|webp
```

`approval.json` 包含：

- 当前审批轮次和存储键
- Round 2 原始本机记录（存在时）
- 当前 Page Decision
- Region Decision
- Frozen 状态
- Lafayette Notes
- 参考图元数据
- 每张参考图在 ZIP 中的实际路径

ZIP 在本机浏览器内生成，不依赖远程 CDN 或上传服务。

## 4. 复制审批摘要

「复制审批摘要」现在会为每个页面输出：

- Lafayette 视觉参考图名称和原始文件名
- 用途
- 参考强度
- 绑定区域
- 是否为 Lafayette 最终视觉参考
- Lafayette 备注
- 高强度参考的强制执行规则

当参考图被标记为「高度复刻」「几何 / 构图 Source of Truth」或「Lafayette 最终视觉参考」时，摘要会明确要求后续 Codex：

1. 先查看审批包里的真实图片；
2. 完成 Reference Decomposition；
3. 建立 Layout Contract；
4. 再实现并执行 Reference vs Final 对比；
5. 不得只读文字摘要后凭感觉重画。

## 5. 已录入的 Lafayette 高保真参考

已把本轮提供的「我的口味档案」图片录入当前本机审批台：

- 审批项目：数据分析 × 4
- 名称：我的口味档案高保真构图参考
- 用途：整页参考
- 参考强度：几何 / 构图 Source of Truth
- 最终视觉标记：是
- 绑定区域：顶部身份区、核心食物主视觉、周边分析节点、核心洞察、TOP 3、分布、代表餐厅图片、底部品牌区
- 备注：已完整记录中央 Food Hero、周边节点与连接线、TOP 3、数据总览、近期洞察、消费、人均、城市、饭搭子、用餐时间、微暖白底和不可退化成纵向 Card Dashboard 等要求。

## 6. 实际浏览器验收

| 验收项 | 结果 |
| --- | --- |
| 14 个项目均显示上传区域 | PASS |
| PNG/JPG/WEBP 类型限制 | PASS |
| 文件选择器上传 | PASS |
| 多文件输入能力 | PASS |
| 拖拽事件与共享导入管线 | PASS |
| 剪贴板图片读取与粘贴 | PASS |
| IndexedDB 刷新后持久存在 | PASS |
| 大图预览 / 缩放 / 全屏入口 | PASS |
| 用途、强度、区域、备注保存 | PASS |
| 最终视觉参考醒目标记 | PASS |
| 替换图片并保留元数据 | PASS |
| 两步删除 | PASS |
| 原有审批选择和 Frozen 状态保留 | PASS |
| 复制摘要包含图片约束 | PASS |
| ZIP 本地生成 | PASS |
| ZIP 文件头 | `PK`，PASS |
| ZIP 包含实际参考图 | 1 张，PASS |
| 浏览器控制台 error / warning | 0 |

## 7. 代码边界

本轮新增或修改的文件全部位于：

`reports/full-layout-parity/visual-approval/`

没有修改：

- Taste Map Swift / SwiftUI
- 候选 SwiftUI 实现
- 业务逻辑
- 数据模型
- API / Worker / D1 / R2
- Production
- Simulator
- App Icon
- Release Purity

## 8. 使用方式

打开：

`http://127.0.0.1:8765/full-layout-parity/visual-approval/index.html?lang=zh-cn-final&references=3`

在任一项目的「我的参考图」区域：

1. 点击「选择图片」，或直接拖入图片，或点击「粘贴剪贴板图片」；
2. 设置用途和参考强度；
3. 勾选约束区域；
4. 如果它是最终方向，勾选「这是最终视觉方向」；
5. 写下必须保留的构图、层级、比例和视觉关系；
6. 使用页面顶部「导出视觉审批包」把全部决定和原始参考图一次性交给后续 Codex。
