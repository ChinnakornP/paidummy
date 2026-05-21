// Package payment abstracts coin-package payment capture behind a Provider
// interface so the shop handler doesn't hard-code a vendor. The shipped
// default is MockProvider (always captures); PromptPay / TrueMoney / IAP
// providers are stubbed and return ErrNotImplemented until real credentials
// + SDKs are wired.
package payment

import (
	"context"
	"errors"

	"github.com/andaseacode/paidummy-server/internal/db"
	"github.com/google/uuid"
)

// ErrNotImplemented is returned by stub providers that have no real backend
// configured yet.
var ErrNotImplemented = errors.New("payment provider not implemented")

// Capture is the result of a successful payment authorisation+capture.
type Capture struct {
	TxnID    string
	Provider string
}

// Provider authorises and captures payment for a coin package. It must NOT
// credit coins — the caller does that via db.PurchasePackage only after a
// successful Capture, keeping the wallet write in one place.
type Provider interface {
	Name() string
	Capture(ctx context.Context, guestID uuid.UUID, pkg db.CoinPackage) (Capture, error)
}

// MockProvider always succeeds — matches the current always-on mock shop.
type MockProvider struct{}

func (MockProvider) Name() string { return "mock" }

func (MockProvider) Capture(_ context.Context, _ uuid.UUID, pkg db.CoinPackage) (Capture, error) {
	return Capture{TxnID: "mock-" + uuid.NewString(), Provider: "mock"}, nil
}

// PromptPayProvider is a stub for Thai PromptPay QR settlement.
type PromptPayProvider struct{}

func (PromptPayProvider) Name() string { return "promptpay" }
func (PromptPayProvider) Capture(context.Context, uuid.UUID, db.CoinPackage) (Capture, error) {
	return Capture{}, ErrNotImplemented
}

// TrueMoneyProvider is a stub for TrueMoney Wallet settlement.
type TrueMoneyProvider struct{}

func (TrueMoneyProvider) Name() string { return "truemoney" }
func (TrueMoneyProvider) Capture(context.Context, uuid.UUID, db.CoinPackage) (Capture, error) {
	return Capture{}, ErrNotImplemented
}

// IAPProvider is a stub for Apple/Google in-app-purchase receipt validation.
type IAPProvider struct{}

func (IAPProvider) Name() string { return "iap" }
func (IAPProvider) Capture(context.Context, uuid.UUID, db.CoinPackage) (Capture, error) {
	return Capture{}, ErrNotImplemented
}
