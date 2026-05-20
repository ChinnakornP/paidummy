package room

import (
	"errors"
	"net/http"

	"github.com/andaseacode/paidummy-server/internal/db"
	"github.com/andaseacode/paidummy-server/internal/session"
	"github.com/gin-gonic/gin"
)

// guestFromCtx reads the guest the httpapi auth middleware stored under "guest".
func guestFromCtx(c *gin.Context) (session.Guest, bool) {
	v, ok := c.Get("guest")
	if !ok {
		return session.Guest{}, false
	}
	g, ok := v.(session.Guest)
	return g, ok
}

// RESTAdapter implements httpapi.RoomAPI over a Hub. It keeps a db handle
// so coin-aware endpoints (QuickPlay) can validate without main passing it.
type RESTAdapter struct {
	hub *Hub
	db  *db.DB
}

func NewRESTAdapter(h *Hub, d *db.DB) *RESTAdapter { return &RESTAdapter{hub: h, db: d} }

// ListOpen GET /api/v1/rooms
func (a *RESTAdapter) ListOpen(c *gin.Context) {
	rooms := a.hub.OpenRooms()
	out := make([]gin.H, 0, len(rooms))
	for _, r := range rooms {
		r.mu.Lock()
		out = append(out, gin.H{
			"id": r.ID, "name": r.Name, "players": len(r.seats),
			"max": r.MaxPlayers, "target": r.TargetScore, "bet": r.Bet,
		})
		r.mu.Unlock()
	}
	c.JSON(http.StatusOK, gin.H{"rooms": out})
}

// Create POST /api/v1/rooms — full custom-room creation with optional
// password and turn-timer override. Host is auto-seated.
func (a *RESTAdapter) Create(c *gin.Context) {
	g, ok := guestFromCtx(c)
	if !ok {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
		return
	}
	var req struct {
		Name         string `json:"name"`
		Password     string `json:"password"`
		MaxPlayers   int    `json:"max_players"`
		TargetScore  int    `json:"target_score"`
		Bet          int    `json:"bet"`
		TurnTimerSec int    `json:"turn_timer_sec"`
	}
	_ = c.ShouldBindJSON(&req)
	if req.Name == "" {
		req.Name = g.Name + "'s room"
	}
	// Coin guard for staked rooms mirrors quickplay — never allow creation
	// at a tier the wallet can't cover the first match.
	if req.Bet > 0 {
		coins, err := a.db.Coins(c.Request.Context(), g.ID)
		if err == nil && coins < int64(req.Bet) {
			c.JSON(http.StatusForbidden, gin.H{
				"error": "insufficient coins for this stake",
				"coins": coins,
				"need":  req.Bet,
			})
			return
		}
	}
	r := a.hub.CreateRoomFull(c.Request.Context(), g.ID.String(), g.Name, CreateOpts{
		Name: req.Name, Password: req.Password,
		MaxPlayers: req.MaxPlayers, TargetScore: req.TargetScore,
		Bet: req.Bet, TurnTimerSec: req.TurnTimerSec,
	})
	_ = r.JoinWith(g.ID.String(), g.Name, req.Password)
	c.JSON(http.StatusOK, gin.H{
		"id":   r.ID,
		"name": r.Name,
		// Echo password back so the host UI can show a shareable chip.
		"password": req.Password,
	})
}

// Join POST /api/v1/rooms/:id/join  body {"password": "..."}
// Password is optional for public rooms. 403 on bad password.
func (a *RESTAdapter) Join(c *gin.Context) {
	g, ok := guestFromCtx(c)
	if !ok {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
		return
	}
	r, ok := a.hub.Get(c.Param("id"))
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "room not found"})
		return
	}
	var req struct {
		Password string `json:"password"`
	}
	_ = c.ShouldBindJSON(&req)
	if err := r.JoinWith(g.ID.String(), g.Name, req.Password); err != nil {
		if errors.Is(err, ErrBadPassword) {
			c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"id": r.ID})
}

// RoomInfo GET /api/v1/rooms/:id — peek a room's metadata before joining.
// Used by the "เข้าด้วยรหัส" flow so the client can show name + locked state
// + seat count without exposing the password.
func (a *RESTAdapter) RoomInfo(c *gin.Context) {
	if _, ok := guestFromCtx(c); !ok {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
		return
	}
	r, ok := a.hub.Get(c.Param("id"))
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "room not found"})
		return
	}
	r.mu.Lock()
	out := gin.H{
		"id": r.ID, "name": r.Name,
		"players": len(r.seats), "max": r.MaxPlayers,
		"target": r.TargetScore, "bet": r.Bet,
		"locked":   r.Password != "",
		"started":  r.state != nil,
		"practice": r.Practice,
	}
	r.mu.Unlock()
	c.JSON(http.StatusOK, out)
}

// AllowedBets is the public tier ladder shown in the client lobby. Kept
// server-side so the server is the source of truth for available stakes.
var AllowedBets = []int{50, 100, 500, 1000, 5000}

func isAllowedBet(b int) bool {
	for _, v := range AllowedBets {
		if v == b {
			return true
		}
	}
	return false
}

// QuickPlay POST /api/v1/quickplay  body {"bet": n}
// Finds the nearest open room at that bet tier, or creates one. Validates
// the player has enough coins to cover the stake.
func (a *RESTAdapter) QuickPlay(c *gin.Context) {
	g, ok := guestFromCtx(c)
	if !ok {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
		return
	}
	var req struct {
		Bet int `json:"bet"`
	}
	_ = c.ShouldBindJSON(&req)
	if !isAllowedBet(req.Bet) {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid bet tier",
			"allowed": AllowedBets,
		})
		return
	}
	coins, err := a.db.Coins(c.Request.Context(), g.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "wallet lookup failed"})
		return
	}
	if coins < int64(req.Bet) {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "insufficient coins for this tier",
			"coins": coins,
			"need":  req.Bet,
		})
		return
	}
	r, err := a.hub.QuickJoin(c.Request.Context(), g.ID.String(), g.Name, req.Bet)
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"room_id": r.ID, "bet": r.Bet})
}

// TiersHandler GET /api/v1/tiers — the bet-tier menu the lobby renders.
// Returns each allowed stake plus a live snapshot of how many players are
// currently seated in open rooms at that stake. Client uses the count to
// surface "ผู้เล่น N คน" on each tier card.
func TiersHandler(h *Hub) gin.HandlerFunc {
	return func(c *gin.Context) {
		counts := tierOccupancy(h)
		out := make([]gin.H, 0, len(AllowedBets))
		for _, bet := range AllowedBets {
			s := counts[bet]
			out = append(out, gin.H{
				"bet":     bet,
				"players": s.players,
				"rooms":   s.rooms,
			})
		}
		c.JSON(http.StatusOK, gin.H{"tiers": out})
	}
}

type tierStat struct{ players, rooms int }

// tierOccupancy walks every open room once and tallies seats by stake.
// Includes rooms still in the pre-start lobby — that's exactly where new
// players land via QuickPlay.
func tierOccupancy(h *Hub) map[int]tierStat {
	out := map[int]tierStat{}
	if h == nil {
		return out
	}
	for _, r := range h.OpenRooms() {
		r.mu.Lock()
		seats := len(r.seats)
		bet := r.Bet
		r.mu.Unlock()
		s := out[bet]
		s.players += seats
		s.rooms++
		out[bet] = s
	}
	return out
}

// PackagesHandler GET /api/v1/shop/packages — the coin-package menu.
// Server is the source of truth for prices, coin amounts, and ids.
func PackagesHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"packages": db.CoinPackages})
	}
}

// PurchaseHandler POST /api/v1/shop/purchase {"package_id": ...} — mock
// payment that always succeeds, credits the wallet atomically, returns the
// new balance and the coins added. Real payment will wrap this with a
// provider capture step before db.PurchasePackage.
func PurchaseHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		g, ok := guestFromCtx(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
			return
		}
		var req struct {
			PackageID string `json:"package_id"`
		}
		_ = c.ShouldBindJSON(&req)
		pkg, ok := db.FindPackage(req.PackageID)
		if !ok {
			c.JSON(http.StatusBadRequest, gin.H{"error": "unknown package_id"})
			return
		}
		bal, err := database.PurchasePackage(c.Request.Context(), g.ID, pkg)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "purchase failed"})
			return
		}
		c.JSON(http.StatusOK, gin.H{
			"status":      "mock_success",
			"package_id":  pkg.ID,
			"coins_added": pkg.Coins,
			"new_balance": bal,
		})
	}
}

// MeHandler GET /api/v1/me — wallet refresh + lifetime stats + rank, so the
// client can render the rank pill in one round trip.
func MeHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		g, ok := guestFromCtx(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
			return
		}
		ctx := c.Request.Context()
		coins, err := database.Coins(ctx, g.ID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "wallet lookup failed"})
			return
		}
		stats, _ := database.LoadStats(ctx, g.ID) // best-effort
		avatar, _ := database.Avatar(ctx, g.ID)
		if avatar == "" {
			avatar = db.DefaultAvatar
		}
		refCode, _ := database.RefCode(ctx, g.ID)
		c.JSON(http.StatusOK, gin.H{
			"id":       g.ID,
			"name":     g.Name,
			"coins":    coins,
			"stats":    stats,
			"rank":     db.ComputeRank(stats.MatchesWon),
			"avatar":   avatar,
			"avatars":  db.AllowedAvatars,
			"ref_code": refCode,
		})
	}
}

// AvatarHandler PATCH /api/v1/me/avatar — sets the guest's avatar to one
// of the preset palette emojis. 400 on unknown glyph.
func AvatarHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		g, ok := guestFromCtx(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
			return
		}
		var req struct {
			Avatar string `json:"avatar"`
		}
		_ = c.ShouldBindJSON(&req)
		if err := database.SetAvatar(c.Request.Context(), g.ID, req.Avatar); err != nil {
			if errors.Is(err, db.ErrInvalidAvatar) {
				c.JSON(http.StatusBadRequest, gin.H{
					"error":   err.Error(),
					"allowed": db.AllowedAvatars,
				})
				return
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": "set avatar failed"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"avatar": req.Avatar})
	}
}

// CoinHistoryHandler GET /api/v1/me/history — recent match results for the
// authenticated guest with coin_delta and balance_after.
func CoinHistoryHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		g, ok := guestFromCtx(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
			return
		}
		rows, err := database.CoinHistory(c.Request.Context(), g.ID, 50)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "history failed"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"history": rows})
	}
}

// RoomHistoryHandler GET /api/v1/rooms/:id/history — recent finished matches
// played in that room with each player's coin outcome.
func RoomHistoryHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		if _, ok := guestFromCtx(c); !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
			return
		}
		matches, err := database.RoomHistory(c.Request.Context(), c.Param("id"), 20)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "history failed"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"matches": matches})
	}
}

// Practice POST /api/v1/practice — spin up a solo training room (host +
// 3 bots, no coin settlement). Returns the room id; client navigates to
// the game screen.
func (a *RESTAdapter) Practice(c *gin.Context) {
	g, ok := guestFromCtx(c)
	if !ok {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
		return
	}
	r, err := a.hub.CreatePractice(c.Request.Context(), g.ID.String(), g.Name)
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"room_id": r.ID})
}

// AddBot POST /api/v1/rooms/:id/bots  body {"count": n}
func (a *RESTAdapter) AddBot(c *gin.Context) {
	if _, ok := guestFromCtx(c); !ok {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
		return
	}
	r, ok := a.hub.Get(c.Param("id"))
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "room not found"})
		return
	}
	var req struct {
		Count int `json:"count"`
	}
	_ = c.ShouldBindJSON(&req)
	if req.Count < 1 {
		req.Count = 1
	}
	added := 0
	for i := 0; i < req.Count; i++ {
		if err := r.AddBot(c.Request.Context()); err != nil {
			break
		}
		added++
	}
	if added == 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "could not add bot (room full or started)"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"added": added})
}

// DailyStatusHandler GET /api/v1/me/daily — returns whether the guest can
// claim today's bonus + the streak/reward they would earn.
func DailyStatusHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		g, ok := guestFromCtx(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
			return
		}
		st, err := database.DailyStatus(c.Request.Context(), g.ID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "daily status failed"})
			return
		}
		c.JSON(http.StatusOK, st)
	}
}

// DailyClaimHandler POST /api/v1/me/daily/claim — credits the daily bonus
// atomically (no body). Returns the new streak, coins added, and balance.
// 409 if the guest has already claimed within the current Asia/Bangkok day.
func DailyClaimHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		g, ok := guestFromCtx(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
			return
		}
		streak, added, bal, err := database.ClaimDaily(c.Request.Context(), g.ID)
		if err != nil {
			if errors.Is(err, db.ErrDailyAlreadyClaimed) {
				c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
				return
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": "claim failed"})
			return
		}
		c.JSON(http.StatusOK, gin.H{
			"streak":      streak,
			"coins_added": added,
			"new_balance": bal,
		})
	}
}

// LeaderboardHandler GET /api/v1/leaderboard?period=alltime|weekly|daily
// — read-only top-N ranking by coin profit. Defaults to alltime, limit 20.
func LeaderboardHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		if _, ok := guestFromCtx(c); !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
			return
		}
		period := db.LeaderboardPeriod(c.DefaultQuery("period", string(db.LeaderboardAllTime)))
		switch period {
		case db.LeaderboardAllTime, db.LeaderboardWeekly, db.LeaderboardDaily:
		default:
			period = db.LeaderboardAllTime
		}
		rows, err := database.Leaderboard(c.Request.Context(), period, 20)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "leaderboard failed"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"period": period, "rows": rows})
	}
}

// HistoryHandler GET /api/v1/matches/history
func HistoryHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		g, ok := guestFromCtx(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
			return
		}
		rows, err := database.MatchHistory(c.Request.Context(), g.ID, 50)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "history failed"})
			return
		}
		out := make([]gin.H, 0, len(rows))
		for _, r := range rows {
			out = append(out, gin.H{
				"match_id": r.MatchID, "room_id": r.RoomID, "status": r.Status,
				"created_at": r.CreatedAt, "total_score": r.TotalScore,
			})
		}
		c.JSON(http.StatusOK, gin.H{"matches": out})
	}
}
