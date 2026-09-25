# -*- coding: utf-8 -*-
"""فحوص الدفعة الثانية (2026-09-25): دفعات الأطباء المساعدين بانتظار تأكيد
المدير، وإقفال الشهر المالي.

تُشغَّل على SQLite حقيقي عبر FastAPI TestClient -- نفس نمط
test_staff_accounts.py. القاعدة التي تُفحص في كل خطوة: الدفعة المعلّقة لا
تمسّ أي رقم (المدفوع، المالية، النسب) قبل التأكيد، والشهر المقفل لا تُمسّ
حركاته من أي مسار.
"""
import os
import sys
import tempfile
from datetime import datetime, timedelta

DB_PATH = os.path.join(tempfile.mkdtemp(), "test_pending_payments.db")
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


OWNER = "owner@pending.dev"
db = database.SessionLocal()
db.add(models.User(email=OWNER, hashed_password=main.hash_password("owner-pass"), doctor_name="د. المدير",
                   tier="premium_plus", is_active=True, clinic_name="عيادة الاختبار",
                   subscription_expires_at=datetime.utcnow() + timedelta(days=30)))
db.commit()
db.close()
O = {"Authorization": "Bearer " + main.create_session_token(OWNER)}


def post(url, headers, body=None):
    return client.post(url, headers=headers, json=body if body is not None else {})


def doctor(name, pct):
    r = post("/api/clinic-doctors", O, {"full_name": name, "commission_percent": pct})
    assert r.status_code in (200, 201), r.text
    return r.json()["id"]


def patient(name, doc=None):
    body = {"full_name": name, "phone": "0999"}
    if doc is not None:
        body["clinic_doctor_id"] = doc
    r = post("/api/patients", O, body)
    assert r.status_code in (200, 201), r.text
    return r.json()["id"]


def invoice(pid, cost, doc=None, headers=O):
    body = {"title": "علاج", "total_cost": cost}
    if doc is not None:
        body["clinic_doctor_id"] = doc
    r = post(f"/api/patients/{pid}/invoices", headers, body)
    assert r.status_code in (200, 201), r.text
    return r.json()["id"]


def invoices_of(pid, headers=O):
    return {i["id"]: i for i in client.get(f"/api/patients/{pid}/invoices", headers=headers).json()}


def summary(year=None, month=None):
    params = {"all_time": "true"} if year is None else {"year": year, "month": month}
    return client.get("/api/finance/summary", headers=O, params=params).json()


def doctor_row(doc_id):
    rows = client.get("/api/clinic-doctors", headers=O, params={"all_time": "true", "include_inactive": "true"}).json()
    return next(d for d in rows if d["id"] == doc_id)


sami = doctor("د. سامي", 40)
lina = doctor("د. لينا", 30)
for doc_id, mail in ((sami, "sami@pending.dev"), (lina, "lina@pending.dev")):
    r = client.put(f"/api/clinic-doctors/{doc_id}/login", headers=O,
                   json={"login_email": mail, "password": "pass-1234"})
    assert r.status_code == 200, r.text
S = {"Authorization": "Bearer " + client.post("/api/auth/login", json={"email": "sami@pending.dev", "password": "pass-1234"}).json()["token"]}
L = {"Authorization": "Bearer " + client.post("/api/auth/login", json={"email": "lina@pending.dev", "password": "pass-1234"}).json()["token"]}

p_sami = patient("مريض سامي", sami)
p_lina = patient("مريض لينا", lina)
inv_sami = invoice(p_sami, 100000, sami)
inv_lina = invoice(p_lina, 50000, lina)

print("1) تسجيل دفعة معلّقة")
url = f"/api/patients/{p_sami}/invoices/{inv_sami}/pending-payments"
check("المدير لا يسجّل دفعة معلّقة (400)", post(url, O, {"amount": 1000}).status_code == 400)
check("مبلغ صفر مرفوض", post(url, S, {"amount": 0}).status_code == 400)
check("مبلغ أكبر من المتبقي مرفوض", post(url, S, {"amount": 100001}).status_code == 400)
check("فاتورة طبيب آخر: مريضه مخفي (404)",
      post(f"/api/patients/{p_lina}/invoices/{inv_lina}/pending-payments", S, {"amount": 1000}).status_code == 404)
r = post(url, S, {"amount": 40000, "description": "قسط أول"})
check("المساعد يسجّل دفعة معلّقة (201)", r.status_code == 201 and r.json()["status"] == "pending", r.text)
pending1 = r.json()["id"]
check("المتبقي ناقص المعلّق يحدّ الدفعة التالية",
      post(url, S, {"amount": 60001}).status_code == 400)
r = post(url, S, {"amount": 20000})
check("دفعة ثانية ضمن المتاح", r.status_code == 201, r.text)
pending2 = r.json()["id"]

print("2) المعلّق لا يمسّ أي رقم")
inv = invoices_of(p_sami)[inv_sami]
check("المدفوع ما زال صفراً", inv["paid_amount"] == 0 and inv["remaining_amount"] == 100000, str(inv))
check("الفاتورة تعرض الدفعتين المعلّقتين", len(inv["pending_payments"]) == 2 and inv["pending_amount"] == 60000, str(inv.get("pending_payments")))
check("اسم المساعد على الدفعة المعلّقة", inv["pending_payments"][0]["staff_name"] == "د. سامي")
check("دخل المالية لم يتغيّر", summary()["total_income"] == 0)
check("حصة سامي صفر", doctor_row(sami)["balance_due"] == 0)
check("المساعد يرى المعلّق على فاتورته", len(invoices_of(p_sami, S)[inv_sami]["pending_payments"]) == 2)

print("3) القوائم والعدّاد")
owner_list = client.get("/api/pending-payments", headers=O).json()
check("المدير يرى المعلّقة كلها", {p["id"] for p in owner_list} == {pending1, pending2})
check("العدّاد للمدير", client.get("/api/pending-payments/count", headers=O).json() == {"count": 2, "amount": 60000.0})
check("لينا لا ترى دفعات سامي", client.get("/api/pending-payments", headers=L).json() == [])
check("عدّاد لينا صفر", client.get("/api/pending-payments/count", headers=L).json()["count"] == 0)
check("حالة غير معروفة 400", client.get("/api/pending-payments", headers=O, params={"status": "x"}).status_code == 400)

print("4) صلاحيات المراجعة")
check("المساعد لا يؤكّد (403)", post(f"/api/pending-payments/{pending1}/confirm", S).status_code == 403)
check("المساعد لا يرفض (403)", post(f"/api/pending-payments/{pending1}/reject", S).status_code == 403)
check("لينا لا تلغي دفعة سامي (404)", client.delete(f"/api/pending-payments/{pending2}", headers=L).status_code == 404)
check("المدير لا يحذف بل يرفض (400)", client.delete(f"/api/pending-payments/{pending2}", headers=O).status_code == 400)
check("المساعد لا يقفل الشهر (403)", post("/api/finance/closed-periods", S, {"year": 2026, "month": 1}).status_code == 403)

print("5) منع حذف فاتورة/مريض عليه معلّق")
r = client.delete(f"/api/patients/{p_sami}/invoices/{inv_sami}", headers=O)
check("حذف الفاتورة ممنوع (409)", r.status_code == 409 and "بانتظار تأكيدك" in r.json()["detail"], r.text)
r = client.delete(f"/api/patients/{p_sami}", headers=O)
check("حذف المريض ممنوع (409)", r.status_code == 409 and "بانتظار تأكيدك" in r.json()["detail"], r.text)

print("6) التأكيد")
db = database.SessionLocal()
recorded_at = db.get(models.PendingPayment, pending1).recorded_at
db.close()
r = post(f"/api/pending-payments/{pending1}/confirm", O)
check("التأكيد ينجح", r.status_code == 200 and r.json()["status"] == "confirmed" and r.json()["transaction_id"], r.text)
check("تأكيد ثانٍ مرفوض", post(f"/api/pending-payments/{pending1}/confirm", O).status_code == 400)
inv = invoices_of(p_sami)[inv_sami]
check("المدفوع صار 40000", inv["paid_amount"] == 40000 and inv["remaining_amount"] == 60000, str(inv))
check("بقيت دفعة معلّقة واحدة", len(inv["pending_payments"]) == 1 and inv["pending_amount"] == 20000)
check("دخل المالية 40000", summary()["total_income"] == 40000)
check("حصة سامي 40% = 16000", doctor_row(sami)["balance_due"] == 16000, str(doctor_row(sami)))
db = database.SessionLocal()
tx = db.query(models.FinancialTransaction).filter(models.FinancialTransaction.invoice_id == inv_sami).one()
check("تاريخ الدفعة = وقت تسجيل المساعد", tx.created_at == recorded_at, f"{tx.created_at} vs {recorded_at}")
check("الدفعة منسوبة لسامي ومعلَّم منشئها", tx.clinic_doctor_id == sami and tx.created_by_staff_id == sami)
db.close()
statement = client.get(f"/api/clinic-doctors/{sami}/statement", headers=S, params={"all_time": "true"}).json()
check("كشف سامي يحوي الدفعة المؤكدة", round(sum(e["doctor_share"] for e in statement["earnings"])) == 16000, str(statement.get("earnings")))

print("7) الرفض والإلغاء")
r = post(f"/api/pending-payments/{pending2}/reject", O, {"note": "لم يصل المبلغ"})
check("الرفض بسبب", r.status_code == 200 and r.json()["status"] == "rejected" and r.json()["review_note"] == "لم يصل المبلغ", r.text)
check("المرفوضة لا تُؤكَّد بعدها", post(f"/api/pending-payments/{pending2}/confirm", O).status_code == 400)
mine = {p["id"]: p for p in client.get("/api/pending-payments", headers=S, params={"status": "all"}).json()}
check("المساعد يرى الرفض وسببه", mine[pending2]["status"] == "rejected" and mine[pending2]["review_note"] == "لم يصل المبلغ")
check("المرفوضة لا تُلغى", client.delete(f"/api/pending-payments/{pending2}", headers=S).status_code == 400)
check("لا معلّق على الفاتورة", invoices_of(p_sami)[inv_sami]["pending_payments"] == [])
r = post(url, S, {"amount": 5000})
p3 = r.json()["id"]
check("المساعد يلغي دفعته قبل المراجعة", client.delete(f"/api/pending-payments/{p3}", headers=S).status_code == 200)
check("الملغاة اختفت", client.get("/api/pending-payments/count", headers=O).json()["count"] == 0)

print("8) تأكيد يتجاوز المتبقي يُرفض ويبقى معلّقاً")
r = post(url, S, {"amount": 60000})
p4 = r.json()["id"]
r = post(f"/api/patients/{p_sami}/invoices/{inv_sami}/payments", O, {"amount": 30000})
check("المدير سجّل 30000 مباشرة", r.status_code == 200, r.text)
r = post(f"/api/pending-payments/{p4}/confirm", O)
check("التأكيد مرفوض لتجاوز المتبقي", r.status_code == 400 and "أكبر من المتبقي" in r.json()["detail"], r.text)
check("بقيت معلّقة", client.get("/api/pending-payments/count", headers=O).json()["count"] == 1)
check("الرفض بلا سبب مقبول", post(f"/api/pending-payments/{p4}/reject", O).status_code == 200)

print("9) إقفال الشهر")
now = main._damascus_now()
cur_year, cur_month = now.year, now.month
prev_month_date = datetime(cur_year, cur_month, 1) - timedelta(days=1)
py, pm = prev_month_date.year, prev_month_date.month
old_moment = datetime(py, pm, 15, 12, 0)
check("الشهر الحالي لا يُقفل", post("/api/finance/closed-periods", O, {"year": cur_year, "month": cur_month}).status_code == 400)
check("شهر غير صالح", post("/api/finance/closed-periods", O, {"year": 2026, "month": 13}).status_code == 400)

# حركات بتاريخ الشهر السابق قبل إقفاله
r = post(f"/api/patients/{p_sami}/invoices/{inv_sami}/payments", O,
         {"amount": 10000, "transaction_date": old_moment.isoformat()})
check("دفعة بتاريخ الشهر السابق قبل الإقفال", r.status_code == 200, r.text)
r = post("/api/finance/expenses", O, {"amount": 2000, "description": "إيجار", "type": "expense",
                                        "transaction_date": old_moment.isoformat()})
check("مصروف بتاريخ الشهر السابق", r.status_code == 200, r.text)
expense_id = r.json()["id"]
r = post(f"/api/clinic-doctors/{sami}/payouts", O, {"amount": 1000, "paid_at": old_moment.isoformat()})
check("تسوية بتاريخ الشهر السابق", r.status_code in (200, 201), r.text)
payout_id = r.json()["id"]

# معلّقة مسجّلة في الشهر السابق تمنع الإقفال
p_inv2 = invoice(p_sami, 20000, sami)
r = post(f"/api/patients/{p_sami}/invoices/{p_inv2}/pending-payments", S, {"amount": 5000})
p5 = r.json()["id"]
db = database.SessionLocal()
db.query(models.PendingPayment).filter(models.PendingPayment.id == p5).update({models.PendingPayment.recorded_at: old_moment})
db.commit()
db.close()
r = post("/api/finance/closed-periods", O, {"year": py, "month": pm})
check("معلّقة في الشهر تمنع إقفاله", r.status_code == 409 and "بانتظار تأكيدك" in r.json()["detail"], r.text)
check("تأكيدها قبل الإقفال", post(f"/api/pending-payments/{p5}/confirm", O).status_code == 200)

r = post("/api/finance/closed-periods", O, {"year": py, "month": pm})
check("إقفال الشهر السابق", r.status_code == 201, r.text)
snap = r.json()
check("لقطة الأرقام: دخل 15000 ومصروف 3000", snap["total_income"] == 15000 and snap["total_expenses"] == 3000, str(snap))
check("لقطة حصص الأطباء (40% من 15000)", snap["doctors_share"] == 6000, str(snap))
check("إقفال مكرر 409", post("/api/finance/closed-periods", O, {"year": py, "month": pm}).status_code == 409)
check("قائمة الأشهر المقفلة", [(c["year"], c["month"]) for c in client.get("/api/finance/closed-periods", headers=O).json()] == [(py, pm)])

print("10) الشهر المقفل محمي من كل المسارات")
db = database.SessionLocal()
old_tx = (db.query(models.FinancialTransaction)
          .filter(models.FinancialTransaction.invoice_id == inv_sami, models.FinancialTransaction.created_at == old_moment).one())
old_tx_id = old_tx.id
recent_tx_id = (db.query(models.FinancialTransaction)
                .filter(models.FinancialTransaction.invoice_id == inv_sami, models.FinancialTransaction.amount == 30000).one().id)
db.close()


def blocked(r):
    return r.status_code == 409 and "مُقفل" in r.json().get("detail", "")


check("دفعة جديدة بتاريخ مقفل", blocked(post(f"/api/patients/{p_sami}/invoices/{inv_sami}/payments", O,
                                              {"amount": 100, "transaction_date": old_moment.isoformat()})))
check("مصروف بتاريخ مقفل", blocked(post("/api/finance/expenses", O, {"amount": 100, "description": "x", "type": "expense",
                                                                      "transaction_date": old_moment.isoformat()})))
check("تعديل حركة في شهر مقفل", blocked(client.put(f"/api/finance/transaction/{old_tx_id}", headers=O,
                                                    json={"amount": 9000, "description": "تعديل"})))
check("نقل حركة حديثة إلى شهر مقفل", blocked(client.put(f"/api/finance/transaction/{recent_tx_id}", headers=O,
                                                         json={"amount": 30000, "description": "نقل",
                                                               "transaction_date": old_moment.isoformat()})))
check("حذف حركة في شهر مقفل", blocked(client.delete(f"/api/finance/transaction/{expense_id}", headers=O)))
check("إعادة نسب دفعة في شهر مقفل", blocked(client.patch(f"/api/finance/transaction/{old_tx_id}/doctor", headers=O,
                                                         json={"clinic_doctor_id": lina})))
check("تسوية بتاريخ مقفل", blocked(post(f"/api/clinic-doctors/{sami}/payouts", O, {"amount": 100, "paid_at": old_moment.isoformat()})))
check("حذف تسوية في شهر مقفل", blocked(client.delete(f"/api/clinic-doctors/{sami}/payouts/{payout_id}", headers=O)))
check("نقل دفعات الفاتورة لطبيب آخر", blocked(client.patch(f"/api/patients/{p_sami}/invoices/{inv_sami}", headers=O,
                                                            json={"total_cost": 100000, "clinic_doctor_id": lina,
                                                                  "apply_to_existing_payments": True})))
check("حذف فاتورة لها دفعة في شهر مقفل",
      blocked(client.delete(f"/api/patients/{p_sami}/invoices/{inv_sami}", headers=O, params={"confirm_doctor_earnings": "true"})))
p_owner = patient("مريض المدير")
inv_owner = invoice(p_owner, 5000)
r = post(f"/api/patients/{p_owner}/invoices/{inv_owner}/payments", O, {"amount": 1000, "transaction_date": (old_moment + timedelta(hours=1)).isoformat()})
check("(تحضير) دفعة المدير في الشهر المقفل مرفوضة أصلاً", blocked(r))
check("تعديل حركة في الشهر الحالي ما زال مسموحاً",
      client.put(f"/api/finance/transaction/{recent_tx_id}", headers=O, json={"amount": 30000, "description": "تصحيح وصف"}).status_code == 200)
check("تعديل التكلفة وحدها مسموح", client.patch(f"/api/patients/{p_sami}/invoices/{inv_sami}", headers=O,
                                                json={"total_cost": 120000}).status_code == 200)
check("ملخص الشهر المقفل لم يتغيّر", summary(py, pm)["total_income"] == 15000)

print("11) فتح القفل")
check("المساعد لا يفتح القفل", client.delete(f"/api/finance/closed-periods/{py}/{pm}", headers=S).status_code == 403)
check("فتح القفل", client.delete(f"/api/finance/closed-periods/{py}/{pm}", headers=O).status_code == 200)
check("فتح غير المقفل 404", client.delete(f"/api/finance/closed-periods/{py}/{pm}", headers=O).status_code == 404)
check("التعديل مسموح بعد الفتح", client.delete(f"/api/finance/transaction/{expense_id}", headers=O).status_code == 200)

print("12) الأطباء المساعدون: مسارات جديدة ضمن القائمة فقط")
check("المساعد لا يرى الأشهر المقفلة (403)", client.get("/api/finance/closed-periods", headers=S).status_code == 403)
check("المساعد لا يرى ملخص المالية (403)", client.get("/api/finance/summary", headers=S).status_code == 403)

print()
print("passed: %d  failed: %d" % (len(PASSED), len(FAILED)))
for name in FAILED:
    print("FAILED:", name)
sys.exit(1 if FAILED else 0)
