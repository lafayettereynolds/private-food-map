PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS restaurants (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL DEFAULT 'owner',
  amap_poi_id TEXT NOT NULL,
  name TEXT NOT NULL,
  address TEXT NOT NULL,
  city TEXT NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  status TEXT NOT NULL,
  preference_level TEXT NOT NULL,
  overall_rating REAL,
  food_rating REAL,
  environment_rating REAL,
  service_rating REAL,
  value_rating REAL,
  tags_json TEXT NOT NULL DEFAULT '[]',
  long_term_note TEXT NOT NULL DEFAULT '',
  price_per_person REAL,
  marker_type TEXT NOT NULL DEFAULT 'emoji',
  merchant_image_url TEXT,
  marker_emoji TEXT NOT NULL DEFAULT '🍽️',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_restaurants_updated_at ON restaurants(updated_at);
CREATE INDEX IF NOT EXISTS idx_restaurants_deleted_at ON restaurants(deleted_at);

CREATE TABLE IF NOT EXISTS visits (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL DEFAULT 'owner',
  restaurant_id TEXT NOT NULL,
  visited_at TEXT NOT NULL,
  rating INTEGER,
  total_price REAL,
  price_per_person REAL,
  party_size INTEGER NOT NULL DEFAULT 1,
  queue_duration TEXT,
  companions_json TEXT NOT NULL DEFAULT '[]',
  dishes_json TEXT NOT NULL DEFAULT '[]',
  note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  FOREIGN KEY (restaurant_id) REFERENCES restaurants(id)
);

CREATE INDEX IF NOT EXISTS idx_visits_restaurant_id ON visits(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_visits_updated_at ON visits(updated_at);
CREATE INDEX IF NOT EXISTS idx_visits_deleted_at ON visits(deleted_at);
