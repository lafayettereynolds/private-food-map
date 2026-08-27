# P2-E Visit dining context

## Web audit and migration matrix

P2-E treats the current React product as the source of field names and enum values. A column being present in D1 is not, by itself, sufficient reason to expose it in the native product.

| Product label | Web field / type | Current Web use | D1 column | Native before P2-E | P2-E decision |
| --- | --- | --- | --- | --- | --- |
| Visibility | `visibility: private \| friends \| public` | Editor, profile, community and restaurant statistics | `visibility` | Missing | Migrate; default/private fallback is security-sensitive |
| Table total | `totalPrice: number \| null` | Editor and spending summaries | `total_price` | Missing | Migrate as optional Decimal |
| My actual spend | `myActualSpend: number \| null` | Editor and personal spending summaries | `my_actual_spend` | P1-C | Keep independent |
| Payment split | `paymentMode: aa \| my_treat \| treated \| separate \| other \| null` | Current `VisitExtraFields` | `payment_mode` | Missing | Migrate without deriving money |
| Derived per-person | `pricePerPerson: number \| null` | Derived by `calculatePricePerPerson` | `price_per_person` | Missing | Store synchronized projection; not directly editable |
| Queue / waiting | `queueDuration: QueueDuration \| null` | Editor, filters and analytics | `queue_duration` | Missing | Migrate exact bucket enum; `nil` differs from `none` |
| Dining scenes | `diningOccasions: DiningOccasion[]` | Current multi-choice editor and analytics | `dining_occasions_json` | Missing | Migrate exact multi-value enum |
| Custom scene | `diningOccasionText: string` | Shown only with `other` | `dining_occasion_text` | Missing | Migrate as nullable native value |
| Legacy scene projection | `diningOccasion: DiningOccasion \| null` | Import/display fallback only | `dining_occasion` | Missing | Do not add to SwiftData; Worker reads fallback and writes first array item |
| Value tags | `valueTags: string[]` | Current editor and analytics | `value_tags_json` | Missing | Migrate presets plus custom strings |
| Environment tags | `environmentTags: string[]` | Current editor and analytics | `environment_tags_json` | Missing | Migrate presets plus custom strings |
| Service tags | `serviceTags: string[]` | Current editor and analytics | `service_tags_json` | Missing | Migrate presets plus custom strings |
| Noise | `noiseLevel: NoiseLevel \| null` | Current expanded editor | `noise_level` | Missing | Migrate exact enum |
| Serving time | `diningDuration: DiningDuration \| null` | Current UI label is “上餐时长” | `dining_duration` | Missing | Migrate existing raw field without renaming the contract |
| Portion | `portionLevel: PortionLevel \| null` | Current primary editor | `portion_level` | Missing | Migrate exact enum |
| Transport | `transportConvenience: TransportConvenience \| null` | Current expanded editor | `transport_convenience` | Missing | Migrate exact enum |
| Special rules | `specialNotes: string` | Current expanded editor | `special_notes` | Missing | Migrate as nullable native text |
| Detailed ratings | `valueRating/environmentRating/serviceRating` | Current editor | matching columns | P2-D | Unchanged |
| Companions/shared meal | `companions`, `companionIds`, `sharedMealId` | Current editor/social/analysis | existing columns | Missing | Audit only; P2-F |
| Recommendation source | three `recommendationSource*` fields | Current editor/analysis | existing columns | Missing | Audit only; P2-F |
| Test marker | `isTestData` | Development seed/cleanup only | `is_test_data` | Missing | Not a product input; do not migrate |

Repository evidence: `src/types/domain.ts`, `src/types/visitExtras.ts`, `src/components/AddVisitModal.tsx`, `src/components/VisitExtraFields.tsx`, `src/services/profileInsights.ts`, `src/services/cloudSyncData.ts`, `worker/index.ts`, `worker/syncV1.ts`, and migrations `0001`, `0003`, `0005`, `0006`, `0007`.

The explicitly retired ideas—return willingness, recommended dishes, avoid dishes, seating, reservation details beyond queue, and best visit time—do not exist as P2-E inputs and were not reintroduced.

## Native model and editor

`Visit` adds optional money/text fields and stable raw-string-backed enums. Multi-value fields are stored as normalized JSON strings because SwiftData does not persist primitive arrays directly. Unknown legacy raw enum values remain in the stored raw value and survive a native edit; known UI choices remain type-safe.

`VisitDraft` remains the only create/edit form model. Validation rejects negative money, normalizes/deduplicates arrays, clears custom scene text when `other` is not selected, and calculates per-person price only from table total and a positive party size. Dish price and `myActualSpend` never participate in that calculation.

The editor remains progressive:

1. Basics: date, dine-in/takeout, optional party size.
2. Dining context: collapsed scene and waiting controls.
3. Overall and detailed ratings.
4. Dish and Photo.
5. Spending: optional split mode, table total, actual spend, read-only per-person projection.
6. Experience context: collapsed noise, serving time, portion, transport, tags, special notes.
7. Note and visibility.

All P2-E values remain optional except visibility, whose secure default is `private`. A minimal Visit still saves immediately.

## Queue and nullable semantics

The canonical queue buckets are `none`, `under15`, `under30`, `under60`, `under90`, `under120`, and `over120`. The Web analysis projection maps them to approximate minutes `0/8/23/45/75/105/135`; the raw contract does not pretend a bucket is an exact duration.

- `null`: the user did not record waiting.
- `none`: the user explicitly recorded no wait, with analysis projection `0`.

A negative JSON number is rejected because `queueDuration` is a nullable string enum, not a numeric duration. Unknown non-numeric legacy strings are preserved without making the editor crash.

## Shared JSON contract

Canonical iOS/Web/Worker V1 encoders now always emit the following required keys:

- required non-null: `visibility`, `diningOccasions`, `valueTags`, `environmentTags`, `serviceTags`;
- required nullable: `totalPrice`, `paymentMode`, `pricePerPerson`, `queueDuration`, `diningOccasionText`, `noiseLevel`, `diningDuration`, `portionLevel`, `transportConvenience`, `specialNotes`.

Legacy P0/P1/P2 payloads may omit any P2-E key. Decoders normalize missing values to `private`, `[]`, or `null` as appropriate. New encoders never omit them, so clear operations are explicit and cannot leave a stale server value.

Visibility accepts only the three public contract values. Other enum-like context strings are retained as raw legacy values for forward compatibility. The UI only presents the audited known options.

## Worker, D1 and legacy preservation

All required D1 columns already exist from migrations `0001`, `0003`, `0005`, `0006`, and `0007`; P2-E therefore has no D1 migration. Development preflight confirmed the tracked schema through `0020`. No database was rebuilt or cleared.

The Sync V1 Visit upsert now owns only the P1/P2 fields understood by native iOS. It deliberately does not update `recommendation_source_*`, `shared_meal_id`, `companions_json`, or `companion_ids_json`. A native P2-E edit therefore preserves P2-F and other legacy Web data already stored in D1.

Pull converts the singular legacy `dining_occasion` into a one-element array only when `dining_occasions_json` is empty. Push writes the new array plus the first-item legacy projection, allowing old Web readers and new native clients to coexist during migration.

## Privacy, offline sync and conflicts

Sync routes always derive ownership from authenticated Worker context, ignore payload `userId` for authorization, and enforce same-owner Restaurant/Visit parents. `/api/v1/sync/pull` is owner-only regardless of visibility. Existing profile/community/statistics queries exclude private records and apply friendship/map-sharing checks to friends/public records. P2-E does not add community UI.

Create/edit/clear writes SwiftData and one persistent Visit mutation before networking. Restart preserves fields and the queue. Idempotent mutation receipts protect response-loss retries. Conflict handling remains entity-level optimistic concurrency using `baseVersion/serverVersion`; device clocks do not choose a winner. Tombstones reject stale resurrection.

Production D1 and Production Worker remain outside P2-E scope.
