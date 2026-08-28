PRAGMA foreign_keys = ON;

-- P3-E: a bounded server-side quota ledger for authenticated public/social APIs.
-- This is additive only: no product data, ownership, relationship, or sync rows
-- are rewritten.
CREATE TABLE IF NOT EXISTS public_api_rate_limits (
  actor_key TEXT NOT NULL,
  bucket TEXT NOT NULL,
  window_started_at TEXT NOT NULL,
  request_count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (actor_key, bucket, window_started_at)
);

CREATE INDEX IF NOT EXISTS idx_public_api_rate_limits_expiry
  ON public_api_rate_limits(window_started_at);
