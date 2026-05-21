// Package notify abstracts push delivery behind a Notifier interface. The
// shipped LogNotifier just logs (no FCM/APNs credentials wired yet); a real
// implementation sends to the device tokens stored in db.device_tokens.
//
// Typical trigger: "ตาคุณแล้ว!" when a room is waiting on a disconnected
// player. Wire LogNotifier → FCMNotifier when credentials exist; call sites
// stay unchanged.
package notify

import (
	"context"
	"log"
)

// Notifier delivers a push to one or more device tokens.
type Notifier interface {
	Push(ctx context.Context, tokens []string, title, body string) error
}

// LogNotifier writes pushes to the server log — a safe default that proves
// the trigger path works without a vendor SDK.
type LogNotifier struct{}

func (LogNotifier) Push(_ context.Context, tokens []string, title, body string) error {
	log.Printf("[notify] push to %d token(s): %q — %q", len(tokens), title, body)
	return nil
}
