-- Align expressions with the existing read contract; do not rewrite stored cities.
CREATE INDEX IF NOT EXISTS idx_restaurants_discovery_trimmed_city
  ON restaurants(TRIM(city), id, user_id)
  WHERE deleted_at IS NULL AND COALESCE(is_test_data,0)=0;
CREATE INDEX IF NOT EXISTS idx_visits_discovery_candidate
  ON visits(restaurant_id, user_id, visibility, visited_at DESC, id)
  WHERE deleted_at IS NULL AND COALESCE(is_test_data,0)=0;
CREATE INDEX IF NOT EXISTS idx_wants_discovery_candidate
  ON want_to_go(restaurant_id, user_id, created_at)
  WHERE deleted_at IS NULL AND COALESCE(is_test_data,0)=0;
