package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/panagiod/infra/apps/kubeship/internal/models"
	"github.com/panagiod/infra/apps/kubeship/internal/store"
	"github.com/panagiod/infra/apps/kubeship/static"
)

func testHandler(t *testing.T) http.Handler {
	t.Helper()
	return New(store.NewMemoryStore(), static.Files).Handler()
}

func TestHealth(t *testing.T) {
	res := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	testHandler(t).ServeHTTP(res, req)

	if res.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", res.Code)
	}
	var body map[string]string
	if err := json.Unmarshal(res.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body["status"] != "ok" || body["service"] != "kubeship" {
		t.Fatalf("unexpected body: %#v", body)
	}
}

func TestUIAndStatic(t *testing.T) {
	h := testHandler(t)

	root := httptest.NewRecorder()
	h.ServeHTTP(root, httptest.NewRequest(http.MethodGet, "/", nil))
	if root.Code != http.StatusOK {
		t.Fatalf("ui status = %d", root.Code)
	}
	if !bytes.Contains(root.Body.Bytes(), []byte("KubeShip")) {
		t.Fatal("ui missing title")
	}

	for _, path := range []string{"/static/app.css", "/static/app.js"} {
		res := httptest.NewRecorder()
		h.ServeHTTP(res, httptest.NewRequest(http.MethodGet, path, nil))
		if res.Code != http.StatusOK {
			t.Fatalf("%s status = %d", path, res.Code)
		}
	}
}

func TestListCarriers(t *testing.T) {
	res := httptest.NewRecorder()
	testHandler(t).ServeHTTP(res, httptest.NewRequest(http.MethodGet, "/api/v1/carriers", nil))
	if res.Code != http.StatusOK {
		t.Fatalf("status = %d", res.Code)
	}
	var carriers []models.Carrier
	if err := json.Unmarshal(res.Body.Bytes(), &carriers); err != nil {
		t.Fatal(err)
	}
	if len(carriers) != 2 {
		t.Fatalf("got %d carriers", len(carriers))
	}
}

func TestShipmentLifecycle(t *testing.T) {
	h := testHandler(t)
	payload := `{
		"origin": {"city": "Limassol", "country": "CY"},
		"destination": {"city": "Athens", "country": "GR"},
		"carrier": "med-express",
		"weight_kg": 3.5
	}`

	create := httptest.NewRecorder()
	h.ServeHTTP(create, httptest.NewRequest(http.MethodPost, "/api/v1/shipments", bytes.NewBufferString(payload)))
	if create.Code != http.StatusCreated {
		t.Fatalf("create status = %d body=%s", create.Code, create.Body.String())
	}

	var shipment models.Shipment
	if err := json.Unmarshal(create.Body.Bytes(), &shipment); err != nil {
		t.Fatal(err)
	}
	if shipment.Status != "created" || shipment.TrackingNumber[:3] != "KS-" {
		t.Fatalf("unexpected shipment: %#v", shipment)
	}

	get := httptest.NewRecorder()
	h.ServeHTTP(get, httptest.NewRequest(http.MethodGet, "/api/v1/shipments/"+shipment.ID, nil))
	if get.Code != http.StatusOK {
		t.Fatalf("get status = %d", get.Code)
	}

	track := httptest.NewRecorder()
	h.ServeHTTP(track, httptest.NewRequest(http.MethodGet, "/api/v1/track/"+shipment.TrackingNumber, nil))
	if track.Code != http.StatusOK {
		t.Fatalf("track status = %d", track.Code)
	}

	patch := httptest.NewRecorder()
	patchReq := httptest.NewRequest(http.MethodPatch, "/api/v1/shipments/"+shipment.ID+"/status", bytes.NewBufferString(`{"status":"in_transit"}`))
	patchReq.Header.Set("Content-Type", "application/json")
	h.ServeHTTP(patch, patchReq)
	if patch.Code != http.StatusOK {
		t.Fatalf("patch status = %d body=%s", patch.Code, patch.Body.String())
	}
}

func TestCreateShipmentValidation(t *testing.T) {
	payload := `{
		"origin": {"city": "Limassol", "country": "CY"},
		"destination": {"city": "Athens", "country": "GR"},
		"carrier": "local-courier",
		"weight_kg": 0
	}`
	res := httptest.NewRecorder()
	testHandler(t).ServeHTTP(res, httptest.NewRequest(http.MethodPost, "/api/v1/shipments", bytes.NewBufferString(payload)))
	if res.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", res.Code)
	}
}

func TestUpdateStatusInvalid(t *testing.T) {
	h := testHandler(t)
	create := httptest.NewRecorder()
	h.ServeHTTP(create, httptest.NewRequest(http.MethodPost, "/api/v1/shipments", bytes.NewBufferString(`{
		"origin": {"city": "Nicosia", "country": "CY"},
		"destination": {"city": "Larnaca", "country": "CY"},
		"carrier": "local-courier",
		"weight_kg": 1
	}`)))
	var shipment models.Shipment
	_ = json.Unmarshal(create.Body.Bytes(), &shipment)

	res := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPatch, "/api/v1/shipments/"+shipment.ID+"/status", bytes.NewBufferString(`{"status":"lost_at_sea"}`))
	req.Header.Set("Content-Type", "application/json")
	h.ServeHTTP(res, req)
	if res.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", res.Code)
	}
}

func TestNotFound(t *testing.T) {
	h := testHandler(t)
	for _, path := range []string{"/api/v1/shipments/missing", "/api/v1/track/KS-NOTFOUND00"} {
		res := httptest.NewRecorder()
		h.ServeHTTP(res, httptest.NewRequest(http.MethodGet, path, nil))
		if res.Code != http.StatusNotFound {
			t.Fatalf("%s status = %d", path, res.Code)
		}
	}
}
