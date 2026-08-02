from fastapi.testclient import TestClient
import database
import main


def test_patients_endpoint_is_available():
    database.init_db()
    client = TestClient(main.app)

    response = client.get("/api/patients")

    assert response.status_code == 200
    assert isinstance(response.json(), list)
