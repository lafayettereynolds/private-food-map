PRAGMA foreign_keys = ON;

-- Authentication identities/sessions remain separate. Business and social
-- features reference users.id (the stable tm_... identity) through this
-- one-to-one profile projection.
CREATE TABLE user_profiles (
  user_id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  bio TEXT NOT NULL DEFAULT '',
  city TEXT NOT NULL DEFAULT '',
  avatar_photo_id TEXT,
  avatar_preset_id TEXT NOT NULL DEFAULT 'polar-bear' CHECK (avatar_preset_id IN (
    'polar-bear', 'penguin', 'cat', 'dog',
    'parrot', 'dinosaur', 'shiba', 'panda',
    'otter', 'hedgehog', 'rabbit', 'koala',
    'fox', 'raccoon', 'deer', 'whale'
  )),
  visibility TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private', 'friends', 'public')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_version INTEGER NOT NULL DEFAULT 0,
  last_mutation_id TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_user_profiles_display_name
  ON user_profiles(display_name COLLATE NOCASE, deleted_at);
CREATE INDEX idx_user_profiles_visibility
  ON user_profiles(visibility, deleted_at);
CREATE INDEX idx_user_profiles_avatar
  ON user_profiles(avatar_photo_id, deleted_at);

-- Preserve every legacy Web profile value. New native edits enforce current
-- bounds, but migration never truncates older names or changes their owner.
INSERT INTO user_profiles (
  user_id, display_name, bio, city, avatar_photo_id, avatar_preset_id,
  visibility, created_at, updated_at, deleted_at, server_version,
  last_mutation_id
)
SELECT
  id,
  CASE WHEN trim(nickname) = '' THEN 'Taste Map 用户' ELSE nickname END,
  COALESCE(bio, ''),
  COALESCE(city, ''),
  avatar_photo_id,
  COALESCE(avatar_preset_id, 'polar-bear'),
  CASE
    WHEN map_sharing_enabled = 1 AND map_visibility IN ('friends', 'public') THEN map_visibility
    ELSE 'private'
  END,
  created_at,
  updated_at,
  deleted_at,
  1,
  'bootstrap:profile:' || id
FROM users;

-- Existing ledgers are immutable. V5 adds Profile while preserving revisions,
-- receipts and therefore every issued cursor.
CREATE TABLE sync_change_log_v5 (
  revision INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN (
    'restaurant', 'visit', 'dish', 'visitDish', 'photo',
    'companion', 'recommendationSource', 'profile'
  )),
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
  server_version INTEGER NOT NULL CHECK (server_version > 0),
  mutation_id TEXT NOT NULL,
  changed_at TEXT NOT NULL,
  UNIQUE (user_id, mutation_id)
);

INSERT INTO sync_change_log_v5 (
  revision, user_id, entity_type, entity_id, operation, server_version,
  mutation_id, changed_at
)
SELECT revision, user_id, entity_type, entity_id, operation, server_version,
  mutation_id, changed_at
FROM sync_change_log_v4
ORDER BY revision;

CREATE INDEX idx_sync_change_log_v5_pull
  ON sync_change_log_v5(user_id, revision);
CREATE INDEX idx_sync_change_log_v5_entity
  ON sync_change_log_v5(user_id, entity_type, entity_id, revision DESC);

CREATE TABLE sync_mutation_receipts_v5 (
  user_id TEXT NOT NULL,
  mutation_id TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN (
    'restaurant', 'visit', 'dish', 'visitDish', 'photo',
    'companion', 'recommendationSource', 'profile'
  )),
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
  status TEXT NOT NULL CHECK (status IN ('applied', 'conflict')),
  server_version INTEGER NOT NULL,
  revision INTEGER,
  conflict_reason TEXT,
  processed_at TEXT NOT NULL,
  PRIMARY KEY (user_id, mutation_id),
  FOREIGN KEY (revision) REFERENCES sync_change_log_v5(revision)
);

INSERT INTO sync_mutation_receipts_v5 (
  user_id, mutation_id, request_fingerprint, entity_type, entity_id, operation,
  status, server_version, revision, conflict_reason, processed_at
)
SELECT user_id, mutation_id, request_fingerprint, entity_type, entity_id,
  operation, status, server_version, revision, conflict_reason, processed_at
FROM sync_mutation_receipts_v4;

CREATE INDEX idx_sync_mutation_receipts_v5_entity
  ON sync_mutation_receipts_v5(user_id, entity_type, entity_id, processed_at DESC);

INSERT INTO sync_change_log_v5 (
  user_id, entity_type, entity_id, operation, server_version, mutation_id,
  changed_at
)
SELECT user_id, 'profile', user_id,
  CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
  server_version, last_mutation_id, updated_at
FROM user_profiles;
