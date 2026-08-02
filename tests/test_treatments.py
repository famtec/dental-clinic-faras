from fastapi.testclient import TestClient
import database
import main


def test_create_treatment_endpoint():
    database.init_db()

    db = database.SessionLocal()
    try:
        db.query(main.models.Treatment).delete()
        db.query(main.models.Visit).delete()
        db.query(main.models.Appointment).delete()
        db.query(main.models.Patient).delete()
        db.commit()

        patient = main.models.Patient(full_name="Test Patient", phone="0500000000", gender="Male")
        db.add(patient)
        db.commit()
        db.refresh(patient)
        patient_id = patient.id
    finally:
        db.close()

    client = TestClient(main.app)
    response = client.post(
        "/api/treatments",
        json={
            "patient_id": patient_id,
            "tooth_number": 18,
            "treatment_type": "Filling",
            "notes": "Cavity",
            "color": "#ef4444"
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["patient_id"] == patient_id
    assert body["tooth_number"] == 18
    assert body["treatment_type"] == "Filling"
