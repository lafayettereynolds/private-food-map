PRAGMA foreign_keys = ON;

-- Server versions are authoritative for conflict detection. Device clocks are
-- retained as domain metadata but are never the concurrency primitive.
ALTER TABLE restaurants ADD COLUMN server_version INTEGER NOT NULL DEFAULT 0;
ALTER TABLE restaurants ADD COLUMN last_mutation_id TEXT;
ALTER TABLE visits ADD COLUMN server_version INTEGER NOT NULL DEFAULT 0;
ALTER TABLE visits ADD COLUMN last_mutation_id TEXT;

UPDATE restaurants SET server_version = 1 WHERE server_version = 0;
UPDATE visits SET server_version = 1 WHERE server_version = 0;

-- A legacy row without a usable provider ID still needs a provider-neutral
-- identity so it can participate in the V1 contract without inventing an Amap
-- or Apple Maps identifier.
INSERT INTO restaurant_place_identities (
  restaurant_id, user_id, provider, external_id, is_primary, created_at, updated_at
)
SELECT
  r.id, r.user_id, 'manual', 'tastemap:' || r.id, 1, r.created_at, r.updated_at
FROM restaurants r
WHERE NOT EXISTS (
  SELECT 1 FROM restaurant_place_identities i WHERE i.restaurant_id = r.id
);

CREATE TABLE sync_change_log (
  revision INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('restaurant', 'visit')),
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
  server_version INTEGER NOT NULL CHECK (server_version > 0),
  mutation_id TEXT NOT NULL,
  changed_at TEXT NOT NULL,
  UNIQUE (user_id, mutation_id)
);

CREATE INDEX idx_sync_change_log_pull
  ON sync_change_log(user_id, revision);
CREATE INDEX idx_sync_change_log_entity
  ON sync_change_log(user_id, entity_type, entity_id, revision DESC);

CREATE TABLE sync_mutation_receipts (
  user_id TEXT NOT NULL,
  mutation_id TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('restaurant', 'visit')),
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
  status TEXT NOT NULL CHECK (status IN ('applied', 'conflict')),
  server_version INTEGER NOT NULL,
  revision INTEGER,
  conflict_reason TEXT,
  processed_at TEXT NOT NULL,
  PRIMARY KEY (user_id, mutation_id),
  FOREIGN KEY (revision) REFERENCES sync_change_log(revision)
);

CREATE INDEX idx_sync_mutation_receipts_entity
  ON sync_mutation_receipts(user_id, entity_type, entity_id, processed_at DESC);

-- Existing rows become the first versioned snapshot. No Restaurant/Visit ID or
-- relationship is rewritten, including rows that are already tombstoned.
INSERT INTO sync_change_log (
  user_id, entity_type, entity_id, operation, server_version, mutation_id, changed_at
)
SELECT
  user_id,
  'restaurant',
  id,
  CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
  server_version,
  'bootstrap:restaurant:' || id,
  updated_at
FROM restaurants;

INSERT INTO sync_change_log (
  user_id, entity_type, entity_id, operation, server_version, mutation_id, changed_at
)
SELECT
  user_id,
  'visit',
  id,
  CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
  server_version,
  'bootstrap:visit:' || id,
  updated_at
FROM visits;
