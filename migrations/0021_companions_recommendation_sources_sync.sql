PRAGMA foreign_keys = ON;

-- P2-F keeps the existing Web dining_companions table and adds only the
-- metadata required by Sync V1. normalized_name is deliberately case
-- sensitive: whitespace/Unicode compatibility forms are normalized by the
-- clients and Worker, but "Alex" and "alex" are not silently merged.
ALTER TABLE dining_companions ADD COLUMN normalized_name TEXT NOT NULL DEFAULT '';
ALTER TABLE dining_companions ADD COLUMN server_version INTEGER NOT NULL DEFAULT 0;
ALTER TABLE dining_companions ADD COLUMN last_mutation_id TEXT;

UPDATE dining_companions
SET normalized_name = trim(display_name),
    server_version = CASE WHEN server_version = 0 THEN 1 ELSE server_version END;

CREATE INDEX idx_dining_companions_owner_name
  ON dining_companions(owner_user_id, normalized_name, deleted_at);

-- Web historically stored recommendation source data directly on Visit. The
-- new directory gives native clients stable identities and history reuse while
-- the original Visit columns remain the compatibility projection for Web.
CREATE TABLE recommendation_sources (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  display_name TEXT NOT NULL,
  normalized_name TEXT NOT NULL,
  source_type TEXT NOT NULL CHECK (source_type IN (
    'friend', 'xiaohongshu', 'douyin', 'dianping', 'blogger', 'self', 'other'
  )),
  linked_user_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_version INTEGER NOT NULL DEFAULT 0,
  last_mutation_id TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (linked_user_id) REFERENCES users(id)
);

CREATE INDEX idx_recommendation_sources_user_name
  ON recommendation_sources(user_id, normalized_name, deleted_at);
CREATE INDEX idx_recommendation_sources_user_updated
  ON recommendation_sources(user_id, updated_at);

ALTER TABLE visits ADD COLUMN recommendation_source_id TEXT;
CREATE INDEX idx_visits_recommendation_source
  ON visits(user_id, recommendation_source_id, deleted_at);

-- The previous ledgers remain immutable. V4 extends their entity check while
-- retaining every revision so existing cursors continue to advance safely.
CREATE TABLE sync_change_log_v4 (
  revision INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN (
    'restaurant', 'visit', 'dish', 'visitDish', 'photo',
    'companion', 'recommendationSource'
  )),
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
  server_version INTEGER NOT NULL CHECK (server_version > 0),
  mutation_id TEXT NOT NULL,
  changed_at TEXT NOT NULL,
  UNIQUE (user_id, mutation_id)
);

INSERT INTO sync_change_log_v4 (
  revision, user_id, entity_type, entity_id, operation, server_version,
  mutation_id, changed_at
)
SELECT revision, user_id, entity_type, entity_id, operation, server_version,
  mutation_id, changed_at
FROM sync_change_log_v3
ORDER BY revision;

CREATE INDEX idx_sync_change_log_v4_pull
  ON sync_change_log_v4(user_id, revision);
CREATE INDEX idx_sync_change_log_v4_entity
  ON sync_change_log_v4(user_id, entity_type, entity_id, revision DESC);

CREATE TABLE sync_mutation_receipts_v4 (
  user_id TEXT NOT NULL,
  mutation_id TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN (
    'restaurant', 'visit', 'dish', 'visitDish', 'photo',
    'companion', 'recommendationSource'
  )),
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
  status TEXT NOT NULL CHECK (status IN ('applied', 'conflict')),
  server_version INTEGER NOT NULL,
  revision INTEGER,
  conflict_reason TEXT,
  processed_at TEXT NOT NULL,
  PRIMARY KEY (user_id, mutation_id),
  FOREIGN KEY (revision) REFERENCES sync_change_log_v4(revision)
);

INSERT INTO sync_mutation_receipts_v4 (
  user_id, mutation_id, request_fingerprint, entity_type, entity_id, operation,
  status, server_version, revision, conflict_reason, processed_at
)
SELECT user_id, mutation_id, request_fingerprint, entity_type, entity_id,
  operation, status, server_version, revision, conflict_reason, processed_at
FROM sync_mutation_receipts_v3;

CREATE INDEX idx_sync_mutation_receipts_v4_entity
  ON sync_mutation_receipts_v4(user_id, entity_type, entity_id, processed_at DESC);

INSERT INTO sync_change_log_v4 (
  user_id, entity_type, entity_id, operation, server_version, mutation_id,
  changed_at
)
SELECT owner_user_id, 'companion', id,
  CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
  server_version, 'bootstrap:companion:' || id, updated_at
FROM dining_companions;
