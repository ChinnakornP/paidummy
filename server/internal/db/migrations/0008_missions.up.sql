-- Daily mission progress, one row per (guest, mission, Asia/Bangkok day).
-- Missions themselves are defined in code (db.MissionDefs); this table only
-- tracks per-day counters + whether the reward was claimed.
CREATE TABLE IF NOT EXISTS mission_progress (
    guest_id   UUID NOT NULL REFERENCES guest_users (id) ON DELETE CASCADE,
    mission_id TEXT NOT NULL,
    day        DATE NOT NULL,
    progress   INT  NOT NULL DEFAULT 0,
    claimed    BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (guest_id, mission_id, day)
);
CREATE INDEX IF NOT EXISTS idx_mission_progress_guest_day
    ON mission_progress (guest_id, day);
