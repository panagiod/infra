package models

type Address struct {
	City    string `json:"city"`
	Country string `json:"country"`
}

type ShipmentCreate struct {
	Origin      Address `json:"origin"`
	Destination Address `json:"destination"`
	Carrier     string  `json:"carrier"`
	WeightKg    float64 `json:"weight_kg"`
}

type StatusEvent struct {
	Status string `json:"status"`
	At     string `json:"at"`
}

type Shipment struct {
	ShipmentCreate
	ID              string        `json:"id"`
	TrackingNumber  string        `json:"tracking_number"`
	Status          string        `json:"status"`
	StatusHistory   []StatusEvent `json:"status_history"`
	CreatedAt       string        `json:"created_at"`
}

type Carrier struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Region string `json:"region"`
}

type StatusUpdate struct {
	Status string `json:"status"`
}

var AllowedStatuses = map[string]struct{}{
	"created":    {},
	"picked_up":  {},
	"in_transit": {},
	"delivered":  {},
	"cancelled":  {},
}
