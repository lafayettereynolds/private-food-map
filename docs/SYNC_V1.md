# Taste Map Sync API V1

更新时间：2026-08-27

## 边界

P0-B1 只建立 `SwiftData ↔ SyncEngine ↔ Worker ↔ D1` 基础链路，不启用产品 UI，也不配置正式生产 URL、Apple Capability 或客户端 Secret。旧 Web `/api/sync` 保持兼容，但真正改变 Restaurant/Visit 时会写入同一 revision log，使原生增量 pull 可以看到 Web 更新。

## API

### `POST /api/v1/sync/push`

请求包含 `apiVersion = 1`、`schemaVersion = 1` 和最多 100 个 mutation。每个 mutation 包含：

- `mutationId`
- `entityType`: `restaurant | visit`
- `entityId`
- `operation`: `upsert | delete`
- `baseVersion`
- `clientTimestamp`
- `payload`：upsert 必填，delete 禁止携带

Restaurant payload 继续使用 P0-A Restaurant JSON Contract V1。Apple Maps-only Restaurant 不需要 `amapPoiId`；D1 旧兼容列保存空字符串，正式 identity 只来自 `placeIdentities`。Visit V1 只包含原生闭环必需字段，不覆盖 Web 端尚未迁移的高级 Visit 字段。P1-C 增加 canonical `diningMode`（`dine_in | takeout`）和 required-but-nullable `partySize`；新客户端始终编码两项，P0 旧 Visit payload 缺少它们时服务端兼容归一化为 `dine_in` 与 `null`。

响应逐项返回 `applied | conflict`、`duplicate`、`serverVersion`、`revision` 和可选冲突原因。

### `GET /api/v1/sync/pull`

参数：

- `schemaVersion=1`
- `cursor`：上次服务端 revision，首次为 `0`
- `limit`：1–200

响应包含变化后的 `restaurants`、`visits`、独立 `tombstones`、`nextCursor` 和 `hasMore`。游标是服务端单调递增 revision 的不透明字符串，不使用设备时间；每次最多读取 200 条 change log。若同一实体在一页中变化多次，只返回该页最后版本；若数据库已经存在更晚版本，旧事件跳过并由后续 revision 返回。返回 Visit 时会附带本页尚未包含的父 Restaurant 依赖快照（即使父记录已 tombstone），确保新设备不会得到失去 Restaurant 映射的 Visit；这不是全库下载。

## Idempotency 与队列

D1 使用 `(authenticated user, mutationId)` 唯一 receipt。实体写入、change log 和成功 receipt 在同一个 D1 batch 中提交。响应丢失后重试同一 mutation 会返回已有 receipt，不会再次增加版本或插入实体。同一 mutation ID 携带不同内容会返回 409。

iOS `SyncMutation` 持久化 mutation ID、实体、动作、时间、base version、JSON payload、重试次数、下次重试时间及状态。相同实体尚未上传的连续编辑会合并为一个 pending mutation；上传时仍产生的新 mutation 会在 acknowledgement 后 rebase。`uploading` 状态在 App 重启时恢复为 `queued`。

网络/API 失败只更新队列重试信息，不回滚 Restaurant/Visit 的本地保存。

## 删除与冲突

- 服务端删除只写 `deleted_at` tombstone，并增加 `server_version`。
- iOS 对已同步记录执行 soft delete；从未到达服务器的本地临时记录可以连同未发送 mutation 一起清除。
- 自动冲突策略是 server-version optimistic concurrency：mutation 的 `baseVersion` 必须等于 D1 当前版本。
- `updatedAt` 和设备时间仅为领域/展示信息，不决定胜负。
- tombstoned entity 不接受普通 upsert；旧设备的 stale update 返回 conflict，pull 后应用服务器 tombstone。
- P0-B1 自动 reconciliation 以服务器版本为准，同时把冲突 mutation/payload 保留为 `conflicted`，供 P0-B2 诊断或未来人工恢复，不自动覆盖服务器。

## 用户隔离与认证边界

V1 route 始终从服务端认证上下文取得 viewer ID，并覆盖 payload 中的 `userId`。实体 ID 已属于其他用户时返回 403；Visit 只能引用当前 viewer 所有的未删除 Restaurant。

本地 Worker 在 loopback 接受 `X-Taste-Map-Test-User` Development identity。隔离的远程 Development Worker 只有同时设置 `APP_ENVIRONMENT=development` 与 `SYNC_AUTH_MODE=development-test` 时才接受该 header，并且缺少 header 时返回 401；Production 或未明确配置的 Worker 不接受测试身份。正式 token/session、JWT 验签和 iOS Keychain 集成属于 P0-B2-B。未配置时返回 503/401，不回退为 `owner`。

P0-B2-A 的远程测试身份仅用于隔离的 Development D1，开发 URL 不是正式认证边界。它不得配置到 Production Worker，也不得承载真实用户数据。

隔离 Development Worker 使用 `https://api-dev.tastemap.cn`；iOS 通过随 App 打包的非敏感 `APIEnvironment.plist` 读取 Development 地址，Info.plist 与进程环境仍可覆盖它。配置文件不包含 Production URL，Production URL 缺失时继续明确失败。

## iOS 模型选择

- 本地 `UUID id` 保留，作为 SwiftData 稳定主键。
- 增加可空 `remoteID`，因为既有 Web/D1 ID 不保证是 UUID；新 iOS 数据使用本地 UUID 字符串作为 remote ID。
- Restaurant/Visit 增加 `deletedAt`、`serverVersion`、`lastSyncedAt`、同步状态；已有 `createdAt/updatedAt` 直接复用。
- P1-C 为 Visit 增加带 `dine_in` 默认值的 `diningMode` 和可空 `partySize`，使用 SwiftData additive lightweight migration，不删除旧 Store。
- Restaurant 保存 `remoteRecordData` 作为不透明 canonical snapshot，使原生编辑名称/地址时不会清空尚未迁移的 Web 字段；没有复制整套 Web 字段到 SwiftData。
- `SyncCheckpoint` 保存 cursor；`SyncMutation` 保存离线队列。

新增属性均为可空或带默认值，新实体通过 SwiftData 当前 schema 自动增量创建；本轮没有启用 CloudKit。

## 部署安全

P0-B2-A 已创建独立 `food-map-db-development` 与 `private-food-map-development`。新 Dev D1 的首次 preflight 只有 Cloudflare 内部表且无业务数据，因此顺序应用完整 migration 链；P1-C 的 `0018_visit_core_fields.sql` 保留 legacy `party_size`，增加 canonical nullable `party_size_optional` 和滚动部署兼容 trigger，不重建 `visits`。真实 Worker/D1 和 iOS API client 往返测试数据最终必须保持 tombstone。

Production D1 尚未预检或修改。后续 Production 部署顺序固定为：

1. 运行 P0-A production preflight。
2. 导出并验证可恢复备份与 migration 风险。
3. 确认正式认证、Production Worker URL 与用户映射策略。
4. 再评估 Production migration；migration 必须先于新 Worker 部署。

客户端不包含 Cloudflare、D1、R2 或 Google Secret。
