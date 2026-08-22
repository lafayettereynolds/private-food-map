PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  auth_provider TEXT NOT NULL DEFAULT 'local',
  auth_subject TEXT,
  email TEXT,
  nickname TEXT NOT NULL,
  bio TEXT NOT NULL DEFAULT '',
  city TEXT NOT NULL DEFAULT '',
  avatar_photo_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_auth_subject
  ON users(auth_provider, auth_subject)
  WHERE auth_subject IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_nickname ON users(nickname);

INSERT OR IGNORE INTO users (
  id, auth_provider, nickname, created_at, updated_at
) VALUES (
  'owner', 'local', 'Taste Map 用户', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);

ALTER TABLE visits ADD COLUMN visibility TEXT NOT NULL DEFAULT 'private';
ALTER TABLE visits ADD COLUMN dining_mode TEXT NOT NULL DEFAULT 'dine_in';
ALTER TABLE visits ADD COLUMN my_actual_spend REAL;
ALTER TABLE visits ADD COLUMN payment_mode TEXT;
ALTER TABLE visits ADD COLUMN dining_occasion TEXT;
ALTER TABLE visits ADD COLUMN value_rating INTEGER;
ALTER TABLE visits ADD COLUMN environment_rating INTEGER;
ALTER TABLE visits ADD COLUMN service_rating INTEGER;
ALTER TABLE visits ADD COLUMN noise_level TEXT;
ALTER TABLE visits ADD COLUMN dining_duration TEXT;
ALTER TABLE visits ADD COLUMN portion_level TEXT;
ALTER TABLE visits ADD COLUMN transport_convenience TEXT;
ALTER TABLE visits ADD COLUMN special_notes TEXT NOT NULL DEFAULT '';
ALTER TABLE visits ADD COLUMN recommendation_source_type TEXT;
ALTER TABLE visits ADD COLUMN recommendation_source_user_id TEXT;
ALTER TABLE visits ADD COLUMN recommendation_source_text TEXT NOT NULL DEFAULT '';
ALTER TABLE visits ADD COLUMN shared_meal_id TEXT;

CREATE TABLE IF NOT EXISTS friendships (
  id TEXT PRIMARY KEY,
  requester_id TEXT NOT NULL,
  addressee_id TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(requester_id, addressee_id),
  FOREIGN KEY (requester_id) REFERENCES users(id),
  FOREIGN KEY (addressee_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_friendships_requester ON friendships(requester_id, status);
CREATE INDEX IF NOT EXISTS idx_friendships_addressee ON friendships(addressee_id, status);

CREATE TABLE IF NOT EXISTS shared_meals (
  id TEXT PRIMARY KEY,
  restaurant_id TEXT NOT NULL,
  created_by_user_id TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  FOREIGN KEY (restaurant_id) REFERENCES restaurants(id),
  FOREIGN KEY (created_by_user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS shared_meal_participants (
  id TEXT PRIMARY KEY,
  shared_meal_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  visit_id TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(shared_meal_id, user_id),
  FOREIGN KEY (shared_meal_id) REFERENCES shared_meals(id),
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (visit_id) REFERENCES visits(id)
);

CREATE INDEX IF NOT EXISTS idx_shared_meals_restaurant ON shared_meals(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_shared_meal_participants_user ON shared_meal_participants(user_id, status);
CREATE INDEX IF NOT EXISTS idx_restaurants_user ON restaurants(user_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_visits_user ON visits(user_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_visits_visibility ON visits(visibility, visited_at);
CREATE INDEX IF NOT EXISTS idx_visits_shared_meal ON visits(shared_meal_id);
