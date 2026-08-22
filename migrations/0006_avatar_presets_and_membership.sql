ALTER TABLE users ADD COLUMN avatar_preset_id TEXT NOT NULL DEFAULT 'polar-bear';
ALTER TABLE users ADD COLUMN membership_tier TEXT NOT NULL DEFAULT 'free';
ALTER TABLE visits ADD COLUMN dining_occasion_text TEXT NOT NULL DEFAULT '';
