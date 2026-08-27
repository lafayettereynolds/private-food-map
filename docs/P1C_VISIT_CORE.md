# P1-C Visit core contract and field audit

P1-C keeps the Web Visit model as the product baseline while limiting the native editor to the daily-use core. Fields marked P2 remain in the Web/D1 model and are not removed.

| Field | Web domain | D1 | iOS before P1-C | Sync V1 before P1-C | Decision |
| --- | --- | --- | --- | --- | --- |
| `id` | `string` | `visits.id` | `UUID` + stable `remoteID` | required | Keep P1-C |
| `restaurantId` | `string` | `visits.restaurant_id` | `UUID` relationship | required | Keep P1-C |
| `visitedAt` | ISO-8601 string created from local date/time | `visits.visited_at` | `Date` | required | Keep P1-C; preserve the instant exactly |
| `rating` | `StarRating \| null`, 0.5...5 half steps | `visits.rating` | `Double?` | required nullable | Keep P1-C |
| `note` | `string` | `visits.note` | `String?` | required nullable | Keep P1-C; blank normalizes to `nil` natively |
| `myActualSpend` | `number \| null` | `visits.my_actual_spend` | `Decimal?` | required nullable | Keep P1-C |
| `diningMode` | `dine_in \| takeout` | `visits.dining_mode` | missing | missing | Add P1-C |
| `partySize` | legacy Web editor requires positive `number` | legacy `party_size NOT NULL` | missing | missing | Add P1-C as nullable; bridge through `party_size_optional` |
| `createdAt` / `updatedAt` / `deletedAt` | ISO timestamps | matching columns | existing | existing | Keep sync metadata |
| visibility / total price / payment mode / per-person price | present | present | missing | missing | P2 |
| queue and dining occasions | present | present | missing | missing | P2 |
| value/environment/service ratings and tags | present | present | missing | missing | P2 |
| noise, duration, portion, transport, special notes | present | present | missing | missing | P2 |
| recommendation source | present | present | missing | missing | P2 |
| companions / shared meal | present | present | missing | missing | P2 |
| dishes / photos | present | present | provider layer only | missing | P2 |

## Canonical Sync V1 rules added by P1-C

- `diningMode` is required in newly encoded payloads and accepts only `dine_in` or `takeout`.
- `partySize` is required-but-nullable in newly encoded payloads. A non-null value must be a positive integer.
- P0 Visit payloads that predate both keys remain accepted and normalize to `diningMode = dine_in`, `partySize = null`.
- `rating`, `note`, `myActualSpend`, `partySize`, and `deletedAt` are encoded as explicit JSON null when empty.
- `visitedAt` remains the existing Web-compatible ISO-8601 instant. Native encode/decode preserves the same instant; UI renders and edits it in the device's current time zone.

## D1 compatibility strategy

Migration `0018_visit_core_fields.sql` does not rebuild or clear `visits`. It keeps legacy `party_size`, adds nullable `party_size_optional`, backfills existing positive values, and provides rolling-deployment triggers for an older Worker that still writes only `party_size`. Native null uses legacy sentinel `0` plus canonical null; all current readers use the canonical nullable value.

## SwiftData migration strategy

`Visit` adds optional `partySize` and a raw-string `diningMode` with a `dine_in` default. Both are additive/lightweight changes: existing stores infer `partySize = nil` and `diningMode = dine_in`. No store deletion or destructive migration is permitted.
