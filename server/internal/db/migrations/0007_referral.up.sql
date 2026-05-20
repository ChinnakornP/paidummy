-- Referral tracking. ref_code is a short user-shareable handle (first 8
-- hex chars of the guest's UUID), referrer_id points to whoever's code
-- the player typed at sign-up, referral_rewarded latches once the +500
-- coin bonus has fired (one-shot, on their first finished match).
ALTER TABLE guest_users
    ADD COLUMN IF NOT EXISTS ref_code           TEXT,
    ADD COLUMN IF NOT EXISTS referrer_id        UUID REFERENCES guest_users(id),
    ADD COLUMN IF NOT EXISTS referral_rewarded  BOOLEAN NOT NULL DEFAULT FALSE;

-- Backfill missing ref_codes from the first 8 chars of the existing id.
UPDATE guest_users
   SET ref_code = SUBSTRING(REPLACE(id::text, '-', ''), 1, 8)
 WHERE ref_code IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_guest_users_ref_code
    ON guest_users (ref_code);
