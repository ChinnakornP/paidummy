-- Daily-login bonus state. last_claim_at is the wall-clock moment the
-- player last claimed; streak_days is how many consecutive Asia/Bangkok
-- calendar days they've claimed in a row (resets to 1 if they skip a day).
ALTER TABLE guest_users
    ADD COLUMN IF NOT EXISTS last_claim_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS streak_days   INT NOT NULL DEFAULT 0;
