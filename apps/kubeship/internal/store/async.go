package store

import (
	"context"
	"log"
	"sync"
	"time"

	"github.com/panagiod/infra/apps/kubeship/internal/models"
)

// asyncStore connects to Couchbase in the background so the HTTP server can
// start immediately and /health can return 503 while the database warms up.
type asyncStore struct {
	mu    sync.RWMutex
	inner Store
	err   error
}

func OpenAsync(parent context.Context) Store {
	a := &asyncStore{}
	go a.connect(parent)
	return a
}

func (a *asyncStore) connect(parent context.Context) {
	connectCtx, cancel := context.WithTimeout(parent, 5*time.Minute)
	defer cancel()
	s, err := OpenDefault(connectCtx)
	a.mu.Lock()
	a.inner = s
	a.err = err
	a.mu.Unlock()
	if err != nil {
		log.Printf("store connect: %v", err)
		return
	}
	log.Printf("store connected")
}

func (a *asyncStore) Ready(ctx context.Context) error {
	a.mu.RLock()
	defer a.mu.RUnlock()
	if a.err != nil {
		return a.err
	}
	if a.inner == nil {
		return ErrNotReady
	}
	return a.inner.Ready(ctx)
}

func (a *asyncStore) ListCarriers(ctx context.Context) ([]models.Carrier, error) {
	a.mu.RLock()
	defer a.mu.RUnlock()
	if a.err != nil {
		return nil, a.err
	}
	if a.inner == nil {
		return nil, ErrNotReady
	}
	return a.inner.ListCarriers(ctx)
}

func (a *asyncStore) CreateShipment(ctx context.Context, input models.ShipmentCreate) (models.Shipment, error) {
	a.mu.RLock()
	defer a.mu.RUnlock()
	if a.err != nil {
		return models.Shipment{}, a.err
	}
	if a.inner == nil {
		return models.Shipment{}, ErrNotReady
	}
	return a.inner.CreateShipment(ctx, input)
}

func (a *asyncStore) GetShipment(ctx context.Context, id string) (models.Shipment, error) {
	a.mu.RLock()
	defer a.mu.RUnlock()
	if a.err != nil {
		return models.Shipment{}, a.err
	}
	if a.inner == nil {
		return models.Shipment{}, ErrNotReady
	}
	return a.inner.GetShipment(ctx, id)
}

func (a *asyncStore) TrackShipment(ctx context.Context, code string) (models.Shipment, error) {
	a.mu.RLock()
	defer a.mu.RUnlock()
	if a.err != nil {
		return models.Shipment{}, a.err
	}
	if a.inner == nil {
		return models.Shipment{}, ErrNotReady
	}
	return a.inner.TrackShipment(ctx, code)
}

func (a *asyncStore) UpdateStatus(ctx context.Context, id, status string) (models.Shipment, error) {
	a.mu.RLock()
	defer a.mu.RUnlock()
	if a.err != nil {
		return models.Shipment{}, a.err
	}
	if a.inner == nil {
		return models.Shipment{}, ErrNotReady
	}
	return a.inner.UpdateStatus(ctx, id, status)
}
