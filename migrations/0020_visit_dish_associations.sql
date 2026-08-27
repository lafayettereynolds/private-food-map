PRAGMA foreign_keys = ON;

-- P2-A retained Web's visit-scoped Dish shape. P2-C keeps every Dish row and
-- adds an explicit association so one canonical Dish can be reused by many
-- Visits without cloning its identity.
CREATE TABLE visit_dishes (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  restaurant_id TEXT NOT NULL,
  visit_id TEXT NOT NULL,
  dish_id TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_version INTEGER NOT NULL DEFAULT 0,
  last_mutation_id TEXT,
  UNIQUE (user_id, visit_id, dish_id),
  FOREIGN KEY (restaurant_id) REFERENCES restaurants(id),
  FOREIGN KEY (visit_id) REFERENCES visits(id),
  FOREIGN KEY (dish_id) REFERENCES dishes(id)
);

CREATE INDEX idx_visit_dishes_visit
  ON visit_dishes(user_id, visit_id, sort_order, deleted_at);
CREATE INDEX idx_visit_dishes_dish
  ON visit_dishes(user_id, dish_id, deleted_at);
CREATE INDEX idx_visit_dishes_restaurant
  ON visit_dishes(user_id, restaurant_id, deleted_at);

-- Deterministic compatibility mapping: every legacy Dish remains untouched and
-- receives one association to its original Visit.
INSERT OR IGNORE INTO visit_dishes (
  id, user_id, restaurant_id, visit_id, dish_id, sort_order,
  created_at, updated_at, deleted_at, server_version, last_mutation_id
)
SELECT
  'legacy:' || id || ':' || visit_id,
  user_id, restaurant_id, visit_id, id, sort_order,
  created_at, updated_at, deleted_at, 1,
  'bootstrap:visitDish:' || id || ':' || visit_id
FROM dishes;

-- Keep 0019's immutable ledger and extend it additively for VisitDish.
CREATE TABLE sync_change_log_v3 (
  revision INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('restaurant', 'visit', 'dish', 'visitDish', 'photo')),
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
  server_version INTEGER NOT NULL CHECK (server_version > 0),
  mutation_id TEXT NOT NULL,
  changed_at TEXT NOT NULL,
  UNIQUE (user_id, mutation_id)
);

INSERT INTO sync_change_log_v3 (
  revision, user_id, entity_type, entity_id, operation, server_version,
  mutation_id, changed_at
)
SELECT revision, user_id, entity_type, entity_id, operation, server_version,
  mutation_id, changed_at
FROM sync_change_log_v2
ORDER BY revision;

CREATE INDEX idx_sync_change_log_v3_pull
  ON sync_change_log_v3(user_id, revision);
CREATE INDEX idx_sync_change_log_v3_entity
  ON sync_change_log_v3(user_id, entity_type, entity_id, revision DESC);

CREATE TABLE sync_mutation_receipts_v3 (
  user_id TEXT NOT NULL,
  mutation_id TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('restaurant', 'visit', 'dish', 'visitDish', 'photo')),
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
  status TEXT NOT NULL CHECK (status IN ('applied', 'conflict')),
  server_version INTEGER NOT NULL,
  revision INTEGER,
  conflict_reason TEXT,
  processed_at TEXT NOT NULL,
  PRIMARY KEY (user_id, mutation_id),
  FOREIGN KEY (revision) REFERENCES sync_change_log_v3(revision)
);

INSERT INTO sync_mutation_receipts_v3 (
  user_id, mutation_id, request_fingerprint, entity_type, entity_id, operation,
  status, server_version, revision, conflict_reason, processed_at
)
SELECT user_id, mutation_id, request_fingerprint, entity_type, entity_id,
  operation, status, server_version, revision, conflict_reason, processed_at
FROM sync_mutation_receipts_v2;

CREATE INDEX idx_sync_mutation_receipts_v3_entity
  ON sync_mutation_receipts_v3(user_id, entity_type, entity_id, processed_at DESC);

INSERT INTO sync_change_log_v3 (
  user_id, entity_type, entity_id, operation, server_version, mutation_id,
  changed_at
)
SELECT user_id, 'visitDish', id,
  CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
  server_version, 'bootstrap:visitDish:' || id, updated_at
FROM visit_dishes;
