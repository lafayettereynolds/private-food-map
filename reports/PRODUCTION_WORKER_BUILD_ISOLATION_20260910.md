# Production Worker build isolation

## Scope and source

This isolated worktree starts from frozen final-integration snapshot commit
25b7a4c, retaining the audited dirty source rather than adopting another window's
new edits. Only build isolation and its verification are changed.

## Purity classification

| Source / symbol | Class | Purpose / Development need | Production need | Previous isolation and inclusion cause | Resolution |
| --- | --- | --- | --- | --- | --- |
| developmentDemoAdminV1 / demo IDs / demo-data routes | DEV_ONLY | Isolated demo administration; required in Dev | None | Runtime environment/host/identity guards; static import and array initializers kept module live | Conditional dynamic import inside compile-time guard |
| index / resolveViewer localhost identity | LOCALHOST_ONLY | Local owner/free tester fixtures | None | Runtime hostname check | Compile-time branch removal |
| index / resolveSyncViewer development identities / ensureDevelopmentSyncUser | TEST_ONLY | Isolated fixture sessions; Dev tests require them | None | Runtime environment/auth mode checks | Compile-time branch removal; unused helper eliminated |
| index / readViewerMembership local premium and free overrides | TEST_ONLY | Local test membership | None | Runtime viewer marker | Compile-time branch removal |
| index / friend recommendation test-user header | QA_ONLY | Include test users in isolated local/QA recommendations | None | Request header enables test candidate selection | Compile-time removal of header-based test selection |
| accountDeletionV1 / developmentIdentity fresh-auth exemption | TEST_ONLY | Test-only account deletion fixture | None | Runtime fixture flag | Compile-time removal; real fresh-auth requirement unchanged |
| membershipV1 / development source and kind | TEST_ONLY | Display local test entitlement provenance | None | Runtime fixture parameter | Compile-time removal; official sources unchanged |
| index / loopback-to-loopback CORS exception | LOCALHOST_ONLY | Vite proxy support | None | Runtime hostname check | Excluded; formal origin checks retained |
| externalRestaurantLinkResolver / localhost and private-host denial | PROD_REQUIRED | SSRF prevention in every environment | Required | Normal security code, not a fixture | Retained |
| appStoreCommerceV1 / PEM delimiters | FALSE_POSITIVE | Parse runtime secret-backed official Apple key | Required | Parser strings are not private key material | Retained; encoded key material forbidden |
| Production rejection of development-test auth misconfiguration | PROD_REQUIRED | Fail closed when misconfigured | Required | Explicit 503 guard | Retained |
| Sandbox StoreKit environment / entitlement tables | PROD_REQUIRED | Verified environment-aware Apple transactions | Required | Official commerce logic, not a QA identity | Retained |
| membership admin deny-local/test checks, official grant sources | PROD_REQUIRED | Protect admin boundary and real grants | Required | Security checks, not bypasses | Retained |
| legacy owner ID / Cloudflare account migration | PROD_REQUIRED | Existing business identity compatibility | Retained, not treated as test-user namespace | Production routes still require verified session | Unchanged |

## Implementation

Wrangler Production defines __TASTEMAP_DEVELOPMENT_TOOLS__ as false and
Development defines it as true. Direct compile-time expressions are necessary:
an imported false constant left dead branch bodies in esbuild's first output.
Undefined defines preserve existing source-test behavior. Production's actual
artifact, not source alone, is the gate. No request or runtime binding can
re-enable a branch omitted from the deployed artifact.

The demo module is not imported by the compiled Production entrypoint. In
Development its error is translated locally to the existing RequestError
status/message contract, preserving the outer JSON error response.

No Apple verification, session validation/refresh, owner/admin permission,
official entitlement, StoreKit, referral, promotion, or grant implementation
has been rewritten. Production legitimate auth behavior is unchanged.

## Verification

- Full suite: 1569/1569 PASS, 0 failed/pending.
- Worker full: 410/410 baseline; re-run results retained with deployment evidence.
- TypeScript: PASS.
- Both Production and Development Wrangler dry-run builds succeed.
- scripts/test-production-worker-artifact.mjs compares compiled Production
  responses with the pre-isolation bundle using fresh in-memory migrated D1
  fixtures. All remote fetches are forbidden. It checks no-auth/malformed
  auth, admin spoof rejection, invalid StoreKit notification, refresh rejection,
  a valid session's free entitlement, non-admin denial, revoked-session rejection,
  and account isolation. The Development artifact still grants its intended
  local premium/free fixtures.
- 20 compiled-artifact checks PASS. No test credential is sent to Production.
- Production artifact SHA-256:
  1ea4f7a9c5d14bdb6d2c19eb38014a4141640d131a3035fc72a8a5af006a9d72.
- Forbidden namespaces, test headers, development routes and development host
  are absent. Remaining localhost literals belong to SSRF denial only.
- PEM validation/parser delimiters are retained; no embedded encoded private key.

Deployment and Production smoke evidence are recorded separately. This report
does not claim authenticated real-device Production E2E.
