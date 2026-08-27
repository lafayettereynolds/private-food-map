# Taste Map Native Auth V1

## Identity boundary

Taste Map business data is owned by the server-generated `users.id` value
(`tm_…`). An Apple `sub` is stored only in `auth_identities.provider_subject`.
Restaurants, visits, friends, and future identities never use an Apple subject
as their owner key.

```text
users.id (tm_…)
  └── auth_identities
        └── provider=apple, provider_subject=<Apple sub>
```

This supports adding email, phone, or another provider to the same Taste Map
user later without rewriting business records.

## Sign-in protocol

1. iOS requests `POST /api/v1/auth/challenge`.
2. Worker generates random state and nonce, stores only SHA-256 hashes, and
   expires the challenge after ten minutes.
3. iOS sends state to AuthenticationServices and sends SHA-256(nonce) as the
   Apple request nonce.
4. iOS checks Apple's returned state, then sends the identity token, raw state,
   and raw nonce to `POST /api/v1/auth/apple/exchange`.
5. Worker verifies the Apple RS256 signature using Apple's JWKS, exact issuer,
   configured audience, expiration/time claims, subject, and nonce. State,
   challenge, and identity-token replay checks are server-side.
6. Worker links or creates an Apple identity and returns an opaque Taste Map
   session. Token plaintext is returned once and is never stored in D1.

## Sessions

- Access token: opaque random token, 15-minute lifetime.
- Refresh token: opaque random token, 30-day rolling lifetime.
- D1 stores SHA-256 hashes only.
- Every refresh rotates both tokens and records the consumed refresh hash.
- Reusing a consumed refresh token revokes the entire session.
- Logout revokes the server session. iOS clears Keychain first even if the
  network revoke cannot complete.
- iOS stores the credential only in Keychain using
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- `AuthSessionManager` serializes refresh work. A later 401 carrying an older
  access token observes the already-rotated credential instead of refreshing
  again.

## Sync authorization

`/api/v1/sync/push` and `/pull` hash and resolve the bearer access token. The
resolved `users.id` is the only authorization identity. Payload `userId` has no
authority and entity ownership is checked in D1.

The `X-Taste-Map-Test-User` mode remains available only when both
`APP_ENVIRONMENT=development` and `SYNC_AUTH_MODE=development-test`. A
Production deployment with that auth mode fails closed.

## Legacy owner linking (not executed in P0-B2-B)

No Apple user is automatically assigned the legacy `owner` or another historic
Web `user_id`. Linking must be a separate, explicit operation with all of these
properties:

1. The caller first has a verified Taste Map session.
2. The legacy owner is proven through an authenticated Web account, signed
   one-time export/claim code, or administrator-assisted recovery. Email text
   alone is insufficient proof.
3. The Worker produces a dry-run report of Restaurant, Visit, photo, list,
   friendship, and sync-log row counts plus ID collisions.
4. The user explicitly confirms the report. A one-time, expiring claim record
   prevents two users from claiming the same legacy owner.
5. One D1 transaction rewrites ownership across all related tables and records
   an immutable audit event. It never rewrites Restaurant/Visit IDs or their
   relationship.
6. Failed validation makes no changes. A post-migration integrity query must
   show zero orphaned Visit/Restaurant references before the claim is complete.

## Apple setup gate

Local Xcode settings currently show bundle identifier
`com.lafayette.TasteMap`, Development Team `7G5J9MJX88`, and automatic signing.
They do not prove the Apple Developer portal registration. Before adding the
Sign in with Apple capability, manually confirm that Team `7G5J9MJX88` has an
explicit App ID for exactly `com.lafayette.TasteMap`, then enable Sign in with
Apple for that identifier and let Xcode refresh its provisioning profile. Also
confirm the App Store Connect app record uses the same Bundle ID. P0-B2-B does
not change signing, entitlements, capabilities, Team, or Bundle ID.
