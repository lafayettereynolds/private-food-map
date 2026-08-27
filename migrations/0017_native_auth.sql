PRAGMA foreign_keys = ON;

-- Native authentication is deliberately separate from legacy users.auth_subject.
-- Business records continue to reference users.id, which is Taste Map's own ID.
CREATE TABLE auth_identities (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  provider TEXT NOT NULL CHECK (provider IN ('apple')),
  provider_subject TEXT NOT NULL,
  email TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_authenticated_at TEXT NOT NULL,
  UNIQUE (provider, provider_subject),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_auth_identities_user
  ON auth_identities(user_id, provider);

CREATE TABLE auth_challenges (
  state_hash TEXT PRIMARY KEY,
  nonce_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  used_at TEXT
);

CREATE INDEX idx_auth_challenges_expiry
  ON auth_challenges(expires_at);

CREATE TABLE auth_sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  access_token_hash TEXT NOT NULL UNIQUE,
  access_expires_at TEXT NOT NULL,
  refresh_token_hash TEXT NOT NULL UNIQUE,
  refresh_expires_at TEXT NOT NULL,
  refresh_generation INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_used_at TEXT NOT NULL,
  revoked_at TEXT,
  revoke_reason TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_auth_sessions_user
  ON auth_sessions(user_id, revoked_at);
CREATE INDEX idx_auth_sessions_access
  ON auth_sessions(access_token_hash, access_expires_at);

-- Consumed refresh hashes are retained for the lifetime of their session so a
-- stolen, already-rotated token revokes the whole session instead of succeeding.
CREATE TABLE auth_refresh_token_history (
  token_hash TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  generation INTEGER NOT NULL,
  consumed_at TEXT NOT NULL,
  FOREIGN KEY (session_id) REFERENCES auth_sessions(id)
);

CREATE INDEX idx_auth_refresh_history_session
  ON auth_refresh_token_history(session_id, generation);

-- An Apple identity token is accepted once. This is independent of nonce/state
-- consumption and closes replay races across multiple challenges.
CREATE TABLE auth_identity_token_uses (
  token_hash TEXT PRIMARY KEY,
  identity_id TEXT NOT NULL,
  used_at TEXT NOT NULL,
  FOREIGN KEY (identity_id) REFERENCES auth_identities(id)
);
