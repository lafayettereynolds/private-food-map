# Formal Hybrid UGC compliance closure

Scope: independent `fix/hybrid-ugc-compliance`, frozen Production RC source `dcbdc59` (1012). No Production data/API writes, migration, deployment, physical-iPhone operation, RC archive, upload, or review submission.

## Audit

| Capability | Before | Formal path after this change |
| --- | --- | --- |
| Report backend | EXISTS | Existing `/api/v1/community/reports`; shared Hybrid `…` → report |
| Block backend | EXISTS | Existing `/api/v1/community/blocks/:user`; shared Hybrid `…` → block |
| Own-comment delete backend | EXISTS | Existing `/api/v1/community/comments/:id` DELETE, owner-only soft deletion and idempotency |
| Content filtering | PARTIAL | Versioned server text policy plus existing rate limits, report review and actioned-content/image exclusion |
| Discovery / Activity | Missing formal safety entry | Shared frame header/identity safety action, preserving footer topology |
| Comments | Missing formal safety/delete entry | Owner-authorized actions, immediate hide, error rollback, blocked-author filtering |
| Restaurant Detail UGC image | No direct safety entry | Actual resolved photo → its Visit report/block target, follows fallback changes |
| Own profile / settings | Existing Native capabilities | Help → support; no profile visibility or account changes |
| Other user profile | Existing Native social capability | Existing social hub/profile safety backend remains wired; content-level Hybrid action no longer depends on finding that Native page |

## Security and behavior

- React requests capabilities; it never decides ownership by comparing IDs. The backend independently enforces all mutations, private/deleted visibility and self-report rejection.
- Comment DELETE does not remove a Visit or mutate the sync queue. It preserves the existing tombstone and idempotent retry behavior. Failed deletion restores the text; reload reads exclude tombstones.
- Block removes only the current viewer's derived public caches and filters other-author UI, including comment/photo references. Original content and other users remain untouched.
- Native UGC transport captures authorization after normal session validation. A 401 cannot replay the request with a different account's token. Auth-epoch fences stop late response application, including A→B→A.
- Text filtering covers comments, public/friends Visit notes/context, public profile and list text, and the still-exposed legacy Visit/profile ingress. Private notes are not rewritten. Attempting to publish prohibited private text is rejected without advancing its version. Legitimate criticism and ordinary links remain accepted.
- The conservative text rules are not image classification or comprehensive contextual moderation. Existing report review and `actioned` image/content eligibility remain necessary. Actioned comments are now excluded from both reads and counts.
- No DB schema change, no Sync ownership/merge change, no Photo Delete fence change, no Auth lifecycle change, no StoreKit/Referral/Gift changes.

## Evidence

- Full Web/Worker: 1601/1601, 0 failed, 0 pending (`.private/ugc-validation/full-tests-final.json`). Initial concurrent run had one existing 2-second analytics timing assertion fail; idle rerun passed without changing it.
- Browser interaction harness uses actual shared components, no network outside localhost: report success and honest error; owner-only delete; immediate hide and failure rollback; rerender tombstone; block filtering; auth reset and late-result rejection. `scripts/test-ugc-hybrid-ui.mjs` is reproducible with Playwright and `tests/ugc/vite.config.ts`. This is not represented as an installed-iPhone test.
- Native API tests exercise authenticated paths, URL-encoded target identity, server failure and request identity capture using an isolated URLProtocol. Other release-safety/community tests remain included.
- Swift bridge tests verify the new methods reach the async runtime, rather than navigation/openNative or a QA-only handler.
- Release Web bundle and staged/built byte parity are validated separately. Fixture harness and test credentials are not application imports.

Final measured results:

| Gate | Result |
| --- | --- |
| Full Web/Worker | 1601 PASS, 0 FAIL, 0 pending |
| Native affected regression | 18/18 PASS (4 suites), isolated Simulator `D3C3F40A-1FC9-4498-9BBE-5076AA98A244` |
| Swift bridge | 43/43 PASS; includes all four new async methods |
| Native adapter contract | PASS; all four typed payloads exercised |
| TypeScript (Web + Worker) | PASS |
| Shared Hybrid browser interaction | PASS, including photo fallback target and A→B→A/late completion |
| Release compile | BUILD SUCCEEDED, unsigned arm64 Simulator validation only |
| Source → staged → built `.app` assets | 26/26 byte-for-byte MATCH |
| Release local-bundle purity | PASS; no UGC test harness/credentials in staged resources |
| New regressions | 0 |
| DB migrations / Production writes | NONE / NONE |

UGC module implementation readiness: PASS. This is a **branch-level integration handoff**, not a claim that Production or the installed 1012 already contains the fix. Raw logs and test JSON are retained under `.private/ugc-validation/`; the shared-component screenshot is `.private/ugc-validation/hybrid-ugc-actions.png` (explicitly a local harness, not a physical-iPhone screenshot).

## Integration / review handoff

1. Integrate this standalone commit; do not replace an integration branch wholesale.
2. Under separate authorization, deploy the updated existing Worker (adds the read-only capability projection and content checks; no migration). Shipping the client first would correctly show an unavailable error on old Workers, not fake success.
3. Generate the next Final RC only in the integration task. The already-installed 1012 does **not** gain these changes automatically. Repeat report, block, own-comment delete and account-change smoke on that integrated build using controlled content.
4. The other task must finish the published support/contact page. In-app Settings → Help → `https://tastemap.cn/support.html` remains reachable.
5. Operational report review and timely response remain an operator responsibility; tests do not prove response time or guarantee App Review acceptance. [Apple Guideline 1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content).
