# 到访编辑器：移除上方粗灰外框

日期：2026-09-06。用户要求仅移除“这次到访”上方额外的粗灰线。

## 已实施

`AddVisitModal` 的共享 Restaurant 摘要使用 `is-unframed` 外框变体，仅将外边框设为 0。新增到访与编辑到访复用同一组件。`这次到访 / 修改这次到访` 标题及左右 1px 细线保留；不删除餐厅信息、照片、表单字段，不改变保存逻辑。

## 同语义使用方检查

- Browser AddVisitModal：新增／编辑共用，已覆盖。
- iOS Capacitor HybridVisitEditorPage：消费同一 AddVisitModal，已覆盖。
- RestaurantEditorModal／AddRestaurantModal：也使用 RestaurantSummarySection，但属于餐厅资料／录入预览卡，不是本次到访上方的多余外框，维持原样。
- 原生 VisitEditorView／VisitEditorPreviews：使用 SwiftUI Form，不存在本次共享 CSS 外框，未作变更。
- Share Extension：没有该 React 外框的独立实现。

## 验证与真实产物

- 71 项 TypeScript 产品／结构测试通过，包括新增的外框移除及内容／细线保留负向契约。
- 隔离 Browser 402×874：新增、编辑两种状态均检查到摘要上下边框为 0px，具名分隔线两侧仍为 1px，餐厅 facts/photos 节点未删除。
- 正式 stage：17 个文件与 dist 逐字节一致。
- DebugQA 构建：`/tmp/tastemap-map-anchor-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app`，内嵌 17 个资源与 stage 一致。
- 固定模拟器：`E4F3EED9-89D8-405C-B4CB-7CA816CE3405`，iPhone 17 Pro／iOS 26.5，独立包 `com.lafayette.tastemap.qa`。
- 实际渲染身份：React Hybrid；DebugQA 强制 visualQA 隔离档案。本证据只验收外观，不代表真实发现信息流已通过。
- 启动参数：`--tastemap-hybrid-development -AppleInterfaceStyle Light`；显式环境 `TASTEMAP_VISUAL_QA_MODE=rich`。
- 最终专项 UI 测试 `testHybridVisitUnframedSummaryVisualCheckpoint` 通过。通过应用自己的 `tastemap://restaurant/00000000-0000-4000-8000-000000032000` 深链进入餐厅，再进入编辑到访。截图已人工检查：上方粗灰线消失，具名细分隔线、笔记、评分、消费方式、取消／保存操作保留；未保存修改。
- 结果包：`/tmp/tastemap-visit-divider-direct-ui.xcresult`。
- Release iPhoneOS 构建成功，17 个内嵌资源一致；39 个应用文件／17 个 Web 文件的纯净性扫描通过。只构建，未安装到 iPhone。

之前三次入口检查未通过：Profile 列表项不可点击、旧 Discovery 动作名称不匹配、从 Profile 的坐标点击未进入预期详情。它们不算通过，也未在本次窄范围修改中宣称修复；最终使用已有的精确餐厅深链完成同一正式到访页面的视觉检查。

## Design System Compliance

- Core UI：本次外框移除及细线保留 PASS，复用共享摘要变体，没有新增尺寸体系。
- Food & Dining：未改动视觉来源、图片或内容节点。
- Canonical Page Template：仅按用户明确要求移除外框；栏目、顺序和其他区域不变，局部验收 PASS。
- 重复组件：本次新增 0；Browser／Capacitor 均复用现有组件。
- 默认 SwiftUI 视觉回退：本次新增 0，没有切换渲染器或正式路由所有权。
- 剩余边界：上述旧入口自动检查未修复；此前发现页数据链路和地图遮挡问题均不在本次去线交付范围，不能据本报告标为完成。

## 效果

- [模拟器编辑到访](./simulator-edit.png)
- [Browser 新增到访](./browser-create.png)
- [Browser 编辑到访](./browser-edit.png)
