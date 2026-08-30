# Taste Map｜Analytics 文案命名 Override

日期：2026-08-31

分支：`fix/full-product-parity-restoration`

## 正式名称

| 原名称 | 新正式名称 |
| --- | --- |
| 饭搭子分析 | 最佳饭搭子 |
| 推荐来源分析 | 谁最会种草 |

## 用户可见范围

- Profile / 我的「发现与洞察」入口
- Premium feature registry、锁定状态与权益展示
- 两个 Analysis 页面的 Navigation Title
- 最佳饭搭子的个人分析说明
- 最佳饭搭子分享海报标题
- 谁最会种草分享海报标题
- UI tests 中用于验证用户可见 Navigation Title 和返回按钮的字符串
- Full Product Parity Audit 中的正式模块名称

内部 `CompanionAnalysis`、`RecommendationSourceAnalysis`、feature raw value、文件名、路由、数据模型和计算逻辑均未重命名。

## 验收

- `rg '饭搭子分析|推荐来源分析' ios/TasteMap`：无结果。
- `最佳饭搭子` 与 `谁最会种草` 在入口、页面、海报、Premium registry 和 UI tests 中正确出现。
- `P4BDiningCompanionTests`：PASS。
- `P4CRecommendationSourceTests`：PASS。
- `P4HPremiumEntitlementTests`：PASS，并新增正式名称 registry 断言。
- `testP4BDiningCompanionAnalysisRefreshAndPoster`：PASS。
- `testP4CRecommendationSourceAnalysisEvidencePosterAndRefresh`：PASS。
- Debug Simulator build：PASS。
- Release Simulator build：PASS。

## Safety

- 页面布局：未修改。
- Design System：未修改。
- SwiftData schema：未修改。
- API / Worker / D1 / Sync：未修改。
- Production：未访问。
