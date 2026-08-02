import main
from fastapi.testclient import TestClient


client = TestClient(main.app)


def clear_patients():
    db = main.database.SessionLocal()
    try:
        db.query(main.models.Patient).delete()
        db.commit()
    finally:
        db.close()


def test_delete_patient_route():
    clear_patients()

    db = main.database.SessionLocal()
    try:
        patient = main.models.Patient(
            doctor_name="Dr. Ali",
            full_name="Ahmed Hassan",
            phone="0500000000",
            medical_history="No known allergies"
        )
        db.add(patient)
        db.commit()
        db.refresh(patient)
        patient_id = patient.id
    finally:
        db.close()

    response = client.delete(f"/api/patients/{patient_id}")

    assert response.status_code == 200
    assert response.json()["message"] == "Patient deleted successfully"

    verification_db = main.database.SessionLocal()
    try:
        deleted_patient = verification_db.query(main.models.Patient).filter(main.models.Patient.id == patient_id).first()
        assert deleted_patient is None
    finally:
        verification_db.close()


def test_update_patient_route():
    clear_patients()

    db = main.database.SessionLocal()
    try:
        patient = main.models.Patient(
            doctor_name="Dr. Ali",
            full_name="Ahmed Hassan",
            phone="0500000000",
            medical_history="No known allergies"
        )
        db.add(patient)
        db.commit()
        db.refresh(patient)
        patient_id = patient.id
    finally:
        db.close()

    response = client.put(
        f"/api/patients/{patient_id}",
        json={
            "doctor_name": "Dr. Sara",
            "full_name": "Ahmed Hassan Updated",
            "phone": "0555555555",
            "medical_history": "Updated history"
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["doctor_name"] == "Dr. Sara"
    assert body["full_name"] == "Ahmed Hassan Updated"
    assert body["phone"] == "0555555555"
    assert body["medical_history"] == "Updated history"

    verification_db = main.database.SessionLocal()
    try:
        updated_patient = verification_db.query(main.models.Patient).filter(main.models.Patient.id == patient_id).first()
        assert updated_patient is not None
        assert updated_patient.doctor_name == "Dr. Sara"
        assert updated_patient.full_name == "Ahmed Hassan Updated"
        assert updated_patient.phone == "0555555555"
        assert updated_patient.medical_history == "Updated history"
    finally:
        verification_db.close()
