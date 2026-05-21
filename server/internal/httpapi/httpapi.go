// Package httpapi exposes the Gin REST surface: guest sessions, room
// management, match history, health, and the WebSocket upgrade route.
package httpapi

import (
	"net/http"
	"strings"

	"github.com/andaseacode/paidummy-server/internal/session"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// WSHandler is the WebSocket upgrade handler, injected by main once the room
// hub exists (kept as an interface seam so httpapi doesn't import ws/room).
type WSHandler interface {
	Upgrade(c *gin.Context)
}

// RoomAPI is the subset of room-management behaviour the REST layer needs.
type RoomAPI interface {
	ListOpen(c *gin.Context)
	Create(c *gin.Context)
	Join(c *gin.Context)
	AddBot(c *gin.Context)
	QuickPlay(c *gin.Context)
	Practice(c *gin.Context)
	RoomInfo(c *gin.Context)
	AdminRooms(c *gin.Context)
	AdminDashboard(c *gin.Context)
}

// Server bundles handler dependencies.
type Server struct {
	Sessions *session.Manager
	WS       WSHandler
	Rooms    RoomAPI
	History  gin.HandlerFunc
	Me       gin.HandlerFunc // wallet refresh: GET /api/v1/me
	Tiers    gin.HandlerFunc // bet-tier menu: GET /api/v1/tiers
	Packages gin.HandlerFunc // coin shop menu: GET /api/v1/shop/packages
	Purchase gin.HandlerFunc // mock purchase: POST /api/v1/shop/purchase
	Tournaments gin.HandlerFunc // GET /api/v1/tournaments

	MyHistory   gin.HandlerFunc // GET /api/v1/me/history — coin timeline
	RoomHistory gin.HandlerFunc // GET /api/v1/rooms/:id/history — table log
	Replay      gin.HandlerFunc // GET /api/v1/matches/:id/replay — score log

	DailyStatus gin.HandlerFunc // GET  /api/v1/me/daily        — claim eligibility
	DailyClaim  gin.HandlerFunc // POST /api/v1/me/daily/claim — credit bonus

	Leaderboard gin.HandlerFunc // GET /api/v1/leaderboard?period=...
	Avatar      gin.HandlerFunc // PATCH /api/v1/me/avatar
	Theme       gin.HandlerFunc // PATCH /api/v1/me/theme

	Missions     gin.HandlerFunc // GET  /api/v1/me/missions
	MissionClaim gin.HandlerFunc // POST /api/v1/me/missions/:id/claim

	Friends        gin.HandlerFunc // GET  /api/v1/me/friends
	FriendRequests gin.HandlerFunc // GET  /api/v1/me/friends/requests
	FriendRequest  gin.HandlerFunc // POST /api/v1/me/friends/request
	FriendAccept   gin.HandlerFunc // POST /api/v1/me/friends/accept

	AdStatus      gin.HandlerFunc // GET  /api/v1/me/ad
	AdClaim       gin.HandlerFunc // POST /api/v1/me/ad/claim
	DeviceToken   gin.HandlerFunc // POST /api/v1/me/device-token
	Report        gin.HandlerFunc // POST /api/v1/reports
	AdminBan      gin.HandlerFunc // POST /api/v1/admin/ban
	AdminReports  gin.HandlerFunc // GET  /api/v1/admin/reports
	AdminToken    string          // shared secret for /admin* routes
	IsBanned      func(string) bool // optional ban gate for authed players
}

const ctxGuestKey = "guest"

// Router builds the Gin engine with middleware and routes.
func (s *Server) Router() *gin.Engine {
	r := gin.New()
	r.Use(gin.Recovery(), requestID(), cors())

	r.GET("/healthz", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"ok": true}) })

	v1 := r.Group("/api/v1")
	v1.POST("/guest", s.createGuest)

	auth := v1.Group("")
	auth.Use(s.authMiddleware())
	{
		if s.Rooms != nil {
			auth.GET("/rooms", s.Rooms.ListOpen)
			auth.POST("/rooms", s.Rooms.Create)
			auth.GET("/rooms/:id", s.Rooms.RoomInfo)
			auth.POST("/rooms/:id/join", s.Rooms.Join)
			auth.POST("/rooms/:id/bots", s.Rooms.AddBot)
			auth.POST("/quickplay", s.Rooms.QuickPlay)
			auth.POST("/practice", s.Rooms.Practice)
		}
		if s.History != nil {
			auth.GET("/matches/history", s.History)
		}
		if s.Me != nil {
			auth.GET("/me", s.Me)
		}
		if s.Tiers != nil {
			auth.GET("/tiers", s.Tiers)
		}
		if s.Packages != nil {
			auth.GET("/shop/packages", s.Packages)
		}
		if s.Purchase != nil {
			auth.POST("/shop/purchase", s.Purchase)
		}
		if s.MyHistory != nil {
			auth.GET("/me/history", s.MyHistory)
		}
		if s.RoomHistory != nil {
			auth.GET("/rooms/:id/history", s.RoomHistory)
		}
		if s.Replay != nil {
			auth.GET("/matches/:id/replay", s.Replay)
		}
		if s.Tournaments != nil {
			auth.GET("/tournaments", s.Tournaments)
		}
		if s.DailyStatus != nil {
			auth.GET("/me/daily", s.DailyStatus)
		}
		if s.DailyClaim != nil {
			auth.POST("/me/daily/claim", s.DailyClaim)
		}
		if s.Leaderboard != nil {
			auth.GET("/leaderboard", s.Leaderboard)
		}
		if s.Avatar != nil {
			auth.PATCH("/me/avatar", s.Avatar)
		}
		if s.Theme != nil {
			auth.PATCH("/me/theme", s.Theme)
		}
		if s.Missions != nil {
			auth.GET("/me/missions", s.Missions)
		}
		if s.MissionClaim != nil {
			auth.POST("/me/missions/:id/claim", s.MissionClaim)
		}
		if s.Friends != nil {
			auth.GET("/me/friends", s.Friends)
		}
		if s.FriendRequests != nil {
			auth.GET("/me/friends/requests", s.FriendRequests)
		}
		if s.FriendRequest != nil {
			auth.POST("/me/friends/request", s.FriendRequest)
		}
		if s.FriendAccept != nil {
			auth.POST("/me/friends/accept", s.FriendAccept)
		}
		if s.Report != nil {
			auth.POST("/reports", s.Report)
		}
		if s.AdStatus != nil {
			auth.GET("/me/ad", s.AdStatus)
		}
		if s.AdClaim != nil {
			auth.POST("/me/ad/claim", s.AdClaim)
		}
		if s.DeviceToken != nil {
			auth.POST("/me/device-token", s.DeviceToken)
		}
	}

	// Admin routes — gated by a shared token (X-Admin-Token header or
	// ?token= query), separate from the player session.
	admin := v1.Group("/admin")
	admin.Use(s.adminMiddleware())
	{
		if s.Rooms != nil {
			admin.GET("/rooms", s.Rooms.AdminRooms)
		}
		if s.AdminReports != nil {
			admin.GET("/reports", s.AdminReports)
		}
		if s.AdminBan != nil {
			admin.POST("/ban", s.AdminBan)
		}
	}
	if s.Rooms != nil {
		// Read-only HTML dashboard, same token gate.
		r.GET("/admin", s.adminGate(), s.Rooms.AdminDashboard)
	}

	if s.WS != nil {
		r.GET("/ws", s.WS.Upgrade) // auth via ?token= in the handshake
	}
	return r
}

type createGuestReq struct {
	DisplayName string `json:"display_name"`
	Ref         string `json:"ref"`
}

func (s *Server) createGuest(c *gin.Context) {
	var req createGuestReq
	_ = c.ShouldBindJSON(&req)
	g, err := s.Sessions.CreateGuest(
		c.Request.Context(),
		strings.TrimSpace(req.DisplayName),
		strings.TrimSpace(req.Ref),
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not create guest"})
		return
	}
	c.JSON(http.StatusOK, g)
}

// authMiddleware resolves a Bearer token to a guest and stores it in context.
// Banned guests are rejected with 403.
func (s *Server) authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		h := c.GetHeader("Authorization")
		token := strings.TrimPrefix(h, "Bearer ")
		g, ok := s.Sessions.Resolve(c.Request.Context(), strings.TrimSpace(token))
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid session"})
			return
		}
		if s.IsBanned != nil && s.IsBanned(g.ID.String()) {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "account suspended"})
			return
		}
		c.Set(ctxGuestKey, g)
		c.Next()
	}
}

// adminMiddleware gates JSON admin endpoints by the shared admin token.
func (s *Server) adminMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		if !s.adminTokenOK(c) {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "admin token required"})
			return
		}
		c.Next()
	}
}

// adminGate is the same check for the HTML dashboard (sends plain text on
// failure so a browser shows something sensible).
func (s *Server) adminGate() gin.HandlerFunc {
	return func(c *gin.Context) {
		if !s.adminTokenOK(c) {
			c.String(http.StatusUnauthorized, "admin token required (?token=...)")
			c.Abort()
			return
		}
		c.Next()
	}
}

func (s *Server) adminTokenOK(c *gin.Context) bool {
	if s.AdminToken == "" {
		return false
	}
	tok := c.GetHeader("X-Admin-Token")
	if tok == "" {
		tok = c.Query("token")
	}
	return tok == s.AdminToken
}

// GuestFromCtx extracts the authenticated guest set by authMiddleware.
func GuestFromCtx(c *gin.Context) (session.Guest, bool) {
	v, ok := c.Get(ctxGuestKey)
	if !ok {
		return session.Guest{}, false
	}
	g, ok := v.(session.Guest)
	return g, ok
}

func requestID() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("X-Request-ID", uuid.NewString())
		c.Next()
	}
}

func cors() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Headers", "Authorization, Content-Type")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PATCH, OPTIONS")
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}
