# 消费金额空值提示精简 · 2026-09-06

## 变更与消费者盘点

按 Lafayette 最新要求，删除「尚未计入消费统计」及对应空行，不改变金额、计算方式或统计语义。

- Browser / Capacitor：共用 `VisitSpendFields`，覆盖添加餐厅、记录到访、编辑到访。空值不渲染 output；已有计算结果保留 `aria-live="polite"`。
- Native / SwiftUI rollback：`VisitEditorView.spendSection` 删除相同的 else 提示，保留消费方式、人均及实际消费结果。
- 源码全局检索未发现 extensions、previews 或其他 accessibility 文案中的同类生产实现。
- 不更改支付服务、持久化、历史金额、页面所有权、餐厅人均或统计规则。未填写仍为未记录；别人请客的明确零支出仍显示。

## 验证

- 58 项测试通过：消费字段、消费计算服务、全局 Product Contract。包含空金额、AA、我请客、别人请客零金额、历史支付保留和禁止文案回归。
- Browser 402 × 874：新增和编辑到访均核对空字段不显示额外提示或空行；输入 175 后仍立即显示实际消费 175 和人均参考 175，清空后结果消失。使用隔离 fixture，未保存。
- 固定 iPhone 17 Pro 模拟器：`testHybridVisitBlankSpendHasNoUnrecordedHint` 通过；已查看真实截图，消费方式说明、金额输入、人数、页头和保存操作仍在。
- 正式资源 staging、QA app、实际安装 app 17 个文件逐字节一致；Debug 测试构建、DebugQA 和 Release 编译通过。
- Release 资源纯净扫描通过：39 个 app 文件、17 个签名 Web 文件，无 Debug fixture、开发地址或凭据暴露。
- Native rollback 的同文案删除通过源码禁止项与编译验证；本次未另外采集其运行截图，不把 Hybrid 截图当作 Native 运行证据。

## 运行身份

- 分支 `feature/hybrid-final-integration`；基础提交 `58bd556b8382734aeae1f08937ba649563682140` 加工作区改动，未提交。
- 构建 `/tmp/tastemap-map-anchor-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app`。
- 模拟器 `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`；bundle `com.lafayette.tastemap.qa`。
- 启动参数 `--tastemap-hybrid-development -AppleInterfaceStyle Light`，环境 `TASTEMAP_VISUAL_QA_MODE=rich`。
- Renderer：React Hybrid；Restaurant 深链接进入 Record Visit。隔离 QA 内容仅证明显示效果，不证明发现页真实推荐或真实消费数据。
- 实际安装包 `.../Containers/Bundle/Application/CD7A935C-D7E6-4C91-AB88-6110D4DDB60C/TasteMap.app` 已校验。
- 测试结果 `/tmp/tastemap-spend-copy-ui.xcresult`；截图 `simulator-create.png`、`browser-create.png`、`browser-edit.png`。
- 仅更新模拟器，没有安装到 iPhone、修改真实到访或发布线上代码。

## Design System Compliance

- Core UI：复用原字段、颜色、字体、间距；仅删除用户不需要的状态行，没有新增局部样式或替代量表。
- Food & Dining：无餐厅图像、地图标记、评分或照片改动。
- Canonical Page Templates：保留连续到访表单的顺序、消费方式提示、可选金额、人均参考和主保存操作。
- 共享组件：Browser 与 Capacitor 继续使用同一 `VisitSpendFields`；Native rollback 保留其合法独立渲染并同步文案规则，没有新增重复组件。
- SwiftUI / gaps：没有引入默认 SwiftUI 视觉替代；Native 独立运行截图未采集。此小改动不代表其他页面或旧问题全部验收。

持久规则已记入 `docs/TASTEMAP_PRODUCT_DESIGN_RULES.md` 的 Visit Editor。
