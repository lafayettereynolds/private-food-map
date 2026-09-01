# Premium, Settings, and Data Utility Layout Contract

## Premium

- The approved historical hamburger is the only Premium identity mark.
- Free/Premium state, benefits, purchase/restore/manage availability, and legal
  context are visually distinct.
- No fake price, fake StoreKit availability, or raw emoji hero.
- Premium gating never changes the layout of content already available to Free
  users beyond an explicit lock/paywall state.

## Settings hierarchy

Settings owns Account, Data & Backup, Sync, Privacy, Permissions, Storage,
Premium, Help, and About. Only implemented/configured capabilities are visible
in Release. Future Import/Restore/Legacy Claim/Delete routes do not appear as
fake working rows.

- Account: identity/edit/sign out; destructive actions are explicitly marked.
- Data & Backup: real Export and real Import flows only.
- Sync: status, pending count, last success, error, and existing retry.
- Permissions: truthful system status and Open Settings when applicable.
- Storage: read-only/cache-only safe controls; never business originals.
- About: Bundle-derived version/build and only configured legal/support URLs.

System Form/List presentation is a permitted iOS adaptation, but hierarchy,
availability, and danger semantics remain the contract.

## Backup/Import/Sync layouts

- Export keeps its privacy warning and `Backup v1 不包含照片原图。`.
- Import visibly separates preflight, dry run, merge plan, confirmation,
  transaction result, and failure-without-write.
- Sync healthy/pending/error states are distinct and use one SyncEngine.

## States

Free/Premium/loading/unavailable StoreKit; logged in/out; legal configured/
missing/malformed; location allowed/denied/not determined; Photos full/limited/
denied; storage empty/nonzero; Sync healthy/pending/error/offline; Backup cancel/
success/failure; Import valid/invalid/ambiguous/confirm/success/rollback.
