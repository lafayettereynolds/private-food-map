# Discovery D1 quota diagnosis

## 2026-09-08 20:26 device evidence and D1 quota blocker

User screenshots: default For You renders cached cards, Hangzhou selected; applying
9+ displays active filters (also unvisited) but results fail. This is NOT a valid
empty result or successful live Discovery acceptance. Current-city label is visible;
actual geographic accuracy is not independently confirmed. Provider category
MKPOICategoryRestaurant leaks into card subtitle; correction remains outstanding.

Read-only reproduction with existing Development owner and current server query
failed in readDiscoveryVisitAggregates. Cloudflare API returned code7500: account
has exceeded D1 free-tier daily row-read limit. Reset stated as midnight UTC
(08:00 Asia/Shanghai). No account token was extracted or client auth fabricated;
quota-counter writes were skipped in the local diagnostic adapter, only SELECT/
WITH statements executed remotely. Failed query/error remain private.

Paused further remote probes. No billing/plan change, key replacement, data reset,
production deployment or new device installation performed. Live For You/filter
Gate remains blocked pending D1 quota restoration. Earlier observed10 Latest and
matching avatar PASS remain historical accepted results, not proof of current
backend availability.
