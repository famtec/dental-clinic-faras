# -*- coding: utf-8 -*-
"""فحوص حسابات الأطباء المساعدين (2026-09-25).

تُشغَّل على SQLite حقيقي عبر FastAPI TestClient -- نفس نمط
test_patient_doctor.py. تغطي: إنشاء حساب الدخول والتحقق منه، دخول المساعد،
قائمة المسارات المسموحة (ما عداها 403)، حصر البيانات بمرضاه ومواعيده،
فرض اسمه على فواتيره، طرد الجلسات عند تغيير كلمة السرّ أو الإيقاف.
"""
import os
import sys
import tempfile
from datetime import datetime, timedelta

DB_PATH = os.path.join(tempfile.mkdtemp(), "test_staff_accounts.db")
os.environ["DATABASE_URL"] = "sqlite:///" + DB_PATH.replace("\\", "/")
os.environ.setdefault("ADMIN_SECRET_KEY", "test-only")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient  # noqa: E402

import database  # noqa: E402
import main  # noqa: E402
import models  # noqa: E402

database.init_db()
client = TestClient(main.app)

PASSED = []
FAILED = []


def check(name, condition, extra=""):
    print(("  ok   " if condition else "  FAIL ") + name)
    (PASSED if condition else FAILED).append(name if condition else "%s  %s" % (name, extra))


def make_owner(email, tier="premium_plus"):
    db = database.SessionLocal()
    try:
        db.add(models.User(email=email, hashed_password=main.hash_password("owner-pass"), doctor_name="د. المدير",
                           tier=tier, is_active=True, clinic_name="عيادة الاختبار",
                           subscription_expires_at=datetime.utcnow() + timedelta(days=30)))
        db.commit()
    finally:
        db.close()
    return {"Authorization": "Bearer " + main.create_session_token(email)}


OWNER = "owner@staff.dev"
O = make_owner(OWNER)
OTHER = make_owner("other@staff.dev")


def doctor(name, pct=40, headers=O):
    r = client.post("/api/clinic-doctors", headers=headers, json={"full_name": name, "commission_percent": pct})
    assert r.status_code in (200, 201), r.text
    return r.json()["id"]


def patient(name, doc=None, headers=O):
    body = {"full_name": name, "phone": "0999"}
    if doc is not None:
        body["clinic_doctor_id"] = doc
    r = client.post("/api/patients", headers=headers, json=body)
    assert r.status_code in (200, 201), r.text
    return r.json()["id"]


def login(email, password):
    return client.post("/api/auth/login", json={"email": email, "password": password})


sami = doctor("د. سامي")
lina = doctor("د. لينا")
p_sami = patient("مريض سامي", sami)
p_lina = patient("مريض لينا", lina)
p_owner = patient("مريض المدير")
other_patient = patient("مريض عيادة أخرى", headers=OTHER)

print("1) إنشاء حساب الدخول (المالك)")
r = client.put(f"/api/clinic-doctors/{sami}/login", headers=O, json={"login_email": "bad-email"})
check("بريد غير صالح مرفوض", r.status_code == 400, r.text)
r = client.put(f"/api/clinic-doctors/{sami}/login", headers=O, json={"login_email": OWNER, "password": "123456"})
check("بريد حساب عيادة مرفوض", r.status_code == 400, r.text)
r = client.put(f"/api/clinic-doctors/{sami}/login", headers=O, json={"login_email": "sami@staff.dev"})
check("حساب جديد بلا كلمة سرّ مرفوض", r.status_code == 400, r.text)
r = client.put(f"/api/clinic-doctors/{sami}/login", headers=O, json={"login_email": "sami@staff.dev", "password": "123"})
check("كلمة سرّ قصيرة مرفوضة", r.status_code == 400, r.text)
r = client.put(f"/api/clinic-doctors/{sami}/login", headers=O, json={"login_email": "Sami@Staff.dev", "password": "sami-pass"})
check("إنشاء الحساب ينجح", r.status_code == 200 and r.json()["login_enabled"] and r.json()["login_email"] == "sami@staff.dev", r.text)
r = client.put(f"/api/clinic-doctors/{lina}/login", headers=O, json={"login_email": "sami@staff.dev", "password": "lina-pass"})
check("بريد طبيب آخر مرفوض", r.status_code == 400, r.text)

print("2) دخول الطبيب المساعد")
r = login("sami@staff.dev", "wrong")
check("كلمة سرّ خاطئة 401", r.status_code == 401, r.text)
r = login("SAMI@staff.dev", "sami-pass")
check("الدخول ينجح بدور staff", r.status_code == 200 and r.json().get("role") == "staff" and r.json().get("clinic_doctor_id") == sami, r.text)
S = {"Authorization": "Bearer " + r.json()["token"]}
r = login(OWNER, "owner-pass")
check("دخول المالك يحمل دور owner", r.status_code == 200 and r.json().get("role") == "owner", r.text)
r = client.get("/api/auth/profile", headers=S)
check("الملف الشخصي للمساعد", r.status_code == 200 and r.json().get("role") == "staff" and r.json().get("doctor_name") == "د. سامي", r.text)

print("3) المرضى: مرضاه وحده")
ids = {p["id"] for p in client.get("/api/patients", headers=S).json()}
check("القائمة فيها مريضه وحده", ids == {p_sami}, str(ids))
check("مريض زميله 404", client.get(f"/api/patients/{p_lina}", headers=S).status_code == 404)
check("مريض المدير 404", client.get(f"/api/patients/{p_owner}", headers=S).status_code == 404)
check("مريض عيادة أخرى 404", client.get(f"/api/patients/{other_patient}", headers=S).status_code == 404)
check("تعديل مريض زميله 404", client.put(f"/api/patients/{p_lina}", headers=S, json={"full_name": "x"}).status_code == 404)
check("مخطط مريض زميله 404", client.put(f"/api/patients/{p_lina}/chart", headers=S, json={"chart_state": {}}).status_code == 404)
check("فواتير مريض زميله 404", client.get(f"/api/patients/{p_lina}/invoices", headers=S).status_code == 404)
r = client.post("/api/patients", headers=S, json={"full_name": "مريض جديد لسامي", "phone": "0911", "clinic_doctor_id": lina})
new_p = r.json()
check("المريض الذي يضيفه يُنسب له حتماً", r.status_code in (200, 201) and new_p.get("clinic_doctor_id") == sami, r.text)
r = client.put(f"/api/patients/{p_sami}", headers=S, json={"full_name": "مريض سامي", "clinic_doctor_id": lina})
check("لا ينقل مريضه لطبيب آخر", r.status_code == 200 and r.json().get("clinic_doctor_id") == sami, r.text)
db = database.SessionLocal()
try:
    audited = db.query(models.Patient).filter(models.Patient.id == new_p["id"]).first().created_by_staff_id
finally:
    db.close()
check("سجل من أدخل المريض", audited == sami, str(audited))

print("4) الفواتير")
r = client.post(f"/api/patients/{p_sami}/invoices", headers=S, json={"title": "حشوة", "total_cost": 50000, "clinic_doctor_id": lina})
check("فاتورته تُنسب له حتماً", r.status_code == 201 and r.json().get("clinic_doctor_id") == sami, r.text)
inv = r.json()["id"]
check("تسجيل دفعة ممنوع (الدفعة الثانية)", client.post(f"/api/patients/{p_sami}/invoices/{inv}/payments", headers=S, json={"amount": 1000}).status_code == 403)
check("تعديل الفاتورة ممنوع", client.patch(f"/api/patients/{p_sami}/invoices/{inv}", headers=S, json={"total_cost": 1}).status_code == 403)
check("حذف الفاتورة ممنوع", client.delete(f"/api/patients/{p_sami}/invoices/{inv}", headers=S).status_code == 403)
check("حذف المريض ممنوع", client.delete(f"/api/patients/{p_sami}", headers=S).status_code == 403)
lina_inv = client.post(f"/api/patients/{p_lina}/invoices", headers=O, json={"title": "x", "total_cost": 100, "clinic_doctor_id": lina}).json()["id"]
check("مواد فاتورة زميله ممنوعة", client.post(f"/api/patients/{p_lina}/invoices/{lina_inv}/materials", headers=S, json=[]).status_code in (403, 404, 422))

print("5) المسارات الممنوعة")
for method, path in [("GET", "/api/finance/summary"), ("GET", "/api/finance/transactions"), ("POST", "/api/finance"),
                     ("GET", "/api/patients/stats"), ("PATCH", f"/api/clinic-doctors/{sami}"),
                     ("POST", f"/api/clinic-doctors/{sami}/payouts"), ("PUT", f"/api/clinic-doctors/{sami}/login"),
                     ("POST", "/api/inventory"), ("POST", "/api/treatment-catalog"), ("GET", "/api/auth/booking-settings"),
                     ("PUT", "/api/auth/profile"), ("POST", "/api/auth/register-device"), ("GET", "/api/finance/backup"),
                     ("PUT", "/api/appointments/1/respond"), ("GET", "/api/recall/due-patients")]:
    r = client.request(method, path, headers=S, json={})
    check(f"{method} {path} → 403", r.status_code == 403, str(r.status_code))
check("قراءة المخزن مسموحة", client.get("/api/inventory", headers=S).status_code == 200)
check("قراءة لائحة الأسعار مسموحة", client.get("/api/treatment-catalog", headers=S).status_code == 200)

print("6) أطباء العيادة وكشف الحساب")
rows = client.get("/api/clinic-doctors", headers=S).json()
check("القائمة بلا نسب ولا أرصدة ولا حسابات دخول",
      all(d["commission_percent"] == 0 and d["balance_due"] == 0 and not d.get("login_email") for d in rows), str(rows)[:200])
check("كشف حسابه مسموح", client.get(f"/api/clinic-doctors/{sami}/statement?all_time=true", headers=S).status_code == 200)
check("كشف زميله 404", client.get(f"/api/clinic-doctors/{lina}/statement?all_time=true", headers=S).status_code == 404)
owner_rows = client.get("/api/clinic-doctors?all_time=true", headers=O).json()
check("المالك يرى حساب الدخول", any(d.get("login_email") == "sami@staff.dev" for d in owner_rows))

print("7) المواعيد")
tomorrow = (datetime.now() + timedelta(days=1)).date().isoformat()
r = client.post("/api/appointments", headers=O, json={"patient_id": p_lina, "date": tomorrow, "time": "10:00",
                                                      "description": "x", "clinic_doctor_id": lina})
lina_appt = r.json()["id"]
r = client.post("/api/appointments", headers=S, json={"patient_id": p_sami, "date": tomorrow, "time": "11:00",
                                                      "description": "فحص", "clinic_doctor_id": lina})
check("موعده باسمه حتماً", r.status_code == 201 and r.json().get("clinic_doctor_id") == sami, r.text)
own_appt = r.json()["id"]
ids = {a["id"] for a in client.get("/api/appointments", headers=S).json()}
check("يرى مواعيده وحده", ids == {own_appt}, str(ids))
check("لا موعد لمريض زميله", client.post("/api/appointments", headers=S, json={"patient_id": p_lina, "date": tomorrow, "time": "12:00", "description": "x"}).status_code == 404)
check("تعديل موعد زميله 404", client.put(f"/api/appointments/{lina_appt}", headers=S, json={"time": "13:00"}).status_code == 404)
check("حالة موعد زميله 404", client.put(f"/api/appointments/{lina_appt}/status", headers=S, json={"status": "checked_in"}).status_code == 404)
check("حذف موعد زميله 404", client.delete(f"/api/appointments/{lina_appt}", headers=S).status_code == 404)
check("حالة موعده تعمل", client.put(f"/api/appointments/{own_appt}/status", headers=S, json={"status": "checked_in"}).status_code == 200)

print("8) الوصفات")
check("وصفة لمريض زميله 404", client.post("/api/prescriptions", headers=S, json={"patient_id": p_lina, "medications": "a", "instructions": "b"}).status_code == 404)
check("وصفة لمريضه تنجح", client.post("/api/prescriptions", headers=S, json={"patient_id": p_sami, "medications": "a", "instructions": "b"}).status_code == 201)
check("وصفات مريض زميله 404", client.get(f"/api/prescriptions/patient/{p_lina}", headers=S).status_code == 404)

print("9) رؤية كل المرضى (خيار المالك)")
client.put(f"/api/clinic-doctors/{sami}/login", headers=O, json={"login_email": "sami@staff.dev", "can_view_all_patients": True})
S2 = {"Authorization": "Bearer " + login("sami@staff.dev", "sami-pass").json()["token"]}
ids = {p["id"] for p in client.get("/api/patients", headers=S2).json()}
check("يرى كل مرضى العيادة", {p_sami, p_lina, p_owner}.issubset(ids), str(ids))
r = client.post(f"/api/patients/{p_lina}/invoices", headers=S2, json={"title": "y", "total_cost": 100})
check("وفاتورته على مريض زميله باسمه هو", r.status_code == 201 and r.json().get("clinic_doctor_id") == sami, r.text)
check("المريض في عيادة أخرى يبقى 404", client.get(f"/api/patients/{other_patient}", headers=S2).status_code == 404)

print("10) طرد الجلسات")
import time as _time
_time.sleep(1.1)
client.put(f"/api/clinic-doctors/{sami}/login", headers=O, json={"login_email": "sami@staff.dev", "password": "new-pass", "can_view_all_patients": True})
check("تغيير كلمة السرّ يطرد الجلسة القديمة", client.get("/api/patients", headers=S2).status_code == 401)
check("كلمة السرّ القديمة لا تعمل", login("sami@staff.dev", "sami-pass").status_code == 401)
S3 = {"Authorization": "Bearer " + login("sami@staff.dev", "new-pass").json()["token"]}
check("الجديدة تعمل", client.get("/api/patients", headers=S3).status_code == 200)
_time.sleep(1.1)
client.delete(f"/api/clinic-doctors/{sami}/login", headers=O)
check("الإيقاف يطرد الجلسة", client.get("/api/patients", headers=S3).status_code == 401)
check("والدخول موقوف 403", login("sami@staff.dev", "new-pass").status_code == 403)
client.put(f"/api/clinic-doctors/{sami}/login", headers=O, json={"login_email": "sami@staff.dev", "login_enabled": True})
S4 = {"Authorization": "Bearer " + login("sami@staff.dev", "new-pass").json()["token"]}
_time.sleep(1.1)
client.patch(f"/api/clinic-doctors/{sami}", headers=O, json={"is_active": False})
check("تعطيل الطبيب يطرده", client.get("/api/patients", headers=S4).status_code == 401)

print("11) باقة العيادة")
lina_login = client.put(f"/api/clinic-doctors/{lina}/login", headers=O, json={"login_email": "lina@staff.dev", "password": "lina-pass"})
db = database.SessionLocal()
try:
    owner = db.query(models.User).filter(models.User.email == OWNER).first()
    owner.tier = "premium"
    db.commit()
finally:
    db.close()
check("بلا باقة العيادات لا دخول للمساعد", login("lina@staff.dev", "lina-pass").status_code == 403)
check("المالك لم يتأثر بشيء", client.get("/api/patients", headers=O).status_code == 200)

print()
print("passed:", len(PASSED), " failed:", len(FAILED))
for f in FAILED:
    print("  -", f)
sys.exit(1 if FAILED else 0)
