PRAGMA foreign_keys = ON;

-- Task 06 keeps the legacy Web shared-meal tables intact and adds the
-- server-authoritative lifecycle fields required by the versioned native API.
-- Existing rows retain their identifiers, participants and Visit references.
ALTER TABLE shared_meals ADD COLUMN source_visit_id TEXT;
ALTER TABLE shared_meals ADD COLUMN mutation_id TEXT;
ALTER TABLE shared_meals ADD COLUMN visibility TEXT NOT NULL DEFAULT 'private';
ALTER TABLE shared_meals ADD COLUMN revoked_at TEXT;
ALTER TABLE shared_meals ADD COLUMN server_version INTEGER NOT NULL DEFAULT 1;

UPDATE shared_meals
SET source_visit_id = (
      SELECT v.id FROM visits v
      WHERE v.shared_meal_id = shared_meals.id
        AND v.user_id = shared_meals.created_by_user_id
      ORDER BY v.created_at ASC, v.id ASC LIMIT 1
    ),
    visibility = COALESCE((
      SELECT v.visibility FROM visits v
      WHERE v.shared_meal_id = shared_meals.id
        AND v.user_id = shared_meals.created_by_user_id
      ORDER BY v.created_at ASC, v.id ASC LIMIT 1
    ), 'private')
WHERE source_visit_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_shared_meals_creator_mutation
  ON shared_meals(created_by_user_id, mutation_id)
  WHERE mutation_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_shared_meals_creator_active
  ON shared_meals(created_by_user_id, updated_at DESC, id)
  WHERE deleted_at IS NULL AND revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_shared_meals_source_visit
  ON shared_meals(created_by_user_id, source_visit_id)
  WHERE source_visit_id IS NOT NULL;

ALTER TABLE shared_meal_participants ADD COLUMN inviter_user_id TEXT;
ALTER TABLE shared_meal_participants ADD COLUMN deleted_at TEXT;
ALTER TABLE shared_meal_participants ADD COLUMN server_version INTEGER NOT NULL DEFAULT 1;

UPDATE shared_meal_participants
SET inviter_user_id = (
  SELECT created_by_user_id FROM shared_meals
  WHERE shared_meals.id = shared_meal_participants.shared_meal_id
)
WHERE inviter_user_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_shared_meal_participant_inbox
  ON shared_meal_participants(user_id, status, updated_at DESC, id)
  WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_shared_meal_participant_meal_active
  ON shared_meal_participants(shared_meal_id, updated_at DESC, id)
  WHERE deleted_at IS NULL;

-- Companion link requests remain explicit consent records. No DiningCompanion
-- is linked or merged by this migration.
ALTER TABLE companion_link_requests ADD COLUMN deleted_at TEXT;
ALTER TABLE companion_link_requests ADD COLUMN server_version INTEGER NOT NULL DEFAULT 1;

CREATE INDEX IF NOT EXISTS idx_companion_link_requests_inbox_v1
  ON companion_link_requests(target_user_id, status, updated_at DESC, id)
  WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_companion_link_requests_outbox_v1
  ON companion_link_requests(requester_user_id, status, updated_at DESC, id)
  WHERE deleted_at IS NULL;

-- Community engagement is authenticated and always re-authorized against the
-- current content visibility. A tombstone preserves idempotency and prevents
-- stale clients from recreating a removed Like or Comment accidentally.
CREATE TABLE IF NOT EXISTS content_likes (
  id TEXT PRIMARY KEY,
  content_type TEXT NOT NULL CHECK (content_type IN ('visit')),
  content_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_version INTEGER NOT NULL DEFAULT 1,
  UNIQUE (content_type, content_id, user_id),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_content_likes_active_content
  ON content_likes(content_type, content_id, updated_at DESC, id)
  WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_content_likes_owner
  ON content_likes(user_id, updated_at DESC, id);

CREATE TABLE IF NOT EXISTS content_comments (
  id TEXT PRIMARY KEY,
  content_type TEXT NOT NULL CHECK (content_type IN ('visit')),
  content_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  body TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 280),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_version INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_content_comments_active_content
  ON content_comments(content_type, content_id, created_at DESC, id)
  WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_content_comments_owner
  ON content_comments(user_id, updated_at DESC, id);
