import main
from fastapi.testclient import TestClient

client = TestClient(main.app)

session = main.database.SessionLocal()
try:
    session.query(main.models.Treatment).delete(synchronize_session=False)
    session.query(main.models.Visit).delete(synchronize_session=False)
    session.query(main.models.Patient).delete(synchronize_session=False)
    session.commit()
finally:
    session.close()

create_resp = client.post(
    '/api/patients',
    json={
        'doctor_name': 'Dr. Ali',
        'full_name': 'Ahmed Hassan',
        'phone': '0500000000',
        'medical_history': 'No known allergies'
    }
)
print('CREATE', create_resp.status_code, create_resp.json())
patient_id = create_resp.json()['id']

update_resp = client.put(
    f'/api/patients/{patient_id}',
    json={
        'doctor_name': 'Dr. Sara',
        'full_name': 'Ahmed Hassan Updated',
        'phone': '0555555555',
        'medical_history': 'Updated history'
    }
)
print('UPDATE', update_resp.status_code, update_resp.json())

delete_resp = client.delete(f'/api/patients/{patient_id}')
print('DELETE', delete_resp.status_code, delete_resp.json())
