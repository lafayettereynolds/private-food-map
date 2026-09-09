-- Retain deletion authority even when an upload has not created photo metadata.
-- Account-scoped immutable photo IDs must never become active again.
CREATE TABLE photo_deletion_fences (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  photo_id TEXT NOT NULL,
  deleted_at TEXT NOT NULL,
  checked_at TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (user_id, photo_id)
);
CREATE INDEX photo_deletion_fences_cleanup ON photo_deletion_fences(checked_at);
