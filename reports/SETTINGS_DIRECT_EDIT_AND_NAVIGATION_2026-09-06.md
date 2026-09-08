# 设置直接编辑与入口逻辑修复

日期：2026-09-06。范围：设置、账户与安全、个人资料编辑、隐私、权限及同类设置入口。不包含地图、餐厅算法或发现算法的新修改。

## 结论

用户指出的问题成立：账户中的“显示名称”和“主页可见范围”原先是只读 `LabeledContent`，与旁边的“编辑资料”形成了不必要的绕路。这两行现在可直接点击，分别打开名称编辑和可见范围编辑；完整“编辑资料”仍保留头像、名称、城市和可见范围。

本次修改已在固定 iPhone 17 Pro 模拟器的 QA App 中执行并验证，没有更新 iPhone 真机、部署线上服务、删除账户或修改真实云端数据。

## 一并发现和处理的问题

| 入口/模式 | 原问题 | 当前行为 |
| --- | --- | --- |
| 账户 → 显示名称 | 只能看，必须先找编辑资料 | 当前值带直接编辑入口，只编辑名称 |
| 账户 → 主页可见范围 | 只能看，入口与值分离 | 直接选择仅自己、好友或公开 |
| 隐私 | 显示当前值、再点修改、再进入完整资料表单 | 同一行显示当前值并直达同一可见范围编辑器 |
| 完整编辑资料 | 与快捷入口可能形成不同实现 | 各入口复用本平台同一编辑器与保存服务；完整入口保留所有原字段 |
| 同步 | 名为状态的行实际上执行同步，结果提示过于笼统 | 原生明确为立即同步/重试同步/正在同步；浏览器入口明确为查看同步详情；按返回状态提示结果 |
| 已允许的权限 | 允许后不能从该状态入口调整 | 已作出决定的权限可前往系统设置调整；未请求的权限只解释实际触发场景 |
| 相机权限 | 原生权限详情没有相机这一项 | 补入相机状态，与定位、照片使用一致状态模型 |
| 浏览器设置分流 | 多种不同设置都打开通用数据弹窗 | 账户、隐私、权限、帮助、关于各自直达对应详情；存储、同步、导入、导出各自聚焦相应内容 |
| 无效按钮外观 | 只读信息也带箭头；个别按钮没有可执行处理 | 只读账户事实不再伪装成动作；能力缺失显示真实说明，不制造空按钮或假版本号 |
| 连续点击与失败 | 多个设置动作缺少统一执行中/异常处理 | 共享设置动作锁定重复触发、禁用执行中的入口，并显示失败信息 |

取消不保存；单项保存保留未编辑的名称/头像/城市/可见范围；保存返回当前设置详情；从账户返回设置再进入，数据保持一致。永久删除账户、退出登录、导入数据、导出备份的安全边界及必要确认未被移除。

## 同语义消费者清单

| 消费者 | 实施方式 | 验证 |
| --- | --- | --- |
| React 设置首页，Browser 与 Capacitor 共用 | `TasteMapSettingsPage`、`HybridEntryRow` 统一动作、权限与执行中语义 | 共享组件/路由合同测试；浏览器与固定模拟器实际入口 |
| iOS Hybrid 的账户/隐私原生接管页面 | `SettingsEditableRow` + 带目标范围的 `ProfileEditorSheet` | 新增两个 UI 测试 |
| Native 主入口/回退设置 | 复用同一账户、权限、隐私组件 | 独立 Debug 模拟器设置完整导航测试 |
| Browser 账户/隐私详情与完整资料 | `AccountPrivacyPage`、`ProfileEditorModal` | 独立浏览器上下文完成取消、保存、完整编辑以及返回验证 |
| Browser 同步/缓存/备份入口 | 同一 `SettingsModal` 按 section 聚焦；原导入导出实现保留 | 四个入口分别打开、关闭并返回设置 |
| Native 预览 | 使用同一设置及资料组件，不新增预览专用编辑器 | Swift 编译覆盖 |
| 分享扩展 | 不承载个人资料设置入口 | 无匹配消费者，无改动 |

## 验证结果

- TypeScript 与 Worker 类型检查：通过；正式 Hybrid 构建与 staging：通过。
- Vitest：4 个测试文件，96 项通过。包含设置交互、全局产品合同、剩余页面合同及平台合同。
- Swift：`SettingsFoundationTests` + `P3AProfileTests` 共 26 项通过。
- Hybrid 模拟器：账户独立入口、原完整资料编辑即时刷新、直接名称/可见范围编辑及其返回路径、隐私单项编辑，4 个独立 UI 用例均通过。
- Native Debug 模拟器：设置 → 账户 → 备份确认 → 同步 → 权限 → 关于，1 个完整导航 UI 用例通过。
- Browser：直接名称修改的取消/保存、单项可见范围保存、完整资料回读，以及隐私、三类权限、帮助、关于、存储、导出、导入、同步的打开/返回均通过；无未捕获页面错误。使用独立浏览器上下文，云同步和社交 API 关闭。
- DebugQA 模拟器构建与 Release iPhoneOS 构建：通过。Release 仅构建检查，未签名发布或安装真机。
- 正式 staged 资源、QA 构建、已安装 QA 应用和 Release 构建的 17 个 Hybrid 资源逐字节一致。
- 已安装 Native 调试动态库与 QA 构建 SHA-256 一致：`bb55d219987c6f26d6d821ce143da027afb7329f1ed1d91d475e0ba953a5b44d`。
- Release 隔离扫描通过：未带入 Debug 开关、测试 fixture、开发地址、本地路径或 React 凭据内容。
- 授权范围内的旧只读名称/可见范围、全设置混入通用数据页、误导性同步状态标题等禁止模式扫描无遗留；修改文件 whitespace 检查通过。

执行过程说明：首次 UI 执行器尚未包含新增测试，随后重新 build-for-testing 并确认新用例实际执行。另一个原生专用 fixture 用例误放在固定 QA 配置下，未进入目标页面；更正为隔离 Debug 模拟器后通过。最终新增 Hybrid 测试结果是 2/2 通过，原生设置测试是 1/1 通过，并非用构建成功代替运行验证。

## 运行身份与证据

- 分支：`feature/hybrid-final-integration`；基线提交：`58bd556b8382734aeae1f08937ba649563682140`。当前未提交工作树包含用户之前的修改；没有提交、重置或清理那些修改。
- 固定模拟器：`E4F3EED9-89D8-405C-B4CB-7CA816CE3405`，iPhone 17 Pro，iOS 26.5。
- QA 包：`/tmp/tastemap-map-anchor-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app`，bundle ID `com.lafayette.tastemap.qa`。
- Hybrid 启动参数：`--tastemap-hybrid-development -AppleInterfaceStyle Light`；环境：`TASTEMAP_VISUAL_QA_MODE=rich`。截图使用隔离的丰富测试档案，不代表用户真实资料。
- 渲染器：设置首页为正式 React Hybrid；账户、隐私与资料为原有 typed Native capability handoff，未切换路线所有权或默认生产运行模式。
- 原生回退验收使用另一台隔离模拟器 `5C24CBC2-5E24-4D82-B7DD-FB815DD7A60A`，Debug 的 F1B3/P3A 测试 fixture；权限截图标识的是这个原生验收，不冒充 Hybrid 首页。
- 浏览器验收地址：`http://127.0.0.1:4179`，Chrome 隔离上下文，402 × 874 视口。
- 最终结果包：`/tmp/tastemap-settings-ui-final.xcresult`；原生结果包：`/tmp/tastemap-settings-native-ui.xcresult`；单元测试结果：`/tmp/tastemap-settings-native.xcresult`。

保存在报告旁的真实截图：

- [账户直接编辑行](settings-direct-edit-2026-09-06/native-account.png)
- [名称单项编辑](settings-direct-edit-2026-09-06/native-name.png)
- [可见范围单项编辑](settings-direct-edit-2026-09-06/native-visibility.png)
- [原生权限详情](settings-direct-edit-2026-09-06/native-permissions.png)
- [浏览器账户](settings-direct-edit-2026-09-06/browser-account.png)
- [浏览器名称](settings-direct-edit-2026-09-06/browser-name.png)
- [浏览器可见范围](settings-direct-edit-2026-09-06/browser-visibility.png)

## Design System Compliance

- Core UI：复用共享设置行、表单、分段选择器、保存栏与错误/忙碌状态；设置编辑行使用共享 44pt/px 最小点击目标。Browser 名称输入为 16px，避免移动 Web 输入聚焦时自动放大。
- Food & Dining：本次不涉及餐厅图片或地图标记；头像渲染、预设和 Premium 上传权限保留原实现。
- Canonical Page Templates：保留已批准的 Settings 索引和 Native 密度；账户与安全仍只有一个详情目的地；原完整资料入口没有被拆掉。
- 剩余重复组件：Browser 和原生能力接管仍各有平台所有的编辑渲染器，这是现有架构边界，不是新建的 Capacitor 专用 React 页面；每个平台内部的完整/单项编辑均复用同一实现。
- 默认 SwiftUI 回归：未引入新的系统默认分段控件、按钮尺度或页面风格；继续使用当前获批原生设置形式和 Taste Map 分段控件。
- 剩余边界：没有执行真实注销、账号删除、真实付款或在线导入/同步；系统权限真实授权弹窗及设备设置项由 iOS 决定，本次验证了权限状态映射与应用内入口，没有替用户更改系统授权。深色模式与极端动态字体未进行本次完整视觉矩阵验收。

新规则已归档到 `docs/TASTEMAP_PRODUCT_DESIGN_RULES.md` 的 Settings direct editing 条目。
