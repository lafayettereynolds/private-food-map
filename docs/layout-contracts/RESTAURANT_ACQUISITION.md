# Restaurant Acquisition Layout Contract

## Product order

1. Search Restaurant by name/address with city context.
2. Nearby based on a fresh CLLocation.
3. External Share ingestion through the Share Extension/pending flow.
4. One Manual Add card for places absent from providers.

Manual link paste is not promoted as a normal in-App section. Location denial
does not block Search or Manual Add.

## Sheet geometry

- Compact native sheet/navigation header.
- Search is the first content card and contains query, current city, and one
  primary search action.
- Nearby is the second content card and clearly separates location state from
  real results; result rows show name/address/distance and one inspect action.
- Manual Add is one compact navigation card, not a nested section plus duplicate
  button.
- Result selection opens the standard Restaurant Detail foundation before an
  explicit `想去` or `去过` mutation.

## Result/preview states

Search: idle, loading, results, zero, error, retry, long names, missing photo.
Nearby: not determined, precise, reduced, denied, stale rejected, inaccurate
rejected, loading, zero, error, sorted results. Share: recognizing, supported,
ambiguous, unsupported, expired, confirmation. Manual: valid, validation error,
candidate preview.

## Image and identity

Candidate rows and preview use the canonical Restaurant image renderer.
Provider IDs are external identities; they never replace the Taste Map UUID.
Probable cross-provider matches require explicit confirmation.
