package api

import (
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"net/http"
	"strings"

	"github.com/panagiod/infra/apps/kubeship/internal/models"
	"github.com/panagiod/infra/apps/kubeship/internal/store"
)

type Server struct {
	store  store.Store
	static fs.FS
}

func New(st store.Store, static fs.FS) *Server {
	return &Server{store: st, static: static}
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.handleHealth)
	mux.HandleFunc("GET /api/v1/carriers", s.handleListCarriers)
	mux.HandleFunc("POST /api/v1/shipments", s.handleCreateShipment)
	mux.HandleFunc("GET /api/v1/shipments/{id}", s.handleGetShipment)
	mux.HandleFunc("GET /api/v1/track/{code}", s.handleTrack)
	mux.HandleFunc("PATCH /api/v1/shipments/{id}/status", s.handleUpdateStatus)
	if s.static != nil {
		mux.Handle("GET /static/", http.StripPrefix("/static/", http.FileServer(http.FS(s.static))))
	}
	mux.HandleFunc("GET /{$}", s.handleUI)
	return mux
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if err := s.store.Ready(r.Context()); err != nil {
		writeError(w, http.StatusServiceUnavailable, "database not ready")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "service": "kubeship"})
}

func (s *Server) handleListCarriers(w http.ResponseWriter, r *http.Request) {
	carriers, err := s.store.ListCarriers(r.Context())
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, carriers)
}

func (s *Server) handleCreateShipment(w http.ResponseWriter, r *http.Request) {
	var input models.ShipmentCreate
	if err := decodeJSON(r.Body, &input); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := validateShipmentCreate(input); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if input.Carrier == "" {
		input.Carrier = "local-courier"
	}
	shipment, err := s.store.CreateShipment(r.Context(), input)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, shipment)
}

func (s *Server) handleGetShipment(w http.ResponseWriter, r *http.Request) {
	shipment, err := s.store.GetShipment(r.Context(), r.PathValue("id"))
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, shipment)
}

func (s *Server) handleTrack(w http.ResponseWriter, r *http.Request) {
	shipment, err := s.store.TrackShipment(r.Context(), r.PathValue("code"))
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, shipment)
}

func (s *Server) handleUpdateStatus(w http.ResponseWriter, r *http.Request) {
	var body models.StatusUpdate
	if err := decodeJSON(r.Body, &body); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	shipment, err := s.store.UpdateStatus(r.Context(), r.PathValue("id"), body.Status)
	if err != nil {
		if errors.Is(err, store.ErrInvalidStatus) {
			writeError(w, http.StatusBadRequest, "status must be one of [cancelled created delivered in_transit picked_up]")
			return
		}
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, shipment)
}

func (s *Server) handleUI(w http.ResponseWriter, _ *http.Request) {
	if s.static == nil {
		http.NotFound(w, nil)
		return
	}
	data, err := fs.ReadFile(s.static, "index.html")
	if err != nil {
		http.NotFound(w, nil)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(data)
}

func validateShipmentCreate(input models.ShipmentCreate) error {
	if strings.TrimSpace(input.Origin.City) == "" || strings.TrimSpace(input.Destination.City) == "" {
		return errors.New("origin and destination city are required")
	}
	if len(input.Origin.Country) != 2 || len(input.Destination.Country) != 2 {
		return errors.New("country must be a 2-letter code")
	}
	if input.WeightKg <= 0 || input.WeightKg > 10000 {
		return errors.New("weight_kg must be greater than 0 and at most 10000")
	}
	return nil
}

func decodeJSON(body io.Reader, dst any) error {
	dec := json.NewDecoder(body)
	dec.DisallowUnknownFields()
	return dec.Decode(dst)
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, detail string) {
	writeJSON(w, status, map[string]string{"detail": detail})
}

func writeStoreError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "not found")
	case errors.Is(err, store.ErrNotReady):
		writeError(w, http.StatusServiceUnavailable, "database not ready")
	default:
		writeError(w, http.StatusInternalServerError, "internal error")
	}
}
