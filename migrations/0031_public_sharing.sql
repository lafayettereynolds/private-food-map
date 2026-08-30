CREATE TABLE IF NOT EXISTS public_share_links (
  share_id TEXT PRIMARY KEY,
  owner_user_id TEXT NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('restaurant', 'profile', 'list')),
  entity_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revoked_at TEXT,
  UNIQUE (owner_user_id, entity_type, entity_id),
  FOREIGN KEY (owner_user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_public_share_links_owner
  ON public_share_links(owner_user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_public_share_links_active
  ON public_share_links(share_id)
  WHERE revoked_at IS NULL;
