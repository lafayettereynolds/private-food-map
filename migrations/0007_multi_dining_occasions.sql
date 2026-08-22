ALTER TABLE visits ADD COLUMN dining_occasions_json TEXT NOT NULL DEFAULT '[]';

UPDATE visits
SET dining_occasions_json = CASE
  WHEN dining_occasion IS NULL OR dining_occasion = '' THEN '[]'
  ELSE '["' || dining_occasion || '"]'
END;
