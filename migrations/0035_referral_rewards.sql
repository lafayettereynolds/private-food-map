-- Attribution is written only in the verified new-account registration transaction.
CREATE TABLE referral_codes (
  user_id TEXT PRIMARY KEY REFERENCES users(id),
  code TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL
);
CREATE TABLE referrals (
  invitee_id TEXT PRIMARY KEY REFERENCES users(id),
  referrer_id TEXT NOT NULL REFERENCES users(id),
  code TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','qualified','capped','revoked')),
  bound_at TEXT NOT NULL,
  qualified_at TEXT,
  qualifying_visit_id TEXT,
  slot INTEGER CHECK(slot BETWEEN 1 AND 5),
  revoked_at TEXT,
  actor TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  CHECK(invitee_id <> referrer_id),
  UNIQUE(referrer_id, slot)
);
CREATE INDEX referrals_referrer ON referrals(referrer_id, bound_at);
CREATE TABLE premium_rewards (
  id TEXT PRIMARY KEY,
  invitee_id TEXT NOT NULL REFERENCES referrals(invitee_id),
  user_id TEXT NOT NULL REFERENCES users(id),
  role TEXT NOT NULL CHECK(role IN ('referrer','invitee')),
  days INTEGER NOT NULL CHECK((role='referrer' AND days=30) OR (role='invitee' AND days=14)),
  state TEXT NOT NULL CHECK(state IN ('pending','active','lifetime','revoked')),
  granted_at TEXT NOT NULL,
  changed_at TEXT,
  starts_at TEXT,
  expires_at TEXT,
  revoked_at TEXT,
  actor TEXT NOT NULL DEFAULT 'system:referral',
  note TEXT NOT NULL DEFAULT '',
  UNIQUE(invitee_id, role)
);
CREATE INDEX premium_rewards_owner ON premium_rewards(user_id, state);
CREATE TABLE referral_audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  invitee_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  reward_id TEXT,
  action TEXT NOT NULL,
  actor TEXT NOT NULL,
  before_json TEXT,
  after_json TEXT NOT NULL,
  note TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TRIGGER referral_immutable BEFORE UPDATE ON referrals BEGIN
  SELECT CASE WHEN NEW.invitee_id<>OLD.invitee_id OR NEW.referrer_id<>OLD.referrer_id
    OR NEW.code<>OLD.code OR NEW.bound_at<>OLD.bound_at
    OR (OLD.slot IS NOT NULL AND NEW.slot IS NOT OLD.slot)
    OR (OLD.status<>'pending' AND NEW.status NOT IN (OLD.status,'revoked'))
    OR (NEW.status='qualified' AND (NEW.slot IS NULL OR NEW.qualified_at IS NULL OR NEW.qualifying_visit_id IS NULL))
    THEN RAISE(ABORT,'invalid referral transition') END;
END;
CREATE TRIGGER referral_bound AFTER INSERT ON referrals BEGIN
  INSERT INTO referral_audit_log(invitee_id,user_id,action,actor,after_json,note,created_at)
    VALUES(NEW.invitee_id,NEW.referrer_id,'bound',NEW.actor,
      json_object('status',NEW.status,'code',NEW.code,'boundAt',NEW.bound_at),NEW.note,NEW.bound_at);
END;
CREATE TRIGGER referral_transition AFTER UPDATE ON referrals WHEN NEW.status<>OLD.status BEGIN
  INSERT INTO referral_audit_log(invitee_id,user_id,action,actor,before_json,after_json,note,created_at)
    VALUES(NEW.invitee_id,NEW.referrer_id,NEW.status,NEW.actor,json_object('status',OLD.status),
      json_object('status',NEW.status,'slot',NEW.slot,'visitID',NEW.qualifying_visit_id),NEW.note,COALESCE(NEW.revoked_at,NEW.qualified_at,NEW.bound_at));
  INSERT INTO premium_rewards(id,invitee_id,user_id,role,days,state,granted_at)
    SELECT 'referral:'||NEW.invitee_id||':referrer',NEW.invitee_id,NEW.referrer_id,'referrer',30,'pending',NEW.qualified_at
    WHERE NEW.status='qualified' AND OLD.status='pending';
  INSERT INTO premium_rewards(id,invitee_id,user_id,role,days,state,granted_at)
    SELECT 'referral:'||NEW.invitee_id||':invitee',NEW.invitee_id,NEW.invitee_id,'invitee',14,'pending',NEW.qualified_at
    WHERE NEW.status='qualified' AND OLD.status='pending';
  UPDATE premium_rewards SET state='revoked',revoked_at=NEW.revoked_at,actor=NEW.actor,note=NEW.note
    WHERE invitee_id=NEW.invitee_id AND state<>'revoked' AND NEW.status='revoked';
END;
CREATE TRIGGER reward_granted AFTER INSERT ON premium_rewards BEGIN
  INSERT INTO referral_audit_log(invitee_id,user_id,reward_id,action,actor,after_json,note,created_at)
    VALUES(NEW.invitee_id,NEW.user_id,NEW.id,'reward_granted',NEW.actor,
      json_object('days',NEW.days,'state',NEW.state,'grantedAt',NEW.granted_at),NEW.note,NEW.granted_at);
END;
CREATE TRIGGER reward_immutable BEFORE UPDATE ON premium_rewards BEGIN
  SELECT CASE WHEN NEW.id<>OLD.id OR NEW.user_id<>OLD.user_id OR NEW.invitee_id<>OLD.invitee_id
    OR NEW.days<>OLD.days OR NEW.role<>OLD.role OR NEW.granted_at<>OLD.granted_at
    OR (OLD.state<>'pending' AND NEW.state NOT IN (OLD.state,'revoked'))
    OR (NEW.state='active' AND (NEW.starts_at IS NULL OR NEW.expires_at IS NULL OR NEW.expires_at<=NEW.starts_at))
    THEN RAISE(ABORT,'invalid reward transition') END;
END;
CREATE TRIGGER reward_transition AFTER UPDATE ON premium_rewards WHEN NEW.state<>OLD.state BEGIN
  INSERT INTO referral_audit_log(invitee_id,user_id,reward_id,action,actor,before_json,after_json,note,created_at)
    VALUES(NEW.invitee_id,NEW.user_id,NEW.id,CASE WHEN NEW.state=OLD.state THEN 'reward_rescheduled' ELSE 'reward_'||NEW.state END,NEW.actor,
      json_object('state',OLD.state,'startsAt',OLD.starts_at,'expiresAt',OLD.expires_at),
      json_object('state',NEW.state,'days',NEW.days,'startsAt',NEW.starts_at,'expiresAt',NEW.expires_at,'revokedAt',NEW.revoked_at),
      NEW.note,COALESCE(NEW.revoked_at,NEW.changed_at,NEW.granted_at));
  INSERT INTO membership_entitlements(id,user_id,source,starts_at,expires_at,status,created_at,updated_at,created_by_user_id)
    SELECT NEW.id,NEW.user_id,'referral_reward',NEW.starts_at,NEW.expires_at,'active',NEW.granted_at,NEW.granted_at,'system:referral'
    WHERE NEW.state='active'
    ON CONFLICT(id) DO UPDATE SET starts_at=excluded.starts_at,expires_at=excluded.expires_at,updated_at=COALESCE(NEW.changed_at,NEW.granted_at);
  UPDATE membership_entitlements SET status='revoked',revoked_at=NEW.revoked_at,revoked_by_user_id=NEW.actor,updated_at=NEW.revoked_at
    WHERE id=NEW.id AND NEW.state='revoked';
  -- Remove only the unconsumed revoked interval; compact later rewards to avoid a gap.
  UPDATE premium_rewards SET
    starts_at=strftime('%Y-%m-%dT%H:%M:%fZ',julianday(starts_at)-max(0,julianday(OLD.expires_at)-max(julianday(OLD.starts_at),julianday(NEW.revoked_at)))),
    expires_at=strftime('%Y-%m-%dT%H:%M:%fZ',julianday(expires_at)-max(0,julianday(OLD.expires_at)-max(julianday(OLD.starts_at),julianday(NEW.revoked_at)))),
    changed_at=NEW.revoked_at,actor=NEW.actor,note='Compacted after referral reward revocation'
    WHERE NEW.state='revoked' AND OLD.state='active' AND state='active' AND user_id=NEW.user_id
      AND starts_at>=OLD.expires_at AND id<>NEW.id AND OLD.expires_at>NEW.revoked_at;
END;
CREATE TRIGGER reward_reschedule AFTER UPDATE ON premium_rewards
WHEN NEW.state='active' AND OLD.state='active' AND (NEW.starts_at IS NOT OLD.starts_at OR NEW.expires_at IS NOT OLD.expires_at) BEGIN
  UPDATE membership_entitlements SET starts_at=NEW.starts_at,expires_at=NEW.expires_at,updated_at=NEW.changed_at WHERE id=NEW.id;
  INSERT INTO referral_audit_log(invitee_id,user_id,reward_id,action,actor,before_json,after_json,note,created_at)
    VALUES(NEW.invitee_id,NEW.user_id,NEW.id,'reward_rescheduled',NEW.actor,
      json_object('startsAt',OLD.starts_at,'expiresAt',OLD.expires_at),
      json_object('startsAt',NEW.starts_at,'expiresAt',NEW.expires_at),NEW.note,NEW.changed_at);
END;
CREATE TRIGGER referral_audit_no_update BEFORE UPDATE ON referral_audit_log BEGIN SELECT RAISE(ABORT,'append-only referral audit'); END;
CREATE TRIGGER referral_audit_no_delete BEFORE DELETE ON referral_audit_log BEGIN SELECT RAISE(ABORT,'append-only referral audit'); END;
