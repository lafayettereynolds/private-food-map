# Taste Map｜Visit Editor 个人评分交互修复验收

日期：2026-09-03
分支：`feature/hybrid-remaining-ui-batch`

## 结论

PASS。可编辑星级评分现在遵循单一、明确的 `SET / CLEAR` 合同：星星或半星点击只会直接设置目标值；只有独立“清除”操作会产生 `nil`。Browser 与 Capacitor 继续消费同一个 React `StarRatingField`。

## Root Cause

`StarRating` 的 pointer 计算原本已经直接返回目标值，真正问题出在两个写入入口都用外层 `<label class="field">` 包裹评分组件。评分存在时，组件内部会渲染一个可交互的“清除” `<button>`；HTML/WKWebView 会把点击非 labelable 星星元素的同一手势再次激活到该隐式 label 的 descendant control，于是同一次用户操作先设置目标评分，再由“清除”按钮写回 `null`。清除按钮消失后，第二次点击才看似生效。

修复措施：

- 新增明确的 `EditableStarRatingAction = SET | CLEAR` reducer；SET 永远返回目标值，重复设置当前值也保持不变。
- `StarRatingField` 使用语义正确的 `<fieldset>/<legend>`，彻底移除交互控件外层 label。
- 星星点击阻止 label/default activation；清除按钮独立发出 CLEAR。
- Add Visit 与 Add Restaurant 的 visited flow 都切换到同一个共享 field；Dish rating 继续复用同一个 direct-set `StarRating`，只读展示未改。
- slider ARIA label/valuetext 同步表达当前评分、5 星总分与十分制分数；键盘/辅助功能继续每次 0.5 步进。

## 评分色

选中星使用共享 token `--color-rating-selected: #E5A629`。该值来自仓库既有、已经用于正式菜品评分摘要的暖金色，现提升为统一评分 token；未选星继续使用浅灰/蓝灰轮廓。

## 自动化结果

- Targeted Vitest：2 files / 43 tests PASS。
- Full Vitest：57 files / 412 tests PASS。
- TypeScript + Worker typecheck：PASS。
- Browser production build：PASS。
- Hybrid Release bundle build/stage：PASS。
- Debug iPhone 17 Pro Simulator build：PASS。
- Release iPhone 17 Pro Simulator build：PASS。
- Generic iOS Device Release build（不改 signing，`CODE_SIGNING_ALLOWED=NO`）：PASS。
- Release Simulator purity scan：PASS；40 app files / 16 signed Web files，无 fixture、debug route、test auth、Development URL、secret 或远端 `server.url`。
- Formal Device Release purity scan：PASS；36 app files / 16 signed Web files，同样无上述 Release 污染。

新增 XCUITest 已编译，并覆盖完整评分序列；本机 XCTest 在进入 WKWebView 辅助功能树时触发系统 `UIAccessibilityLoaderWebShared` 重复加载并被 SIGKILL，未到达产品断言。该 runner 异常不作为 PASS 证据；真实固定 Simulator 手动操作与共享组件自动化结果如下。

## Browser / Capacitor 共享组件实测

同一移动宽度 React 页面从已有 4.0 开始，依次验证：

`4.0 → 3.5 → 5.0 → 2.5 → 4.5 → 清除 → 3.0`

每一步一次操作完成，ARIA label、星星、描述文案和十分制映射同一次更新。重复点击当前 3.0 后仍保持 3.0；ArrowRight 从 3.0 调整到 3.5，确认辅助功能步长为 0.5。

- [Browser/Capacitor shared 4.5](/Users/lafayette/Projects/private-food-map-hybrid-remaining-ui/reports/hybrid-architecture/visit-rating-direct-set/browser-capacitor-shared-4-5-star.png)
- [Browser/Capacitor shared final 3.0](/Users/lafayette/Projects/private-food-map-hybrid-remaining-ui/reports/hybrid-architecture/visit-rating-direct-set/browser-capacitor-shared-final-3-star.png)

## 固定 Simulator 实测

设备：iPhone 17 Pro，iOS 26.5，UDID `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`。

真实执行同一序列：

- [4.0](/Users/lafayette/Projects/private-food-map-hybrid-remaining-ui/reports/hybrid-architecture/visit-rating-direct-set/simulator-4-0.jpeg)
- [3.5](/Users/lafayette/Projects/private-food-map-hybrid-remaining-ui/reports/hybrid-architecture/visit-rating-direct-set/simulator-3-5.jpeg)
- [5.0](/Users/lafayette/Projects/private-food-map-hybrid-remaining-ui/reports/hybrid-architecture/visit-rating-direct-set/simulator-5-0.jpeg)
- [2.5](/Users/lafayette/Projects/private-food-map-hybrid-remaining-ui/reports/hybrid-architecture/visit-rating-direct-set/simulator-2-5.jpeg)
- [4.5](/Users/lafayette/Projects/private-food-map-hybrid-remaining-ui/reports/hybrid-architecture/visit-rating-direct-set/simulator-4-5.jpeg)
- [清除](/Users/lafayette/Projects/private-food-map-hybrid-remaining-ui/reports/hybrid-architecture/visit-rating-direct-set/simulator-cleared.jpeg)
- [3.0](/Users/lafayette/Projects/private-food-map-hybrid-remaining-ui/reports/hybrid-architecture/visit-rating-direct-set/simulator-3-0.jpeg)

`4.0 → 3.5` 一次点击完成，没有空星中间态；清除后 `nil → 3.0` 同样一次点击完成。模拟器最终保持打开并停留在 3.0 星编辑页面，未保存或写入业务数据。
