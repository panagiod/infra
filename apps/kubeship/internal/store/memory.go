package store

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/panagiod/infra/apps/kubeship/internal/models"
)

type MemoryStore struct {
	mu        sync.RWMutex
	shipments map[string]models.Shipment
	tracking  map[string]string
	carriers  []models.Carrier
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		shipments: make(map[string]models.Shipment),
		tracking:  make(map[string]string),
		carriers: []models.Carrier{
			{ID: "local-courier", Name: "Local Courier", Region: "CY"},
			{ID: "med-express", Name: "Med Express", Region: "EU"},
		},
	}
}

func (m *MemoryStore) Ready(context.Context) error { return nil }

func (m *MemoryStore) ListCarriers(context.Context) ([]models.Carrier, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	out := make([]models.Carrier, len(m.carriers))
	copy(out, m.carriers)
	return out, nil
}

func (m *MemoryStore) CreateShipment(_ context.Context, input models.ShipmentCreate) (models.Shipment, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	id := uuid.NewString()
	now := time.Now().UTC().Format(time.RFC3339)
	shipment := models.Shipment{
		ShipmentCreate: input,
		ID:             id,
		TrackingNumber: newTrackingNumber(),
		Status:         "created",
		StatusHistory:  []models.StatusEvent{{Status: "created", At: now}},
		CreatedAt:      now,
	}
	m.shipments[id] = shipment
	m.tracking[shipment.TrackingNumber] = id
	return shipment, nil
}

func (m *MemoryStore) GetShipment(_ context.Context, id string) (models.Shipment, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	shipment, ok := m.shipments[id]
	if !ok {
		return models.Shipment{}, ErrNotFound
	}
	return shipment, nil
}

func (m *MemoryStore) TrackShipment(_ context.Context, code string) (models.Shipment, error) {
	m.mu.RLock()
	id, ok := m.tracking[code]
	m.mu.RUnlock()
	if !ok {
		return models.Shipment{}, ErrNotFound
	}
	return m.GetShipment(context.Background(), id)
}

func (m *MemoryStore) UpdateStatus(_ context.Context, id, status string) (models.Shipment, error) {
	if _, ok := models.AllowedStatuses[status]; !ok {
		return models.Shipment{}, ErrInvalidStatus
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	shipment, ok := m.shipments[id]
	if !ok {
		return models.Shipment{}, ErrNotFound
	}
	now := time.Now().UTC().Format(time.RFC3339)
	shipment.Status = status
	shipment.StatusHistory = append(shipment.StatusHistory, models.StatusEvent{Status: status, At: now})
	m.shipments[id] = shipment
	return shipment, nil
}

func newTrackingNumber() string {
	buf := make([]byte, 5)
	_, _ = rand.Read(buf)
	return fmt.Sprintf("KS-%s", hex.EncodeToString(buf))
}
