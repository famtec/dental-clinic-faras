# -*- coding: utf-8 -*-
"""فحوص الطبيب المعالج على المريض -- patients.clinic_doctor_id (2026-09-24).

تُشغَّل على SQLite حقيقي عبر FastAPI TestClient -- نفس نمط
test_treatment_catalog.py.
"""
import os
import sys
import tempfile
from datetime import datetime, timedelta

DB_PATH = os.path.join(tempfile.mkdtemp(), "test_patient_doctor.db")
os.environ["DATABASE_URL"] = "sqlite:///" + DB_PATH.replace("\\", "/")
os.environ.setdefault("ADMIN_SECRET_KEY", "test-only")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine, inspect, text  # noqa: E402

import database  # noqa: E402
import main  # noqa: E402
import models  # noqa: E402

client = TestClient(main.app)

PASSED = []
FAILED = []


def check(name, condition, extra=""):
    print(("  ok   " if condition else "  FAIL ") + name)
    if condition:
        PASSED.append(name)
    else:
        FAILED.append("%s  %s" % (name, extra))


def make_user(email, tier="premium_plus"):
    db = database.SessionLocal()
    try:
        db.add(
            models.User(
                email=email,
                hashed_password="x",
                doctor_name="د. المدير",
                tier=tier,
                is_active=True,
                subscription_expires_at=datetime.utcnow() + timedelta(days=30),
            )
        )
        db.commit()
    finally:
        db.close()
    return {"Authorization": "Bearer " + main.create_session_token(email)}


def make_doctor(clinic_email, name):
    db = database.SessionLocal()
    try:
        doctor = models.ClinicDoctor(clinic_email=clinic_email, full_name=name, commission_percent=30)
        db.add(doctor)
        db.commit()
        db.refresh(doctor)
        return doctor.id
    finally:
        db.close()


def patient_row(headers, patient_id):
    for row in client.get("/api/patients", headers=headers).json():
        if row["id"] == patient_id:
            return row
    return None


# ------------------------------------------------------------------
# 0. ترحيل قاعدة قائمة بلا العمود: init_db يضيفه بلا لمس الصفوف
# ------------------------------------------------------------------
print("[0] ترحيل جدول patients قائم")
legacy_path = os.path.join(tempfile.mkdtemp(), "legacy.db")
legacy_engine = create_engine("sqlite:///" + legacy_path.replace("\\", "/"))
with legacy_engine.begin() as conn:
    conn.execute(text("CREATE TABLE patients (id INTEGER PRIMARY KEY, full_name VARCHAR, phone VARCHAR NOT NULL)"))
    conn.execute(text("INSERT INTO patients (id, full_name, phone) VALUES (1, 'قديم', '0999')"))
original_engine = database.engine
database.engine = legacy_engine
try:
    database.init_db()
finally:
    database.engine = original_engine
legacy_cols = {c["name"] for c in inspect(legacy_engine).get_columns("patients")}
check("العمود أُضيف لجدول قائم", "clinic_doctor_id" in legacy_cols, str(legacy_cols))
with legacy_engine.connect() as conn:
    row = conn.execute(text("SELECT full_name, clinic_doctor_id FROM patients WHERE id = 1")).first()
check("الصف القديم باقٍ وطبيبه NULL (= المدير)", row is not None and row[0] == "قديم" and row[1] is None, str(row))
# تشغيل ثانٍ لا يفشل بـ duplicate column
database.engine = legacy_engine
try:
    database.init_db()
    second_ok = True
except Exception as exc:  # noqa: BLE001
    second_ok = False
    print(exc)
finally:
    database.engine = original_engine
check("init_db ثانية على نفس القاعدة لا تفشل", second_ok)

# ------------------------------------------------------------------
database.init_db()
A = make_user("a@clinic.test")
B = make_user("b@clinic.test")
lina = make_doctor("a@clinic.test", "د. لينا مرعي")
fadi = make_doctor("a@clinic.test", "د. فادي نصّار")
other_clinic_doc = make_doctor("b@clinic.test", "د. من عيادة أخرى")

# ------------------------------------------------------------------
print("[1] الإنشاء")
r = client.post("/api/patients", headers=A, json={"full_name": "بلا طبيب", "phone": "0911"})
check("إنشاء بلا الحقل (عميل قديم) ينجح", r.status_code == 200, r.text)
legacy_client_patient = r.json()
check("بلا الحقل ⇒ clinic_doctor_id null", legacy_client_patient.get("clinic_doctor_id") is None, r.text)
check("بلا الحقل ⇒ clinic_doctor_name null", legacy_client_patient.get("clinic_doctor_name") is None, r.text)

r = client.post("/api/patients", headers=A, json={"full_name": "مريض لينا", "phone": "0912", "clinic_doctor_id": lina})
check("إنشاء بطبيب من العيادة", r.status_code == 200, r.text)
lina_patient = r.json()
check("الرد يحمل المعرّف", lina_patient.get("clinic_doctor_id") == lina, r.text)
check("الرد يحمل الاسم", lina_patient.get("clinic_doctor_name") == "د. لينا مرعي", r.text)

r = client.post("/api/patients", headers=A, json={"full_name": "صفر", "phone": "0913", "clinic_doctor_id": 0})
check("clinic_doctor_id=0 ⇒ المدير", r.status_code == 200 and r.json().get("clinic_doctor_id") is None, r.text)

r = client.post("/api/patients", headers=A, json={"full_name": "سرقة", "phone": "0914", "clinic_doctor_id": other_clinic_doc})
check("طبيب عيادة أخرى ⇒ 404", r.status_code == 404, r.text)
r = client.post("/api/patients", headers=A, json={"full_name": "وهمي", "phone": "0915", "clinic_doctor_id": 99999})
check("معرّف غير موجود ⇒ 404", r.status_code == 404, r.text)
names = [p["full_name"] for p in client.get("/api/patients", headers=A).json()]
check("الرفض لم يُنشئ مريضاً", "سرقة" not in names and "وهمي" not in names, str(names))

# ------------------------------------------------------------------
print("[2] القراءة")
row = patient_row(A, lina_patient["id"])
check("القائمة تحمل المعرّف والاسم", row and row["clinic_doctor_id"] == lina and row["clinic_doctor_name"] == "د. لينا مرعي", str(row))
row = patient_row(A, legacy_client_patient["id"])
check("القائمة: مريض المدير null/null", row and row["clinic_doctor_id"] is None and row["clinic_doctor_name"] is None, str(row))
r = client.get("/api/patients/%d" % lina_patient["id"], headers=A)
check("المريض المفرد يحمل الاسم", r.status_code == 200 and r.json().get("clinic_doctor_name") == "د. لينا مرعي", r.text)

# ------------------------------------------------------------------
print("[3] التعديل")
pid = lina_patient["id"]
r = client.put("/api/patients/%d" % pid, headers=A, json={"full_name": "مريض لينا", "phone": "0912", "medical_history": "x"})
check("تعديل بلا الحقل ينجح", r.status_code == 200, r.text)
check("تعديل بلا الحقل لا يمسّ الطبيب", r.json().get("clinic_doctor_id") == lina, r.text)
check("رد التعديل يحمل الاسم", r.json().get("clinic_doctor_name") == "د. لينا مرعي", r.text)

r = client.put("/api/patients/%d" % pid, headers=A, json={"clinic_doctor_id": fadi})
check("نقل المريض لطبيب آخر", r.status_code == 200 and r.json().get("clinic_doctor_id") == fadi, r.text)
check("الاسم الجديد في الرد", r.json().get("clinic_doctor_name") == "د. فادي نصّار", r.text)

r = client.put("/api/patients/%d" % pid, headers=A, json={"clinic_doctor_id": other_clinic_doc})
check("نقل لطبيب عيادة أخرى ⇒ 404", r.status_code == 404, r.text)
check("الرفض لم يغيّر الطبيب", patient_row(A, pid)["clinic_doctor_id"] == fadi)

r = client.put("/api/patients/%d" % pid, headers=A, json={"clinic_doctor_id": None})
check("null صريح ⇒ يعود للمدير", r.status_code == 200 and r.json().get("clinic_doctor_id") is None, r.text)

client.put("/api/patients/%d" % pid, headers=A, json={"clinic_doctor_id": lina})
r = client.put("/api/patients/%d/chart" % pid, headers=A, json={"chart_state": {"UR1": "filling"}})
check("حفظ المخطط يُبقي اسم الطبيب في الرد", r.status_code == 200 and r.json().get("clinic_doctor_name") == "د. لينا مرعي", r.text)

# ------------------------------------------------------------------
print("[4] العزل بين العيادات")
r = client.get("/api/patients", headers=B)
check("العيادة B لا ترى مرضى A", r.status_code == 200 and all(p["doctor_email"] == "b@clinic.test" for p in r.json()), r.text)
r = client.put("/api/patients/%d" % pid, headers=B, json={"clinic_doctor_id": other_clinic_doc})
check("B لا تعدّل مريض A", r.status_code == 404, r.text)

# ------------------------------------------------------------------
print("[5] حذف الطبيب يفكّ ربط مرضاه")
r = client.delete("/api/clinic-doctors/%d" % lina, headers=A)
check("حذف طبيب بلا سجل مالي", r.status_code == 200, r.text)
row = patient_row(A, pid)
check("مريضه عاد للمدير", row and row["clinic_doctor_id"] is None and row["clinic_doctor_name"] is None, str(row))

# ------------------------------------------------------------------
print()
print("نجح: %d   فشل: %d" % (len(PASSED), len(FAILED)))
for failure in FAILED:
    print("  FAIL", failure)
sys.exit(1 if FAILED else 0)
