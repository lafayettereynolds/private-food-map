PRAGMA foreign_keys = ON;

-- Add server-authoritative lifecycle metadata without replacing either legacy table.
ALTER TABLE friendships ADD COLUMN pair_user_a TEXT;
ALTER TABLE friendships ADD COLUMN pair_user_b TEXT;
ALTER TABLE friendships ADD COLUMN deleted_at TEXT;
ALTER TABLE friendships ADD COLUMN server_version INTEGER NOT NULL DEFAULT 1;

UPDATE friendships SET
  pair_user_a = CASE WHEN requester_id < addressee_id THEN requester_id ELSE addressee_id END,
  pair_user_b = CASE WHEN requester_id < addressee_id THEN addressee_id ELSE requester_id END;

-- Preserve every legacy row while deactivating only lower-priority reversed duplicates.
WITH ranked AS (
  SELECT id, ROW_NUMBER() OVER (
    PARTITION BY pair_user_a, pair_user_b
    ORDER BY CASE status WHEN 'accepted' THEN 0 WHEN 'pending' THEN 1 ELSE 2 END,
      updated_at DESC, id ASC
  ) AS position
  FROM friendships
  WHERE status IN ('pending', 'accepted')
)
UPDATE friendships SET status = 'removed', deleted_at = COALESCE(deleted_at, updated_at)
WHERE id IN (SELECT id FROM ranked WHERE position > 1);

CREATE UNIQUE INDEX IF NOT EXISTS idx_friendships_active_canonical_pair
  ON friendships(pair_user_a, pair_user_b)
  WHERE deleted_at IS NULL AND status IN ('pending', 'accepted');
CREATE INDEX IF NOT EXISTS idx_friendships_pair_state
  ON friendships(pair_user_a, pair_user_b, status, updated_at);

CREATE TRIGGER IF NOT EXISTS friendships_reject_self_insert
BEFORE INSERT ON friendships WHEN NEW.requester_id = NEW.addressee_id
BEGIN SELECT RAISE(ABORT, 'friendship_self_relation'); END;
CREATE TRIGGER IF NOT EXISTS friendships_reject_self_update
BEFORE UPDATE OF requester_id, addressee_id ON friendships
WHEN NEW.requester_id = NEW.addressee_id
BEGIN SELECT RAISE(ABORT, 'friendship_self_relation'); END;

ALTER TABLE follows ADD COLUMN updated_at TEXT;
ALTER TABLE follows ADD COLUMN deleted_at TEXT;
ALTER TABLE follows ADD COLUMN server_version INTEGER NOT NULL DEFAULT 1;
UPDATE follows SET updated_at = created_at WHERE updated_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_follows_active_follower
  ON follows(follower_id, updated_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_follows_active_followed
  ON follows(followed_user_id, updated_at) WHERE deleted_at IS NULL;

CREATE TRIGGER IF NOT EXISTS follows_reject_self_insert
BEFORE INSERT ON follows WHEN NEW.follower_id = NEW.followed_user_id
BEGIN SELECT RAISE(ABORT, 'follow_self_relation'); END;
CREATE TRIGGER IF NOT EXISTS follows_reject_self_update
BEFORE UPDATE OF follower_id, followed_user_id ON follows
WHEN NEW.follower_id = NEW.followed_user_id
BEGIN SELECT RAISE(ABORT, 'follow_self_relation'); END;

-- A bounded, per-authenticated-user search window; no client-provided actor is trusted.
CREATE TABLE IF NOT EXISTS social_search_rate_limits (
  user_id TEXT NOT NULL,
  window_started_at TEXT NOT NULL,
  request_count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, window_started_at),
  FOREIGN KEY (user_id) REFERENCES users(id)
);
