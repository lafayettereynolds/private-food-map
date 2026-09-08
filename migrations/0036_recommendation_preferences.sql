-- Owner-private preference events, deliberately separate from telemetry and
-- Sync V1's entity ledger. Never cascade on Restaurant deletion: an excluded
-- restaurant need not be saved in the owner's private Restaurant collection.
CREATE TABLE recommendation_preference_events (
  revision INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL REFERENCES users(id),
  event_id TEXT NOT NULL,
  payload_json TEXT NOT NULL CHECK(json_valid(payload_json)),
  received_at TEXT NOT NULL,
  UNIQUE(user_id, event_id)
);
CREATE INDEX recommendation_preference_events_owner_revision
  ON recommendation_preference_events(user_id, revision);

-- Enforce idempotency inside the write transaction, including concurrent
-- requests that both passed a preflight read. Identical retries are ignored.
CREATE TRIGGER recommendation_preference_event_insert_guard
BEFORE INSERT ON recommendation_preference_events BEGIN
  SELECT (CASE WHEN NOT EXISTS (
    SELECT 1 FROM users WHERE id = NEW.user_id AND deleted_at IS NULL
  ) OR EXISTS (
    SELECT 1 FROM account_deletion_jobs WHERE user_id = NEW.user_id
  ) THEN RAISE(ABORT, 'recommendation_preference_account_unavailable') END);
  SELECT (CASE WHEN EXISTS (
    SELECT 1 FROM recommendation_preference_events
    WHERE user_id = NEW.user_id AND event_id = NEW.event_id
      AND payload_json <> NEW.payload_json
  ) THEN RAISE(ABORT, 'recommendation_preference_idempotency_conflict') END);
END;
CREATE TRIGGER recommendation_preference_event_immutable
BEFORE UPDATE ON recommendation_preference_events BEGIN
  SELECT RAISE(ABORT, 'recommendation_preference_event_immutable');
END;
