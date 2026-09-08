-- Products and StoreKit transaction IDs are unchanged. This is an entitlement alias.
UPDATE membership_entitlements SET source = 'app_store_annual' WHERE source = 'app_store_yearly';
ALTER TABLE membership_entitlements ADD COLUMN updated_by_user_id TEXT;

-- Audit and entitlement mutation are one SQLite transaction, including direct internal writes.
CREATE TRIGGER gift_entitlement_validate_insert BEFORE INSERT ON membership_entitlements
WHEN NEW.source IN ('gift_annual', 'gift_lifetime')
BEGIN
  SELECT (CASE WHEN NEW.created_by_user_id IS NULL OR NEW.starts_at IS NULL
    OR (NEW.source = 'gift_lifetime' AND (NEW.expires_at IS NOT NULL OR NEW.is_lifetime <> 1))
    OR (NEW.source = 'gift_annual' AND (NEW.expires_at IS NULL OR NEW.expires_at <= NEW.starts_at OR NEW.is_lifetime <> 0))
    THEN RAISE(ABORT, 'invalid gift entitlement') END);
END;

CREATE TRIGGER gift_entitlement_validate_update BEFORE UPDATE ON membership_entitlements
WHEN OLD.source IN ('gift_annual', 'gift_lifetime')
BEGIN
  SELECT (CASE WHEN NEW.source <> OLD.source OR NEW.user_id <> OLD.user_id
    OR NEW.starts_at <> OLD.starts_at OR NEW.created_at <> OLD.created_at
    OR NEW.created_by_user_id IS NOT OLD.created_by_user_id OR NEW.updated_by_user_id IS NULL
    OR (OLD.status = 'revoked' AND NEW.status <> 'revoked')
    OR (NEW.status = 'revoked' AND (NEW.revoked_at IS NULL OR NEW.revoked_by_user_id IS NULL))
    OR (NEW.source = 'gift_lifetime' AND (NEW.expires_at IS NOT NULL OR NEW.is_lifetime <> 1))
    OR (NEW.source = 'gift_annual' AND (NEW.expires_at IS NULL OR NEW.expires_at < OLD.expires_at OR NEW.is_lifetime <> 0))
    THEN RAISE(ABORT, 'invalid gift mutation') END);
END;

CREATE TRIGGER gift_entitlement_audit_insert AFTER INSERT ON membership_entitlements
WHEN NEW.source IN ('gift_annual', 'gift_lifetime')
BEGIN
  INSERT INTO membership_audit_log (id, actor_user_id, target_user_id, action, entitlement_id, before_json, after_json, reason, created_at)
  VALUES ('gift-audit:' || lower(hex(randomblob(16))), NEW.created_by_user_id, NEW.user_id, 'grant', NEW.id, NULL,
    json_object('userID', NEW.user_id, 'source', NEW.source, 'startedAt', NEW.starts_at,
      'grantedAt', NEW.created_at, 'expiresAt', NEW.expires_at, 'grantedBy', NEW.created_by_user_id,
      'note', NEW.note, 'revokedAt', NEW.revoked_at), NEW.note, NEW.created_at);
END;

CREATE TRIGGER gift_entitlement_audit_update AFTER UPDATE ON membership_entitlements
WHEN OLD.source IN ('gift_annual', 'gift_lifetime')
BEGIN
  INSERT INTO membership_audit_log (id, actor_user_id, target_user_id, action, entitlement_id, before_json, after_json, reason, created_at)
  VALUES ('gift-audit:' || lower(hex(randomblob(16))), NEW.updated_by_user_id, NEW.user_id,
    CASE WHEN NEW.status <> OLD.status THEN 'revoke' WHEN NEW.expires_at IS NOT OLD.expires_at THEN 'extend' ELSE 'note' END,
    NEW.id,
    json_object('userID', OLD.user_id, 'source', OLD.source, 'startedAt', OLD.starts_at,
      'grantedAt', OLD.created_at, 'expiresAt', OLD.expires_at, 'grantedBy', OLD.created_by_user_id,
      'note', OLD.note, 'revokedAt', OLD.revoked_at),
    json_object('userID', NEW.user_id, 'source', NEW.source, 'startedAt', NEW.starts_at,
      'grantedAt', NEW.created_at, 'expiresAt', NEW.expires_at, 'grantedBy', NEW.created_by_user_id,
      'note', NEW.note, 'revokedAt', NEW.revoked_at), NEW.note, NEW.updated_at);
END;
