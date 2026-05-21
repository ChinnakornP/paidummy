package room

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// Tournaments are scheduled high-stakes events. v1 is a computed daily
// schedule (no persistence): fixed Asia/Bangkok times, each a stake tier.
// "Live" means within the join window around start; the client then enters
// via the normal quickplay flow at that stake.

var tourLoc = func() *time.Location {
	if l, err := time.LoadLocation("Asia/Bangkok"); err == nil {
		return l
	}
	return time.UTC
}()

// tourSlots are the daily event templates (hour in Asia/Bangkok → name+bet).
var tourSlots = []struct {
	Hour int
	Name string
	Bet  int
}{
	{12, "ศึกเที่ยงวัน", 500},
	{20, "ห้อง VIP ค่ำคืน", 1000},
}

// tourJoinWindow is how long after a start time the event stays joinable.
const tourJoinWindow = 30 * time.Minute

type tournamentView struct {
	Name     string `json:"name"`
	Bet      int    `json:"bet"`
	StartsAt string `json:"starts_at"`
	StartMs  int64  `json:"start_ms"`
	Live     bool   `json:"live"`
}

// upcomingTournaments returns today's + tomorrow's events from now, soonest
// first, marking any currently within the join window as live.
func upcomingTournaments(now time.Time) []tournamentView {
	nowL := now.In(tourLoc)
	out := make([]tournamentView, 0, len(tourSlots)*2)
	for dayOffset := 0; dayOffset <= 1; dayOffset++ {
		day := nowL.AddDate(0, 0, dayOffset)
		for _, s := range tourSlots {
			start := time.Date(day.Year(), day.Month(), day.Day(), s.Hour, 0, 0, 0, tourLoc)
			// Skip events whose join window already closed.
			if now.After(start.Add(tourJoinWindow)) {
				continue
			}
			live := !now.Before(start) && now.Before(start.Add(tourJoinWindow))
			out = append(out, tournamentView{
				Name:     s.Name,
				Bet:      s.Bet,
				StartsAt: start.Format(time.RFC3339),
				StartMs:  start.UnixMilli(),
				Live:     live,
			})
		}
	}
	// Soonest first (insertion sort — list is tiny).
	for i := 1; i < len(out); i++ {
		for j := i; j > 0 && out[j].StartMs < out[j-1].StartMs; j-- {
			out[j], out[j-1] = out[j-1], out[j]
		}
	}
	return out
}

// TournamentsHandler GET /api/v1/tournaments — upcoming scheduled events.
func TournamentsHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		if _, ok := guestFromCtx(c); !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"tournaments": upcomingTournaments(time.Now())})
	}
}
