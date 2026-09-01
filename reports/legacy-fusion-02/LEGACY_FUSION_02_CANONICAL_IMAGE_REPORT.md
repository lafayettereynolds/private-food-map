# Taste Map — Legacy Fusion 02 验收报告

## Canonical Restaurant Image Renderer

- 分支：`fix/product-ux-correction-8-tasks`
- 任务前基线：`a523d834e1207256d4c06858f1daa101dc26e89d`
- 固定视觉验收设备：iPhone 17 Pro / iOS 26.5 Simulator
- Simulator UDID：`E4F3EED9-89D8-405C-B4CB-7CA816CE3405`
- Production：未访问、未修改
- SwiftData / Worker / D1 / R2 / Sync / Signing / Capability：均未修改

## 1. Before：重复 resolver 审计

任务开始时共确认 **15 条页面级或 feature-level Restaurant image selection / loading path**：

1. Map marker source selection
2. Map marker remote loader
3. Map/List browse row resolver
4. Discovery Restaurant image resolver
5. Community activity thumbnail resolver
6. Add Restaurant hero resolver
7. Add Restaurant result-row resolver
8. Restaurant Detail hero resolver
9. Restaurant Detail gallery/fallback resolver
10. Lists / public-list resolver
11. Roulette resolver
12. Analysis Food Hero resolver
13. Analysis representative Restaurant evidence resolver
14. Poster preload resolver
15. Public sharing Restaurant resolver

这些路径分别处理过 `PhotoAsset`、`markerPhotoId`、`merchantImageUrl`、`RestaurantCandidate.photoURL`、网络失败和 Food/Dining fallback，存在跨页面漂移风险。

## 2. After：唯一 canonical architecture

最终只保留两个正式职责层：

```text
RestaurantImagePriorityPolicy
        ↓
RestaurantImageResolution（有序、可失败续接的真实图片来源）
        ↓
RestaurantImageLoader（本地 / API / HTTPS / cache / decode）
        ↓
TasteMapRestaurantImage（loading / success / failure / final fallback）
        ↓
页面只决定 frame / ratio / crop / mask / corner radius
```

唯一优先级是：

1. 用户自己的有效 Restaurant / Visit `PhotoAsset`
2. 合法 public/cached `markerPhotoId`
3. 合法 HTTPS provider `merchantImageUrl` / candidate photo URL
4. 所有真实来源缺失或逐项失败后，才使用 `FoodDiningVisualLibrary`

本地用户照片由 `RestaurantImagePhotoSelectionPolicy` 稳定选择：明确引用的 marker photo →有效 `restaurantMarker` →最新有效照片 → `sortOrder` →稳定 UUID。该规则不依赖页面。

加载层具备：

- source-by-source failure chaining；
- loading 与 final fallback 分离；
- URL scheme、HTTP status、MIME、大小与可解码图片校验；
- 同请求 in-flight 去重；
- 32 MB / 96-entry 有界内存缓存；
- 取消任务时停止继续加载；
- 单图失败不阻塞页面或列表。

## 3. 技术适配器说明

以下薄适配器仍因 UI 技术形态存在，但**不再决定 source priority**：

- MapKit annotation view：不能直接嵌 SwiftUI renderer，因此调用同一个 `RestaurantImageResolution` 和 `RestaurantImageLoader`；Legacy Fusion 01 的 natural overlap、selected/rating/visit-count/stable-ID z-order 完全未改。
- Analysis poster preload：`ImageRenderer` 生成海报前调用同一个 resolution 与 remote loader，避免 poster 自己建立 URL 优先级或缓存。
- 页面内 compact/hero/card wrapper：只提供尺寸、裁切、圆角和 accessibility label。
- Restaurant Detail gallery 的额外缩略图：是用户显式照片集合，而不是 Restaurant cover resolver；主 Hero 仍使用 canonical renderer。

## 4. 已统一页面

- Map marker / selected marker
- My Map / My List / Taste Footprints
- Nearby / Search / Add Restaurant preview 与结果行
- Discovery
- Community / Activity Card
- Restaurant Detail hero / gallery entry
- Lists / public list / Restaurant membership
- Roulette candidate / wheel/result image
- 我的口味档案
- 最佳饭搭子
- 谁最会种草
- 本月回顾
- 年度回顾
- 五类 Analysis poster
- Public Restaurant / List sharing

同一个 Restaurant 的 Map、List、Discovery、Detail、Roulette 与 Analytics 使用同一份 `RestaurantImageResolution`。页面裁切可以不同，source identity 与失败顺序相同。

## 5. Rich Demo 图片覆盖

Rich Visual QA 共 **115 家有效 Restaurant**，固定且 deterministic：

| 来源 | Restaurant 数量 | 比例 |
| --- | ---: | ---: |
| User photo | 60 | 52.2% |
| Public / cached | 20 | 17.4% |
| Provider / merchant | 20 | 17.4% |
| Honest Food/Dining fallback | 15 | 13.0% |

因此 100/115 家具备真实图片 source contract，15 家故意无图用于验证 honest fallback。DEBUG Visual QA 使用仓库中已有、已批准的本地 restaurant-style Food Hero 资产渲染可重复的测试照片；不声称它们是线上商户图片，也不会向后端或真实用户数据写入。

## 6. Map 验收

- Map 不再大面积错误显示咖啡杯、刀叉或餐盘 fallback。
- 有真实来源 contract 的 marker 显示 Restaurant-style image。
- 明确无图或所有来源失败的 Restaurant 才显示 Food/Dining fallback。
- Natural overlap、无数字 cluster、selected → rating → visit count → stable ID 层级均保留。

## 7. Release purity

扫描对象：

- Release Simulator 主 App Mach-O
- `TasteMapShareExtension.appex` Mach-O
- 完整 Release `.app` package

以下 marker 均为 **0 命中**：

- `TasteMapVisualQAFixtures`
- `TasteMapUITestFixtures`
- `TASTEMAP_VISUAL_QA_MODE`
- `visual-qa.invalid`
- Rich Demo / fixture-user / Visual QA Premium marker
- test resolver marker

结论：Release binary 与 Share Extension **不包含 DEBUG fixture activation 或 test Restaurant resolver**。正式优先级、loader 与 renderer 属于产品运行时；Rich Demo 的图片注入仍受 `#if DEBUG` 严格隔离。

## 8. 自动化与构建

| 验证 | 结果 |
| --- | --- |
| `RestaurantImageCanonicalRendererTests` | PASS：priority、failure chain、invalid/empty、cross-surface、Rich Demo mix |
| 相关 Roulette / Analysis regression | PASS |
| Full `TasteMapTests` | **648 / 648 PASS**，0 failed，0 skipped |
| Legacy Fusion 02 UI tests | **2 / 2 PASS** |
| Debug Simulator build | PASS |
| Release Simulator build | PASS |
| Generic iOS Device Release build（不改 signing） | PASS |
| `git diff --check` | PASS |

完整回归曾发现一条旧断言把 `.photo(id, providerFallback: url)` 错误地期望为 `.photo(id)`。该断言已更新为正式 contract：本地照片仍第一优先，但必须保留 provider 作为本地文件失败后的下一合法来源；没有通过降低真实图片优先级来修改测试。

## 9. 视觉证据

- [Map — real Restaurant images](screenshots/map-real-restaurant-images.png)
- [Map — honest fallback examples](screenshots/map-fallback-example.png)
- [My List](screenshots/my-list-images.png)
- [Discovery](screenshots/discovery-images.png)
- [Restaurant Detail](screenshots/restaurant-detail-image.png)
- [Roulette](screenshots/roulette-images.png)
- [Analytics representative Restaurants](screenshots/analytics-restaurant-images.png)

所有截图均为固定 iPhone 17 Pro Simulator 的 1206 × 2622 输出。

## 10. 结论

Legacy Fusion 02 达到关闭条件：Restaurant 图片来源选择、故障降级与 fallback 已从页面级实现收口到 canonical policy + canonical presentation layer。没有修改产品布局、数据模型、后端、Production 或 Legacy Fusion 01 的 Map 规则。
