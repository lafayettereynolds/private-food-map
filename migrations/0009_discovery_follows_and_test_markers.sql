ALTER TABLE users ADD COLUMN is_test_user INTEGER NOT NULL DEFAULT 0;
ALTER TABLE restaurants ADD COLUMN is_test_data INTEGER NOT NULL DEFAULT 0;
ALTER TABLE visits ADD COLUMN is_test_data INTEGER NOT NULL DEFAULT 0;
ALTER TABLE friendships ADD COLUMN is_test_data INTEGER NOT NULL DEFAULT 0;
ALTER TABLE shared_meals ADD COLUMN is_test_data INTEGER NOT NULL DEFAULT 0;
ALTER TABLE shared_meal_participants ADD COLUMN is_test_data INTEGER NOT NULL DEFAULT 0;
ALTER TABLE dining_companions ADD COLUMN is_test_data INTEGER NOT NULL DEFAULT 0;
ALTER TABLE companion_link_requests ADD COLUMN is_test_data INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS follows (
  id TEXT PRIMARY KEY,
  follower_id TEXT NOT NULL,
  followed_user_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  is_test_data INTEGER NOT NULL DEFAULT 0,
  UNIQUE(follower_id, followed_user_id),
  FOREIGN KEY (follower_id) REFERENCES users(id),
  FOREIGN KEY (followed_user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows(follower_id, created_at);
CREATE INDEX IF NOT EXISTS idx_follows_followed ON follows(followed_user_id, created_at);

CREATE TABLE IF NOT EXISTS want_to_go (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  restaurant_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  deleted_at TEXT,
  is_test_data INTEGER NOT NULL DEFAULT 0,
  UNIQUE(user_id, restaurant_id),
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (restaurant_id) REFERENCES restaurants(id)
);

CREATE INDEX IF NOT EXISTS idx_want_to_go_user ON want_to_go(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_want_to_go_restaurant ON want_to_go(restaurant_id, created_at);
