# P2-A Dish + Photo 数据基础

更新时间：2026-08-27

## 审计结论

| 对象 | Web | D1 / Worker（P2-A 前） | iOS（P2-A 前） | P2-A |
|---|---|---|---|---|
| Dish | `Visit.dishes[]`；字段 `id/name/taste/rating/price/imageData/photoId` | `visits.dishes_json`，只走旧 `/api/sync` | 无 | 独立、Visit-scoped Dish；继续投影 `dishes_json` |
| Photo | 独立 metadata；本地 data URL/cache；待上传 | `photos` 表；旧同步；验证偏 Google Drive | 只有 Provider 协议 | `PhotoAsset` metadata + sandbox file；Sync V1 metadata |
| Binary provider | 默认用户授权的私有 Google Drive；CloudKit 占位 | D1 不存 binary/token | 无实现 | 保持 provider-neutral；binary upload 延后 P2-B |

Development D1 在迁移前有 21 Restaurant、14 Visit、0 Photo、0 个含 Dish 的 Visit；没有 malformed `dishes_json`、空/重复 Dish ID 或 orphan Photo。Production 未查询。

## Dish JSON Contract V1

所有 key 都是 required；`nullable` 表示 key 必须出现且值可以是 `null`。

| 字段 | 类型 | nullable | 说明 |
|---|---|---:|---|
| schemaVersion | 1 | 否 | 合同版本 |
| id/userId | string | 否 | Taste Map Dish ID；userId 无授权意义 |
| restaurantId/visitId | string | 否 | 当前用户拥有的父关系 |
| name/taste | string | 否 | 保留 Web 真实字段；允许空字符串兼容旧草稿 |
| rating | 0.5...5 half-step | 是 | 未评分为 null |
| price | non-negative number | 是 | 菜品价格 |
| photoId | string | 是 | 兼容 Web 代表图片引用 |
| sortOrder | non-negative integer | 否 | 由旧数组 index 回填 |
| createdAt/updatedAt | ISO datetime | 否 | 领域时间，不做并发裁决 |
| deletedAt | ISO datetime | 是 | soft delete |

Dish 仍表示“某次 Visit 中记录的一道菜”，Restaurant 由直接 `restaurantId` 和 Visit 双重校验。当前 Web 没有稳定的 Restaurant-level canonical dish，因此 P2-A 不凭空合并同名菜；未来若需要跨 Visit 复用，应新增 RestaurantDish + association migration。

## Photo JSON Contract V1

所有 key 都是 required；nullable key 不可省略。

| 字段 | 类型 | nullable | 说明 |
|---|---|---:|---|
| id/userId | string | 否 | Taste Map Photo ID；与 provider key 分离 |
| restaurantId/visitId/dishId | string | 是 | 按 kind 校验必需组合 |
| kind | restaurant-marker/visit/dish/avatar | 否 | 业务用途 |
| storageProvider | google-drive/cloudkit/r2/oss/cos | 否 | provider-neutral discriminator |
| storageKey | string | 否 | provider locator；不是 Photo ID 或 signed URL |
| providerAccountId | string | 是 | Drive 等账号隔离；不含 token |
| thumbnailStorageKey/fileName | string | 是 | metadata |
| mimeType/byteSize | string/integer | 否 | byteSize 非负 |
| width/height | positive integer | 是 | 原图尺寸 |
| sortOrder | non-negative integer | 否 | 展示顺序 |
| visibility | private/friends/public | 否 | metadata 访问范围 |
| createdAt/updatedAt/deletedAt | ISO datetime | deletedAt | soft delete |

iOS 的 `PhotoAsset` 额外保存 `localFileRelativePath`、`uploadState`、retry/error 和普通 sync metadata；这些设备状态不进入共享 JSON contract。

## Provider 与本地文件

- 当前真实 Web provider 是 Google Drive OAuth；CloudKit 是未实现占位，Development Worker 没有 R2 binding。
- P2-A 不选择或迁移 provider。R2/Google Drive object key 永远不是 Photo 主键。
- 原图保存于 Application Support/TasteMap/Photos，SwiftData 只保存相对路径和 metadata，不保存 JPEG/HEIC/PNG bytes。
- localOnly→queued→uploading→uploaded/failed；删除进入 deleted。Visit 保存不等待上传。
- P2-A 只完成状态机和 metadata handoff；provider binary upload、response-loss object 去重、下载/cache 进入 P2-B。

## 同步、删除与兼容

- push 依赖顺序固定为 Restaurant→Visit→Dish→Photo。
- 四实体共享 mutation ID、serverVersion、revision cursor、receipt、idempotency、conflict 与 tombstone。
- `0019` 新增 `dishes`，扩展 `photos`，并复制 0016 ledger 到允许四实体的新 ledger；旧 ledger 和旧 migration 不删除。
- 旧 Web Visit 写入会双写 Dish rows；V1 Dish/Photo 写入会刷新旧 `dishes_json`、`photo_ids_json`、marker/dish photo projection。
- Photo metadata tombstone 与 provider object 物理删除解耦。本地 tombstone 默认保留文件 7 天后可清理；远端 object retention/garbage collection 延后 P2-B。
- Worker 只按认证 viewer 读写 metadata；客户端声明的 userId 被覆盖。P2-A 不新增公开 object/download URL。
