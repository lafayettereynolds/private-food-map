# P2-D multidimensional Visit ratings

## Web audit and field matrix

P2-D follows the existing Web `Visit` domain rather than inventing rating categories.

| Product label | Web field | Web type | Scale | Nullable | D1 column | Native state before P2-D | P2-D handling |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Overall rating | `rating` | `StarRating \| null` | 0.5–5.0, half-star | Yes | `visits.rating` | Implemented | Remains independent |
| Value | `valueRating` | `StarRating \| null` | 0.5–5.0, half-star | Yes | `visits.value_rating` | Missing | Additive optional Visit field |
| Environment | `environmentRating` | `StarRating \| null` | 0.5–5.0, half-star | Yes | `visits.environment_rating` | Missing | Additive optional Visit field |
| Service | `serviceRating` | `StarRating \| null` | 0.5–5.0, half-star | Yes | `visits.service_rating` | Missing | Additive optional Visit field |

The Web Restaurant model also contains legacy aggregate fields named `foodRating`, `environmentRating`, `serviceRating`, and `valueRating`. They are not Visit input dimensions and are not copied into the native Visit model. In particular, P2-D does not introduce a Visit `foodRating`.

The audited Web code stores and restores the three Visit fields in `Visit`, `VisitExtraFieldsValue`, IndexedDB backup/import, cloud payloads, Worker mappings, and D1. Current profile analytics primarily use overall `Visit.rating`; P2-D only establishes the detailed-rating calculation foundation and does not change recommendation or profile behavior.

## Semantics

- Overall `Visit.rating` is the user's independent assessment of the complete Visit.
- `valueRating`, `environmentRating`, and `serviceRating` describe separate parts of that Visit.
- `Dish.rating` describes one canonical Restaurant Dish and is never included in Visit or Restaurant detailed-rating averages.
- No value is derived from another. Partial input is valid, `nil` is not zero, and every value can be cleared.
- The scale remains 0.5 through 5.0 in half-star increments.

## Local-first and conflicts

The three fields are optional additive SwiftData properties. Visit create/edit saves them with the rest of the Visit in one local transaction and enqueues one Visit mutation only when the user taps Save. App restart preserves both values and the mutation queue.

Conflict handling remains entity-level using `baseVersion` and `serverVersion`. P2-D does not implement unsafe device-time last-write-wins or field-level merging.

## Shared contract and legacy compatibility

New Swift and TypeScript encoders always emit:

- `valueRating`
- `environmentRating`
- `serviceRating`

as explicit numbers or `null`. Decoders accept legacy P0/P1 payloads that omit these three properties and normalize them to `null`. Invalid ranges and non-half-star steps are rejected.

The existing D1 columns were introduced by migration `0003_social_visit_fields.sql`; no P2-D D1 migration is required. Sync V1 now reads and writes these columns. The Visit upsert continues updating only native-owned columns, so unmigrated Web fields such as queue, tags, occasions, payment, companions, and recommendation source remain untouched.

## Aggregation

`RatingStatistics` filters tombstoned Visits and calculates each dimension independently from non-null, valid samples. Every summary contains average, sample count, latest value, and latest Visit date. Restaurant Detail displays only real dimensions and never renders missing data as zero.
