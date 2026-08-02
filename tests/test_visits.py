import unittest
import database
import main


class VisitCreationTests(unittest.TestCase):
    def setUp(self):
        database.init_db()
        self.session = database.SessionLocal()
        self.session.query(main.models.Treatment).delete()
        self.session.query(main.models.Visit).delete()
        self.session.query(main.models.Appointment).delete()
        self.session.query(main.models.Patient).delete()
        self.session.commit()

        patient = main.models.Patient(full_name="Test Patient", phone="0500000000", gender="Male")
        self.session.add(patient)
        self.session.commit()
        self.session.refresh(patient)
        self.patient_id = patient.id

    def tearDown(self):
        self.session.close()

    def test_create_visit_saves_visit_and_treatments(self):
        payload = main.VisitCreate(
            patient_id=self.patient_id,
            diagnosis="Cavity treatment",
            total_cost=250.50,
            amount_paid=100.00,
            treatments=[
                main.TreatmentCreate(tooth_number=18, procedure="Filling", cost=150.00, notes="Composite filling")
            ],
        )

        result = main.create_visit(payload, db=self.session)

        self.assertEqual(result["patient_id"], self.patient_id)
        self.assertEqual(result["diagnosis"], "Cavity treatment")
        self.assertEqual(len(result["treatments"]), 1)
        self.assertEqual(result["treatments"][0]["procedure"], "Filling")


if __name__ == "__main__":
    unittest.main()
