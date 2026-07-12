"""Pytest fixtures for KubeShip API tests."""

from __future__ import annotations

import os
import sys
from pathlib import Path
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tests.fake_couchbase import FakeCollection, fake_cluster  # noqa: E402


@pytest.fixture()
def client():
    os.environ["COUCHBASE_PASSWORD"] = "test-password"
    collection = FakeCollection()

    with patch("src.main.Cluster", return_value=fake_cluster(collection)):
        from src import main

        main.cluster = None
        with TestClient(main.app) as test_client:
            yield test_client, collection
