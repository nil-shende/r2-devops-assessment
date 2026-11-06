"""Unit tests: the database is replaced by an in-memory fake repository."""
from datetime import datetime, timezone

from fastapi.testclient import TestClient

from app.main import app, get_repo


class FakeRepo:
    def __init__(self, healthy: bool = True):
        self.items: list[dict] = []
        self.healthy = healthy

    def ping(self):
        if not self.healthy:
            raise RuntimeError("db down")
        return True

    def list_items(self):
        return list(reversed(self.items))

    def create_item(self, name):
        item = {"id": len(self.items) + 1, "name": name,
                "created_at": datetime.now(timezone.utc).isoformat()}
        self.items.append(item)
        return item


def client_with(repo):
    app.dependency_overrides[get_repo] = lambda: repo
    return TestClient(app)


def test_health_does_not_need_database():
    c = client_with(FakeRepo(healthy=False))
    r = c.get("/api/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_ready_reports_database_failure():
    c = client_with(FakeRepo(healthy=False))
    assert c.get("/api/ready").status_code == 503


def test_create_and_list_items():
    c = client_with(FakeRepo())
    assert c.post("/api/items", json={"name": "  first  "}).status_code == 201
    c.post("/api/items", json={"name": "second"})
    names = [i["name"] for i in c.get("/api/items").json()]
    assert names == ["second", "first"]


def test_validation_rejects_empty_name():
    c = client_with(FakeRepo())
    assert c.post("/api/items", json={"name": ""}).status_code == 422


def test_info_shows_deployment_metadata():
    c = client_with(FakeRepo())
    body = c.get("/api/info").json()
    assert body["database"] == "connected"
    assert {"environment", "version", "deployment_target"} <= body.keys()
