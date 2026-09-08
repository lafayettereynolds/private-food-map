# Privacy retention — implementation and release activation

This is a local, un-deployed change. `PRIVACY_RETENTION_ENABLED=true` must only be enabled after migration `0040_privacy_retention.sql` and the policy are reviewed for the same release. No Production deployment or D1 query was performed.

All windows are centralized in `worker/privacyRetentionPolicy.ts`. These are product retention decisions, not assertions of a statutory retention obligation.

| Class | Data | Reason and lifecycle |
|---|---|---|
| A | Ordinary deleted record payload | Keep for 30 days for sync/retry/conflict recovery, then remove free text, coordinates, ratings, image references and other payload. R2 deletion must succeed before erasing object keys. |
| C | Minimal tombstone IDs, owner/parent IDs, deletion date and server version | Preserve while the account exists so long-offline devices cannot restore deleted records and FK graphs remain valid. These are minimized synchronization metadata, **not anonymous data**. After account closure they enter the finite account purge below. |
| B | Account Visit/Restaurant/UGC payload, private directory avatars | Account is disabled when deletion processing starts. R2 objects are deleted before the job reports completed. D1 payload enters clearing at 30 days; ordinary owned graph and sync ledgers are physically purged at 365 days after closure, subject only to the specific financial/other-user benefit dependencies below. |
| B | Closed-account security/recommendation records, reports and revoked sessions | 90 days for retry, moderation and abuse investigation, then purge. Active-account recommendation preference events remain because they are the current preference source, not disposable analytics. |
| D | Closed-account Apple transaction/owner proof | Keep until 365 days after both account closure and the transaction's end/latest update, for reconciliation and dispute investigation. Then remove audits, transactions, owners and account-token mapping in FK order. No payment-card data. |
| D | Gift / Referral provenance shared with another user | Do not destroy another user's benefit when an inviter deletes their account. Keep the minimum relation while that related reward is pending/effective and for 365 days after its end; then purge it and the closed account. Lifetime benefits have no scheduled expiry while their recipient remains eligible; this is a concrete entitlement dependency, not a general permission to retain deleted content forever. Own deleted-account rewards do not block purge. |
| B | Deletion task/token hashes | Retained through retries and the account retention period; removed with the final account purge. |

`completed` on the account-deletion API means: account unusable, public content withdrawn, authentication identity/email removed, and a fresh owner-prefix R2 listing plus the object queue both prove zero remaining. It does **not** promise immediate physical erasure from D1/backups. If R2 or D1 processing fails, the job remains failed/retryable and the opaque status token can resume it.

The existing five-minute scheduled Worker is reused for deletion continuation when explicitly enabled. The D1 retention pass runs daily at 18:00 UTC (02:00 China time). A failed run is not a successful purge; repeat execution is safe. Accounts held by a financial dependency rotate through `privacy_retention_attempts`, rather than starving later accounts.

Source audit covered actual migrations, FK dependencies, sync mutation receipts and change logs, stale-write conflict rules, account authentication, R2 keys, StoreKit ownership and immutable referral reward relationships. We do not rewrite the sync protocol, delete another user's independent comments, change Premium entitlement calculation, or consume offer codes.

Website review must distinguish “enters clearing after 30 days” from an impossible unconditional deadline during storage outages. Deployment operations must monitor failed jobs and scheduled failures and resolve them; the implementation does not mark failure as completed.
