CREATE TABLE IF NOT EXISTS app_store_accounts (
  user_id TEXT PRIMARY KEY,
  app_account_token TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS app_store_subscription_owners (
  original_transaction_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  app_account_token TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (app_account_token) REFERENCES app_store_accounts(app_account_token)
);

CREATE INDEX IF NOT EXISTS idx_app_store_subscription_owners_user
  ON app_store_subscription_owners(user_id, updated_at);

CREATE TABLE IF NOT EXISTS app_store_transactions (
  transaction_id TEXT PRIMARY KEY,
  original_transaction_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  app_account_token TEXT NOT NULL,
  product_id TEXT NOT NULL,
  environment TEXT NOT NULL,
  purchase_at TEXT NOT NULL,
  original_purchase_at TEXT,
  expires_at TEXT,
  revocation_at TEXT,
  revocation_reason TEXT,
  ownership_type TEXT,
  transaction_reason TEXT,
  signed_transaction_digest TEXT NOT NULL,
  verification_source TEXT NOT NULL,
  verified_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (original_transaction_id)
    REFERENCES app_store_subscription_owners(original_transaction_id),
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (app_account_token) REFERENCES app_store_accounts(app_account_token)
);

CREATE INDEX IF NOT EXISTS idx_app_store_transactions_original
  ON app_store_transactions(original_transaction_id, expires_at, purchase_at);

CREATE INDEX IF NOT EXISTS idx_app_store_transactions_user
  ON app_store_transactions(user_id, verified_at);

CREATE TABLE IF NOT EXISTS app_store_notification_events (
  notification_uuid TEXT PRIMARY KEY,
  notification_type TEXT NOT NULL,
  subtype TEXT,
  transaction_id TEXT NOT NULL,
  signed_payload_digest TEXT NOT NULL,
  processed_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_app_store_notification_transaction
  ON app_store_notification_events(transaction_id, processed_at);
