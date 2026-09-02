# Taste Map｜完整核心页面人工视觉审批范围修正报告

日期：2026-09-02

范围：仅 `reports/full-layout-parity/visual-approval/`

正式 Taste Map SwiftUI / 业务代码修改：**NO**

## 1. 修正规则

本轮正式取消以下错误等价关系：

```text
Codex Visual PASS / Task C CLOSED
≠
Lafayette Visual Approval
```

自动化、截图报告、Codex 审计或历史 `CLOSED` 只能说明对应检查曾执行，不能替代 Lafayette 的人工视觉决定。

只有同时满足以下条件，页面才显示「最终确认」：

1. Lafayette 在审批工具中明确选择页面级方向；
2. 页面所有必要区域均由 Lafayette 选择「保留现版」「保留旧版」或「保留融合版」；
3. 所有必要区域进入已冻结状态。

## 2. 审批项目从 9 项扩展为 14 项

新增重新开放人工审批的 5 个页面：

1. 我的地图 / 我的列表
2. 发现
3. 添加餐厅 / Nearby
4. 餐厅详情
5. 今天吃什么 / Roulette

原有 9 项继续保留：

6. 我的页面
7. 到访记录
8. 菜品与照片
9. 公开主页 / Social Hub
10. 我的食单 / 公开食单
11. 数据分析 × 4
12. 五类分享海报
13. Premium 会员页
14. 设置 / 数据

新增 5 项默认状态：

- 页面选择：待决定
- 区域冻结：0
- 自动批准：无
- 区域选择按钮：全部可用
- Lafayette 用户参考图：每页可独立上传和绑定

原有 9 项的页面决定、区域决定、Frozen 状态、Notes 和 IndexedDB 参考图没有被清空或覆盖。

## 3. 我的地图 / 我的列表

区域：

- 顶部标题与地图 / 列表切换
- 去过 / 想吃 / 推荐
- 筛选栏
- 餐厅标记与重叠层级
- 用户位置
- 选中餐厅与预览
- 添加餐厅按钮
- 我的列表条目
- 地图 / 列表状态保持
- 空白 / 加载 / 错误

真实证据：

- Current My Map：`final-atlas/task-04-map-after.png`
- Current My List：`final-atlas/legacy-fusion-02-my-list-images.png`
- Legacy Web Map：`full-product-parity-assets/web-map-before.jpg`
- Legacy Web List：`full-product-parity-assets/web-list-before.jpg`
- Current FUSE implementation：自然重叠 / 稳定层级与真实图片截图

## 4. 发现

按 Lafayette 指令完整拆分为：

- 标题
- 五个一级 Tab
- 筛选栏
- 动态卡片
- 用户 / 时间
- 餐厅图片 / 信息
- 到访评分
- 点赞 / 评论 / 更多
- 餐厅操作
- 同味之选内容
- 空白 / 加载 / 错误

真实证据包含：

- 为你推荐
- 关注动态
- 同味之选
- 最新
- 趋势
- 错误 / 重试
- Legacy Web 发现页
- Current FUSE 餐厅真实图片状态

## 5. 添加餐厅 / Nearby

按 Lafayette 指令完整拆分为：

- 顶部
- 搜索
- 附近餐厅
- 手动添加
- 分享导入
- 搜索结果
- 附近结果
- 餐厅预览
- 想去 / 记录到访操作
- 餐厅详情过渡

真实证据包含：

- Current Nearby
- Current 搜索候选预览
- Current Manual Add 预览
- Current Share Import 识别
- Legacy Web 添加餐厅页面
- Current FUSE 正式实现

视觉审批不改变 fresh CLLocation、精度/时间戳校验、provider identity、去重、3km 距离和真实排序等业务语义。

## 6. 餐厅详情

区域：

- Hero
- 名称与操作
- 基础信息
- 评分参考
- 用户实拍
- 到访概览
- 下游内容

真实证据包含：

- Current 详情顶部
- Current 本地餐厅下游内容
- Current 远程 / Community 入口主体
- Legacy Web 餐厅详情
- Current FUSE 真实图片状态

审批可以决定视觉布局，但不能分叉 `RestaurantDetailView` / `RestaurantDetailStandardBody`，也不能让 entry source 改变主体内容。

## 7. 今天吃什么 / Roulette

区域：

- 顶部
- 候选概览
- 轮盘几何
- 指针与中心
- 餐厅分区
- 空白分区
- 候选管理
- 抽签结果
- 餐厅图片
- 空白 / 错误

真实证据包含：

- Current 大型候选池
- Current 抽签结果
- Current 真实餐厅图片
- Legacy Web 轮盘顶部
- Legacy Web 完整轮盘 / 候选管理页面
- Current FUSE 正式实现

视觉审批不改变 stable Restaurant identity、最多 10 家、至少 2 家、候选池一一对应和均匀随机语义。

## 8. 页面与区域审批能力

5 个新增页面均支持页面级：

- 现版
- 旧版
- 融合版
- 方案 A
- 方案 B
- 重新设计

每个区域均支持：

- 保留现版
- 保留旧版
- 保留融合版
- 需要修改
- 重新设计

选择三种「保留」之一会冻结对应区域；解除冻结会清除该区域选择并重新开放。

## 9. 用户参考图兼容性

14 个页面均保留「我的参考图」能力：

- 文件选择
- 多图
- 拖拽
- 剪贴板粘贴
- IndexedDB 持久化
- 用途 / 强度 / 区域 / 最终视觉标记 / Notes
- ZIP 审批包导出

本轮开始前已经存在的「我的口味档案高保真构图参考」仍然存在：

- Lafayette 最终视觉参考：是
- 参考强度：几何 / 构图 Source of Truth
- 区域绑定：8
- 完整备注：保留

## 10. 浏览器验收结果

| 验收项 | 结果 |
| --- | --- |
| 项目总数 | 14，PASS |
| 导航项目数 | 14，PASS |
| 新增页面待决定 | 5，PASS |
| 原有页面决定保留 | 9 / 9，PASS |
| 原有 Frozen 区域保留 | 55，PASS |
| 新增页面 Frozen 区域 | 0，PASS |
| 我的地图 / 列表区域 | 10，PASS |
| 发现区域 | 11，PASS |
| 添加餐厅 / Nearby 区域 | 10，PASS |
| 餐厅详情区域 | 7，PASS |
| Roulette 区域 | 10，PASS |
| 新增页面均有 Current 截图 | PASS |
| 新增页面均有 Legacy Web 真实截图 | PASS |
| 新增页面均有 Current FUSE 真实实现截图 | PASS |
| 新增页面均有用户参考图上传区 | PASS |
| 截图加载失败 | 0 |
| 复制摘要项目数 | 14，PASS |
| ZIP 导出页面数 | 14，PASS |
| IndexedDB 参考图 | 1，PASS |
| 浏览器 Console error / warning | 0 |

## 11. 修改边界

本轮只修改视觉审批工具文件，没有修改：

- Swift / SwiftUI 正式 App
- Design Tokens / Shared Components
- Map / Discovery / Add Restaurant / Restaurant Detail / Roulette 实现
- 业务逻辑和数据模型
- Worker / D1 / R2 / Production
- Simulator
- App Icon
- StoreKit / Signing / Capabilities
