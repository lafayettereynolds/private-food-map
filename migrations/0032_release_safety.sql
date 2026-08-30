PRAGMA foreign_keys = ON;

-- Account deletion is a durable, resumable job. The opaque status token is
-- represented only by a SHA-256 hash; neither auth nor deletion credentials
-- are stored in plaintext.
CREATE TABLE IF NOT EXISTS account_deletion_jobs (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  request_id TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  status_token_hash TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL CHECK (status IN (
    'previewed', 'confirmed', 'deleting_data', 'deleting_objects',
    'completed', 'failed'
  )),
  requested_at TEXT NOT NULL,
  confirmed_at TEXT,
  completed_at TEXT,
  updated_at TEXT NOT NULL,
  retry_count INTEGER NOT NULL DEFAULT 0,
  last_error_code TEXT,
  UNIQUE (user_id, request_id),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_account_deletion_jobs_user
  ON account_deletion_jobs(user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS account_deletion_objects (
  job_id TEXT NOT NULL,
  storage_key TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'deleted', 'failed')),
  retry_count INTEGER NOT NULL DEFAULT 0,
  last_error_code TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (job_id, storage_key),
  FOREIGN KEY (job_id) REFERENCES account_deletion_jobs(id)
);

CREATE INDEX IF NOT EXISTS idx_account_deletion_objects_pending
  ON account_deletion_objects(job_id, status, updated_at);

-- App Review safety for user-generated content. Blocks are symmetric for
-- visibility (either direction hides content), although only the blocker may
-- create or remove their row. Reports are private moderation records.
CREATE TABLE IF NOT EXISTS user_blocks (
  id TEXT PRIMARY KEY,
  blocker_user_id TEXT NOT NULL,
  blocked_user_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  UNIQUE (blocker_user_id, blocked_user_id),
  CHECK (blocker_user_id <> blocked_user_id),
  FOREIGN KEY (blocker_user_id) REFERENCES users(id),
  FOREIGN KEY (blocked_user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_user_blocks_active_blocker
  ON user_blocks(blocker_user_id, blocked_user_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_user_blocks_active_blocked
  ON user_blocks(blocked_user_id, blocker_user_id) WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS content_reports (
  id TEXT PRIMARY KEY,
  reporter_user_id TEXT NOT NULL,
  content_type TEXT NOT NULL CHECK (content_type IN ('visit', 'comment', 'user')),
  content_id TEXT NOT NULL,
  reason TEXT NOT NULL CHECK (reason IN (
    'spam', 'harassment', 'hate', 'sexual', 'violence', 'privacy', 'other'
  )),
  details TEXT NOT NULL DEFAULT '' CHECK (length(details) <= 500),
  request_id TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'reviewed', 'actioned', 'dismissed'
  )),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE (reporter_user_id, request_id),
  FOREIGN KEY (reporter_user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_content_reports_moderation
  ON content_reports(status, created_at, id);
CREATE INDEX IF NOT EXISTS idx_content_reports_reporter
  ON content_reports(reporter_user_id, created_at DESC);
