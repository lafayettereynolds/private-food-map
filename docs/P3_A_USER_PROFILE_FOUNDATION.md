# P3-A User Profile Foundation

## Web audit and migration matrix

| Product field | Existing Web source | Existing type / behavior | P3-A native status | Backend dependency |
| --- | --- | --- | --- | --- |
| Taste Map User ID | `UserProfile.id`, `users.id` | Stable business identity; native auth creates `tm_...` | Reused unchanged as the only owner/social identity | `users`, `auth_identities` |
| Display Name | `UserProfile.nickname` | Editable, duplicates allowed, Web max 30 | Migrated as `displayName`; trimmed, required, max 30 for new edits, Unicode/emoji allowed | `user_profiles.display_name` |
| Bio | `UserProfile.bio` | Retired from display and editing; legacy read/sync/backup compatibility only | Schema retained; no product UI | `user_profiles.bio` |
| City | `UserProfile.city` | Editable and visible on the existing public page, max 30 | Migrated | `user_profiles.city` |
| Avatar photo | `avatarPhotoId` / `Photo.kind = avatar` | Stable photo ID; Web also has legacy inline image data | Migrated by ID and reuses P2 Photo/R2/cache pipeline; inline base64 is legacy-only | `photos`, R2, `user_profiles.avatar_photo_id` |
| Preset avatar | `avatarPresetId` | 16 local sprite presets in `public/taste-map-avatar-presets.png` | Migrated with the same IDs and local asset | App Assets, `user_profiles.avatar_preset_id` |
| Profile visibility | `mapSharingEnabled` + `mapVisibility` | `private / friends / public`; historically also gates map records | Migrated as the profile projection boundary | `user_profiles.visibility` |
| Joined date | `UserProfile.createdAt` | Read-only display | Migrated as `createdAt`; public DTO calls it `joinedAt` | `user_profiles.created_at` |
| Basic own statistics | Web derives from Restaurant/Visit | Factual counts/ratings/spend | Derived locally from the authenticated user's active SwiftData records | Existing P0–P2 data |
| Public statistics | Existing public profile uses filtered records | Must respect Visit visibility | API derives only from `visibility = public` Visit rows | D1 query only |
| Email / Apple subject | Auth/internal User fields | Authentication only | Explicitly not migrated to Profile contracts or UI identity | Auth tables only |
| Handle / username | `publicHandle()` derives text from nickname at render time | Not stored, not unique, not a real product identity | Not migrated | P3-B decision if needed |
| Avatar inline base64 | `avatarImageData` | Legacy IndexedDB/Web compatibility | Not added to native contract | Kept in legacy `users` projection |
| Membership | `membershipTier` | Entitlement/product concern | Not added to Profile sync/public DTO | Existing membership service |
| Followers/following | Existing Web social tables | Real Web functionality, but P3-B scope | Not displayed or migrated in P3-A | P3-B |
| Location, cuisine, social links | No official profile fields | Not defined | Not invented | None |

## Identity and privacy decisions

- `users.id` remains the stable Taste Map User ID. Apple `sub`, email and sessions never become profile or business keys.
- `user_profiles.user_id` is a one-to-one projection and is also the Sync entity ID. It is not a second identity.
- Own Profile sync carries only editable profile metadata. Public Profile is a separate, explicit allowlist DTO.
- Public statistics count only public Visits and Restaurants referenced by those public Visits. Private totals cannot be inferred from the DTO.
- A profile avatar is readable by another authenticated user only when that exact active Photo is the target profile's current avatar and the target visibility allows the viewer. This does not make other photos or the bucket public.
- Existing Web `users` rows seed `user_profiles` without changing IDs or truncating legacy values. Legacy Web writes continue to update the compatibility projection.
- No legacy `owner` or other Web account is automatically linked to an Apple-authenticated `tm_...` user.

The editable Display Name limit is 30 Unicode code points. The Profile wire
contract has a 200-code-point compatibility ceiling because existing Web data
contains longer nicknames. Migration never truncates them: an over-limit legacy
name may pass through unchanged while another field is edited, but cannot be
replaced by a new over-limit value.

## Conflict and avatar replacement policy

- Profile sync uses the existing server `serverVersion + baseVersion` policy; device time is metadata only.
- A conflict retains the local edit, stores the server snapshot, and surfaces the existing conflict state rather than silently overwriting.
- Replacing an avatar changes the profile reference only after the new Photo can use the P2 upload/sync pipeline. The previous avatar remains a private Photo; P3-A does not destructively delete it automatically.
