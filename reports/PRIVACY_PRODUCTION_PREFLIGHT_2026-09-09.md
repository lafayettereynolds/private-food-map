# Privacy Production closure preflight — 2026-09-09

## Outcome

NEW CANONICAL SOURCE CREATED. Website factual patch PASS locally; not deployed. D1 RETENTION PRODUCTION BLOCKED by observed Cloudflare error 7500 (daily free-tier row-read limit). Final consistency PENDING. App Privacy PENDING USER SCREENSHOT, unchanged. No Production migration, Worker rollout, policy rollout, Hybrid cutover, Final RC or TestFlight upload occurred.

## Website provenance and recovery

Original repositories/worktrees/hidden paths, Desktop/Documents/Downloads/Projects, Git history, archive inventories, shell/Wrangler history had not yielded a recoverable source in the preceding audit. Additional filename searches and current deployment metadata confirmed the existing service, but no original directory. We stopped searching and used the newly authorized canonical-source recovery.

`web-public/public/` is the formal Git-managed source for index, privacy, support, styles and the metadata-derived root rewrite. Commit `9882cfe` preserves the original four public resource bytes. Homepage/support/styles hashes remain identical after privacy changes. No redesign, meta/title/CSS change or support-page replacement. The support page's historical deletion-path placeholder remains unchanged under the explicit unaffected-page requirement; fixing it would be a separate content delta.

Cloudflare website Worker `fancy-fog-1341`, version `f9d342db-afb5-4153-9085-8385dd725f01`, deployment `9d8775c1-dcb6-4a4e-a4f0-0bc80e0afc88`. Version API confirms assets-only, html_handling=none, root internal rewrite `/ /index.html 200`. Source download HTTP 204 is explained by assets-only deployment, not proof of an unavailable JavaScript source. No bindings. Public URLs fetched successfully over HTTPS with curl.

Privacy changes are limited to actual identity/purchase/entitlement fields, Apple/MapKit/Cloudflare roles, removal of supplier and deletion-path placeholders, and precise lifecycle semantics in sections 2,5,7,8 plus effective date. No payment-card collection claimed. The policy explains eligibility windows and dependency-based extensions rather than falsely promising all data disappears by an absolute day-365 deadline.

The reviewed policy cannot go live ahead of retention activation. Current online policy remains the pre-change baseline. No new online hash/version is claimed. Source hashes and rollback version are recorded in web-public/baseline.json; build/deploy/rollback instructions are in web-public/README.md.

## Production preflight evidence

- Active API Worker `private-food-map`, version `8d658acc-c58a-4486-becf-850cfcbdd467`, deployment `3206b397-7e04-431f-a2e5-ea89b79733cf`.
- DB: `food-map-db`, ID `064f6607-5464-4530-bc58-5f7d1e02f09f`.
- R2: `PHOTO_STORAGE` -> `taste-map-photos`.
- Cron: `*/5 * * * *`; retention switch absent/disabled.
- 40 applied migrations; most recent `0038_storekit_environment_isolation.sql`. 0040 tables/lease columns absent and existing immutable triggers unchanged. 0040 pending.
- Schema delta: two new tables, two nullable job-lease columns, three DELETE guards replaced with atomic-retention authorization conditions. No table rebuild or Restaurant/Visit content update in the migration.
- Four successful bounded metadata/count queries: 361 rows read, 0 written. Observed 2 users (none closed), 24 restaurants (none deleted), 23 visits (2 soft deleted), 0 photo rows, no deletion jobs. These are a preflight snapshot, not post-deployment proof.
- A subsequent migration-list/retention-eligibility query was rejected with 7500 daily quota exceeded. No repeat queries or Production cleanup were attempted after that response. Do not infer that the bounded diagnostic caused the account-wide exhaustion.
- A D1 Time Travel bookmark was captured privately before any possible mutation. It is not an export and does not prove recovery has been tested.

## Isolated backend candidate

Path: `.private/privacy-production-candidate`, retained by branch `privacy-retention-production-20260909`, commit `f13e0b2`.

Base `e03f0495` reconstructs the production integration. Comparing its compiled JS to downloaded active Worker after normalizing only dependency paths revealed exactly the live eight-line Referral hold; candidate preserves that hold and adds privacy commit 0b02bed (cherry-pick 6adde00). No unrelated dirty Hybrid/auth/discovery changes from the main working tree enter this candidate. Production asset snapshot remains 28/28 matching the previously verified baseline hashes. Fresh online 28-file parity must be checked before actual rollout; local snapshot equality is not a fresh deployment check.

Candidate Worker TypeScript PASS. Candidate Worker suite: 37 files / 374 tests PASS, including privacy boundary/retry/tombstone and preserved referral boundary. Website Wrangler dry-run PASS. API Wrangler dry-run PASS. Original main-tree 378-test and iOS F1-C4/account isolation results remain unchanged; isolated branch has a different suite inventory.

## Ordered rollout and recovery — prepared, not executed

1. Restore D1 quota, re-read migration state and bounded retention eligibility, ensure current live Worker version still matches this preflight, and freshly verify preserved asset hashes. If any drift appears, stop and reconcile.
2. Validate schema compatibility and 0040 locally; capture a fresh recovery bookmark. Run only pending 0040 after verifying no unrelated pending migrations. Do not blindly apply a changed migration directory.
3. Deploy isolated candidate with switch disabled, preserving current variables/secrets/domains/routes/assets. Verify health/ready, authentication boundaries and bindings.
4. Before enabling retention, complete a read-only eligibility/dry-run against restored D1 and measure row usage. Only then enable `PRIVACY_RETENTION_ENABLED=true`; scheduled deletion retry runs every five minutes, content retention at 18:00 UTC daily. No HTTP cleanup bypass endpoint is introduced.
5. Verify a bounded safe execution and unchanged active owner records, plus account-deletion behavior on controlled test data. Do not delete a real user's account as a test. Capture post-run counts/errors and actual deployment IDs. All these post-deploy checks are currently NOT RUN.
6. Once backend activation and policy factual review pass, deploy `web-public/wrangler.jsonc`; verify live policy hash/HTTPS/URLs and unchanged homepage/support/styles.

Quota impact: deletion retries query only queued jobs/account prefixes, R2 cleanup paginates. Retention has configured photo/redaction/account batches but several history-cleanup SQL statements may scan whole relevant tables; bounded output is not a guarantee of bounded billed D1 reads. Daily execution and existing five-minute settlement cron share the account quota. R2 list/delete cost depends on eligible objects; no R2 mutation was made by this preflight. Production eligibility/cost verification is still blocked, so activation is not classified safe/ready.

Rollback: disable retention first; restore API version `8d658acc-c58a-4486-becf-850cfcbdd467` if rollout regresses. Leave additive 0040 schema in place unless a reviewed recovery requires otherwise; do not blindly downgrade tables or restore the entire database over newer user writes. R2 physical deletion is irreversible without an independently verified backup, so code rollback cannot recover objects. Website rollback is independent and uses its recorded version/baseline. No speculative promise of R2 recovery is made.

Rollback package prepared locally: `.private/privacy-production-closure/website-rollback-9882cfe.tar.gz`; SHA-256 `be80737c63d05a5a5c4859d33db95e84034a48e6c130d47810cc1ef1c3fb4a29`. Contains the Git baseline pages, verified root mapping and website-only Wrangler config.
