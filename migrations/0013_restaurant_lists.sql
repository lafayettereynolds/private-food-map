CREATE TABLE IF NOT EXISTS restaurant_lists (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  visibility TEXT NOT NULL DEFAULT 'private',
  is_ranked INTEGER NOT NULL DEFAULT 0,
  cover_mode TEXT NOT NULL DEFAULT 'automatic',
  custom_cover_photo_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_restaurant_lists_user_updated ON restaurant_lists(user_id, updated_at);

CREATE TABLE IF NOT EXISTS restaurant_list_items (
  id TEXT PRIMARY KEY,
  list_id TEXT NOT NULL,
  restaurant_id TEXT NOT NULL,
  position INTEGER NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  UNIQUE(list_id, restaurant_id)
);

CREATE INDEX IF NOT EXISTS idx_restaurant_list_items_list_position ON restaurant_list_items(list_id, position);
