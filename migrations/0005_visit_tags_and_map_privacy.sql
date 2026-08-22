ALTER TABLE visits ADD COLUMN value_tags_json TEXT NOT NULL DEFAULT '[]';
ALTER TABLE visits ADD COLUMN environment_tags_json TEXT NOT NULL DEFAULT '[]';
ALTER TABLE visits ADD COLUMN service_tags_json TEXT NOT NULL DEFAULT '[]';

ALTER TABLE users ADD COLUMN map_sharing_enabled INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN map_visibility TEXT NOT NULL DEFAULT 'private';
