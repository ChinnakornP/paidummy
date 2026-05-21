-- Friend graph. friend_requests holds pending one-directional invites;
-- friendships holds accepted edges stored in BOTH directions so a lookup
-- by either side is a single indexed scan.
CREATE TABLE IF NOT EXISTS friend_requests (
    from_id    UUID NOT NULL REFERENCES guest_users (id) ON DELETE CASCADE,
    to_id      UUID NOT NULL REFERENCES guest_users (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (from_id, to_id)
);
CREATE INDEX IF NOT EXISTS idx_friend_requests_to ON friend_requests (to_id);

CREATE TABLE IF NOT EXISTS friendships (
    guest_id   UUID NOT NULL REFERENCES guest_users (id) ON DELETE CASCADE,
    friend_id  UUID NOT NULL REFERENCES guest_users (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (guest_id, friend_id)
);
