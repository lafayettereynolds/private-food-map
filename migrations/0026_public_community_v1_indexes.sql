-- P3-D: additive indexes for authorization-aware public content and timeline queries.
-- No existing rows or ownership relationships are rewritten.

CREATE INDEX IF NOT EXISTS idx_visits_public_content_owner
  ON visits(user_id, visibility, visited_at DESC, id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_visits_community_timeline
  ON visits(visibility, visited_at DESC, id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_photos_public_content_visit
  ON photos(visit_id, visibility, sort_order, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_restaurants_public_want_owner
  ON restaurants(user_id, status, updated_at DESC, id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_friendships_content_authorization
  ON friendships(pair_user_a, pair_user_b, status, deleted_at);

CREATE INDEX IF NOT EXISTS idx_follows_community_timeline
  ON follows(follower_id, followed_user_id, deleted_at);
