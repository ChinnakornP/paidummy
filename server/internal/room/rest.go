package room

import (
	"errors"
	"html"
	"net/http"
	"strconv"
	"strings"

	"github.com/andaseacode/paidummy-server/internal/db"
	"github.com/andaseacode/paidummy-server/internal/session"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
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

// ReportHandler POST /api/v1/reports {"target_id","reason"} — one player
// reports another. Append-only; moderation happens out of band.
func ReportHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		g, ok := guestFromCtx(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
			return
		}
		var req struct {
			TargetID string `json:"target_id"`
			Reason   string `json:"reason"`
		}
		_ = c.ShouldBindJSON(&req)
		target, perr := uuid.Parse(req.TargetID)
		if perr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "bad target_id"})
			return
		}
		if target == g.ID {
			c.JSON(http.StatusConflict, gin.H{"error": "cannot report yourself"})
			return
		}
		if err := database.CreateReport(c.Request.Context(), g.ID, target, req.Reason); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "report failed"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"ok": true})
	}
}

// AdminBanHandler POST /api/v1/admin/ban {"guest_id","banned"} — admin-gated.
func AdminBanHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req struct {
			GuestID string `json:"guest_id"`
			Banned  bool   `json:"banned"`
		}
		_ = c.ShouldBindJSON(&req)
		id, perr := uuid.Parse(req.GuestID)
		if perr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "bad guest_id"})
			return
		}
		if err := database.SetBanned(c.Request.Context(), id, req.Banned); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "ban failed"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"guest_id": id, "banned": req.Banned})
	}
}

// AdminReportsHandler GET /api/v1/admin/reports — recent reports.
func AdminReportsHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		rows, err := database.RecentReports(c.Request.Context(), 100)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "reports failed"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"reports": rows})
	}
}

// AdminRooms GET /api/v1/admin/rooms — live room snapshot for the dashboard.
func (a *RESTAdapter) AdminRooms(c *gin.Context) {
	rooms := a.hub.OpenRooms()
	out := make([]gin.H, 0, len(rooms))
	players := 0
	for _, r := range rooms {
		r.mu.Lock()
		seats := len(r.seats)
		out = append(out, gin.H{
			"id": r.ID, "name": r.Name, "players": seats,
			"max": r.MaxPlayers, "bet": r.Bet, "started": r.state != nil,
			"practice": r.Practice, "locked": r.Password != "",
		})
		players += seats
		r.mu.Unlock()
	}
	c.JSON(http.StatusOK, gin.H{
		"rooms": out, "room_count": len(out), "player_count": players,
	})
}

// AdminDashboard GET /admin?token=... — a minimal read-only HTML view of
// live rooms + recent reports. Token-gated (query or X-Admin-Token header,
// checked by the caller's middleware). Intentionally dependency-free HTML.
func (a *RESTAdapter) AdminDashboard(c *gin.Context) {
	rooms := a.hub.OpenRooms()
	players := 0
	var rb strings.Builder
	for _, r := range rooms {
		r.mu.Lock()
		seats := len(r.seats)
		players += seats
		started := "lobby"
		if r.state != nil {
			started = "playing"
		}
		rb.WriteString("<tr><td>" + htmlEscape(r.Name) + "</td><td>" +
			itoa(seats) + "/" + itoa(r.MaxPlayers) + "</td><td>" +
			itoa(r.Bet) + "</td><td>" + started + "</td></tr>")
		r.mu.Unlock()
	}
	reports, _ := a.db.RecentReports(c.Request.Context(), 50)
	var pb strings.Builder
	for _, rep := range reports {
		pb.WriteString("<tr><td>" + rep.CreatedAt.Format("01-02 15:04") +
			"</td><td>" + htmlEscape(rep.Reporter) + "</td><td>" +
			htmlEscape(rep.Target) + "</td><td>" + htmlEscape(rep.Reason) +
			"</td></tr>")
	}
	html := "<!doctype html><meta charset=utf-8><title>Pai Dummy admin</title>" +
		"<style>body{font-family:system-ui;margin:24px;background:#0d1b2a;color:#eee}" +
		"table{border-collapse:collapse;margin:12px 0;width:100%}" +
		"th,td{border:1px solid #345;padding:6px 10px;text-align:left}" +
		"th{background:#1b2a3a}h1{color:#ffd24a}h2{margin-top:28px}</style>" +
		"<h1>Pai Dummy — admin</h1>" +
		"<p>Open rooms: <b>" + itoa(len(rooms)) + "</b> · seated players: <b>" +
		itoa(players) + "</b></p>" +
		"<h2>Rooms</h2><table><tr><th>Name</th><th>Players</th><th>Bet</th><th>State</th></tr>" +
		rb.String() + "</table>" +
		"<h2>Recent reports</h2><table><tr><th>When</th><th>By</th><th>Target</th><th>Reason</th></tr>" +
		pb.String() + "</table>"
	c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(html))
}

func itoa(n int) string {
	return strconv.Itoa(n)
}

func htmlEscape(s string) string {
	return html.EscapeString(s)
}

// FriendsHandler GET /api/v1/me/friends — accepted friends.
func FriendsHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		g, ok := guestFromCtx(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
			return
		}
		fs, err := database.Friends(c.Request.Context(), g.ID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "friends failed"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"friends": fs})
	}
}

// FriendRequestsHandler GET /api/v1/me/friends/requests — incoming pending.
func FriendRequestsHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		g, ok := guestFromCtx(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
			return
		}
		rs, err := database.IncomingRequests(c.Request.Context(), g.ID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "requests failed"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"requests": rs})
	}
}

// FriendRequestHandler POST /api/v1/me/friends/request {"ref_code": "..."}
func FriendRequestHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		g, ok := guestFromCtx(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
			return
		}
		var req struct {
			RefCode string `json:"ref_code"`
		}
		_ = c.ShouldBindJSON(&req)
		auto, err := database.SendFriendRequest(c.Request.Context(), g.ID, req.RefCode)
		if err != nil {
			switch {
			case errors.Is(err, db.ErrFriendNotFound):
				c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			case errors.Is(err, db.ErrFriendSelf), errors.Is(err, db.ErrAlreadyFriends):
				c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
			default:
				c.JSON(http.StatusInternalServerError, gin.H{"error": "request failed"})
			}
			return
		}
		c.JSON(http.StatusOK, gin.H{"auto_accepted": auto})
	}
}

// FriendAcceptHandler POST /api/v1/me/friends/accept {"from_id": "..."}
func FriendAcceptHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		g, ok := guestFromCtx(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
			return
		}
		var req struct {
			FromID string `json:"from_id"`
		}
		_ = c.ShouldBindJSON(&req)
		from, perr := uuid.Parse(req.FromID)
		if perr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "bad from_id"})
			return
		}
		if err := database.AcceptFriendRequest(c.Request.Context(), g.ID, from); err != nil {
			if errors.Is(err, db.ErrFriendNotFound) {
				c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
				return
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": "accept failed"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"ok": true})
	}
}

// MissionsHandler GET /api/v1/me/missions — today's daily missions with
// the caller's progress + claim state.
func MissionsHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		g, ok := guestFromCtx(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
			return
		}
		ms, err := database.MissionsFor(c.Request.Context(), g.ID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "missions failed"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"missions": ms})
	}
}

// ClaimMissionHandler POST /api/v1/me/missions/:id/claim — credits the
// reward for a completed mission. 409 if incomplete or already claimed.
func ClaimMissionHandler(database *db.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		g, ok := guestFromCtx(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
			return
		}
		reward, bal, err := database.ClaimMission(c.Request.Context(), g.ID, c.Param("id"))
		if err != nil {
			switch {
			case errors.Is(err, db.ErrUnknownMission):
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			case errors.Is(err, db.ErrMissionIncomplete), errors.Is(err, db.ErrMissionClaimed):
				c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
			default:
				c.JSON(http.StatusInternalServerError, gin.H{"error": "claim failed"})
			}
			return
		}
		c.JSON(http.StatusOK, gin.H{"reward": reward, "new_balance": bal})
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
