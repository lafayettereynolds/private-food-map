-- The historical entitlement is the permanent per-account claim record.
CREATE UNIQUE INDEX membership_signup_trial_once
ON membership_entitlements(user_id) WHERE source = 'signup_trial';

CREATE TRIGGER membership_signup_trial_immutable
BEFORE UPDATE ON membership_entitlements
WHEN OLD.source = 'signup_trial' OR NEW.source = 'signup_trial'
BEGIN
  SELECT (CASE WHEN NEW.id IS NOT OLD.id OR NEW.user_id IS NOT OLD.user_id
    OR NEW.source IS NOT OLD.source OR NEW.starts_at IS NOT OLD.starts_at
    OR NEW.expires_at IS NOT OLD.expires_at OR NEW.is_lifetime IS NOT OLD.is_lifetime
    OR NEW.created_at IS NOT OLD.created_at
    OR (OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS NOT OLD.revoked_at)
    OR (OLD.status = 'revoked' AND NEW.status != 'revoked')
  THEN RAISE(ABORT, 'Signup trial claim facts are immutable') END);
END;

CREATE TRIGGER membership_signup_trial_retain_history
BEFORE DELETE ON membership_entitlements WHEN OLD.source = 'signup_trial'
BEGIN SELECT RAISE(ABORT, 'Signup trial history must be retained'); END;
