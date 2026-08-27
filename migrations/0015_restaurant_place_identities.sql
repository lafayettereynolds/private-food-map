PRAGMA foreign_keys = ON;

-- Restaurant.id remains the Taste Map-owned stable ID. Provider POI IDs are
-- independent lookup evidence and never replace Restaurant.id or Visit links.
CREATE TABLE restaurant_place_identities (
  restaurant_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  provider TEXT NOT NULL CHECK (provider IN ('amap', 'apple_maps', 'manual', 'other')),
  external_id TEXT NOT NULL CHECK (length(trim(external_id)) > 0),
  is_primary INTEGER NOT NULL DEFAULT 0 CHECK (is_primary IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (restaurant_id, provider, external_id),
  FOREIGN KEY (restaurant_id) REFERENCES restaurants(id)
);

CREATE INDEX idx_restaurant_place_identities_lookup
  ON restaurant_place_identities(user_id, provider, external_id);
CREATE INDEX idx_restaurant_place_identities_restaurant
  ON restaurant_place_identities(restaurant_id, is_primary DESC, updated_at DESC);
CREATE UNIQUE INDEX idx_restaurant_place_identities_one_primary
  ON restaurant_place_identities(restaurant_id)
  WHERE is_primary = 1;

-- Preserve every existing Restaurant row, including ambiguous duplicate POI
-- mappings. Duplicates are diagnosed before deployment and never auto-merged.
INSERT INTO restaurant_place_identities (
  restaurant_id, user_id, provider, external_id, is_primary, created_at, updated_at
)
SELECT id, user_id, 'amap', trim(amap_poi_id), 1, created_at, updated_at
FROM restaurants
WHERE amap_poi_id IS NOT NULL AND length(trim(amap_poi_id)) > 0;
