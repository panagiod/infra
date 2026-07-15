package store

import (
	"context"
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/couchbase/gocb/v2"
	"github.com/google/uuid"
	"github.com/panagiod/infra/apps/kubeship/internal/models"
)

type CouchbaseStore struct {
	cluster *gocb.Cluster
	bucket  *gocb.Bucket
}

func NewCouchbaseStore(ctx context.Context) (*CouchbaseStore, error) {
	conn := getenv("COUCHBASE_CONNECTION_STRING", "couchbase://couchbase.couchbase.svc")
	bucketName := getenv("COUCHBASE_BUCKET", "kubeship")
	username := getenv("COUCHBASE_USERNAME", "Administrator")
	password := os.Getenv("COUCHBASE_PASSWORD")
	if password == "" {
		return nil, errors.New("COUCHBASE_PASSWORD is required")
	}

	cluster, err := gocb.Connect(conn, gocb.ClusterOptions{
		Authenticator: gocb.PasswordAuthenticator{
			Username: username,
			Password: password,
		},
	})
	if err != nil {
		return nil, err
	}

	if err := cluster.WaitUntilReady(5*time.Minute, &gocb.WaitUntilReadyOptions{Context: ctx}); err != nil {
		return nil, err
	}

	bucket := cluster.Bucket(bucketName)
	if err := bucket.WaitUntilReady(5*time.Minute, &gocb.WaitUntilReadyOptions{Context: ctx}); err != nil {
		return nil, err
	}

	store := &CouchbaseStore{cluster: cluster, bucket: bucket}
	if err := store.seedCarriers(ctx); err != nil {
		return nil, err
	}
	return store, nil
}

func (c *CouchbaseStore) collection() *gocb.Collection {
	return c.bucket.DefaultCollection()
}

func (c *CouchbaseStore) Ready(ctx context.Context) error {
	if c.bucket == nil || c.cluster == nil {
		return ErrNotReady
	}
	checkCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 3*time.Second)
	defer cancel()
	exists, err := c.collection().Exists("carrier::local-courier", &gocb.ExistsOptions{Context: checkCtx})
	if err != nil {
		return err
	}
	if !exists.Exists() {
		return ErrNotReady
	}
	return nil
}

func (c *CouchbaseStore) ListCarriers(ctx context.Context) ([]models.Carrier, error) {
	ids := []string{"local-courier", "med-express"}
	out := make([]models.Carrier, 0, len(ids))
	for _, id := range ids {
		var carrier models.Carrier
		res, err := c.collection().Get("carrier::"+id, &gocb.GetOptions{Context: ctx})
		if err != nil {
			continue
		}
		if err := res.Content(&carrier); err != nil {
			continue
		}
		out = append(out, carrier)
	}
	return out, nil
}

func (c *CouchbaseStore) CreateShipment(ctx context.Context, input models.ShipmentCreate) (models.Shipment, error) {
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
	if _, err := c.collection().Insert("shipment::"+id, shipment, &gocb.InsertOptions{Context: ctx}); err != nil {
		return models.Shipment{}, err
	}
	if _, err := c.collection().Insert("track::"+shipment.TrackingNumber, map[string]string{"shipment_id": id}, &gocb.InsertOptions{Context: ctx}); err != nil {
		return models.Shipment{}, err
	}
	return shipment, nil
}

func (c *CouchbaseStore) GetShipment(ctx context.Context, id string) (models.Shipment, error) {
	res, err := c.collection().Get("shipment::"+id, &gocb.GetOptions{Context: ctx})
	if err != nil {
		return models.Shipment{}, ErrNotFound
	}
	var shipment models.Shipment
	if err := res.Content(&shipment); err != nil {
		return models.Shipment{}, err
	}
	return shipment, nil
}

func (c *CouchbaseStore) TrackShipment(ctx context.Context, code string) (models.Shipment, error) {
	res, err := c.collection().Get("track::"+code, &gocb.GetOptions{Context: ctx})
	if err != nil {
		return models.Shipment{}, ErrNotFound
	}
	var pointer struct {
		ShipmentID string `json:"shipment_id"`
	}
	if err := res.Content(&pointer); err != nil {
		return models.Shipment{}, err
	}
	return c.GetShipment(ctx, pointer.ShipmentID)
}

func (c *CouchbaseStore) UpdateStatus(ctx context.Context, id, status string) (models.Shipment, error) {
	if _, ok := models.AllowedStatuses[status]; !ok {
		return models.Shipment{}, ErrInvalidStatus
	}
	shipment, err := c.GetShipment(ctx, id)
	if err != nil {
		return models.Shipment{}, err
	}
	now := time.Now().UTC().Format(time.RFC3339)
	shipment.Status = status
	shipment.StatusHistory = append(shipment.StatusHistory, models.StatusEvent{Status: status, At: now})
	if _, err := c.collection().Upsert("shipment::"+id, shipment, &gocb.UpsertOptions{Context: ctx}); err != nil {
		return models.Shipment{}, err
	}
	return shipment, nil
}

func (c *CouchbaseStore) seedCarriers(ctx context.Context) error {
	carriers := []models.Carrier{
		{ID: "local-courier", Name: "Local Courier", Region: "CY"},
		{ID: "med-express", Name: "Med Express", Region: "EU"},
	}
	for _, carrier := range carriers {
		_, err := c.collection().Insert("carrier::"+carrier.ID, carrier, &gocb.InsertOptions{Context: ctx})
		if err != nil && !errors.Is(err, gocb.ErrDocumentExists) {
			return err
		}
	}
	return nil
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func OpenDefault(ctx context.Context) (Store, error) {
	if os.Getenv("COUCHBASE_PASSWORD") == "" {
		return nil, fmt.Errorf("COUCHBASE_PASSWORD is required")
	}
	return NewCouchbaseStore(ctx)
}
