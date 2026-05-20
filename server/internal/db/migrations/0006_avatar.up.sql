-- Avatar is one of a small preset of emoji glyphs picked by the player in
-- the in-game profile dialog. Stored as a short UTF-8 string (up to 8
-- bytes covers any single emoji + combining marks we'd ever ship).
ALTER TABLE guest_users
    ADD COLUMN IF NOT EXISTS avatar VARCHAR(8) NOT NULL DEFAULT '🙂';
