CREATE TABLE IF NOT EXISTS recommendation_events (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  event_name TEXT NOT NULL,
  recommendation_type TEXT NOT NULL,
  surface TEXT NOT NULL,
  restaurant_id TEXT NOT NULL,
  rank INTEGER,
  score REAL,
  reason_codes_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_recommendation_events_user_created ON recommendation_events(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_recommendation_events_restaurant ON recommendation_events(restaurant_id, created_at);
