-- Fair scheduling: a retained financial dependency must not starve other accounts.
CREATE TABLE privacy_retention_attempts (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  attempted_at TEXT NOT NULL
);

ALTER TABLE account_deletion_jobs ADD COLUMN cleanup_lease TEXT;
ALTER TABLE account_deletion_jobs ADD COLUMN cleanup_lease_until TEXT;

-- Only an atomic retention batch may authorize deleting expired immutable facts.
-- The row is created and removed in the same D1 batch; normal API writes never
-- open this gate. Existing UPDATE immutability triggers remain unchanged.
CREATE TABLE privacy_purge_authorization (id INTEGER PRIMARY KEY CHECK(id=1), cutoff TEXT NOT NULL);
DROP TRIGGER referral_audit_no_delete;
CREATE TRIGGER referral_audit_no_delete BEFORE DELETE ON referral_audit_log
WHEN NOT EXISTS(SELECT 1 FROM privacy_purge_authorization p JOIN users u ON u.id=OLD.user_id
  WHERE p.id=1 AND OLD.created_at<=p.cutoff AND u.deleted_at<=p.cutoff)
BEGIN SELECT RAISE(ABORT,'append-only referral audit'); END;
DROP TRIGGER store_verification_audit_no_delete;
CREATE TRIGGER store_verification_audit_no_delete BEFORE DELETE ON app_store_verification_audit
WHEN NOT EXISTS(SELECT 1 FROM privacy_purge_authorization p JOIN users u ON u.id=OLD.user_id
  WHERE p.id=1 AND OLD.verified_at<=p.cutoff AND u.deleted_at<=p.cutoff)
BEGIN SELECT RAISE(ABORT,'immutable verification audit'); END;
DROP TRIGGER membership_signup_trial_retain_history;
CREATE TRIGGER membership_signup_trial_retain_history BEFORE DELETE ON membership_entitlements
WHEN OLD.source='signup_trial' AND NOT EXISTS(SELECT 1 FROM privacy_purge_authorization p JOIN users u ON u.id=OLD.user_id
  WHERE p.id=1 AND OLD.created_at<=p.cutoff AND u.deleted_at<=p.cutoff)
BEGIN SELECT RAISE(ABORT,'Signup trial history must be retained'); END;
