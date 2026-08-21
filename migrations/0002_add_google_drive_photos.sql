PRAGMA foreign_keys = ON;

ALTER TABLE restaurants ADD COLUMN marker_photo_id TEXT;
ALTER TABLE visits ADD COLUMN photo_ids_json TEXT NOT NULL DEFAULT '[]';

CREATE TABLE photos (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL DEFAULT 'owner',
  restaurant_id TEXT,
  visit_id TEXT,
  storage_provider TEXT NOT NULL DEFAULT 'google-drive',
  drive_account_id TEXT NOT NULL,
  drive_file_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  file_name TEXT,
  mime_type TEXT NOT NULL,
  file_size INTEGER NOT NULL,
  width INTEGER,
  height INTEGER,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  FOREIGN KEY (restaurant_id) REFERENCES restaurants(id),
  FOREIGN KEY (visit_id) REFERENCES visits(id)
);

CREATE INDEX idx_photos_restaurant_id ON photos(restaurant_id);
CREATE INDEX idx_photos_visit_id ON photos(visit_id);
CREATE INDEX idx_photos_updated_at ON photos(updated_at);
CREATE INDEX idx_photos_deleted_at ON photos(deleted_at);
