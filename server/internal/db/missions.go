package db

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
)

// Mission claim error sentinels.
var (
	ErrUnknownMission    = errors.New("unknown mission")
	ErrMissionIncomplete = errors.New("mission not complete")
	ErrMissionClaimed    = errors.New("mission already claimed")
)

// MissionKind is the event a mission counts. IncrementMissions maps a match
// outcome to one or more of these.
type MissionKind string

const (
	MissionPlay  MissionKind = "play"  // any finished match
	MissionWin   MissionKind = "win"   // match won
	MissionKnock MissionKind = "knock" // round ended by this player's knock
)

// MissionDef is a server-defined daily mission. Goal is the target count;
// Reward is the coin payout on claim.
type MissionDef struct {
	ID     string      `json:"id"`
	Title  string      `json:"title"`
	Kind   MissionKind `json:"kind"`
	Goal   int         `json:"goal"`
	Reward int64       `json:"reward"`
}

// MissionDefs is the canonical daily mission set. Order is preserved in the
// client list.
var MissionDefs = []MissionDef{
	{ID: "play3", Title: "เล่น 3 ตา", Kind: MissionPlay, Goal: 3, Reward: 150},
	{ID: "win1", Title: "ชนะ 1 ตา", Kind: MissionWin, Goal: 1, Reward: 250},
	{ID: "knock1", Title: "น็อค 1 ครั้ง", Kind: MissionKnock, Goal: 1, Reward: 300},
}

// MissionStatus is a mission definition joined with the caller's progress
// for the current Asia/Bangkok day.
type MissionStatus struct {
	MissionDef
	Progress int  `json:"progress"`
	Claimed  bool `json:"claimed"`
	Complete bool `json:"complete"`
}

func today() time.Time {
	return calendarDay(time.Now())
}

// MissionsFor returns every mission with the guest's progress today.
func (d *DB) MissionsFor(ctx context.Context, guestID uuid.UUID) ([]MissionStatus, error) {
	day := today()
	rows, err := d.Pool.Query(ctx,
		`SELECT mission_id, progress, claimed
		   FROM mission_progress
		  WHERE guest_id = $1 AND day = $2`, guestID, day)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	type prog struct {
		progress int
		claimed  bool
	}
	byID := map[string]prog{}
	for rows.Next() {
		var id string
		var p prog
		if err := rows.Scan(&id, &p.progress, &p.claimed); err != nil {
			return nil, err
		}
		byID[id] = p
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	out := make([]MissionStatus, 0, len(MissionDefs))
	for _, def := range MissionDefs {
		p := byID[def.ID]
		out = append(out, MissionStatus{
			MissionDef: def,
			Progress:   p.progress,
			Claimed:    p.claimed,
			Complete:   p.progress >= def.Goal,
		})
	}
	return out, nil
}

// IncrementMissions bumps every mission of the given kind for the guest by
// [n] for today. Best-effort: callers ignore the error since missions are
// non-critical to match flow.
func (d *DB) IncrementMissions(ctx context.Context, guestID uuid.UUID, kind MissionKind, n int) error {
	if n <= 0 {
		return nil
	}
	day := today()
	for _, def := range MissionDefs {
		if def.Kind != kind {
			continue
		}
		if _, err := d.Pool.Exec(ctx, `
			INSERT INTO mission_progress (guest_id, mission_id, day, progress)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (guest_id, mission_id, day)
			DO UPDATE SET progress = mission_progress.progress + $4`,
			guestID, def.ID, day, n); err != nil {
			return err
		}
	}
	return nil
}

// ClaimMission credits the reward for a completed, unclaimed mission. Returns
// the reward and new balance. Atomic; double-claims are rejected.
func (d *DB) ClaimMission(ctx context.Context, guestID uuid.UUID, missionID string) (reward int64, newBalance int64, err error) {
	var def *MissionDef
	for i := range MissionDefs {
		if MissionDefs[i].ID == missionID {
			def = &MissionDefs[i]
			break
		}
	}
	if def == nil {
		return 0, 0, ErrUnknownMission
	}
	day := today()
	tx, err := d.Pool.Begin(ctx)
	if err != nil {
		return 0, 0, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	var progress int
	var claimed bool
	err = tx.QueryRow(ctx,
		`SELECT progress, claimed FROM mission_progress
		  WHERE guest_id = $1 AND mission_id = $2 AND day = $3 FOR UPDATE`,
		guestID, missionID, day,
	).Scan(&progress, &claimed)
	if err != nil {
		// no row → no progress yet, can't claim
		return 0, 0, ErrMissionIncomplete
	}
	if claimed {
		return 0, 0, ErrMissionClaimed
	}
	if progress < def.Goal {
		return 0, 0, ErrMissionIncomplete
	}
	if _, err = tx.Exec(ctx,
		`UPDATE mission_progress SET claimed = TRUE
		  WHERE guest_id = $1 AND mission_id = $2 AND day = $3`,
		guestID, missionID, day); err != nil {
		return 0, 0, err
	}
	if err = tx.QueryRow(ctx,
		`UPDATE guest_users SET coins = coins + $2 WHERE id = $1 RETURNING coins`,
		guestID, def.Reward).Scan(&newBalance); err != nil {
		return 0, 0, err
	}
	if err = tx.Commit(ctx); err != nil {
		return 0, 0, err
	}
	return def.Reward, newBalance, nil
}
