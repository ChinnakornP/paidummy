package room

import (
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

// RESTAdapter implements httpapi.RoomAPI over a Hub.
type RESTAdapter struct{ hub *Hub }

func NewRESTAdapter(h *Hub) *RESTAdapter { return &RESTAdapter{hub: h} }

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

// Create POST /api/v1/rooms
func (a *RESTAdapter) Create(c *gin.Context) {
	g, ok := guestFromCtx(c)
	if !ok {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no session"})
		return
	}
	var req struct {
		Name        string `json:"name"`
		MaxPlayers  int    `json:"max_players"`
		TargetScore int    `json:"target_score"`
		Bet         int    `json:"bet"`
	}
	_ = c.ShouldBindJSON(&req)
	if req.Name == "" {
		req.Name = g.Name + "'s room"
	}
	r := a.hub.CreateRoom(c.Request.Context(), g.ID.String(), g.Name, req.Name, req.MaxPlayers, req.TargetScore, req.Bet)
	_ = r.Join(g.ID.String(), g.Name)
	c.JSON(http.StatusOK, gin.H{"id": r.ID, "name": r.Name})
}

// Join POST /api/v1/rooms/:id/join
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
	if err := r.Join(g.ID.String(), g.Name); err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"id": r.ID})
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
