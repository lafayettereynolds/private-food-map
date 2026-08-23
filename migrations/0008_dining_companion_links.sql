ALTER TABLE visits ADD COLUMN companion_ids_json TEXT NOT NULL DEFAULT '[]';

CREATE TABLE IF NOT EXISTS dining_companions (
  id TEXT PRIMARY KEY,
  owner_user_id TEXT NOT NULL,
  display_name TEXT NOT NULL,
  linked_user_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  FOREIGN KEY (owner_user_id) REFERENCES users(id),
  FOREIGN KEY (linked_user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_dining_companions_owner ON dining_companions(owner_user_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_dining_companions_linked ON dining_companions(linked_user_id, updated_at);

CREATE TABLE IF NOT EXISTS companion_link_requests (
  id TEXT PRIMARY KEY,
  companion_id TEXT NOT NULL,
  companion_display_name TEXT NOT NULL,
  requester_user_id TEXT NOT NULL,
  target_user_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (companion_id) REFERENCES dining_companions(id),
  FOREIGN KEY (requester_user_id) REFERENCES users(id),
  FOREIGN KEY (target_user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_companion_link_requests_target ON companion_link_requests(target_user_id, status, updated_at);
CREATE INDEX IF NOT EXISTS idx_companion_link_requests_requester ON companion_link_requests(requester_user_id, status, updated_at);
