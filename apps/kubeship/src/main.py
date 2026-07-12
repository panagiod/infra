"""KubeShip — paper shipping management API backed by Couchbase."""

from __future__ import annotations

import os
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Any

from pathlib import Path

from couchbase.auth import PasswordAuthenticator
from couchbase.cluster import Cluster
from couchbase.exceptions import BucketAlreadyExistsException, DocumentExistsException
from couchbase.management.buckets import BucketSettings
from couchbase.options import ClusterOptions
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

BUCKET_NAME = os.environ.get("COUCHBASE_BUCKET", "kubeship")
CONN_STR = os.environ.get(
    "COUCHBASE_CONNECTION_STRING",
    "couchbase://couchbase.couchbase.svc",
)
USERNAME = os.environ.get("COUCHBASE_USERNAME", "Administrator")
PASSWORD = os.environ.get("COUCHBASE_PASSWORD", "")

cluster: Cluster | None = None


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def tracking_number() -> str:
    return f"KS-{uuid.uuid4().hex[:10].upper()}"


class Address(BaseModel):
    city: str
    country: str = Field(min_length=2, max_length=2)


class ShipmentCreate(BaseModel):
    origin: Address
    destination: Address
    carrier: str = "local-courier"
    weight_kg: float = Field(gt=0, le=10_000)


class Shipment(ShipmentCreate):
    id: str
    tracking_number: str
    status: str
    status_history: list[dict[str, str]]
    created_at: str


class StatusUpdate(BaseModel):
    status: str


STATIC_DIR = Path(__file__).resolve().parent.parent / "static"

def get_collection():
    if cluster is None:
        raise HTTPException(status_code=503, detail="database not ready")
    return cluster.bucket(BUCKET_NAME).default_collection()


def ensure_bucket(cb: Cluster) -> None:
    mgr = cb.buckets()
    try:
        mgr.create_bucket(BucketSettings(name=BUCKET_NAME, ram_quota_mb=100))
    except BucketAlreadyExistsException:
        pass


def seed_carriers(col) -> None:
    carriers = [
        {"id": "local-courier", "name": "Local Courier", "region": "CY"},
        {"id": "med-express", "name": "Med Express", "region": "EU"},
    ]
    for carrier in carriers:
        try:
            col.insert(f"carrier::{carrier['id']}", carrier)
        except DocumentExistsException:
            pass


@asynccontextmanager
async def lifespan(_: FastAPI):
    global cluster
    if not PASSWORD:
        raise RuntimeError("COUCHBASE_PASSWORD is required")

    cb = Cluster(CONN_STR, ClusterOptions(PasswordAuthenticator(USERNAME, PASSWORD)))
    cb.wait_until_ready(timeout=300)
    ensure_bucket(cb)
    cluster = cb
    seed_carriers(get_collection())
    yield
    cluster = None


app = FastAPI(title="KubeShip", version="0.1.0", lifespan=lifespan)

if STATIC_DIR.is_dir():
    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.get("/")
def ui() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/health")
def health() -> dict[str, str]:
    get_collection()
    return {"status": "ok", "service": "kubeship"}


@app.get("/api/v1/carriers")
def list_carriers() -> list[dict[str, Any]]:
    col = get_collection()
    carriers: list[dict[str, Any]] = []
    for carrier_id in ("local-courier", "med-express"):
        try:
            carriers.append(col.get(f"carrier::{carrier_id}").content_as[dict])
        except Exception:  # noqa: BLE001
            continue
    return carriers


@app.post("/api/v1/shipments", response_model=Shipment, status_code=201)
def create_shipment(body: ShipmentCreate) -> Shipment:
    col = get_collection()
    shipment_id = str(uuid.uuid4())
    doc = Shipment(
        id=shipment_id,
        tracking_number=tracking_number(),
        status="created",
        status_history=[{"status": "created", "at": utc_now()}],
        created_at=utc_now(),
        **body.model_dump(),
    )
    col.insert(f"shipment::{shipment_id}", doc.model_dump())
    col.insert(f"track::{doc.tracking_number}", {"shipment_id": shipment_id})
    return doc


@app.get("/api/v1/shipments/{shipment_id}", response_model=Shipment)
def get_shipment(shipment_id: str) -> Shipment:
    col = get_collection()
    try:
        result = col.get(f"shipment::{shipment_id}")
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=404, detail="shipment not found") from exc
    return Shipment(**result.content_as[dict])


@app.get("/api/v1/track/{code}", response_model=Shipment)
def track(code: str) -> Shipment:
    col = get_collection()
    try:
        pointer = col.get(f"track::{code}")
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=404, detail="tracking number not found") from exc
    shipment_id = pointer.content_as[dict]["shipment_id"]
    return get_shipment(shipment_id)


@app.patch("/api/v1/shipments/{shipment_id}/status", response_model=Shipment)
def update_status(shipment_id: str, body: StatusUpdate) -> Shipment:
    allowed = {"created", "picked_up", "in_transit", "delivered", "cancelled"}
    status = body.status
    if status not in allowed:
        raise HTTPException(status_code=400, detail=f"status must be one of {sorted(allowed)}")

    col = get_collection()
    key = f"shipment::{shipment_id}"
    try:
        current = col.get(key).content_as[dict]
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=404, detail="shipment not found") from exc

    current["status"] = status
    current.setdefault("status_history", []).append({"status": status, "at": utc_now()})
    col.upsert(key, current)
    return Shipment(**current)
