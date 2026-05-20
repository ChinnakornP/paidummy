-- Wallet: every guest starts with a coin balance; matches settle coins
-- between winner and losers based on the room's bet.
ALTER TABLE guest_users
    ADD COLUMN IF NOT EXISTS coins BIGINT NOT NULL DEFAULT 1000;

ALTER TABLE matches
    ADD COLUMN IF NOT EXISTS bet INT NOT NULL DEFAULT 0;
