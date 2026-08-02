from fastapi.testclient import TestClient
import database
import main


def test_create_appointment_for_existing_patient():
    database.init_db()

    db = database.SessionLocal()
    try:
        db.query(main.models.Appointment).delete()
        db.query(main.models.Patient).delete()
        db.commit()

        patient = main.models.Patient(
            full_name="Ahmed Ali",
            phone="0501234567",
            gender="Male",
            medical_history="No known allergies"
        )
        db.add(patient)
        db.commit()
        db.refresh(patient)
        patient_id = patient.id
    finally:
        db.close()

    client = TestClient(main.app)
    response = client.post(
        "/api/appointments",
        json={
            "patient_id": patient_id,
            "appointment_date": "2026-07-24T10:30:00",
            "notes": "Routine checkup"
        }
    )

    assert response.status_code == 200
    body = response.json()
    assert body["patient_id"] == patient_id
    assert body["status"] == "Pending"
    assert body["notes"] == "Routine checkup"
