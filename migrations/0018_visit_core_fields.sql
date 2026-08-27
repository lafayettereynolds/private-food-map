PRAGMA foreign_keys = ON;

-- The legacy Web schema requires party_size and historically normalizes it to
-- at least 1. Native P1-C needs to distinguish "not recorded" from 1 person.
-- Keep the legacy column intact and add a nullable canonical value so existing
-- Web data and deployments remain compatible without rebuilding visits.
ALTER TABLE visits ADD COLUMN party_size_optional INTEGER
  CHECK (party_size_optional IS NULL OR party_size_optional >= 1);

UPDATE visits
SET party_size_optional = CASE WHEN party_size >= 1 THEN party_size ELSE NULL END;

-- During a rolling deployment, an older Worker may still write only the legacy
-- party_size column. Preserve those positive values in the nullable column.
CREATE TRIGGER visits_party_size_optional_after_insert
AFTER INSERT ON visits
WHEN NEW.party_size_optional IS NULL AND NEW.party_size >= 1
BEGIN
  UPDATE visits SET party_size_optional = NEW.party_size WHERE id = NEW.id;
END;

CREATE TRIGGER visits_party_size_optional_after_legacy_update
AFTER UPDATE OF party_size ON visits
WHEN NEW.party_size >= 1
  AND NEW.party_size != OLD.party_size
  AND NEW.party_size_optional IS OLD.party_size_optional
BEGIN
  UPDATE visits SET party_size_optional = NEW.party_size WHERE id = NEW.id;
END;
