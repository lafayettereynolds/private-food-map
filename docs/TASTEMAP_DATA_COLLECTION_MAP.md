# Taste Map Data Collection Map

Status: refreshed for the 2026-09-08 Release Privacy Manifest audit (see `reports/IOS_RELEASE_PRIVACY_MANIFEST_AUDIT_2026-09-08.md`). This document describes the current repository; it is not a substitute for Lafayette's final App Store Connect privacy questionnaire or legal review.

## Principles

- No cross-app or third-party advertising tracking is implemented.
- The iOS client talks to the public Taste Map Worker API. Cloudflare credentials, D1 credentials, R2 secrets, App Store Connect keys, and Apple private keys are not client data.
- Business records are owner-scoped by the Worker-authenticated Taste Map user ID. Client-supplied `userId` fields have no authorization meaning.
- SwiftData is an offline-first local cache and mutation queue. Keychain stores authentication/session credentials and the opaque account-deletion resume credential.
- Development Visual QA records, isolated credentials, fixture sessions, and Premium overrides compile only under `DEBUG` and are not user data.

## Current data map

| Data family | Representative fields | Source | Local processing/storage | Server processing/storage | Linked to user | Tracking | Current purpose |
|---|---|---|---|---|---|---|---|
| Taste Map user ID | `tm_…` stable ID | Worker after verified Sign in with Apple | Session state; owner scope on cached records | `users`, ownership and auth tables | Yes | No | Account and app functionality |
| Apple auth identity | Apple subject, identity token during exchange | Apple AuthenticationServices | Credentials only in Keychain after exchange; Apple token is not trusted locally | Verified by Worker; identity maps to Taste Map user | Yes | No | Authentication and fraud/replay prevention |
| Profile | Display name, optional email from first Apple authorization, city, avatar reference, visibility; legacy bio remains compatibility-only and is no longer collected through UI | User / Apple authorization | SwiftData cache | D1 user/profile records | Yes | No | Profile and social functionality |
| Restaurant and want-to-go | Restaurant UUID, provider identities, name, address, city, coordinates, status, tags | User, Apple Maps, AMap/link resolution | SwiftData | D1 owner-scoped records | Yes | No | Food map and sync |
| Visit and dining details | Date, optional ratings, notes, spend, dishes, dining context, companion/source references, visibility | User | SwiftData | D1 owner-scoped records | Yes | No | Food diary, analytics, and sharing under visibility rules |
| Precise device location | Current location used for map and nearby search | Core Location with when-in-use permission | Transient UI/search input; not persisted as the user's movement history | Not stored as a device-location history by Taste Map; selected restaurant coordinates may be saved as restaurant content | No device history | No | Nearby restaurant search and map position |
| Photos and videos | User-selected restaurant/visit/dish images and metadata | Photos picker / user | Protected local app files and SwiftData metadata | Private R2 objects plus D1 metadata when synced | Yes | No | User content and app functionality |
| Social graph | Follows, friendships, blocks, companion links | User | Derived/cache state | D1 | Yes | No | Social and safety functionality |
| Community content | Public/friends Visit activity, likes, comments, report records | User | Display/cache state and offline mutation state | D1; visibility, block, ownership, tombstone, and rate-limit enforcement | Yes | No | Community functionality and moderation |
| Lists and public shares | List title/content/visibility, share ID and revocation | User | SwiftData/cache | D1 public projection and revocable share links | Yes | No | App functionality and user-initiated sharing |
| Purchases | Product ID, transaction/original transaction ID, entitlement state, expiry/revocation/refund state | App Store / user purchase action | Keychain entitlement cache; StoreKit state | D1 entitlement/event state after server verification | Yes | No | Premium entitlement and account functionality |
| Diagnostics | Sync stage, bounded timing/category, error category, pending counts | App operation | In-memory/presentation diagnostics; no token or business-content logging | Worker operational logs may include non-secret request metadata | Potentially | No | Reliability and debugging |
| Product analytics / advertising identifiers | None implemented | — | No analytics SDK or IDFA storage found | None found in current Worker contract | No | No | Not collected |

## Apple privacy-manifest mapping

The main target declares ten linked data types, none used for tracking:

| Manifest data type suffix | Actual retained data | Purposes |
|---|---|---|
| Name | Profile/Apple sign-in name; named private companion/source records | App Functionality |
| EmailAddress | Apple sign-in email/account identity | App Functionality |
| UserID | Account and ownership IDs | App Functionality, Product Personalization |
| PurchaseHistory | StoreKit entitlements and recorded dining purchases/price evidence | App Functionality, Product Personalization |
| PhotosorVideos | Selected/captured images synced to private R2 storage | App Functionality |
| OtherUserContent | Ratings, notes, dishes, saved restaurants, lists and other authored content | App Functionality, Product Personalization |
| PreciseLocation | User-confirmed visits linked to stored restaurant coordinates and dates | App Functionality, Product Personalization |
| CoarseLocation | Stored profile city and city-scoped dining history | App Functionality, Product Personalization |
| Contacts | In-app follows/friendships/companion links (the user's social graph) | App Functionality, Product Personalization |
| ProductInteraction | Synced explicit recommendation dismissals and community likes | App Functionality, Product Personalization |

The location declarations describe retained user/place data, not background GPS tracking. Transient Core Location input is not itself added as a separate data type or tracking purpose. Apple's Contacts data category includes a social graph; this declaration does not add an address-book permission or Contacts framework. Local report calculations are user-facing features, not evidence of a product-analytics SDK. Backend request-error category logging does not by itself demonstrate collection of client diagnostic data or device IDs.

The main app uses `NSPrivacyAccessedAPICategoryFileTimestamp` / `C617.1` for cleanup of its own backup/poster files, and `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1` for app-local preferences and recommendation state. The actual Share Extension uses an App Group JSON file queue, not shared UserDefaults, and declares no tracking, collection or Required Reason APIs. Legacy `ios/Shared` and `ios/ShareExtension` templates with shared defaults are not members of the formal targets.

Only `fileSizeKey` is used on user-selected backup imports. That key is not on Apple's current Required Reason API list; do not add `3B52.1` solely because a document picker is used. No disk-space, boot-time, keyboard-list, shared-defaults or SDK-wrapper reasons are added.

The app requests only:

- Location When In Use, for the map position and nearby restaurants.
- Camera, for user-initiated dining/food photographs.
- Photos add-only, when the user explicitly saves a generated analysis or memory poster.

`PhotosPicker`/`PHPickerViewController` supply user-selected input without broad photo-library read permission. No microphone, contacts/address-book, Bluetooth, notifications, tracking or always-on location permission is declared.

Formal third-party iOS dependencies are the signed Capacitor and Cordova 8.5.1 binary frameworks. Both ship their own manifests. The local first-party `TasteMapHybridBridge` package is used by the separate internal Capacitor shell and is not a package dependency of the formal app; the formal app compiles its own native source. Cloudflare Workers, D1 and R2 are HTTPS backend services, not embedded iOS SDKs.

## Manual release gates

- Lafayette/legal review must map this factual inventory to the final App Store Connect privacy answers.
- Real Privacy Policy, Terms of Service, and Support HTTPS URLs must be configured; current Production configuration intentionally fails closed while they are missing.
- A moderation owner, review SLA, appeal path, and support channel are operational decisions and cannot be inferred or invented in code.
