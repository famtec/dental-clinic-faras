from datetime import datetime, timedelta

from fastapi.testclient import TestClient

import database
import main


def test_get_patient_financial_transactions_returns_income_transactions_newest_first():
    database.init_db()

    db = database.SessionLocal()
    try:
        db.query(main.models.FinancialTransaction).delete()
        db.query(main.models.Patient).delete()
        db.commit()

        patient = main.models.Patient(full_name="Test Patient", phone="0500000000", gender="Male")
        db.add(patient)
        db.commit()
        db.refresh(patient)

        now = datetime.utcnow()
        first_transaction = main.models.FinancialTransaction(
            patient_id=patient.id,
            amount=100,
            type="income",
            description="Older income",
            created_at=now - timedelta(days=1),
        )
        second_transaction = main.models.FinancialTransaction(
            patient_id=patient.id,
            amount=250,
            type="income",
            description="Newest income",
            created_at=now,
        )
        ignored_transaction = main.models.FinancialTransaction(
            patient_id=patient.id,
            amount=50,
            type="expense",
            description="Expense should not appear",
            created_at=now + timedelta(days=1),
        )
        db.add_all([first_transaction, second_transaction, ignored_transaction])
        db.commit()
    finally:
        db.close()

    client = TestClient(main.app)
    response = client.get(f"/api/finance/patient/{patient.id}")

    assert response.status_code == 200
    body = response.json()
    assert len(body) == 2
    assert [item["description"] for item in body] == ["Newest income", "Older income"]
    assert all(item["type"] == "income" for item in body)