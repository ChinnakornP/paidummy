ALTER TABLE guest_users
    DROP COLUMN IF EXISTS last_claim_at,
    DROP COLUMN IF EXISTS streak_days;
