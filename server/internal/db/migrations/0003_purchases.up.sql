-- Audit trail for coin purchases. The current build "mock-succeeds" all
-- payments; real payment integration will add provider id / receipt later.
CREATE TABLE IF NOT EXISTS purchases (
    id         UUID PRIMARY KEY,
    guest_id   UUID NOT NULL REFERENCES guest_users (id),
    package_id TEXT NOT NULL,
    coins      INT  NOT NULL,
    price_thb  INT  NOT NULL,
    status     TEXT NOT NULL,           -- mock_success | failed | refunded
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_purchases_guest ON purchases (guest_id);
