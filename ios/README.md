# Taste Map iOS 分享导入源码

这里提供外部餐厅链接导入所需的平台无关模型、App Group 待处理队列、Share Extension 控制器和主 App 导入协调器。当前仓库尚无 Xcode 工程，因此 Windows 端不会生成伪造的签名文件或声称 Share Extension 已安装。

在 Mac/Xcode 中需要完成：

1. 创建主 App 与 Share Extension Target，并把 `Shared/` 同时加入两个 Target。
2. 在两个 Target 启用同一个 App Groups Capability，把真实组名写入 `TASTE_MAP_APP_GROUP_ID` Build Setting。
3. 主 App 注册 `tastemap` URL Scheme，并将传入 URL 交给 `ExternalImportCoordinator`；解析完成后展示 `ExternalRestaurantImportConfirmationView`。
4. 初始化 `ExternalImportCoordinator` 时通过 `authorizeRequest` 注入当前原生登录态；不得在分享扩展或 Deep Link 中携带令牌。
5. 将已登录用户的稳定认证 subject 写入 App Group 的 `taste-map.current-user-subject`；退出登录时清除。
6. 在真机上验证高德、Apple 地图、网页 URL、纯文字、重复分享、离线重试和账号切换。

Deep Link 只包含不可预测的 `importId`；原始分享内容保存在 App Group 的私有容器中，解析成功后立即删除。

确认页不会因为解析成功就自动创建 Restaurant 或加入“想吃”。高置信度唯一候选仍需用户选择操作；中等置信度显示候选列表；低置信度只打开现有餐厅搜索。
