# Sandbox referral Offer Code testing

## Adopted mapping and test boundary — 2026-09-08

VERIFIED mappings: 580777 → invitee14; 580852 → Reward1; 580833 → Reward2; 580908 → Reward3; 580853 → Reward4; 580922 → Reward5. Mapping gate PASS. Retained inventory evidence:60 unused codes in ignored private Sandbox inventory; no code values are published here.

The user authorizes a separate Sandbox build, private-food-map-development and Sandbox inventory only for invitee14 and Reward1 real-device acceptance. Required chain: Apple Sandbox redemption → verified Apple transaction → Sandbox server verification → Taste Map account binding → authoritative entitlement → Premium UI refresh. No Production entitlement/reward-ledger writes. Rewards2–5 need automated mapping/allocation/idempotency/isolation coverage, not real code consumption.

Production baseline dd0369b9 is ADOPTED. Its sandbox_offer_forbidden403 is expected and must remain. Formal candidate2026090801 stays on https://api.tastemap.cn, no origin fallback or test-server default. No codes in the formal client, Production inventory or Debug verification bypass. Separate-path authorization does not mean a Sandbox build or real redemption has passed. Both real Offer gates remain USER ACTION REQUIRED. See [current baseline report](../reports/PRODUCTION_BASELINE_ADOPTION_2026-09-08.md); conflicting earlier mapping/approval notices below are historical.

## Scope and current gate

This is a local internal-operator test tool, not a shipping reward-delivery channel.
It does not add StoreKit products, alter App Store Monthly/Annual, replace the
authoritative entitlement service, or change production referral reward rules.
No Production inventory is created. Every CLI operation requires `--environment sandbox`.

The six supplied downloads each contain ten codes and no headers, offer names,
durations, expiration dates, or environment metadata. Sandbox provenance comes
from the user's explicit description; it cannot be inferred from the CSV bytes.
All sixty entries were imported as unused and **unmapped**. Do not infer the
file-to-offer mapping from ascending filenames. Await the user's confirmation.
The Apple Offer reference identifier must also match App Store Connect exactly.

| Logical key | Offer | Reward |
|---|---|---|
| invitee | 被邀请用户 14 天会员 | Qualified invitee, once, 14 days |
| referrer_1 | 邀请奖励 1 | Qualified referrer slot 1, 30 days |
| referrer_2 | 邀请奖励 2 | Qualified referrer slot 2, 30 days |
| referrer_3 | 邀请奖励 3 | Qualified referrer slot 3, 30 days |
| referrer_4 | 邀请奖励 4 | Qualified referrer slot 4, 30 days |
| referrer_5 | 邀请奖励 5 | Qualified referrer slot 5, 30 days |

## Private storage and Git protection

Private storage relative to the repository: `.private/sandbox-offer-codes/`.
`inventory.sqlite` holds the inventory and append-only operator audit. Each
batch's archival CSV is named with its opaque batch UUID. Original WeChat
downloads remain unchanged. Directories use 0700; database, archives and private
handoff files use 0600. These are local plaintext secrets, not encrypted storage;
do not put this directory into cloud sync, backups shared with others, or attachments.

`.gitignore` excludes `.private/` and `OfferCodeOneTimeUseCodes_*.csv` everywhere.
Run `pnpm run sandbox:offers git-guard --environment sandbox` before any commit.
It scans tracked/non-ignored files and staged blobs for actual imported secrets,
and rejects private inventory/download paths. It only emits safe counts or a
generic failure, never matching lines, values, SQL errors, or secret fingerprints.
This is an explicit check, not an installed Git hook; `git add -f` bypasses ignore
rules and must not be used on private files. Do not submit the inventory or archives.

## Operator commands

Run from the repository with Node 24+ and pnpm. `sandbox:offers` enables Node's
TypeScript transform to reuse the authoritative commerce verifier.
Place a trusted local **Sandbox/development** SQLite referral ledger snapshot
inside the private directory before assignment. The CLI opens it read-only and
uses the Development D1 only for the explicit refresh-ledger/publish commands. Do not supply a Production snapshot.
Refresh this snapshot after qualification, reward settlement or revocation.

```sh
pnpm run sandbox:offers refresh-ledger --environment sandbox
pnpm run sandbox:offers status --environment sandbox
pnpm run sandbox:offers import --environment sandbox /absolute/path/to/download.csv
pnpm run sandbox:offers map --environment sandbox BATCH_UUID invitee 'EXACT_APPLE_OFFER_REFERENCE'
pnpm run sandbox:offers assign --environment sandbox .private/sandbox-offer-codes/sandbox-ledger.sqlite REWARD_ID
pnpm run sandbox:offers publish --environment sandbox .private/sandbox-offer-codes/sandbox-ledger.sqlite ASSIGNMENT_UUID
pnpm run sandbox:offers handoff --environment sandbox .private/sandbox-offer-codes/sandbox-ledger.sqlite ASSIGNMENT_UUID
pnpm run sandbox:offers sync-redemption --environment sandbox .private/sandbox-offer-codes/sandbox-ledger.sqlite ASSIGNMENT_UUID
pnpm run sandbox:offers fail --environment sandbox ASSIGNMENT_UUID cancelled
pnpm run sandbox:offers verify --environment sandbox .private/sandbox-offer-codes/sandbox-ledger.sqlite ASSIGNMENT_UUID TRANSACTION_ID .private/sandbox-offer-codes/apple-sandbox.json
pnpm run sandbox:offers git-guard --environment sandbox
```

All uppercase arguments above are placeholders, never actual redemption values.
For mapping other offers, use `referrer_1` through `referrer_5`. Mapping is immutable
after confirmation. The command returns an opaque assignment ID, not a secret.
`handoff` writes a one-time private `.redemption.txt` file for the operator to read
locally and enter on the Sandbox device. Do not paste its contents into chat,
terminal commands, logs, screenshots, docs, or test fixtures.

The private Apple configuration contains the existing commerce environment keys:
`APP_ENVIRONMENT=development`, `APP_STORE_API_ENVIRONMENT=sandbox`,
`APP_STORE_BUNDLE_ID`, existing `APP_STORE_MONTHLY_PRODUCT_ID` and
`APP_STORE_YEARLY_PRODUCT_ID`, `APP_STORE_ISSUER_ID`, `APP_STORE_KEY_ID`,
`APP_STORE_PRIVATE_KEY`. Create/configure this privately; it is not generated with
dummy credentials. Verification always uses Apple's Sandbox Server API via the
existing server verifier. There is no CLI command to force `redeemed`.

## Data and state rules

- `batches`: UUID, source filename, digest, optional confirmed logical key and
  exact Apple offer identifier, import time. Reimport is idempotent.
- `codes`: opaque UUID, batch, private secret (unique), state, unique reward ID,
  owner Taste Map user ID, assigned/changed times, unique verified transaction ID.
- `audit`: append-only action, assignment UUID where relevant, local operator
  actor and timestamp. No secret value is included. This local tool trusts the
  OS account; it is not a multi-admin web service.
- `unused → assigned → redeemed` or `assigned → failed`; failed codes are never
  returned to the pool. A late verified transaction may move failed to redeemed.
- SQLite `BEGIN IMMEDIATE` and unique constraints serialize assignments. The same
  reward always returns its original assignment, including a terminal failure.
- Eligibility reads existing qualified referral + active premium reward, validates
  owner, role, days and lifetime qualification slot. Pending, capped, revoked,
  lifetime and unqualified rewards are denied. An active lifetime gift is denied.
- App Store deferred reward balances must settle in the authoritative service
  before assignment. This tool never accelerates a pending balance or changes
  StoreKit dates. The local ledger must be current; it is not a live revocation feed.
- Redemption verification requires a verified Sandbox transaction, `offerType=3`,
  exact offer identifier, matching appAccountToken and purchase at/after assignment,
  no revocation, and a previously unused transaction ID. An absent account token
  fails closed; do not auto-claim an external purchase to a Taste Map user.

Apple transaction evidence identifies the **offer**, not the individual one-time
code. Thus `redeemed` records a matching verified offer transaction for the private
assignment, not an independent Apple code-inventory lookup. Keep handoffs exclusive.
An Apple Offer redemption may create an auto-renewable subscription transaction;
it is not proof that the production app-owned 14/30-day ledger was granted correctly.
Use isolated Sandbox users and examine both ledgers; never add a second reward on
verification. Normal Native purchase/restore and authoritative reconciliation still
determine App Premium. Missing appAccountToken is an explicit end-to-end blocker.

## Actual device test and release boundary

Use a development-signed app and a Sandbox Apple Account. Apple documents testing
outside-app purchases in device Settings → Developer → Sandbox Apple Account.
See [Apple's testing guide](https://developer.apple.com/documentation/storekit/testing-purchases-made-outside-your-app)
and [Offer Code transaction support](https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app).
Use the existing Native transaction listener/restore flow and authoritative service
to reconcile. The inventory verifier only marks inventory; it never grants Premium.

This task did not consume a real code or complete an Apple Sandbox redemption.
All real inventory remains unused. Apple server credentials and the Development ledger snapshot are prepared. Mapping confirmation, qualified real test accounts, and authenticated Sandbox-device transactions are still required. Mock-verifier tests are not Apple redemption results.

The new tool and inventory are outside Worker/App import graphs and shipping
resources. No UI route, Premium bypass, debug entitlement, bundled redemption
value, production inventory or StoreKit product is added by this change.

## Verification on 2026-09-07

- 40 tests passed across Sandbox inventory, referral rewards, App Store commerce,
  gifts and release safety. Inventory tests use runtime-generated synthetic values
  and mocked Apple verification, never the sixty supplied codes.
- TypeScript typecheck and lint of the two new script files passed.
- Actual inventory: 60 unused, 0 assigned, 0 redeemed, 0 failed; all six mappings
  remain unconfirmed. Duplicate import created no additional records.
- Git guard passed for 1,892 tracked/non-ignored files and zero staged files.
- The current dist (26 files), formal staged web resources (26 files) and existing
  Release simulator app (50 files) had zero matches for the imported secrets.
  This is a scan of existing artifacts, not a new Release build or device test.
- Real Apple Sandbox redemption: **not run / awaiting prerequisites**. No actual
  Apple code was marked redeemed based on a simulated transaction.

## 2026-09-08 server admission and device preparation

Development migration `0038_sandbox_offer_assignments.sql` stores assignment metadata only, never redemption codes. Publish each assignment before private handoff. Server reconciliation requires the authenticated owner, matching Apple offer identifier and Sandbox environment, and uses a compare-and-set original transaction binding to reject concurrent reuse. Refresh the private ledger after an actual transaction, then sync-redemption; this cannot force a redeemed state without server-verified evidence. Existing Apple subscriptions remain independent of later referral reward changes.

Sandbox credentials are configured in Worker secrets. No new key is needed. Normal Production verification remains strict; it does not fall back to Sandbox after HTTP 401. The dedicated `TasteMap Sandbox TestFlight` scheme archives `ReleaseSandbox` against the independent Development backend. This is a test artifact, not the build to submit for public release. Normal `TasteMap` Release retains Production routing.

On device, Apple documents Settings → Developer → Sandbox Apple Account → Manage → Initiate Transaction → Offer Codes. Use Sandbox controls, not the production gift-card redemption screen. Codes are bearer values at Apple: the server prevents an unassigned Taste Map account from obtaining the entitlement, but cannot prevent someone entering a shared code in Apple's UI. Apple transaction evidence identifies the offer, not an individual code. Missing appAccountToken remains a blocking verification result.

Latest automated coverage: 48 server/operator tests and 36 iOS tests passed. Real transactions and real UI confirmation remain pending. See `reports/STOREKIT_SANDBOX_E2E_2026-09-08.md` for the acceptance boundary.
