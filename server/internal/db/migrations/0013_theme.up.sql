-- Cosmetic felt/card theme selected by the player. Validated against
-- db.AllowedThemes server-side. 'classic' matches the original green felt.
ALTER TABLE guest_users
    ADD COLUMN IF NOT EXISTS theme TEXT NOT NULL DEFAULT 'classic';
