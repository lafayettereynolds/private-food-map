# Remote D1 diagnostic budget

Default per round: 10,000 estimated rows read. Per query: 1,000.
Use Analytics/Query Insights first; these inspect historical activity, not business tables.
All remote SQL must first have a local EXPLAIN/fixture and a conservative scanned-row
estimate. A result LIMIT does not bound scanned rows. Unknown cost, SELECT *, COUNT(*)
over business tables, JOINs or >1,000 estimated reads require explicit reviewed override.
Never put user values, credentials or raw private payloads in diagnostic logs.

Use `createD1DiagnosticBudget` from `scripts/d1-diagnostics-budget.mjs` around each
remote execution. It reserves estimates before execution and accounts for larger
actual meta.rows_read before the next query. Failed/missing-metadata calls keep
their reservation. It cannot undo a costly query, nor intercept direct Wrangler
commands; this is an opt-in tool guard plus operating policy, not an account firewall.
Existing scripts do not automatically gain enforcement by importing nothing.

Do not use these limits to throttle or rewrite Production business queries. No
Production index/deployment/data action is authorized by this policy. Remote Dev
is for bounded E2E after local correctness/cost tests. All-account quota remains
shared even though Dev and Production use different databases.
