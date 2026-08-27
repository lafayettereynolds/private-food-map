# P2-B Photo Selection + Local Gallery + Binary Transfer

更新时间：2026-08-28

## 范围与数据流

P2-B 继续使用 P2-A 的 `PhotoAsset`、`PhotoSyncContractV1` 和 provider-neutral
`storageProvider + storageKey + metadata`。没有创建第二套 Photo 模型，也没有把二进制放进
`/api/v1/sync`。

```text
PhotosPicker
  -> PhotoImportService (orientation + display + thumbnail)
  -> Application Support/TasteMap/Photos (relative paths)
  -> PhotoAsset + persistent upload state in SwiftData
  -> PhotoTransferCoordinator
       -> authenticated Worker binary API
       -> Photo metadata mutation through SyncCoordinator
  -> Development R2 + Development D1
```

SwiftUI 页面只调用 `PhotoTransferCoordinator`。它依赖 `PhotoBinaryAPI` 这一受认证的、
provider-neutral gateway；页面和本地数据层不知道 bucket、R2 credential 或 signed URL。
Worker 当前在 Development 将 gateway 映射到 R2，未来可依据 `storageProvider` 在服务端增加
其他实现，而不改变页面或 Photo identity。

## 选择、文件和压缩

- 使用系统 `PhotosPicker`，保留选择顺序，单个 Visit 最多 10 张。
- 接受 JPEG、HEIC/HEIF、PNG；原始/高质量本地文件保留其受支持格式。
- 使用 ImageIO 应用 EXIF orientation，在 actor 上生成标准 JPEG 展示版和缩略图。
- 展示版长边最多 2048 px、quality 0.84；缩略图长边最多 480 px、quality 0.76。
- 文件写入 `Application Support/TasteMap/Photos/{originals,display,thumbnails}`，文件名使用
  Taste Map Photo UUID，SwiftData 只保存相对路径。
- 三个变体采用 atomic write。部分写入或 metadata 关联失败时清理已经产生的文件；启动时
  也会清理没有 metadata 引用的孤立文件。

## Upload queue 与幂等

`PhotoAsset` 的设备本地状态为：

```text
localOnly -> queued -> uploading -> uploaded
                       |             |
                       +-> failed ---+ (manual/automatic retry)
any active state -> deleted (metadata tombstone)
```

- `uploadMutationID`、retry count、retry-after 和最后一个友好错误保存在 SwiftData；App 被杀后
  `uploading` 恢复为 `queued`。
- 网络恢复、认证恢复、App 回到前台和指数退避到期都会唤醒 queue。
- display/thumbnail object key 由认证用户、Photo UUID 和 variant 决定；Worker 校验 SHA-256。
  相同 key + 相同 bytes 返回 duplicate success，不会重新创建 object；相同 key + 不同 bytes
  返回 409。因此“object 已写入但 response 丢失”可以安全重试。
- 只有两个 binary variant 均成功后，才写入 provider reference 并 enqueue metadata mutation。
  Visit 的本地保存不等待这个过程。

## 下载、缓存与私有访问

- fresh client 先通过 Sync V1 pull Photo metadata，再以 Photo ID 请求受认证 binary endpoint。
- 下载先查本地 original/display/thumbnail；缺失时向 Worker 请求并写入本地 cache。相同请求在
  进程内 single-flight，第二次打开直接读取文件。
- P2-A 旧记录没有 thumbnail key 时，thumbnail 请求会安全回退到 display binary 并建立本地
  thumbnail cache，不把临时 URL 持久化。
- Worker 以已验证的 Taste Map session user 为 owner，D1 查询必须同时匹配 `photo.id` 和
  `user_id`；客户端 payload、猜测 object key 或复制 URL 都没有授权意义。
- R2 object 没有公开 URL。响应使用 private/no-store，并且 iOS 不包含 Cloudflare/R2 Secret。

## 删除与清理

- 用户删除时先在本地写 Photo tombstone，UI 立即隐藏；metadata delete mutation 继续使用 P0/P1
  的 serverVersion、cursor 和 stale-client 防复活规则。
- 只有 metadata tombstone 已经同步后，Worker 才允许清理 private binary；binary cleanup 失败
  不会撤销 tombstone，也不会让照片重新出现。
- 本地原图、展示图和缩略图在 tombstone retention 后清理。取消未保存 Visit 时，prepared files
  或已有 Visit 的 draft Photo metadata 会立即清理；异常退出后启动清理未提交 draft。

## 环境与部署

- Development Worker：`https://api-dev.tastemap.cn`
- Development D1：`food-map-db-development`
- Development R2：`taste-map-photos-development`
- P2-B 不需要新的 D1 migration；使用 P2-A `0019` 已提供的 Photo metadata/tombstone schema。
- Production Worker/D1/bucket 未访问或修改。Production 没有 `PHOTO_STORAGE` binding 时，binary
  endpoint 明确返回 503，绝不静默回退到 Development。
