"""KubeShip product sanity tests — API and UI smoke without a real Couchbase cluster."""

from __future__ import annotations


def test_health(client):
    http, _ = client
    res = http.get("/health")
    assert res.status_code == 200
    body = res.json()
    assert body["status"] == "ok"
    assert body["service"] == "kubeship"


def test_ui_root(client):
    http, _ = client
    res = http.get("/")
    assert res.status_code == 200
    assert "KubeShip" in res.text
    assert "/static/app.js" in res.text


def test_static_assets(client):
    http, _ = client
    for path in ("/static/app.css", "/static/app.js"):
        res = http.get(path)
        assert res.status_code == 200
        assert res.content


def test_list_carriers(client):
    http, _ = client
    res = http.get("/api/v1/carriers")
    assert res.status_code == 200
    carriers = res.json()
    assert len(carriers) == 2
    ids = {c["id"] for c in carriers}
    assert ids == {"local-courier", "med-express"}


def test_shipment_lifecycle(client):
    http, _ = client

    create = http.post(
        "/api/v1/shipments",
        json={
            "origin": {"city": "Limassol", "country": "CY"},
            "destination": {"city": "Athens", "country": "GR"},
            "carrier": "med-express",
            "weight_kg": 3.5,
        },
    )
    assert create.status_code == 201
    shipment = create.json()
    assert shipment["status"] == "created"
    assert shipment["tracking_number"].startswith("KS-")
    assert shipment["origin"]["city"] == "Limassol"
    assert len(shipment["status_history"]) == 1

    shipment_id = shipment["id"]
    tracking = shipment["tracking_number"]

    get_res = http.get(f"/api/v1/shipments/{shipment_id}")
    assert get_res.status_code == 200
    assert get_res.json()["id"] == shipment_id

    track_res = http.get(f"/api/v1/track/{tracking}")
    assert track_res.status_code == 200
    assert track_res.json()["tracking_number"] == tracking

    patch_res = http.patch(
        f"/api/v1/shipments/{shipment_id}/status",
        json={"status": "in_transit"},
    )
    assert patch_res.status_code == 200
    updated = patch_res.json()
    assert updated["status"] == "in_transit"
    assert updated["status_history"][-1]["status"] == "in_transit"


def test_create_shipment_validation(client):
    http, _ = client
    res = http.post(
        "/api/v1/shipments",
        json={
            "origin": {"city": "Limassol", "country": "CY"},
            "destination": {"city": "Athens", "country": "GR"},
            "carrier": "local-courier",
            "weight_kg": 0,
        },
    )
    assert res.status_code == 422


def test_update_status_rejects_invalid_value(client):
    http, _ = client
    create = http.post(
        "/api/v1/shipments",
        json={
            "origin": {"city": "Nicosia", "country": "CY"},
            "destination": {"city": "Larnaca", "country": "CY"},
            "carrier": "local-courier",
            "weight_kg": 1.0,
        },
    )
    shipment_id = create.json()["id"]

    res = http.patch(
        f"/api/v1/shipments/{shipment_id}/status",
        json={"status": "lost_at_sea"},
    )
    assert res.status_code == 400
    assert "status must be one of" in res.json()["detail"]


def test_get_shipment_not_found(client):
    http, _ = client
    res = http.get("/api/v1/shipments/does-not-exist")
    assert res.status_code == 404


def test_track_not_found(client):
    http, _ = client
    res = http.get("/api/v1/track/KS-NOTFOUND00")
    assert res.status_code == 404
