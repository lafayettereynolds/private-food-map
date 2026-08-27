PRAGMA foreign_keys = ON;

-- Web historically stores dishes inside visits.dishes_json. P2-A adds a
-- versioned, visit-scoped Dish entity while retaining that JSON projection for
-- rolling Web compatibility.
CREATE TABLE dishes (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  restaurant_id TEXT NOT NULL,
  visit_id TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  taste TEXT NOT NULL DEFAULT '',
  rating REAL CHECK (rating IS NULL OR (rating >= 0.5 AND rating <= 5.0 AND rating * 2 = CAST(rating * 2 AS INTEGER))),
  price REAL CHECK (price IS NULL OR price >= 0),
  photo_id TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_version INTEGER NOT NULL DEFAULT 0,
  last_mutation_id TEXT,
  FOREIGN KEY (restaurant_id) REFERENCES restaurants(id),
  FOREIGN KEY (visit_id) REFERENCES visits(id)
);

CREATE INDEX idx_dishes_user_updated ON dishes(user_id, updated_at);
CREATE INDEX idx_dishes_restaurant ON dishes(user_id, restaurant_id, deleted_at);
CREATE INDEX idx_dishes_visit ON dishes(user_id, visit_id, sort_order, deleted_at);
CREATE INDEX idx_dishes_photo ON dishes(user_id, photo_id);

INSERT OR IGNORE INTO dishes (
  id, user_id, restaurant_id, visit_id, name, taste, rating, price, photo_id,
  sort_order, created_at, updated_at, deleted_at, server_version,
  last_mutation_id
)
SELECT
  json_extract(d.value, '$.id'),
  v.user_id,
  v.restaurant_id,
  v.id,
  COALESCE(json_extract(d.value, '$.name'), ''),
  COALESCE(json_extract(d.value, '$.taste'), ''),
  CASE WHEN json_type(d.value, '$.rating') IN ('integer', 'real') THEN json_extract(d.value, '$.rating') ELSE NULL END,
  CASE WHEN json_type(d.value, '$.price') IN ('integer', 'real') THEN json_extract(d.value, '$.price') ELSE NULL END,
  CASE WHEN json_type(d.value, '$.photoId') = 'text' THEN json_extract(d.value, '$.photoId') ELSE NULL END,
  CAST(d.key AS INTEGER),
  v.created_at,
  v.updated_at,
  v.deleted_at,
  1,
  'bootstrap:dish:' || json_extract(d.value, '$.id')
FROM visits v, json_each(CASE WHEN json_valid(v.dishes_json) THEN v.dishes_json ELSE '[]' END) d
WHERE COALESCE(TRIM(json_extract(d.value, '$.id')), '') != '';

-- Photo remains a provider-neutral business record. Provider-specific keys are
-- storage locators, never the Photo primary key.
ALTER TABLE photos ADD COLUMN dish_id TEXT;
ALTER TABLE photos ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0 CHECK (sort_order >= 0);
ALTER TABLE photos ADD COLUMN server_version INTEGER NOT NULL DEFAULT 0;
ALTER TABLE photos ADD COLUMN last_mutation_id TEXT;

UPDATE photos
SET dish_id = (
  SELECT d.id FROM dishes d
  WHERE d.user_id = photos.user_id AND d.photo_id = photos.id
  ORDER BY d.updated_at DESC LIMIT 1
)
WHERE kind = 'dish' AND dish_id IS NULL;

UPDATE photos
SET sort_order = COALESCE((
  SELECT CAST(p.key AS INTEGER)
  FROM visits v, json_each(CASE WHEN json_valid(v.photo_ids_json) THEN v.photo_ids_json ELSE '[]' END) p
  WHERE v.id = photos.visit_id AND v.user_id = photos.user_id AND p.value = photos.id
  LIMIT 1
), 0);

UPDATE photos SET server_version = 1 WHERE server_version = 0;

CREATE INDEX idx_photos_dish_id ON photos(user_id, dish_id, deleted_at);
CREATE INDEX idx_photos_sort_order ON photos(user_id, visit_id, sort_order, deleted_at);

-- 0016 intentionally constrained entity_type to Restaurant/Visit. Keep those
-- immutable tables intact and introduce a copied V2 ledger that extends the
-- same opaque revision cursor to Dish/Photo without deleting any history.
CREATE TABLE sync_change_log_v2 (
  revision INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('restaurant', 'visit', 'dish', 'photo')),
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
  server_version INTEGER NOT NULL CHECK (server_version > 0),
  mutation_id TEXT NOT NULL,
  changed_at TEXT NOT NULL,
  UNIQUE (user_id, mutation_id)
);

INSERT INTO sync_change_log_v2 (
  revision, user_id, entity_type, entity_id, operation, server_version,
  mutation_id, changed_at
)
SELECT revision, user_id, entity_type, entity_id, operation, server_version,
  mutation_id, changed_at
FROM sync_change_log
ORDER BY revision;

CREATE INDEX idx_sync_change_log_v2_pull
  ON sync_change_log_v2(user_id, revision);
CREATE INDEX idx_sync_change_log_v2_entity
  ON sync_change_log_v2(user_id, entity_type, entity_id, revision DESC);

CREATE TABLE sync_mutation_receipts_v2 (
  user_id TEXT NOT NULL,
  mutation_id TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('restaurant', 'visit', 'dish', 'photo')),
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
  status TEXT NOT NULL CHECK (status IN ('applied', 'conflict')),
  server_version INTEGER NOT NULL,
  revision INTEGER,
  conflict_reason TEXT,
  processed_at TEXT NOT NULL,
  PRIMARY KEY (user_id, mutation_id),
  FOREIGN KEY (revision) REFERENCES sync_change_log_v2(revision)
);

INSERT INTO sync_mutation_receipts_v2 (
  user_id, mutation_id, request_fingerprint, entity_type, entity_id, operation,
  status, server_version, revision, conflict_reason, processed_at
)
SELECT user_id, mutation_id, request_fingerprint, entity_type, entity_id,
  operation, status, server_version, revision, conflict_reason, processed_at
FROM sync_mutation_receipts;

CREATE INDEX idx_sync_mutation_receipts_v2_entity
  ON sync_mutation_receipts_v2(user_id, entity_type, entity_id, processed_at DESC);

INSERT INTO sync_change_log_v2 (
  user_id, entity_type, entity_id, operation, server_version, mutation_id,
  changed_at
)
SELECT user_id, 'dish', id,
  CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
  server_version, 'bootstrap:dish:' || id, updated_at
FROM dishes;

INSERT INTO sync_change_log_v2 (
  user_id, entity_type, entity_id, operation, server_version, mutation_id,
  changed_at
)
SELECT user_id, 'photo', id,
  CASE WHEN deleted_at IS NULL THEN 'upsert' ELSE 'delete' END,
  server_version, 'bootstrap:photo:' || id, updated_at
FROM photos;
