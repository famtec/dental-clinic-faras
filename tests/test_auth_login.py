from fastapi.testclient import TestClient
import main


def test_login_returns_token_for_valid_credentials():
    client = TestClient(main.app)

    response = client.post(
        "/api/auth/login",
        json={"email": "admin@dental.com", "password": "123456"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["subscription_active"] is True
    assert body["token"] == "fake-token-123"


def test_login_returns_forbidden_when_subscription_is_inactive(monkeypatch):
    client = TestClient(main.app)
    monkeypatch.setattr(main, "MOCK_SUBSCRIPTION_ACTIVE", False)

    response = client.post(
        "/api/auth/login",
        json={"email": "admin@dental.com", "password": "123456"},
    )

    assert response.status_code == 403
    assert response.json()["detail"] == "عذراً، انتهت مدة الاشتراك. يرجى التواصل مع الإدارة للتجديد"
