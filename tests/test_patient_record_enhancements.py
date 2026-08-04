import json
from datetime import datetime

from sqlalchemy import text

import main


def clear_patient_related_tables(db):
    db.query(main.models.Appointment).delete()
    db.query(main.models.Treatment).delete()
    db.query(main.models.Visit).delete()
    db.query(main.models.Patient).delete()
    db.commit()


def test_update_patient_chart_persists_json_state():
    main.database.init_db()

    db = main.database.SessionLocal()
    try:
        clear_patient_related_tables(db)

        patient = main.models.Patient(full_name="Test Patient", phone="0500000000", gender="Male")
        db.add(patient)
        db.commit()
        db.refresh(patient)

        result = main.update_patient_chart(
            patient_id=patient.id,
            chart_update=main.PatientChartUpdate(chart_state={"18": "#fca5a5", "11": "#22c55e"}),
            db=db,
        )

        db.refresh(patient)
        assert result.id == patient.id
        assert json.loads(patient.chart_state) == {"18": "#fca5a5", "11": "#22c55e"}
    finally:
        db.close()


def test_update_appointment_persists_new_date_time_and_description():
    main.database.init_db()

    db = main.database.SessionLocal()
    try:
    clear_patient_related_tables(db)

    patient = main.models.Patient(full_name="Ahmed Ali", phone="0500000000", gender="Male")
    db.add(patient)
    db.commit()
    db.refresh(patient)

    db.execute(
      text(
        """
        INSERT INTO appointments (patient_id, patient_name, appointment_date, appointment_time, procedure_type, notes, status)
        VALUES (:patient_id, :patient_name, :appointment_date, :appointment_time, :procedure_type, :notes, :status)
        """
      ),
      {
        "patient_id": patient.id,
        "patient_name": "Ahmed Ali",
        "appointment_date": datetime(2026, 7, 24, 9, 0, 0),
        "appointment_time": "09:00",
        "procedure_type": "فحص",
        "notes": "Initial note",
        "status": "Pending",
      },
    )
    db.commit()

    appointment = db.query(main.models.Appointment).first()
    assert appointment is not None

    new_date = datetime(2026, 8, 2, 14, 30, 0)
    result = main.update_appointment(
      appointment_id=appointment.id,
      appointment_update=main.AppointmentUpdate(
        appointment_date=new_date,
        appointment_time="14:30",
        description="مراجعة دورية بعد العلاج",
      ),
      db=db,
    )

    db.refresh(appointment)
    assert result.id == appointment.id
    assert appointment.appointment_date == new_date
    assert appointment.appointment_time == "14:30"
    assert appointment.notes == "مراجعة دورية بعد العلاج"
    finally:
    db.close()