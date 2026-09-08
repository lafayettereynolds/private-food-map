# work — 返回键常驻修复

日期：2026-09-06

## 结论

餐厅详情原来的返回按钮位于普通文档流，向下滚动后会离开屏幕。现已接入共享的顶部常驻返回栏：始终保留一个左箭头，点击区域不小于 44 × 44 点，停留在状态栏安全区下方。无需先滑回顶部再返回上一页。

本次只固定紧凑的导航区，没有固定餐厅大图、评分或到访概览，也没有更改餐厅数据、原始坐标、图片选择、消费算法或路由历史。

最终模拟器截图：
- [餐厅详情滚动到到访概览](/Users/lafayette/Projects/private-food-map-hybrid-final-integration/reports/persistent-back-navigation-2026-09-06/restaurant-scrolled.png)
- [餐厅详情页面底部](/Users/lafayette/Projects/private-food-map-hybrid-final-integration/reports/persistent-back-navigation-2026-09-06/restaurant-page-end.png)
- [设置页面底部](/Users/lafayette/Projects/private-food-map-hybrid-final-integration/reports/persistent-back-navigation-2026-09-06/settings-bottom.png)

## 改动及同类入口清查

| 场景 | 处理与证据 |
| --- | --- |
| Hybrid 餐厅详情 | 替换私有返回按钮；全屏卡片不再重复显示关闭 X；外层页面和内部到访历史滚动均验证返回箭头可见、可点 |
| 添加餐厅、食单与食单详情、口味档案与分析、设置、会员 | 通过原有 HybridBackButton 统一接入共享常驻导航；不新增各页面的私有返回实现 |
| Browser 全屏餐厅详情的两个入口 | 同一返回组件；沿用原关闭/返回回调；嵌套滚动容器的吸顶位置正确 |
| 公开主页、公开主页子页面、账户页面、味觉足迹 | 原导航头接入共享容器；公开主页导航移出短 hero，避免吸顶被 hero 高度限制；账户页面移除会阻断吸顶的非实际滚动祖先 |
| Browser 设置嵌套页面 | 原有外层关闭操作保持可达，不被内层返回栏覆盖 |
| 模态卡片和编辑弹层 | 保留既有关闭语义，不额外增加重复返回按钮 |
| Native 回退、Native 能力交接、预览与扩展 | 静态清查：Native 导航使用 NavigationStack/toolbar，位于 ScrollView 之外；地图/列表餐厅入口仍为原有 sheet 语义。本次没有修改其呈现方式，没有把 Native 运行验收冒充为 Hybrid 验收。扩展没有此 React 二级页面返回组件消费者 |

人工看图还发现了详情页底部预留不足：最后一段到访笔记会被固定底栏盖住。已让详情页底部间距使用与底栏相同的 56 点内容高度变量，加上页面间距；安全区仍由外壳负责。最后一条到访内容不被底栏遮挡的 UI 断言及截图均通过。

## 共享实现

- 共享导航：[TasteMapHybridShared.tsx](/Users/lafayette/Projects/private-food-map-hybrid-final-integration/src/components/TasteMapHybridShared.tsx:16)
- 样式唯一来源：[tasteMapNavigation.css](/Users/lafayette/Projects/private-food-map-hybrid-final-integration/src/components/tasteMapNavigation.css)
- Hybrid 详情接入：[HybridAppShell.tsx](/Users/lafayette/Projects/private-food-map-hybrid-final-integration/src/hybrid/app/HybridAppShell.tsx:426)
- 回归脚本：[check-persistent-back-navigation.mjs](/Users/lafayette/Projects/private-food-map-hybrid-final-integration/hybrid/scripts/check-persistent-back-navigation.mjs)
- 产品规则与架构说明已记录常驻返回、状态栏背景、单一入口及原路返回要求。

导航层背景阻止滚动内容穿透状态栏；辅助背景不截获点击。返回操作继续由现有回调/Hybrid history 处理，未创建第二套路由栈或改变主导航。

## 验证结果与范围

1. 最终代码：4 个 Vitest 文件、100 项测试全部通过；包括页面模板、全局契约、平台与路由测试。
2. 最终浏览器共享组件检查：240 项通过。覆盖 360 / 402 / 900 宽度、深浅色、四种滚动位置、十种页面/滚动容器组合；验证唯一按钮、44 点点击区、安全区位置、命中测试、实际回调和外层关闭可达性。这是组件几何/交互测试，不冒充整页线上数据验收。
3. 最终 iOS QA 安装包长页面 UI 测试通过（87.159 秒）：真实列表进入餐厅，检查中部/到访历史/外层页底；再检查设置和口味档案的滚动及返回。明确断言最后一条到访笔记清空底栏遮挡区域。
4. 本轮二级页面往返 UI 回归通过（73.230 秒），地图与发现连续切换回归通过（74.878 秒，8 轮）。这两项执行后，仅补齐详情页底部间距；补齐后再次执行了上述最终长页面 UI、全部 100 项契约测试及 240 项浏览器检查。
5. 最终 QA、Debug 测试目标、Release 构建均成功。正式资源暂存与构建包/安装包均有 17 个 Hybrid 文件逐字节匹配；QA 构建包与实际安装包整体 diff 无差异。
6. Release 纯净扫描通过：39 个 app 文件、17 个 signed Web 文件，无测试开关、fixture、Development URL、本地路径、secret 或 React 凭据界面。
7. 改动文件的 git diff --check 通过；保留已有未提交修改，未创建提交。

验证中修正了三类检查问题：初始 UI 选择器误选了模态层背后的同名足迹，改为可见地图列表入口；Browser 入场动画的矩形浮点精度产生 43.999992 点读数，现等待动画结束并允许 0.001 点数值误差；底栏契约从字面 56px 调整为校验同值共享变量及页面预留。没有减少产品可点击尺寸、隐藏失败或取消返回断言。此前账户滚动祖先问题和底部遮挡均实际修改后复验。

## Design System Compliance

- Core UI System：使用共享导航容器、现有语义颜色和 44 点点击尺寸；安全区与底栏空间有明确归属。
- Food & Dining Visual System：食物图像、裁剪、头像、评分和消费数据不变；未生成替代食物图片。
- Canonical Page Templates：餐厅各内容区顺序、信息密度、操作能力保留；只调整导航常驻与底部必要避让空间。
- 重复实现：移除 Hybrid 私有详情返回样式及全屏重复关闭，Browser/Hybrid 共用返回原语；没有新增 SwiftUI 默认控件或第二套路由。
- 剩余验证边界：真实 iPhone 尚未安装本次版本；Native 回退的历史 sheet 外观本次仅做静态清查，未宣称重新验收全部 Native 页面。没有新增待用户决策的产品选项。

## 运行身份与交付边界

- 仓库：/Users/lafayette/Projects/private-food-map-hybrid-final-integration
- 分支：feature/hybrid-final-integration；基准 HEAD：58bd556b8382734aeae1f08937ba649563682140
- 固定模拟器：E4F3EED9-89D8-405C-B4CB-7CA816CE3405，iPhone 17 Pro / iOS 26.5
- 包：com.lafayette.tastemap.qa，DebugQA；构建目录 /tmp/tastemap-map-anchor-qa
- 实际安装目录：/Users/lafayette/Library/Developer/CoreSimulator/Devices/E4F3EED9-89D8-405C-B4CB-7CA816CE3405/data/Containers/Bundle/Application/2B60A2FE-AB52-4F63-881A-2BED0D669052/TasteMap.app
- 启动：--tastemap-hybrid-development -AppleInterfaceStyle Light；隔离测试环境 TASTEMAP_VISUAL_QA_MODE=rich
- 截图中的餐厅和数值来自明确隔离的 QA fixture，只用于重复 UI 验证，不是线上推荐或真实个人记录的证明。
- 未安装到用户 iPhone，未改动真实账户、餐厅记录或线上服务；Release 主入口仍保持原有 Native 策略。
- 最终 UI 结果：/tmp/tastemap-persistent-back-shipping-scroll.xcresult
- 其他回归结果：/tmp/tastemap-persistent-back-routes-final.xcresult

