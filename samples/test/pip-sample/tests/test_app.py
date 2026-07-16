"""HTTP endpoint tests via FastAPI TestClient (uses httpx, a test-only dependency)."""

from fastapi.testclient import TestClient

from sampleapp.app import app, format_greeting


client = TestClient(app)


def test_root():
    response = client.get("/")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "Hello, Ubuntu!"
    assert body["service"] == "sampleapp"


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_greeting_default_name():
    response = client.get("/api/greeting")
    assert response.status_code == 200
    body = response.json()
    assert body["content"] == "Hello, World!"
    assert body["id"] >= 1


def test_greeting_capitalizes_provided_name():
    response = client.get("/api/greeting", params={"name": "ada"})
    assert response.status_code == 200
    assert response.json()["content"] == "Hello, Ada!"


def test_echo():
    response = client.post("/echo", json={"message": "ping"})
    assert response.status_code == 200
    assert response.json() == {"echo": "ping"}


def test_format_greeting_uses_capitalize(mocker):
    """Uses pytest-mock (test-only) for a lightweight dependency demo."""
    mocker.patch("sampleapp.app.format_greeting", return_value="Hello, Mocked!")
    from sampleapp import app as app_module

    assert app_module.format_greeting("anything") == "Hello, Mocked!"


def test_format_greeting_blank_falls_back_to_world():
    assert format_greeting("  ") == "Hello, World!"
    assert format_greeting("") == "Hello, World!"
