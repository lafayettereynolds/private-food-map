-- Private presentation metadata, never a public Profile avatar or Photo pool item.
CREATE TABLE private_directory_profiles (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK(kind IN ('companion','source')),
  entity_id TEXT NOT NULL,
  avatar_data TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(user_id,kind,entity_id)
);
CREATE TABLE private_directory_audit (
  id INTEGER PRIMARY KEY,
  user_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  action TEXT NOT NULL,
  target_user_id TEXT,
  created_at TEXT NOT NULL
);
