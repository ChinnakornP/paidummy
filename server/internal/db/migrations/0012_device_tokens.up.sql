-- Push notification device tokens (FCM/APNs). One row per (guest, token);
-- platform is 'android' | 'ios' | 'web'. updated_at lets a cleanup job age
-- out stale tokens later.
CREATE TABLE IF NOT EXISTS device_tokens (
    guest_id   UUID NOT NULL REFERENCES guest_users (id) ON DELETE CASCADE,
    token      TEXT NOT NULL,
    platform   TEXT NOT NULL DEFAULT 'unknown',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (guest_id, token)
);
CREATE INDEX IF NOT EXISTS idx_device_tokens_guest ON device_tokens (guest_id);
