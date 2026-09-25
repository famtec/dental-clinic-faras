# -*- coding: utf-8 -*-
"""فحوص أمان محرّك نسب الأطباء (2026-09-25).

تُشغَّل على SQLite حقيقي عبر FastAPI TestClient -- نفس نمط
test_patient_doctor.py. كل سيناريو هنا كان خللاً صامتاً مثبتاً قبل الإصلاح:
فاتورة التطبيق بلا طبيب، تصحيح الطبيب لا ينقل الأقساط، حذف فاتورة/مريض يمحو
نسباً مسلَّمة، دفعة تتجاوز الفاتورة، وقت الدفعة بتوقيت UTC، طبيب معطَّل.
"""
import os
import sys
import tempfile
from datetime import datetime, timedelta

DB_PATH = os.path.join(tempfile.mkdtemp(), "test_commission_safety.db")
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


EMAIL = "owner@commission.dev"
db = database.SessionLocal()
db.add(models.User(email=EMAIL, hashed_password="x", doctor_name="د. المدير", tier="premium_plus",
                   is_active=True, subscription_expires_at=datetime.utcnow() + timedelta(days=30)))
db.commit()
db.close()
H = {"Authorization": "Bearer " + main.create_session_token(EMAIL)}


def doctor(name, pct):
    r = client.post("/api/clinic-doctors", headers=H, json={"full_name": name, "commission_percent": pct})
    assert r.status_code in (200, 201), r.text
    return r.json()["id"]


def patient(name, doc=None):
    body = {"full_name": name, "phone": "0999"}
    if doc:
        body["clinic_doctor_id"] = doc
    r = client.post("/api/patients", headers=H, json=body)
    assert r.status_code in (200, 201), r.text
    return r.json()["id"]


def invoice(pid, total, **extra):
    r = client.post(f"/api/patients/{pid}/invoices", headers=H, json={"title": "علاج", "total_cost": total, **extra})
    return r


def pay(pid, inv, amount, **extra):
    return client.post(f"/api/patients/{pid}/invoices/{inv}/payments", headers=H, json={"amount": amount, **extra})


def share(doc_id):
    rows = client.get("/api/clinic-doctors?all_time=true", headers=H).json()
    d = next(x for x in rows if x["id"] == doc_id)
    return d["total_doctor_share"], d["balance_due"]


def payments_of(inv):
    s = database.SessionLocal()
    try:
        return s.query(models.FinancialTransaction).filter(models.FinancialTransaction.invoice_id == inv).all()
    finally:
        s.close()


print("1) الحساب الأساسي (لم يتغيّر)")
sami = doctor("سامي", 40)
p = patient("أ", sami)
inv = invoice(p, 100000, clinic_doctor_id=sami).json()["id"]
pay(p, inv, 30000)
pay(p, inv, 70000)
check("قسطان بنسبة 40٪ = 40000", share(sami)[0] == 40000)

print("2) الفاتورة بلا طبيب صريح تُنسب لطبيب المريض")
lina = doctor("لينا", 30)
p2 = patient("ب", lina)
r = invoice(p2, 10000)                                   # كما يرسل التطبيق القديم
check("الفاتورة بلا الحقل ترث طبيب المريض", r.json().get("clinic_doctor_id") == lina, r.text)
pay(p2, r.json()["id"], 10000)
check("والنسبة تُحسب للطبيب (3000)", share(lina)[0] == 3000)
r = invoice(p2, 5000, clinic_doctor_id=None)             # اختيار «الطبيب المدير» صراحةً
check("null صريحة تبقى للطبيب المدير", r.json().get("clinic_doctor_id") is None, r.text)

print("3) الطبيب المعطَّل")
old = doctor("متقاعد", 50)
p3 = patient("ج", old)
client.patch(f"/api/clinic-doctors/{old}", headers=H, json={"is_active": False})
r = invoice(p3, 1000, clinic_doctor_id=old)
check("فاتورة جديدة باسم طبيب معطَّل مرفوضة", r.status_code == 400, r.text)
r = invoice(p3, 1000)
check("ومريضه تذهب فاتورته للمدير بدل الطبيب المعطَّل", r.status_code in (200, 201) and r.json().get("clinic_doctor_id") is None, r.text)

print("4) تصحيح طبيب الفاتورة مع نقل الأقساط")
omar = doctor("عمر", 40)
p4 = patient("د")
inv4 = invoice(p4, 100000, clinic_doctor_id=sami).json()["id"]
pay(p4, inv4, 50000)
sami_before = share(sami)[0]
r = client.patch(f"/api/patients/{p4}/invoices/{inv4}", headers=H,
                 json={"total_cost": 100000, "clinic_doctor_id": omar, "apply_to_existing_payments": True})
check("التصحيح ينجح", r.status_code == 200, r.text)
check("القسط السابق انتقل لعمر (20000)", share(omar)[0] == 20000, str(share(omar)))
check("وخرج من سامي", share(sami)[0] == sami_before - 20000, str(share(sami)))
check("الدفعة نفسها صارت باسم عمر", all(t.clinic_doctor_id == omar for t in payments_of(inv4)))
p4b = patient("هـ")
inv4b = invoice(p4b, 10000, clinic_doctor_id=sami).json()["id"]
pay(p4b, inv4b, 5000)
before = share(sami)[0]
client.patch(f"/api/patients/{p4b}/invoices/{inv4b}", headers=H, json={"total_cost": 10000, "clinic_doctor_id": omar})
check("بلا النقل: القسط السابق يبقى للطبيب الأول (سلوك التغيير المستقبلي)", share(sami)[0] == before)

print("5) حذف فاتورة عليها نسب")
nour = doctor("نور", 50)
p5 = patient("و", nour)
inv5 = invoice(p5, 100000).json()["id"]
pay(p5, inv5, 100000)
client.post(f"/api/clinic-doctors/{nour}/payouts", headers=H, json={"amount": 50000})
r = client.delete(f"/api/patients/{p5}/invoices/{inv5}", headers=H)
check("الحذف بلا تأكيد مرفوض 409 برسالة الأثر", r.status_code == 409 and "نور" in r.json()["detail"], r.text)
check("ولم يُحذف شيء", share(nour)[0] == 50000)

print("6) حذف مريض له نسب")
r = client.delete(f"/api/patients/{p5}", headers=H)
check("حذف المريض مرفوض 409", r.status_code == 409 and "نور" in r.json()["detail"], r.text)
r = client.delete(f"/api/patients/{p5}/invoices/{inv5}?confirm_doctor_earnings=true", headers=H)
check("حذف الفاتورة بعد التأكيد ينجح", r.status_code == 200, r.text)
check("وأثره الموثَّق: رصيد نور −50000", share(nour)[1] == -50000, str(share(nour)))
r = client.delete(f"/api/patients/{p5}", headers=H)
check("بعدها يُحذف المريض", r.status_code == 200, r.text)
p6 = patient("مريض بلا نسب")
inv6 = invoice(p6, 1000, clinic_doctor_id=None).json()["id"]
pay(p6, inv6, 1000)
check("مريض دفعاته للمدير فقط يُحذف مباشرة", client.delete(f"/api/patients/{p6}", headers=H).status_code == 200)

print("7) الدفعة لا تتجاوز المتبقي")
p7 = patient("ز", sami)
inv7 = invoice(p7, 50000).json()["id"]
r = pay(p7, inv7, 80000)
check("دفعة 80000 على فاتورة 50000 مرفوضة", r.status_code == 400 and "المتبقي" in r.json()["detail"], r.text)
check("دفعة 30000 تُقبل", pay(p7, inv7, 30000).status_code == 200)
check("دفعة تتجاوز الـ20000 الباقية مرفوضة", pay(p7, inv7, 20001).status_code == 400)
check("دفعة تساوي الباقي بالضبط تُقبل", pay(p7, inv7, 20000).status_code == 200)
first = payments_of(inv7)[0].id
r = client.put(f"/api/finance/transaction/{first}", headers=H, json={"amount": 30001, "description": "x"})
check("تعديل دفعة لتتجاوز الفاتورة مرفوض", r.status_code == 400, r.text)
r = client.put(f"/api/finance/transaction/{first}", headers=H, json={"amount": 25000, "description": "x"})
check("تعديل دفعة ضمن الفاتورة مقبول", r.status_code == 200, r.text)
r = client.post("/api/finance", headers=H, json={"amount": 999999, "description": "x", "type": "income",
                                                 "patient_id": p7, "invoice_id": inv7})
check("دفعة زائدة عبر مسار المالية العام مرفوضة", r.status_code == 400, r.text)
r = client.patch(f"/api/patients/{p7}/invoices/{inv7}", headers=H, json={"total_cost": 10000})
check("تخفيض تكلفة الفاتورة تحت المدفوع مرفوض", r.status_code == 400, r.text)

print("8) وقت الدفعة بتوقيت دمشق")
p8 = patient("ح")
inv8 = invoice(p8, 100, clinic_doctor_id=None).json()["id"]
pay(p8, inv8, 100)
stored = payments_of(inv8)[0].created_at
drift = abs((main._damascus_now() - stored).total_seconds())
check("الدفعة مخزّنة بتوقيت دمشق (فرق أقل من دقيقة)", drift < 60, f"{drift/3600:.1f} ساعة")

print()
print("passed:", len(PASSED), " failed:", len(FAILED))
for f in FAILED:
    print("  -", f)
sys.exit(1 if FAILED else 0)
