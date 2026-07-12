package store

import (
	"context"
	"errors"

	"github.com/panagiod/infra/apps/kubeship/internal/models"
)

var (
	ErrNotFound      = errors.New("not found")
	ErrNotReady      = errors.New("database not ready")
	ErrInvalidStatus = errors.New("invalid status")
)

type Store interface {
	Ready(ctx context.Context) error
	ListCarriers(ctx context.Context) ([]models.Carrier, error)
	CreateShipment(ctx context.Context, input models.ShipmentCreate) (models.Shipment, error)
	GetShipment(ctx context.Context, id string) (models.Shipment, error)
	TrackShipment(ctx context.Context, code string) (models.Shipment, error)
	UpdateStatus(ctx context.Context, id, status string) (models.Shipment, error)
}
