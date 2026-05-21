// Package ws is the WebSocket transport: handshake auth, JSON envelope
// decoding, and per-connection read/write pumps. All game truth lives in the
// room layer; ws only moves bytes and never inspects private state.
package ws

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/andaseacode/paidummy-server/internal/room"
	"github.com/andaseacode/paidummy-server/internal/session"
	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

const (
	writeWait  = 10 * time.Second
	pongWait   = 60 * time.Second
	pingPeriod = 20 * time.Second
	sendBuffer = 32
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 4096,
	CheckOrigin:     func(*http.Request) bool { return true }, // guest game, dev-open
}

// Handler upgrades connections and binds them to rooms.
type Handler struct {
	hub      *room.Hub
	sessions *session.Manager
}

func NewHandler(h *room.Hub, s *session.Manager) *Handler {
	return &Handler{hub: h, sessions: s}
}

// envelope is the wire format in both directions.
type envelope struct {
	Type string          `json:"type"`
	ID   string          `json:"id,omitempty"`
	TS   int64           `json:"ts,omitempty"`
	Data json.RawMessage `json:"data,omitempty"`
}

// conn is one player's live socket; it satisfies room.Sender.
type conn struct {
	guestID   string
	name      string
	ws        *websocket.Conn
	send      chan []byte
	room      *room.Room
	spectator bool
}

func (c *conn) GuestID() string { return c.guestID }
func (c *conn) Name() string    { return c.name }
func (c *conn) Send(p []byte) {
	select {
	case c.send <- p:
	default: // slow/dead client: drop rather than block the room
	}
}

// Upgrade handles GET /ws?token=<session>&room=<roomID>.
func (h *Handler) Upgrade(c *gin.Context) {
	token := c.Query("token")
	roomID := c.Query("room")
	g, ok := h.sessions.Resolve(c.Request.Context(), token)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid session"})
		return
	}
	r, ok := h.hub.Get(roomID)
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "room not found"})
		return
	}
	spectate := c.Query("spectate") == "1" || c.Query("spectate") == "true"
	wsConn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}
	cn := &conn{
		guestID: g.ID.String(), name: g.Name, ws: wsConn,
		send: make(chan []byte, sendBuffer), room: r, spectator: spectate,
	}
	go cn.writePump()
	if spectate {
		r.AttachSpectator(cn)
	} else {
		r.Attach(cn)
	}
	cn.readPump()
}

func (c *conn) readPump() {
	defer func() {
		if c.spectator {
			c.room.DetachSpectator(c.guestID)
		} else {
			c.room.Detach(c.guestID)
		}
		_ = c.ws.Close()
		close(c.send)
	}()
	c.ws.SetReadLimit(8192)
	_ = c.ws.SetReadDeadline(time.Now().Add(pongWait))
	c.ws.SetPongHandler(func(string) error {
		return c.ws.SetReadDeadline(time.Now().Add(pongWait))
	})
	for {
		_, raw, err := c.ws.ReadMessage()
		if err != nil {
			return
		}
		var env envelope
		if json.Unmarshal(raw, &env) != nil || env.Type == "" {
			c.Send(serverErr("malformed message"))
			continue
		}
		// Spectators are view-only: allow chat, ignore everything else so
		// they can never mutate game state.
		if c.spectator && env.Type != "chat" {
			continue
		}
		c.room.HandleMessage(context.Background(), c.guestID, env.Type, env.Data)
	}
}

func (c *conn) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		_ = c.ws.Close()
	}()
	for {
		select {
		case msg, ok := <-c.send:
			_ = c.ws.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				_ = c.ws.WriteMessage(websocket.CloseMessage, nil)
				return
			}
			if err := c.ws.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			_ = c.ws.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.ws.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func serverErr(msg string) []byte {
	b, _ := json.Marshal(envelope{
		Type: "error", TS: time.Now().Unix(),
		Data: mustJSON(map[string]string{"message": msg}),
	})
	return b
}

func mustJSON(v any) json.RawMessage {
	b, _ := json.Marshal(v)
	return b
}
