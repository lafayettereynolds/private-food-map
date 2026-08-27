-- Read-only P0-A preflight. Run against each target D1 before applying 0015.
SELECT
  COUNT(*) AS restaurant_count,
  SUM(CASE WHEN id IS NULL OR length(trim(id)) = 0 THEN 1 ELSE 0 END) AS empty_restaurant_ids,
  SUM(CASE WHEN amap_poi_id IS NULL OR length(trim(amap_poi_id)) = 0 THEN 1 ELSE 0 END) AS empty_amap_ids,
  SUM(CASE WHEN id = amap_poi_id THEN 1 ELSE 0 END) AS provider_id_used_as_primary_id
FROM restaurants;

SELECT COUNT(*) AS duplicate_provider_groups_per_user
FROM (
  SELECT user_id, amap_poi_id
  FROM restaurants
  WHERE amap_poi_id IS NOT NULL AND length(trim(amap_poi_id)) > 0
  GROUP BY user_id, amap_poi_id
  HAVING COUNT(*) > 1
);

SELECT COUNT(*) AS provider_ids_shared_across_users
FROM (
  SELECT amap_poi_id
  FROM restaurants
  WHERE amap_poi_id IS NOT NULL AND length(trim(amap_poi_id)) > 0
  GROUP BY amap_poi_id
  HAVING COUNT(DISTINCT user_id) > 1
);

SELECT COUNT(*) AS orphan_visits
FROM visits v
LEFT JOIN restaurants r ON r.id = v.restaurant_id
WHERE r.id IS NULL;
