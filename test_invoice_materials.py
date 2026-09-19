# -*- coding: utf-8 -*-
"""فحوص مسارَي مواد الفاتورة: الإضافة على فاتورة قائمة والحذف بإرجاع للمخزن.

أُضيف 2026-09-18 مع نقل الميزة إلى تطبيق الموبايل. سبب إفراده عن
test_treatment_catalog.py: ذاك يغطّي الوصفة وإنشاء الفاتورة بموادها (70 فحصاً)
لكنه **لا يلمس** POST/DELETE على
/api/patients/{pid}/invoices/{iid}/materials إطلاقاً -- وهما المساران
الوحيدان اللذان يحرّكان المخزن **بعد** إغلاق الفاتورة، أي أخطر ما في الميزة:
حذف سطر يزيد المخزون، فخطأ فيه يخلق مخزوناً من الهواء.

نفس نمط الملفات الأخرى: SQLite حقيقي عبر FastAPI TestClient.
"""
import os
import sys

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "test_inv_materials.db")
if os.path.exists(DB_PATH):
    os.remove(DB_PATH)
os.environ["DATABASE_URL"] = "sqlite:///" + DB_PATH.replace("\\", "/")

from fastapi.testclient import TestClient  # noqa: E402

import database  # noqa: E402
import main  # noqa: E402
import models  # noqa: E402

client = TestClient(main.app)

PASSED = []
FAILED = []


def check(name, condition, extra=""):
    if condition:
        PASSED.append(name)
        print("  ok   " + name)
    else:
        FAILED.append("%s  %s" % (name, extra))
        print("  FAIL " + name + "  " + str(extra))


def make_user(email, tier="premium"):
    from datetime import datetime, timedelta

    db = database.SessionLocal()
    try:
        db.add(models.User(
            email=email,
            hashed_password="x",
            doctor_name="د. تجربة",
            tier=tier,
            is_active=True,
            subscription_expires_at=datetime.utcnow() + timedelta(days=30),
        ))
        db.commit()
    finally:
        db.close()
    return {"Authorization": "Bearer " + main.create_session_token(email)}


def make_patient(headers, name):
    r = client.post("/api/patients", headers=headers,
                    json={"full_name": name, "phone": "0999", "age": 30})
    assert r.status_code in (200, 201), r.text
    return r.json()["id"]


def make_item(headers, name, quantity, unit_cost):
    r = client.post("/api/inventory", headers=headers, json={
        "item_name": name, "quantity": quantity, "unit_cost": unit_cost,
    })
    assert r.status_code in (200, 201), r.text
    return r.json()["id"]


def stock_of(headers, item_id):
    for row in client.get("/api/inventory", headers=headers).json():
        if row["id"] == item_id:
            return int(row["quantity"])
    return None


database.init_db()
A = make_user("a@clinic.test")
B = make_user("b@clinic.test")
patient = make_patient(A, "مريض المواد")

zircon = make_item(A, "زركونيوم", 10, 2500)
anesth = make_item(A, "مخدر موضعي", 4, 300)

print("\n[1] فاتورة بلا مواد ثم إضافة مادة إليها")
r = client.post(f"/api/patients/{patient}/invoices", headers=A,
                json={"title": "تلبيسة", "total_cost": 100000})
check("إنشاء فاتورة بلا مواد", r.status_code in (200, 201), r.text)
invoice = r.json()
check("تكلفة المواد صفر", invoice["materials_cost"] == 0, str(invoice["materials_cost"]))
check("الربح = كامل التكلفة", invoice["net_profit"] == 100000, str(invoice["net_profit"]))
invoice_id = invoice["id"]

r = client.post(f"/api/patients/{patient}/invoices/{invoice_id}/materials", headers=A,
                json=[{"inventory_item_id": zircon, "quantity": 1}])
check("إضافة مادة بالمعرّف", r.status_code in (200, 201), r.text)
updated = r.json()
check("تكلفة المواد = 2500", updated["materials_cost"] == 2500, str(updated["materials_cost"]))
check("الربح انخفض إلى 97500", updated["net_profit"] == 97500, str(updated["net_profit"]))
check("سطر واحد على الفاتورة", len(updated["materials"]) == 1, str(updated["materials"]))
check("المخزن خُصم 10 -> 9", stock_of(A, zircon) == 9, str(stock_of(A, zircon)))

print("\n[2] الإضافة بالاسم (مطابقة غير حساسة لحالة الأحرف)")
r = client.post(f"/api/patients/{patient}/invoices/{invoice_id}/materials", headers=A,
                json=[{"item_name": "  مخدر موضعي  ", "quantity": 2}])
check("إضافة بالاسم مع مسافات زائدة", r.status_code in (200, 201), r.text)
updated = r.json()
check("تكلفة المواد = 2500 + 600", updated["materials_cost"] == 3100, str(updated["materials_cost"]))
check("المخدر خُصم 4 -> 2", stock_of(A, anesth) == 2, str(stock_of(A, anesth)))
check("سطران على الفاتورة", len(updated["materials"]) == 2, str(len(updated["materials"])))

print("\n[3] الرفض لا يخصم شيئاً (كل شيء أو لا شيء)")
before_z = stock_of(A, zircon)
before_a = stock_of(A, anesth)
r = client.post(f"/api/patients/{patient}/invoices/{invoice_id}/materials", headers=A,
                json=[{"inventory_item_id": zircon, "quantity": 1},
                      {"inventory_item_id": anesth, "quantity": 99}])
check("كمية أكبر من المتوفر تُرفض بـ400", r.status_code == 400, r.text)
check("رسالة الرفض تسمّي المادة", "مخدر" in r.text, r.text)
# جوهر الفحص: المادة الأولى في نفس الطلب **لم** تُخصَم رغم كفايتها.
check("المادة الكافية في الطلب المرفوض لم تُخصَم",
      stock_of(A, zircon) == before_z, f"{before_z} -> {stock_of(A, zircon)}")
check("المخزن الآخر لم يتغيّر", stock_of(A, anesth) == before_a,
      f"{before_a} -> {stock_of(A, anesth)}")

r = client.post(f"/api/patients/{patient}/invoices/{invoice_id}/materials", headers=A,
                json=[{"item_name": "مادة لا وجود لها", "quantity": 1}])
check("اسم غير موجود في المخزن يُرفض بـ404", r.status_code == 404, r.text)

r = client.post(f"/api/patients/{patient}/invoices/{invoice_id}/materials", headers=A,
                json=[{"inventory_item_id": zircon, "quantity": 0}])
check("كمية صفر تُرفض بـ400", r.status_code == 400, r.text)

r = client.post(f"/api/patients/{patient}/invoices/{invoice_id}/materials", headers=A, json=[])
check("قائمة فارغة تُرفض بـ400", r.status_code == 400, r.text)

print("\n[4] حذف سطر يُرجِع الكمية إلى المخزن")
current = client.get(f"/api/patients/{patient}/invoices", headers=A).json()[0]
zircon_line = None
for line in current["materials"]:
    if line["item_name"] == "زركونيوم":
        zircon_line = line
        break
check("سطر الزركونيوم موجود", zircon_line is not None, str(current["materials"]))
before = stock_of(A, zircon)
r = client.delete(
    f"/api/patients/{patient}/invoices/{invoice_id}/materials/{zircon_line['id']}", headers=A)
check("حذف السطر ينجح", r.status_code == 200, r.text)
after = r.json()
check("الكمية رجعت للمخزن 9 -> 10", stock_of(A, zircon) == before + 1,
      f"{before} -> {stock_of(A, zircon)}")
check("تكلفة المواد انخفضت إلى 600", after["materials_cost"] == 600, str(after["materials_cost"]))
check("الربح عاد إلى 99400", after["net_profit"] == 99400, str(after["net_profit"]))
check("بقي سطر واحد", len(after["materials"]) == 1, str(after["materials"]))

r = client.delete(
    f"/api/patients/{patient}/invoices/{invoice_id}/materials/{zircon_line['id']}", headers=A)
check("حذف السطر نفسه مرتين = 404 (لا إرجاع مزدوج)", r.status_code == 404, r.text)
check("المخزن لم يزد مرة ثانية", stock_of(A, zircon) == before + 1, str(stock_of(A, zircon)))

print("\n[5] الملكية (fail closed)")
r = client.post(f"/api/patients/{patient}/invoices/{invoice_id}/materials", headers=B,
                json=[{"inventory_item_id": zircon, "quantity": 1}])
check("عيادة أخرى لا تضيف مواداً على فاتورة غيرها", r.status_code == 404, r.text)
r = client.delete(
    f"/api/patients/{patient}/invoices/{invoice_id}/materials/{zircon_line['id']}", headers=B)
check("عيادة أخرى لا تحذف سطراً من فاتورة غيرها", r.status_code == 404, r.text)

b_patient = make_patient(B, "مريض العيادة الأخرى")
r = client.post(f"/api/patients/{b_patient}/invoices", headers=B,
                json={"title": "فحص", "total_cost": 5000})
b_invoice = r.json()["id"]
r = client.post(f"/api/patients/{b_patient}/invoices/{b_invoice}/materials", headers=B,
                json=[{"inventory_item_id": zircon, "quantity": 1}])
check("مادة عيادة أخرى لا تُخصَم من مخزن غيرها", r.status_code == 404, r.text)
check("مخزن العيادة الأولى سليم بعد كل ذلك", stock_of(A, zircon) == before + 1,
      str(stock_of(A, zircon)))

print("\n[6] الدفعات لا تمسّ المواد ولا الربح")
r = client.post(f"/api/patients/{patient}/invoices/{invoice_id}/payments", headers=A,
                json={"amount": 50000})
check("تسجيل دفعة ينجح", r.status_code == 200, r.text)
paid = r.json()
check("تكلفة المواد لم تتغيّر بالدفعة", paid["materials_cost"] == 600, str(paid["materials_cost"]))
check("الربح المفوتَر لم يتغيّر بالدفعة", paid["net_profit"] == 99400, str(paid["net_profit"]))
check("المدفوع = 50000", paid["paid_amount"] == 50000, str(paid["paid_amount"]))

print("\n" + "=" * 52)
print("نجح %d فحصاً" % len(PASSED))
if FAILED:
    print("فشل %d فحص:" % len(FAILED))
    for f in FAILED:
        print("  -", f)
    sys.exit(1)
print("كل الفحوص نجحت")
