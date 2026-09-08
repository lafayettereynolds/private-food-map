# 味图夜间修改与验收记录

更新时间：2026-09-06 00:43，承接 9 月 5 日晚的任务。分支 `feature/hybrid-final-integration`，基线 `58bd556b8382734aeae1f08937ba649563682140`，未提交工作区。保留已有无关修改，没有重置仓库。

## 本轮结果

1. 撤回已被用户否定的附近 35 m / 24 px、固定五头像花瓣排列。城市/街区保留不同坐标的独立餐厅，允许自然遮挡；只对严格同坐标做真实成员叠层/完整列表。没有改动原始坐标或编造店铺数量。高分置前、纯拖动身份/图片/层级稳定。
2. `去过 / 想吃 / 推荐` 独立保存筛选、搜索和排序；第一次进入另一组条件为空，回来恢复本组。同组地图/列表共享，切组不重设地图。异步旧查询不能带回旧筛选或触发延迟镜头回跳。高级筛选全部进入缓存键。
3. 保留用户认可的区域视图大小；跨度超过 2.4° 后继续按对数比例缩小，80° 到最小尺寸。Native 外圈基线 28→14 pt；Browser CSS border-box 32→14 px，原白环保留。想吃/推荐仍略大，远处加大量逐渐降至 1 pt。44 pt 根锚点不缩放，显示尺寸不反向改变分组半径。
4. Profile 三项统计上下收紧约 45 px（源代码几何差），共享 8 / 4 / 44 / 10 节奏。保留统计计算、金额字体、金额列宽、三项信息和点击高度。
5. 搜索增加有界简称匹配、同城精确位置补查、真实 provider 联想解析和继续加载；Nearby 合并额外 500 m POI 查询后按实际距离排序，仍守 3 km 边界。粗略定位提示开启精确位置。过期 accepted GPS 重新取点，失败仍允许城市搜索。手选异地城市优先。固定测试定位只与显式假 provider 配对。
6. 分页与异步请求增加 owner/query/generation 校验，游标单次消费并有时限；编辑查询清除旧结果，不能把旧下一页加到新搜索中。

## 实际运行与产物身份

- 固定预览模拟器：iPhone 17 Pro / iOS 26.5，`E4F3EED9-89D8-405C-B4CB-7CA816CE3405`。
- 安装的独立 QA：`com.lafayette.tastemap.qa`，构建 `/tmp/tastemap-map-anchor-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app`。
- 最终安装目录：`/Users/lafayette/Library/Developer/CoreSimulator/Devices/E4F3EED9-89D8-405C-B4CB-7CA816CE3405/data/Containers/Bundle/Application/8E31FFD3-507E-4728-B90A-505EB60976B9/TasteMap.app`。
- 最后启动：`--tastemap-hybrid-development -AppleInterfaceStyle Light`；环境 `TASTEMAP_VISUAL_QA_MODE=rich`、`TASTEMAP_CORE_PARITY_INITIAL_TAB=map`。后者不决定 Hybrid 初始路由，实际停在 Profile，已截图确认；底栏地图可进入本轮地图。没有把 Native rollback 冒充 Hybrid。
- 渲染：React Hybrid 公共页面 + Native MapKit 地图画布；数据为隔离 Rich QA。分页验收另加 `TASTEMAP_RESTAURANT_ACQUISITION_UI_TEST=1`，其中 24 家明确命名为“分页测试拉面”的假候选只验证分页，不证明真实分店覆盖。
- 最终 staged / DebugQA built / installed / Release built 的 17 个 Hybrid 资源逐字节一致。安装版与构建版 `TasteMap.debug.dylib` 逐字节一致，SHA-256 `2fead2109de69e0e33077df942bfe8de83fb9aa397cd4618dee1ab0445bd28f6`。
- Release 只构建不安装/发布：`/tmp/tastemap-night-release/Build/Products/Release-iphonesimulator/TasteMap.app`。纯净扫描通过（41 app files，17 Web files），无 Debug 开关/fixture/开发地址/本地路径/React 凭证泄漏。
- 没有更新、重启、操作 iPhone；没有生产发布、线上数据修改或地图引擎替换。隔离单测模拟器已关闭，数据未清除。

## 测试证据

- 最终 TypeScript：12 套，154 项 PASS；[日志](./tastemap-night-final-web.log)。包含 Map state/cache/rendering/sizing、全局/地图/Profile 产品合同、搜索位置/简称、Platform、remaining UI contract。typecheck 在正式 stage 内通过。
- 最终 Native：4 套，80 项 PASS；[日志](./tastemap-night-final-native.log)。`MapBrowsingParityTests`、`MapMarkerFarZoomTests`、`CoreProductLayoutParityTests`、`RestaurantAcquisitionTests`。后者真正执行停留 30 秒后重新定位、新坐标传入搜索、刷新失败仍城市搜索等测试。
- Map/Profile UI：2 项 PASS；[日志](./tastemap-night-map-profile-ui.log)。4 次来回拖动、4 次缩放、三组筛选首次清空/返回恢复/Map-List、远景缩放恢复、统计按钮高度。
- 最终新增/复测 UI：3 项 PASS；[日志](./tastemap-night-final-ui.log)。20→24 候选无重复、编辑后清空、纯 pan 实际 compositor 层级、想吃/推荐更大且中心不漂。
- Map/Profile UI 的视觉代码在最终搜索补丁期间未再更改；最终 QA 再次通过 pan/尺寸测试。不是把已被否定的花瓣试版截图当作最终证据。
- 自然重叠测试测得 274 个实际圆心样本，最大投影误差 0.464 pt（门槛 1 pt），初始可见 annotation 36 个。这个数字是测试统计，未显示在餐厅标记上，也不等于全部餐厅数量。
- 远景实际外圈：跨度 1.766° 为 28.000 pt；22.420° 为 19.079 pt；107.769° 为 14.000 pt。点击框始终 44 pt。
- 初次 Native 77-test run 的一个失败来自旧测试要求裸 checkmark，与已确认 checkmark.circle 合同冲突；修正该旧断言后最终 80 项全通过。旧花瓣试版测试及其失败记录不作为本轮通过证据。
- `git diff --check` PASS。

## 截图（均为真实模拟器渲染，QA 数据）

- [城市自然重叠](./map-natural-overlap.png)
- [长三角区域基线](./map-region.png)、[全国比例](./map-country.png)、[世界比例](./map-world.png)
- [想吃标记](./map-want-to-go.png)
- [紧凑 Profile](./profile-compact.png)、[最终实际安装版 Profile](./final-installed-profile.png)
- [分页首 20 个测试候选](./search-page-1.png)、[追加至 24 个](./search-page-2.png)

已逐张检查城市、Profile、全国、想吃与两张分页图。分页页顶部滚动内容进入状态栏下方的既有安全区表现未在本轮重新设计，不将这一局部测试称为整个 Add 页面视觉验收全通过。

## 未关闭、留待用户查看/真机验证

1. **城市密度最终视觉认可**：固定花瓣已撤掉，但“自然重叠是否足够显得记录丰富”仍需用户看图。QA 餐厅坐标集中在少量反复使用的锚点，不能为美化截图移动数据。不同真实坐标独立展示、同坐标叠层/列表的硬约束已保留。
2. **真实漏店/定位**：用户在杭州 iPhone 的“兰州牛肉拉面（凯旋门商业中心店）”场景尚未现场复测。简称测试证明本地匹配接受该名称，不证明 Apple 此刻已返回该店；有界补查不是“连锁分店全部覆盖”。联想是提交后的 provider 补查，不是新增实时下拉 UI。不能声称真实 GPS 偏差已消失。
3. **此前全局闪一下/刷新跳固定页**：本轮解决 scope 异步 fit，不等于关闭 App Shell bootstrap/remount 的更大刷新问题。该旧反馈仍需独立复现和修复，不应在晨间验收时误判为已完成。
4. **历史城市/记录完整性反馈**：本轮独立筛选与同城搜索偏置并不等于已经审计所有餐厅城市标签、地点真值或全部消费历史。本轮不重算/改写私人消费记录，也不补造餐厅城市坐标。
5. **真机更新**：未授权在此夜间操作真机，保持不动。要实际验证新逻辑，需后续明确允许安装新版本或由用户使用更新后的版本复测。

## Design System Compliance

- Core UI：限定范围 PASS。Profile 共享 tokens、Map 固定锚框、Acquisition 44 pt 次级分页按钮；未缩小金额或命中范围。没有新增 page-local 视觉刻度替代共享 token。
- Food & Dining：保留当前 owner-only Map 图源和共享真实图片/category fallback、评分实线/未去过虚线；真实叠层不复制 leader 或画空轮廓代替成员。没有新图源 resolver。
- Canonical Templates：Map top chrome、三 scopes、同组 Map/List、单 Add CTA、Profile 区块顺序、Acquisition 四入口均保留。自然密度最终观感仍是 OPEN，不以自动测试替用户批准。
- 消费者：Browser 与 Capacitor 共享 MyMapBrowsePage/ProfilePage/Acquisition Scaffold；Native rollback 的 MapHomeView/ProfileSummaryTemplate/RestaurantAcquisitionViewModel 已同步本轮语义，owner preview 同步紧凑 token。Public Profile 不属于三项 owner 统计，不改。
- 新增重复页面/组件：0；新增默认 SwiftUI 视觉替代：0。原有 native rollback 是明确保留的渲染边界，不以本轮擅自删除。
- 剩余缺口：用户密度观感、真实 iPhone 搜索定位、全局刷新跳页、全面深色/大字号/小屏及 Browser 真地图运行时，本轮不宣称全部通过。
- 长久规则已同步 Product Design Rules、Map/List 与 Profile layout contracts、Hybrid Architecture 和 Migration Status；没有提升 primary-route 状态。
