ALTER TABLE photos ADD COLUMN storage_key TEXT;
ALTER TABLE photos ADD COLUMN thumbnail_storage_key TEXT;
ALTER TABLE photos ADD COLUMN thumbnail_file_size INTEGER;
ALTER TABLE photos ADD COLUMN visibility TEXT NOT NULL DEFAULT 'private';
ALTER TABLE photos ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'synced';

UPDATE photos SET storage_key = drive_file_id WHERE storage_key IS NULL;
