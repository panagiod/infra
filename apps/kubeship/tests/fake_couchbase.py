"""In-memory Couchbase stand-in for API sanity tests."""

from __future__ import annotations

from couchbase.exceptions import DocumentExistsException


class FakeGetResult:
    def __init__(self, content: dict) -> None:
        self.content_as = _ContentAs(content)


class _ContentAs:
    def __init__(self, content: dict) -> None:
        self._content = content

    def __getitem__(self, _typ: type) -> dict:
        return self._content


class FakeCollection:
    def __init__(self) -> None:
        self._store: dict[str, dict] = {}

    def insert(self, key: str, doc: dict) -> None:
        if key in self._store:
            raise DocumentExistsException()
        self._store[key] = doc

    def get(self, key: str) -> FakeGetResult:
        if key not in self._store:
            raise KeyError(key)
        return FakeGetResult(self._store[key])

    def upsert(self, key: str, doc: dict) -> None:
        self._store[key] = doc


def fake_cluster(collection: FakeCollection):
    from unittest.mock import MagicMock

    from couchbase.exceptions import BucketAlreadyExistsException

    bucket = MagicMock()
    bucket.default_collection.return_value = collection

    cluster = MagicMock()
    cluster.bucket.return_value = bucket
    cluster.wait_until_ready.return_value = None
    cluster.buckets.return_value.create_bucket.side_effect = BucketAlreadyExistsException()

    return cluster
