DROP INDEX IF EXISTS idx_guest_users_ref_code;
ALTER TABLE guest_users
    DROP COLUMN IF EXISTS referral_rewarded,
    DROP COLUMN IF EXISTS referrer_id,
    DROP COLUMN IF EXISTS ref_code;
