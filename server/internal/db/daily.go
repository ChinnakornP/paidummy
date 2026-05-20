package db

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
)

// DailyRewardLadder is the per-streak coin reward. Day 7+ caps at the
// final entry so the reward never grows unboundedly.
var DailyRewardLadder = []int64{
	100, // day 1
	150, // day 2
	200, // day 3
	300, // day 4
	400, // day 5
	500, // day 6
	700, // day 7+
}

// DailyBonus is the wire shape returned by status + claim handlers.
type DailyBonus struct {
	Claimable   bool       `json:"claimable"`
	Streak      int        `json:"streak"`
	NextReward  int64      `json:"next_reward"`
	LastClaimAt *time.Time `json:"last_claim_at,omitempty"`
	NextClaimAt *time.Time `json:"next_claim_at,omitempty"`
}

// dailyLoc is the calendar reference for "today" boundaries. Pai Dummy is a
// Thai-first product so we anchor to Asia/Bangkok; falls back to UTC if the
// runtime's tzdata is missing.
var dailyLoc = func() *time.Location {
	if l, err := time.LoadLocation("Asia/Bangkok"); err == nil {
		return l
	}
	return time.UTC
}()

func calendarDay(t time.Time) time.Time {
	t = t.In(dailyLoc)
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, dailyLoc)
}

// rewardFor returns the coin reward for the given streak (1-based). Streaks
// past the ladder length cap at the final entry.
func rewardFor(streak int) int64 {
	if streak <= 0 {
		return DailyRewardLadder[0]
	}
	if streak > len(DailyRewardLadder) {
		streak = len(DailyRewardLadder)
	}
	return DailyRewardLadder[streak-1]
}

// DailyStatus returns whether the guest can claim their daily bonus right
// now, plus the streak they would earn it under.
func (d *DB) DailyStatus(ctx context.Context, id uuid.UUID) (DailyBonus, error) {
	var last *time.Time
	var streak int
	if err := d.Pool.QueryRow(ctx,
		`SELECT last_claim_at, streak_days FROM guest_users WHERE id = $1`, id,
	).Scan(&last, &streak); err != nil {
		return DailyBonus{}, err
	}
	now := time.Now()
	today := calendarDay(now)
	out := DailyBonus{LastClaimAt: last}

	if last == nil {
		out.Claimable = true
		out.Streak = 1
		out.NextReward = rewardFor(1)
		return out, nil
	}
	lastDay := calendarDay(*last)
	days := int(today.Sub(lastDay).Hours() / 24)
	switch {
	case days <= 0:
		// Already claimed today — next claim opens at next midnight.
		nextOpen := today.AddDate(0, 0, 1)
		out.Claimable = false
		out.Streak = streak
		out.NextReward = rewardFor(streak + 1)
		out.NextClaimAt = &nextOpen
	case days == 1:
		// Consecutive day — streak continues.
		out.Claimable = true
		out.Streak = streak + 1
		out.NextReward = rewardFor(out.Streak)
	default:
		// Missed at least a full day — streak resets to 1.
		out.Claimable = true
		out.Streak = 1
		out.NextReward = rewardFor(1)
	}
	return out, nil
}

// ErrDailyAlreadyClaimed is returned by ClaimDaily when the guest has
// already claimed within the current Asia/Bangkok calendar day.
var ErrDailyAlreadyClaimed = errors.New("daily bonus already claimed today")

// ClaimDaily credits the daily-bonus coins atomically. Returns the awarded
// streak, coin delta, and the new balance. If the guest has already claimed
// today the call is a no-op and returns ErrDailyAlreadyClaimed.
func (d *DB) ClaimDaily(ctx context.Context, id uuid.UUID) (streak int, coinsAdded int64, newBalance int64, err error) {
	tx, err := d.Pool.Begin(ctx)
	if err != nil {
		return 0, 0, 0, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	var last *time.Time
	var prevStreak int
	if err = tx.QueryRow(ctx,
		`SELECT last_claim_at, streak_days FROM guest_users WHERE id = $1 FOR UPDATE`, id,
	).Scan(&last, &prevStreak); err != nil {
		return 0, 0, 0, err
	}
	now := time.Now()
	today := calendarDay(now)
	switch {
	case last == nil:
		streak = 1
	default:
		lastDay := calendarDay(*last)
		days := int(today.Sub(lastDay).Hours() / 24)
		if days <= 0 {
			return 0, 0, 0, ErrDailyAlreadyClaimed
		}
		if days == 1 {
			streak = prevStreak + 1
		} else {
			streak = 1
		}
	}
	coinsAdded = rewardFor(streak)
	if err = tx.QueryRow(ctx,
		`UPDATE guest_users
		   SET coins = coins + $2,
		       last_claim_at = $3,
		       streak_days = $4
		 WHERE id = $1
		 RETURNING coins`,
		id, coinsAdded, now, streak,
	).Scan(&newBalance); err != nil {
		return 0, 0, 0, err
	}
	if err = tx.Commit(ctx); err != nil {
		return 0, 0, 0, err
	}
	return streak, coinsAdded, newBalance, nil
}
