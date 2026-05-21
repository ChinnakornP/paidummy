-- Rewarded-ad cooldown. last_ad_at is the wall-clock time of the last
-- claimed (mock) ad reward; the handler enforces a fixed cooldown between
-- claims.
ALTER TABLE guest_users
    ADD COLUMN IF NOT EXISTS last_ad_at TIMESTAMPTZ;
