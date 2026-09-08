-- Metadata only: never store redemption codes here. Populated only in isolated Sandbox D1.
CREATE TABLE sandbox_offer_assignments (
  assignment_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  reward_id TEXT NOT NULL UNIQUE REFERENCES premium_rewards(id),
  offer_identifier TEXT NOT NULL,
  environment TEXT NOT NULL DEFAULT 'Sandbox' CHECK(environment = 'Sandbox'),
  assigned_at TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'assigned' CHECK(state IN ('assigned','failed','redeemed')),
  transaction_id TEXT UNIQUE,
  original_transaction_id TEXT,
  redeemed_at TEXT
);
CREATE INDEX sandbox_offer_assignment_owner ON sandbox_offer_assignments(user_id,offer_identifier);
