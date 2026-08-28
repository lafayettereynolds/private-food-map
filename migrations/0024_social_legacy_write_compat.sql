PRAGMA foreign_keys = ON;

-- The existing Web client still writes the legacy Friendship shape. Keep those
-- writes compatible while the versioned native Social API owns the state machine.
CREATE TRIGGER IF NOT EXISTS friendships_fill_canonical_pair_insert
AFTER INSERT ON friendships
WHEN NEW.pair_user_a IS NULL OR NEW.pair_user_b IS NULL
BEGIN
  UPDATE friendships SET
    pair_user_a = CASE WHEN NEW.requester_id < NEW.addressee_id THEN NEW.requester_id ELSE NEW.addressee_id END,
    pair_user_b = CASE WHEN NEW.requester_id < NEW.addressee_id THEN NEW.addressee_id ELSE NEW.requester_id END
  WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS friendships_fill_canonical_pair_update
AFTER UPDATE OF requester_id, addressee_id ON friendships
BEGIN
  UPDATE friendships SET
    pair_user_a = CASE WHEN NEW.requester_id < NEW.addressee_id THEN NEW.requester_id ELSE NEW.addressee_id END,
    pair_user_b = CASE WHEN NEW.requester_id < NEW.addressee_id THEN NEW.addressee_id ELSE NEW.requester_id END
  WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS follows_fill_updated_at_insert
AFTER INSERT ON follows WHEN NEW.updated_at IS NULL
BEGIN UPDATE follows SET updated_at = NEW.created_at WHERE id = NEW.id; END;
