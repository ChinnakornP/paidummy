CREATE TABLE IF NOT EXISTS guest_users (
    id           UUID PRIMARY KEY,
    display_name TEXT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sessions (
    token      TEXT PRIMARY KEY,
    guest_id   UUID NOT NULL REFERENCES guest_users (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_guest ON sessions (guest_id);

CREATE TABLE IF NOT EXISTS matches (
    id              UUID PRIMARY KEY,
    room_id         TEXT NOT NULL,
    status          TEXT NOT NULL,            -- pending | active | finished
    target_score    INT  NOT NULL,
    ruleset         JSONB NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at     TIMESTAMPTZ,
    winner_guest_id UUID REFERENCES guest_users (id)
);
CREATE INDEX IF NOT EXISTS idx_matches_room ON matches (room_id);

CREATE TABLE IF NOT EXISTS match_players (
    match_id UUID NOT NULL REFERENCES matches (id) ON DELETE CASCADE,
    guest_id UUID NOT NULL REFERENCES guest_users (id),
    seat     INT  NOT NULL,
    PRIMARY KEY (match_id, guest_id)
);
CREATE INDEX IF NOT EXISTS idx_match_players_guest ON match_players (guest_id);

CREATE TABLE IF NOT EXISTS rounds (
    id               UUID PRIMARY KEY,
    match_id         UUID NOT NULL REFERENCES matches (id) ON DELETE CASCADE,
    round_no         INT  NOT NULL,
    seed             BIGINT NOT NULL,
    ended_reason     TEXT NOT NULL,           -- knock | deck_exhaust
    knocker_guest_id UUID REFERENCES guest_users (id),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_rounds_match ON rounds (match_id);

CREATE TABLE IF NOT EXISTS round_scores (
    round_id  UUID NOT NULL REFERENCES rounds (id) ON DELETE CASCADE,
    guest_id  UUID NOT NULL REFERENCES guest_users (id),
    score     INT  NOT NULL,
    breakdown JSONB NOT NULL,
    PRIMARY KEY (round_id, guest_id)
);
