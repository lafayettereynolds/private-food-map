PRAGMA foreign_keys = ON;

-- P4-F upgrades the existing Web list tables in place. No list, item,
-- Restaurant or Visit identity is rewritten and no production database is
-- touched by this migration file itself.
ALTER TABLE restaurant_lists ADD COLUMN server_version INTEGER NOT NULL DEFAULT 0;
ALTER TABLE restaurant_lists ADD COLUMN last_mutation_id TEXT;
ALTER TABLE restaurant_lists ADD COLUMN active_item_count INTEGER NOT NULL DEFAULT 0;

ALTER TABLE restaurant_list_items ADD COLUMN user_id TEXT;
ALTER TABLE restaurant_list_items ADD COLUMN restaurant_global_key TEXT;
ALTER TABLE restaurant_list_items ADD COLUMN restaurant_snapshot_json TEXT;
ALTER TABLE restaurant_list_items ADD COLUMN server_version INTEGER NOT NULL DEFAULT 0;
ALTER TABLE restaurant_list_items ADD COLUMN last_mutation_id TEXT;

UPDATE restaurant_lists
SET server_version = 1,
    last_mutation_id = 'bootstrap:restaurantList:' || id,
    active_item_count = (
      SELECT COUNT(*) FROM restaurant_list_items rli
      WHERE rli.list_id = restaurant_lists.id AND rli.deleted_at IS NULL
    )
WHERE server_version = 0;

UPDATE restaurant_list_items
SET user_id = (SELECT rl.user_id FROM restaurant_lists rl WHERE rl.id = restaurant_list_items.list_id),
    restaurant_global_key = COALESCE((
      SELECT rpi.provider || ':' || rpi.external_id
      FROM restaurant_place_identities rpi
      WHERE rpi.restaurant_id = restaurant_list_items.restaurant_id
        AND rpi.user_id = (SELECT rl.user_id FROM restaurant_lists rl WHERE rl.id = restaurant_list_items.list_id)
      ORDER BY rpi.is_primary DESC, rpi.updated_at ASC
      LIMIT 1
    ), 'manual:tastemap:' || restaurant_id),
    server_version = 1,
    last_mutation_id = 'bootstrap:restaurantListItem:' || id
WHERE server_version = 0;

CREATE INDEX idx_restaurant_lists_owner_visibility_updated
  ON restaurant_lists(user_id, visibility, updated_at DESC, id);
CREATE INDEX idx_restaurant_list_items_owner_list_position
  ON restaurant_list_items(user_id, list_id, deleted_at, position, id);
CREATE INDEX idx_restaurant_list_items_global_identity
  ON restaurant_list_items(list_id, restaurant_global_key, deleted_at);

-- Sync V1 ledger V6 adds list entities while preserving every previous cursor
-- revision and mutation receipt.
CREATE TABLE sync_change_log_v6 (
  revision INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN (
    'restaurant', 'visit', 'dish', 'visitDish', 'photo',
    'companion', 'recommendationSource', 'profile',
    'restaurantList', 'restaurantListItem'
  )),
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
  server_version INTEGER NOT NULL CHECK (server_version > 0),
  mutation_id TEXT NOT NULL,
  changed_at TEXT NOT NULL,
  UNIQUE (user_id, mutation_id)
);

INSERT INTO sync_change_log_v6 (
  revision, user_id, entity_type, entity_id, operation, server_version,
  mutation_id, changed_at
)
SELECT revision, user_id, entity_type, entity_id, operation, server_version,
  mutation_id, changed_at
FROM sync_change_log_v5
ORDER BY revision;

CREATE INDEX idx_sync_change_log_v6_pull
  ON sync_change_log_v6(user_id, revision);
CREATE INDEX idx_sync_change_log_v6_entity
  ON sync_change_log_v6(user_id, entity_type, entity_id, revision DESC);

CREATE TABLE sync_mutation_receipts_v6 (
  user_id TEXT NOT NULL,
  mutation_id TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN (
    'restaurant', 'visit', 'dish', 'visitDish', 'photo',
    'companion', 'recommendationSource', 'profile',
    'restaurantList', 'restaurantListItem'
  )),
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
  status TEXT NOT NULL CHECK (status IN ('applied', 'conflict')),
  server_version INTEGER NOT NULL,
  revision INTEGER,
  conflict_reason TEXT,
  processed_at TEXT NOT NULL,
  PRIMARY KEY (user_id, mutation_id),
  FOREIGN KEY (revision) REFERENCES sync_change_log_v6(revision)
);

INSERT INTO sync_mutation_receipts_v6 (
  user_id, mutation_id, request_fingerprint, entity_type, entity_id, operation,
  status, server_version, revision, conflict_reason, processed_at
)
SELECT user_id, mutation_id, request_fingerprint, entity_type, entity_id,
  operation, status, server_version, revision, conflict_reason, processed_at
FROM sync_mutation_receipts_v5;

CREATE INDEX idx_sync_mutation_receipts_v6_entity
  ON sync_mutation_receipts_v6(user_id, entity_type, entity_id, processed_at DESC);

INSERT INTO sync_change_log_v6 (
  user_id, entity_type, entity_id, operation, server_version, mutation_id, changed_at
)
SELECT user_id, 'restaurantList', id,
  CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
  server_version, last_mutation_id, updated_at
FROM restaurant_lists;

INSERT INTO sync_change_log_v6 (
  user_id, entity_type, entity_id, operation, server_version, mutation_id, changed_at
)
SELECT user_id, 'restaurantListItem', id,
  CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
  server_version, last_mutation_id, updated_at
FROM restaurant_list_items
WHERE user_id IS NOT NULL;
