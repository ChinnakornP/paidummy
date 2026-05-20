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
}

// Server bundles handler dependencies.
type Server struct {
	Sessions *session.Manager
	WS       WSHandler
	Rooms    RoomAPI
	History  gin.HandlerFunc
	Me       gin.HandlerFunc // wallet refresh: GET /api/v1/me
	Tiers    gin.HandlerFunc // bet-tier menu: GET /api/v1/tiers
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
			auth.POST("/rooms/:id/join", s.Rooms.Join)
			auth.POST("/rooms/:id/bots", s.Rooms.AddBot)
			auth.POST("/quickplay", s.Rooms.QuickPlay)
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
	}

	if s.WS != nil {
		r.GET("/ws", s.WS.Upgrade) // auth via ?token= in the handshake
	}
	return r
}

type createGuestReq struct {
	DisplayName string `json:"display_name"`
}

func (s *Server) createGuest(c *gin.Context) {
	var req createGuestReq
	_ = c.ShouldBindJSON(&req)
	g, err := s.Sessions.CreateGuest(c.Request.Context(), strings.TrimSpace(req.DisplayName))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not create guest"})
		return
	}
	c.JSON(http.StatusOK, g)
}

// authMiddleware resolves a Bearer token to a guest and stores it in context.
func (s *Server) authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		h := c.GetHeader("Authorization")
		token := strings.TrimPrefix(h, "Bearer ")
		g, ok := s.Sessions.Resolve(c.Request.Context(), strings.TrimSpace(token))
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid session"})
			return
		}
		c.Set(ctxGuestKey, g)
		c.Next()
	}
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
		c.Header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}
