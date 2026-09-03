# Taste Map Data Collection Map

Status: code-fact audit for Task 13. This document describes the current repository; it is not a substitute for Lafayette's final App Store Connect privacy questionnaire or legal review.

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

The main target currently declares Name, Email Address, User ID, Purchase History, Photos or Videos, and Other User Content as linked, not used for tracking, and used for app functionality. It declares file timestamp access reason `C617.1` because bounded cleanup of app-created backup/poster temporary files reads creation or modification dates. The Share Extension declares no tracking, collection, or Required Reason API access; it accepts user-invoked shared text/URL and places the clue in the App Group import queue for the main app.

The app requests only:

- Location When In Use, for the map position and nearby restaurants.
- Photos add-only, when the user explicitly saves a generated analysis poster.

`PhotosPicker` supplies user-selected input without a broad photo-library read permission. No camera, microphone, contacts, notifications, tracking, or always-on location permission is declared by the current target.

## Manual release gates

- Lafayette/legal review must map this factual inventory to the final App Store Connect privacy answers.
- Real Privacy Policy, Terms of Service, and Support HTTPS URLs must be configured; current Production configuration intentionally fails closed while they are missing.
- A moderation owner, review SLA, appeal path, and support channel are operational decisions and cannot be inferred or invented in code.
