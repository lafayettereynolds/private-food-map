PRAGMA foreign_keys = ON;

-- P3-C keeps Discovery as an authenticated read model. These indexes support
-- visibility-first candidate reads without copying derived recommendations.
CREATE INDEX IF NOT EXISTS idx_visits_discovery_public
  ON visits(visibility, visited_at DESC, restaurant_id, user_id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_visits_discovery_owner
  ON visits(user_id, visited_at DESC, restaurant_id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_restaurants_discovery_city
  ON restaurants(city, id, user_id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_want_to_go_discovery
  ON want_to_go(created_at DESC, restaurant_id, user_id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_restaurant_identity_discovery
  ON restaurant_place_identities(provider, external_id, restaurant_id);

CREATE TABLE IF NOT EXISTS discovery_rate_limits (
  user_id TEXT NOT NULL,
  window_started_at TEXT NOT NULL,
  request_count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, window_started_at),
  FOREIGN KEY (user_id) REFERENCES users(id)
);
