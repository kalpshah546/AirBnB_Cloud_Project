from fastapi.testclient import TestClient

from services.search.app import app, burn_cpu, initialize_search_data


def test_dataset_has_requested_size():
    assert initialize_search_data() == 50_000


def test_cpu_work_is_bounded():
    assert burn_cpu(0) == 0
    assert burn_cpu(2) > 0


def test_search_endpoint_returns_listings():
    with TestClient(app) as client:
        response = client.get("/search?city=Goa&limit=5&work_ms=0")
    assert response.status_code == 200
    body = response.json()
    assert body["service"] == "search"
    assert body["dataset_size"] == 50_000
    assert len(body["results"]) <= 5
    assert all(item["city"] == "Goa" for item in body["results"])
