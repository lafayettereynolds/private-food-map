-- Additive environment-qualified ledger. Legacy audit tables remain intact.
CREATE TABLE app_store_owners_v2 (
  environment TEXT NOT NULL CHECK(environment IN ('Sandbox','Production')),
  original_transaction_id TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(id),
  app_account_token TEXT NOT NULL REFERENCES app_store_accounts(app_account_token),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(environment, original_transaction_id)
);
CREATE TABLE app_store_transactions_v2 (
  environment TEXT NOT NULL CHECK(environment IN ('Sandbox','Production')),
  transaction_id TEXT NOT NULL,
  original_transaction_id TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(id),
  app_account_token TEXT NOT NULL,
  product_id TEXT NOT NULL,
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
  PRIMARY KEY(environment, transaction_id),
  FOREIGN KEY(environment, original_transaction_id) REFERENCES app_store_owners_v2(environment, original_transaction_id)
);
INSERT INTO app_store_owners_v2
SELECT DISTINCT t.environment, o.original_transaction_id, o.user_id, o.app_account_token, o.created_at, o.updated_at
FROM app_store_subscription_owners o JOIN app_store_transactions t USING(original_transaction_id)
WHERE t.environment IN ('Sandbox','Production');
INSERT INTO app_store_transactions_v2
SELECT environment,transaction_id,original_transaction_id,user_id,app_account_token,product_id,
purchase_at,original_purchase_at,expires_at,revocation_at,revocation_reason,ownership_type,transaction_reason,
signed_transaction_digest,verification_source,verified_at,created_at,updated_at FROM app_store_transactions
WHERE environment IN ('Sandbox','Production');
CREATE INDEX idx_store_v2_subscription ON app_store_transactions_v2(environment, original_transaction_id, user_id, expires_at);
CREATE TABLE app_store_verification_audit (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  environment TEXT NOT NULL CHECK(environment IN ('Sandbox','Production')),
  transaction_id TEXT NOT NULL,
  original_transaction_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  signed_transaction_digest TEXT NOT NULL,
  verified_at TEXT NOT NULL,
  FOREIGN KEY(environment, transaction_id) REFERENCES app_store_transactions_v2(environment, transaction_id)
);
CREATE INDEX idx_store_verification_subscription ON app_store_verification_audit(environment,original_transaction_id,id);
CREATE TRIGGER store_verification_audit_no_update BEFORE UPDATE ON app_store_verification_audit BEGIN SELECT RAISE(ABORT,'immutable verification audit'); END;
CREATE TRIGGER store_verification_audit_no_delete BEFORE DELETE ON app_store_verification_audit BEGIN SELECT RAISE(ABORT,'immutable verification audit'); END;

CREATE TABLE app_store_notification_events_v2 (
  environment TEXT NOT NULL CHECK(environment IN ('Sandbox','Production')),
  notification_uuid TEXT NOT NULL,
  notification_type TEXT NOT NULL,
  subtype TEXT,
  transaction_id TEXT,
  signed_payload_digest TEXT NOT NULL,
  disposition TEXT NOT NULL CHECK(disposition IN ('test','ignored','unlinked','reconciled')),
  processed_at TEXT NOT NULL,
  PRIMARY KEY(environment, notification_uuid)
);
CREATE TABLE sandbox_membership_entitlements (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  source TEXT NOT NULL CHECK(source IN ('app_store_monthly','app_store_annual')),
  starts_at TEXT NOT NULL,
  expires_at TEXT,
  is_lifetime INTEGER NOT NULL DEFAULT 0 CHECK(is_lifetime=0),
  status TEXT NOT NULL CHECK(status IN ('active','revoked')),
  note TEXT NOT NULL DEFAULT '',
  metadata_json TEXT NOT NULL,
  created_by_user_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revoked_at TEXT,
  revoked_by_user_id TEXT
);
-- Move only positively identified historical Sandbox subscription projections;
-- gifts/trials/referrals and every Production transaction remain untouched.
INSERT INTO sandbox_membership_entitlements
SELECT e.id,e.user_id,e.source,e.starts_at,e.expires_at,e.is_lifetime,e.status,e.note,e.metadata_json,
e.created_by_user_id,e.created_at,e.updated_at,e.revoked_at,e.revoked_by_user_id
FROM membership_entitlements e
WHERE e.source IN ('app_store_monthly','app_store_annual') AND e.is_lifetime=0
AND EXISTS(SELECT 1 FROM app_store_transactions t WHERE t.environment='Sandbox'
 AND e.id='app-store:'||t.original_transaction_id AND e.user_id=t.user_id)
AND NOT EXISTS(SELECT 1 FROM app_store_transactions t WHERE t.environment='Production'
 AND e.id='app-store:'||t.original_transaction_id AND e.user_id=t.user_id);
DELETE FROM membership_entitlements WHERE id IN (SELECT id FROM sandbox_membership_entitlements);
UPDATE users SET membership_tier=CASE WHEN EXISTS(
  SELECT 1 FROM membership_entitlements e WHERE e.user_id=users.id AND e.status='active'
  AND e.revoked_at IS NULL AND julianday(e.starts_at)<=julianday('now')
  AND (e.is_lifetime=1 OR julianday(e.expires_at)>julianday('now'))
) THEN 'member' ELSE 'free' END
WHERE id IN (SELECT user_id FROM sandbox_membership_entitlements);
ALTER TABLE auth_sessions ADD COLUMN store_environment TEXT NOT NULL DEFAULT 'Production'
 CHECK(store_environment IN ('Sandbox','Production'));
