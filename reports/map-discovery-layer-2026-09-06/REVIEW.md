# 地图与发现切换：原生地图层串页修复

日期：2026-09-06。范围：用户截图中的 Discovery 标题、筛选条仍在，但内容区被 MapKit 覆盖，底部残留地图按钮开孔。

## 原因与修改

这不是发现页选择了地图布局。React 保留地图页面以保存状态，而 MapKit 是 WebView 之外的原生叠层；CSS 隐藏 React 页面不会自动隐藏该叠层。旧实现直接根据任意一次 `visible=true` 更新显示叠层，没有检查 Native 当前路由，也没有拒绝异步恢复会话期间过期的地图更新。截图与该失效路径一致；没有从用户 iPhone 提取现场运行日志。

- React 的隐藏指令直接在布局切换时发送，不再等待下一次动画帧；同时取消未发送的旧显示帧。
- Native 在收到隐藏指令时立即隐藏图层，不让会话恢复延迟这项操作。
- 地图更新在桥接入口、任何 `await` 之前编号；过期的显示和隐藏都不能覆盖更新的状态。
- 地图可见性同时要求“当前路由为 Hybrid Map”和“最新展示请求允许显示”。非地图路由独立关闭图层；提前到达的地图几何可先隐藏准备，避免切回地图变成空白。
- 保留原 MapKit 实例、坐标、缩放、标记和图片缓存。不重建 WebView，不刷新整个页面，不更换底图，不改推荐算法、数据来源或卡片样式。

## 同类入口清单

| 消费端 | 核查与处理 |
| --- | --- |
| Capacitor 地图、发现、我的、设置、餐厅详情 | 共用唯一 NativeMapSurface / Native host；在共享生命周期边界修复，无页面局部遮罩 |
| Capacitor 地图/列表与 React 筛选弹层 | 同一可见性入口；当前路由是地图也不能无条件显示 MapKit |
| React Browser | BrowserMapSurface 在 inactive 时返回 null；不存在 WebView 外的原生图层，本次不改引擎 |
| Native rollback | RootTabView 按选中标签创建 activeView，不使用 Hybrid 叠层；不改回退页面结构 |
| 扩展、预览 | 未发现第二个 Hybrid MapKit host；无独立同类实现需要修改 |
| 无障碍 | 实际安装测试断言 `restaurant-map` 在非地图页面不存在，不能仅验证标题可见 |

## 验证记录

- Web / Bridge / Global Product Contract：88 项通过。
- 实际 React NativeMapSurface 的本地浏览器测试：30 轮切换；62 次请求；61 个应答逆序返回。离开首帧前立即隐藏、取消旧帧、弹层隐藏、卸载隐藏和忽略旧应答通过。这是发送组件测试，不冒充 iOS MapKit 视觉验收。
- 实际 iOS 集成套件：14 项通过，包含过期显示、过期隐藏、提前几何、路由切换、React 弹层的两个新增状态测试。
- 已安装 QA 筛选弹层 UI 回归通过。
- 最终连续切换与内容交互 UI 回归通过（74.563 秒）：8 轮 Map ↔ Discovery，交替进入同味之选/为你推荐；每次离开地图断言原生层不存在、每次回来精确比较平移后的 viewport；另测 Map/List、Profile/Settings、发现餐厅点击/详情返回及真实 feed 滚动。筛选弹层测试另行通过（22.166 秒）。
- 实际截图人工核对：[发现往返后](discovery-after-switches.png)、[发现滚动](discovery-scrolling.png)、[返回地图](map-returned.png)。发现内容区无地图和按钮开孔，底部导航保持；返回地图仍是原生 MapKit，标记与实际地图可见。截图为明确标识的 QA 数据验收，非线上内容证明。
- 资源真值门禁通过：dist ↔ formal staged ↔ QA built ↔ installed 各 17 个 Web 文件逐字节一致。安装目录为 `2D81F0A6-05AF-48BB-8A1A-D4F05F92ABA5/TasteMap.app`；原生可执行文件 SHA-256 与构建一致：`1b2d76495b2927cafcfee91f829b3431d87843eed9890d30912b2bbe8009b95b`。
- QA / Debug 测试构建 / Release 构建均成功；Release 纯净扫描通过：39 个 app 文件、17 个 Web 文件。

验证过程中的两次 UI 检查修正：第一次在手势坐标尚未发布时取了旧视野，现等待实际 viewport 更新；第二次错误地按静态文字查找餐厅，而真实无障碍节点是“查看餐厅 …”按钮，现按可点击入口验证。这两次失败没有通过放宽产品断言掩盖。单独的 Swift Package 测试因已有包源清单未包含 BridgeService 所需类型而无法编译，未记为通过；图层状态测试改在实际 iOS 工程目标中执行，14 项均实际运行。

## Design System Compliance

修复属于 Core UI System 的跨渲染器生命周期边界。Food & Dining Visual System、Map / Discovery Canonical Page Templates、字体、间距、颜色、圆角与操作入口保持不变。只扩展现有共享 host 的显示权限；产品规则和架构说明已记录禁止串页及保留视野的回归要求。

## 运行身份与边界

- 分支 `feature/hybrid-final-integration`；基准 HEAD `58bd556b8382734aeae1f08937ba649563682140`，基于已有未提交工作增量修改，未创建提交。
- 固定 QA 模拟器：`E4F3EED9-89D8-405C-B4CB-7CA816CE3405`，iPhone 17 Pro / iOS 26.5。
- 构建：`/tmp/tastemap-map-anchor-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app`，应用 `com.lafayette.tastemap.qa`。
- 启动：`--tastemap-hybrid-development -AppleInterfaceStyle Light`；环境 `TASTEMAP_VISUAL_QA_MODE=rich`。
- 渲染：React Hybrid 页面 + Native MapKit 图层；QA 数据用于可重复 UI 回归，不代表真实线上推荐内容。
- 未安装到用户 iPhone，未读取或修改真实餐厅记录、账户、权限、定位或线上服务。真实 iPhone 现场还需安装包含此修复的版本后复核。
