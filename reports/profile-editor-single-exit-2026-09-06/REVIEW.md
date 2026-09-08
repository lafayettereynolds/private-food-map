# work — 资料编辑单一返回入口

日期：2026-09-06

## 结果

“编辑资料”左上角只保留返回 icon，右侧仍为“保存”，不再同时显示“取消”。账户设置的“修改显示名称”和隐私设置的“主页可见范围”使用同一规则。返回沿用退出编辑、不写入草稿的行为；保存期间不能通过返回或交互下拉退出。

原因是 Hybrid Native 外层容器添加返回箭头，而 ProfileEditorSheet 自己又有 NavigationStack 和“取消”。现在明确由有导航的目标页面拥有退出入口，外层不再重复包装。原生回退、主页和设置中的编辑入口共用同一个返回组件；Browser 资料编辑也去掉底部取消和右上角 X，使用同一个左返回按钮，保留原有保存位置。

截图（均为隔离 QA 测试资料，不代表线上个人记录）：

- [编辑资料最终效果](/Users/lafayette/Projects/private-food-map-hybrid-final-integration/reports/profile-editor-single-exit-2026-09-06/profile-editor.png)
- [修改显示名称](/Users/lafayette/Projects/private-food-map-hybrid-final-integration/reports/profile-editor-single-exit-2026-09-06/display-name.png)
- [主页可见范围](/Users/lafayette/Projects/private-food-map-hybrid-final-integration/reports/profile-editor-single-exit-2026-09-06/visibility.png)
- [Browser 编辑资料](/Users/lafayette/Projects/private-food-map-hybrid-final-integration/reports/profile-editor-single-exit-2026-09-06/browser-editor.png)

## 同类消费者清查

| 范围 | 处理 | 验证边界 |
| --- | --- | --- |
| Native 主页编辑、账户完整编辑、修改名称、主页可见范围、隐私快捷编辑 | 共享 TasteMapReturnButton；删除重复取消；保留 Save 与草稿逻辑 | 三项最终 Hybrid → Native UI 测试通过，原生回退保存与重启持久化测试通过 |
| Browser ProfilePage、AccountPrivacyPage 三种编辑目标 | 共享 PageBackIconButton + ModalShell back 变体；移除取消和 X | 实际 React 组件交互，12 个屏宽/主题/目标组合，以及异步保存失败/重试测试通过 |
| Native 餐厅编辑、原生添加餐厅 | 相同取消位置改为共享返回；既有自带导航页面不再叠加 host 返回 | 编译及导航归属单元测试；本轮未逐个执行这些页面的完整业务 UI 流程 |
| Native 加入食单、Premium Store | 取消外层重复导航；保留页面自己的“完成”/关闭及业务清理 | 编译及导航归属单元测试；未发起购买、恢复或食单写入验收 |
| Native 缺少资料/无权编辑分支 | 自带导航目标失败时仍提供单一返回，防止移除 host 后无法退出 | 源码审查、全局契约与编译；本轮无单独失败态 UI 测试 |
| 普通 body-only Native 设置/系统页 | 继续由 host 提供返回；未移除必要导航 | 账户设置与隐私往返 UI 测试通过 |
| 其他 modal、删除确认、扩展和 Preview | 不全局替换业务取消/完成；Profile Preview 复用正式组件；扩展无相关组件消费者 | 静态清查 |

## 验证证据

1. Vitest：5 文件、104 项通过。覆盖默认 modal 关闭保留、编辑返回唯一性、保存禁用、全局产品/路由/平台契约。
2. Browser 实际组件：375/402 宽度 × 浅色/深色 × 完整资料/名称/可见范围，共 12 组合通过。验证唯一返回、44 点目标、点击命中、草稿丢弃；另验证保存期间禁用返回与 Escape、错误保留草稿、重试成功、只修改名称不写隐私。
3. 已有常驻返回回归：240 项通过，确保共享图标抽取没有破坏餐厅详情、设置等页面的滚动返回。
4. 最终 QA 包的三个 UI 测试全部通过：主页编辑返回/重开/保存即时刷新 47.133 秒；隐私设置 37.666 秒；账户设置名称、可见范围和完整编辑 57.866 秒。截图人工检查确认不再出现取消或第二个 host 返回。
5. Native 导航归属 Swift Testing：1 项通过，逐一检查完整 route enum，仅明确的自导航目标跳过 host。Native 原有 Profile 编辑与重启持久化 UI 测试通过（97.669 秒）。该原生回退测试在按钮 plain 样式微调之前执行；最终样式的 44 点目标与实际点击在 QA UI 三项复测中验证。
6. Debug 测试目标、最终 DebugQA、最终 Release 构建成功。正式资源暂存、QA 构建与实际安装包的 17 个 Hybrid 文件逐字节匹配，构建包/安装包整体 diff 无差异。Release 纯净扫描通过：39 app 文件、17 signed Web 文件。
7. 涉及的跟踪文件 git diff --check 通过；未提交，保留既有工作区修改。

首轮验收没有忽略失败：Native 默认 toolbar 把返回高度压到 36 点，实测断言失败；共享按钮改用 plain 样式后最终 44 点断言通过。Browser 初始断言发生在入场动画尚未结束，改为等待真实动画完成后测量；没有降低点击区域要求。

复现脚本：`hybrid/scripts/check-profile-editor-single-exit.mjs`；UI 结果 `/tmp/tastemap-single-exit-qa-final.xcresult`；Native 结果 `/tmp/tastemap-single-exit-native.xcresult`。

## Design System Compliance

- Core UI：共享 Native/React 返回原语，使用既有图标/44 点 token，保留无障碍标签“返回上一页”；无私有重复按钮。Native plain 样式避免默认 toolbar 缩小点击区域。
- Food & Dining：未修改头像资产、食物视觉、图片选择、评分或消费信息。
- Canonical Templates：资料字段、顺序、隐私语义及各平台既有 Save 位置保留；只收敛重复退出入口。浏览器单个保存按钮使用共享 footer 整行布局。
- Duplicate/default SwiftUI：没有引入第二套路由；已存在自导航能力页面不再被重复包裹。没有新增默认 SwiftUI 表单或擅自迁移 UI 所有权。
- 边界：资料编辑核心路径已验收；其余自导航目标仅做明确列出的单元/静态/编译验证。未安装用户 iPhone，不把模拟器结果宣称为真机验收。无新增待用户决策项。

## 运行身份

- 仓库：/Users/lafayette/Projects/private-food-map-hybrid-final-integration
- 分支：feature/hybrid-final-integration；基准 HEAD：58bd556b8382734aeae1f08937ba649563682140
- QA：com.lafayette.tastemap.qa，DebugQA，iPhone 17 Pro / iOS 26.5
- 固定模拟器：E4F3EED9-89D8-405C-B4CB-7CA816CE3405
- 最终构建：/tmp/tastemap-map-anchor-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app
- 已验收安装：/Users/lafayette/Library/Developer/CoreSimulator/Devices/E4F3EED9-89D8-405C-B4CB-7CA816CE3405/data/Containers/Bundle/Application/592E4FD7-7F21-4D65-889F-988B93797FD2/TasteMap.app
- 启动参数：--tastemap-hybrid-development -AppleInterfaceStyle Light；隔离 fixture：TASTEMAP_VISUAL_QA_MODE=rich
- 未改变 Release 的 NATIVE_PRIMARY 策略、真实账号数据、Worker、StoreKit 产品或线上服务。
