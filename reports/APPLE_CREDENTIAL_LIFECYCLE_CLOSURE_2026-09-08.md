# Sign in with Apple credential revocation lifecycle closure

2026-09-09 后继：Apple lifecycle 已独立提交 `d3ea340`；原 3 条 Worker deletion 失败已关闭且全 Worker 382/382 PASS。当前结果以 [Account deletion regression closure](ACCOUNT_DELETION_REGRESSION_CLOSURE_2026-09-09.md) 为准；本报告下文保留 9 月 8 日历史时点，不再代表当前 Apple lifecycle 仍失败。

2026-09-08；项目 `/Users/lafayette/Projects/private-food-map-hybrid-final-integration`。
范围仅认证撤销生命周期；此前 capability/entitlement、权限、Share Extension 审计结论保持不变。

## 最终状态（23:23 CST）

| 项目 | 结果 |
|---|---|
| SIGN IN WITH APPLE CONFIG | PASS（沿用已验收配置，本轮签名回归通过） |
| CREDENTIAL STATE CHECK | PASS |
| CREDENTIAL REVOKED NOTIFICATION | PASS |
| APP LAUNCH / RESTORE CHECK | PASS |
| ACCOUNT SWITCH ISOLATION | PASS（自动化） |
| LOCAL SESSION CLEANUP | PASS（自动化） |
| SERVER ACCOUNT PRESERVED | PASS（撤销路径只有 logout，没有 Account Delete） |
| NATIVE AUTH / ACCOUNT TESTS | PASS，21 tests / 3 suites |
| AUTH TESTS（包含额外 Worker 回归） | FAIL，Worker 11 条中 8 PASS / 3 FAIL，均为账号删除相关 |
| RELEASE BUILD | PASS，最新源码 signed Release iPhoneOS main + extension |
| EXISTING RELEASE CAPABILITY AUDIT | PASS，44/44 |
| EMBEDDED SIGNATURE / IDENTITY / PROVISIONING | PASS |
| SIGN IN WITH APPLE LIFECYCLE 最终全绿 gate | FAIL / NOT CLOSED：客户端实现与 Native 验证完成，但当前工作区扩展回归未全绿，不能宣称本轮全部自动化通过 |
| REAL DEVICE TEST STILL REQUIRED | YES |

这不是 Apple credential 检测仍未实现：该缺口已由下面的源码和 21 条 Native 回归覆盖。保留 FAIL 是为了不隐去当前工作区真实失败，也不把模拟器测试冒充真机。

### 唯一新增的集成回归阻塞

本轮未修改的 `worker/accountDeletionV1.ts` 正在包含另一组隐私保留策略改动。首次 Worker 回归因引用不存在的 `./privacyRetentionV1` 无法加载；该 import 在工作区随后改为 `./privacyRetentionPolicy`。本任务没有修改任一文件。重跑后 3 条真实失败：

1. `worker/authV1.integration.test.js`：删除完成后相同 Apple identity 新建账号；预期 deletion status=completed，实际 failed。
2. `worker/releaseSafetyV1.integration.test.js`：持久幂等 D1/R2 account deletion；预期 completed/retryable=false，实际 failed/retryable=true。
3. 同文件：R2 失败后恢复删除任务；预期该阶段 users.deleted_at=null，实际已有时间值。

以上是本地 mock 数据库测试，不访问 Production D1/R2。没有把失败归因为已证实的具体后端根因，也没有为了绿灯跳过用例、回退其他任务改动或改写账号删除语义。需由该后端改动完成回归后再重跑并关闭最终 gate；客户端撤销代码不应因此重构。

最终审计包：`/tmp/tastemap-apple-lifecycle.tVwjud/Release/Build/Products/Release-iphoneos/TasteMap.app`。
主可执行文件 SHA-256：`dda0e51379dbc0d5a87a3b754ac2def63d3b6bdb7a22bb813cb961378f29677f`。
build=1、version=1.0，沿用源码默认，仅独立本地审计；Apple Development 签名，不是 Final RC/真机唯一测试包，未安装。

## 实现与边界

现有入口仍是 Native Profile / Hybrid auth handoff → `AppleSignInService` → AuthenticationServices callback → nonce/state + identity token → 原有 backend exchange → `AuthSessionManager.accept` → 私有 Keychain。没有改 backend payload/endpoint、authorization code 策略、Bundle ID、Team、entitlement 或登录 UI 设计。

唯一新增身份字段 `AuthCredential.appleUserIdentifier: String?` 来自成功 Apple credential 的 `user`，与同一 backend exchange 得到的 Taste Map userID 一起保存在原有私有 Keychain credential。不使用设备 ID、不用 Taste Map userID 冒充 Apple ID、不向 React 暴露、不写日志。Token refresh 保留这个字段。

旧版 Keychain 的 Codable 解码仍兼容；但旧会话没有 Apple ID，无法安全检查授权，因此在正式 restore 时清除认证会话并要求一次重新登录来补齐。不会删除本地记录、服务器账户或购买权益；不要求重复购买或 Restore。代码不从未验证 JWT/邮箱/其他账号猜测 Apple ID。

| Apple 状态 | 行为 |
|---|---|
| authorized | 保留 session |
| revoked | 原子使当前 session generation 失效、停用内存 credential、删除对应私有 Keychain credential、异步 best-effort 原有 logout |
| notFound | 同上，当前 credential 不再有效 |
| transferred | 保留 session，不当作 revoked；未来真正 Team transfer 时需单独补用户 identifier migration |
| unknown 新枚举值 / 系统调用错误 | 不武断当作 revoked，不删除数据；下一次 foreground/通知可重试 |

Apple 官方定义 transferred 为需要迁移 identifier 的 App Team transfer，并允许将当前 session 视为已授权。Taste Map 目前没有执行 Team transfer，因此本轮只保留安全边界，迁移流程明确为 follow-up，而不是假装已实现。参考：[CredentialState](https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidprovider/credentialstate)、[Bringing new apps and users into your team](https://developer.apple.com/documentation/signinwithapple/bringing-new-apps-and-users-into-your-team)。

## 生命周期与异步隔离

- `AppleCredentialObservers` 每个 NativeAuthServices 实例只创建一次，监听 Apple credentialRevokedNotification 和 UIApplication.didBecomeActiveNotification；notification payload 不决定要清谁，只触发查询当前 Apple identity。
- observer callback 弱引用 services；observer 析构移除全部 registration，无 retain cycle。重复 notification 和重复 restore 查询在 session manager 同 generation 下复用一个正在进行的 Apple request。
- `restoreLocalAccountScope()` 在恢复 authenticated UI scope 前 await credential validation；Native / Hybrid 均使用已有入口。不是 React render/page appearance 驱动的全局轮询。
- actor 中每次 accept/logout/invalidation 都更换 UUID generation。Apple request 记录 originating generation + Taste Map userID + Apple userID；结果全部仍匹配才允许清理。
- Native UI scope 也有独立 generation，阻止迟到的旧账号结果覆盖新 UI scope。同一账号普通页面激活不无故换 generation。
- 现有 token refresh 同样加入 generation guard（包括复用 in-flight refresh 的调用者），避免撤销/切换后旧 refresh 成功或失败 callback 写回/清理新凭据。

## 清理内容，不删除业务数据

`AuthSessionManager.validateAppleCredential()` 不持有 SwiftData container、文件数据清理器、Account Delete API 或服务器账号管理 API。只清当前 auth material，并复用原有 `AuthAPI.logout`；网络失败不恢复本地登录，也不阻塞 UI 清理。

NativeAuthServices 将 scope 切 guest，再调用 `TasteMapHybridRuntime.appleCredentialDidInvalidate()`：清 acquisition/photo-selection 的内存缓存、bridge read caches，调用既有 Premium `sessionDidEnd` 与 Sync `sessionDidEnd`，发出正常 signedOut auth event。没有修改 Premium/StoreKit 规则，只复用现有 logout 清理方法。

`ContentView` 对 authenticated userID 设 presentation identity，使账号退出时旧私有页面的 SwiftUI state 不继续展示。没有新增页面、技术错误文案或视觉设计；持久化 Restaurant/Visit/Photo/待同步业务数据不删除，现有 owner scoping 保留其他账号数据。

Keychain 删除异常只记录非敏感分类 `credential_cleanup_failed`；内存 credential 仍失效。本轮自动测试覆盖正常存储清理，未伪称系统 Keychain 永远不会报错。若 OS 拒绝删除，后续启动仍要重新执行 Apple validation，不将已确认失效的当前内存 session 恢复。

## 本轮文件

- `ios/TasteMap/TasteMap/Models/Remote/AuthV1Contracts.swift`：本地可选 Apple identity 字段。
- `ios/TasteMap/TasteMap/Services/AppleSignInService.swift`：关联成功 credential.user 与 backend session；现有验证不变。
- `ios/TasteMap/TasteMap/Services/AuthSessionManager.swift`：验证、单次处理、generation 和 refresh 隔离。
- `ios/TasteMap/TasteMap/Services/AppleCredentialLifecycle.swift`：Apple API adapter 和 observer owner（新增）。
- `ios/TasteMap/TasteMap/Services/NativeAuthServices.swift`：restore/foreground/notification 接入和 scope invalidation。
- `ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntime.swift`：现有 signed-out 内存上下文清理入口。
- `ios/TasteMap/TasteMap/TasteMapApp.swift`：弱引用连接 invalidation handler。
- `ios/TasteMap/TasteMap/ContentView.swift`：清除跨会话 presentation state。
- `ios/TasteMap/TasteMapTests/AppleCredentialLifecycleTests.swift`：新增 Native 自动测试。
- 本报告及前一 capability 报告的后继链接。

COMMIT BASE：`4d5fe935ff8658644ef2ecf3cfc872b87a9fcc50`。
本轮变更在 dirty integration workspace 中，未新建 Git commit，未把其他任务改动混入提交；不得把 HEAD 当成已包含修复的独立 release commit。

## 验证证据目录

`/tmp/tastemap-apple-lifecycle.tVwjud` 为独立临时审计目录，不覆盖真机 QA build/staged assets，不是长期 Archive。

- `tests-closure.log` / `Tests/Logs/Test/*.xcresult`：AppleCredentialLifecycleTests、AuthSessionManagerTests、LocalMultiAccountIsolationTests。
- `release-final.log`：最新集成源码显式 Release / generic iOS device build。
- `backend-tests-final.log`：本地 mock Auth/Release Safety 回归，无 Production D1。
- `capability-audit.json` / `embedded-identity.json`：完成构建后的签名与既有 capability audit。

本轮不安装物理 iPhone、不触发真实 Apple 登录/授权撤销、不部署 Production、不切 HYBRID_PRIMARY、不 Archive、不生成 Final RC、不上传 TestFlight。

## 真机仍需验证

REAL DEVICE TEST STILL REQUIRED：YES。

- Apple Sign In：正常登录，确认 Taste Map 用户与历史内容恢复。
- revoke / re-login（条件允许）：使用已批准同一个真实测试包，在系统 Apple 账户的 Sign in with Apple 管理中停止对 Taste Map 的授权；回到 App 应处于正常未登录状态，重新登录后业务数据仍在。不要把这个动作当 Account Delete，不需要重买/Restore。
- Universal Link 和 Share Extension：沿用前一报告的 cold/warm 验收，不在本轮自动化中冒充真机 PASS。
