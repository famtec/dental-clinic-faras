# -*- coding: utf-8 -*-
"""فحوص لائحة أسعار العلاجات + استهلاك المواد (2026-09-14).

تُشغَّل على SQLite حقيقي عبر FastAPI TestClient -- نفس نمط test_commission.py.
"""
import os
import sys

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "test_catalog.db")
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
    else:
        FAILED.append("%s  %s" % (name, extra))


def make_user(email, tier="premium"):
    from datetime import datetime, timedelta

    db = database.SessionLocal()
    try:
        user = models.User(
            email=email,
            hashed_password="x",
            doctor_name="د. تجربة",
            tier=tier,
            is_active=(tier != "pending_activation"),
            # اشتراك مستقبلي حقيقي -- بدونه يعامله ensure_user_subscription_is_active
            # كحساب وهمي ويرجع 402 (سدّ ثغرة موثّق في main.py).
            subscription_expires_at=(
                None if tier == "pending_activation" else datetime.utcnow() + timedelta(days=30)
            ),
        )
        db.add(user)
        db.commit()
    finally:
        db.close()
    return {"Authorization": "Bearer " + main.create_session_token(email)}


def make_patient(headers, name):
    r = client.post("/api/patients", headers=headers, json={"full_name": name, "phone": "0999", "age": 30})
    assert r.status_code in (200, 201), r.text
    return r.json()["id"]


def stock(item_id, headers):
    rows = client.get("/api/inventory", headers=headers).json()
    for row in rows:
        if row["id"] == item_id:
            return row
    return None


# ------------------------------------------------------------------
database.init_db()
A = make_user("a@clinic.test")
B = make_user("b@clinic.test")

# --- 1. مخزن بتكلفة وحدة -----------------------------------------------
r = client.post("/api/inventory", headers=A, json={"item_name": "زركونيوم", "quantity": 10, "unit_cost": 2500})
check("إنشاء مادة بتكلفة وحدة", r.status_code == 201, r.text)
zirc = r.json()["id"]
check("تكلفة الوحدة تعود في الرد", r.json().get("unit_cost") == 2500, r.text)

r = client.post("/api/inventory", headers=A, json={"item_name": "مخدر", "quantity": 4})
anes = r.json()["id"]
check("مادة بلا تكلفة تُنشأ بصفر", r.json().get("unit_cost") == 0, r.text)

r = client.post("/api/inventory", headers=A, json={"item_name": "سالب", "quantity": 1, "unit_cost": -5})
check("رفض تكلفة وحدة سالبة", r.status_code == 400, r.text)

r = client.put("/api/inventory/%d" % anes, headers=A, json={"unit_cost": 300})
check("تعديل تكلفة الوحدة", r.status_code == 200 and r.json()["unit_cost"] == 300, r.text)

# --- 2. لائحة الأسعار ---------------------------------------------------
r = client.post(
    "/api/treatment-catalog",
    headers=A,
    json={
        "name": "تلبيسة زركونيوم",
        "price": 100000,
        "notes": "جلستان",
        "materials": [
            {"inventory_item_id": zirc, "quantity": 1},
            {"inventory_item_id": anes, "quantity": 2},
        ],
    },
)
check("إنشاء حالة مع وصفة", r.status_code == 201, r.text)
crown = r.json()
check("تكلفة الوصفة = 2500 + 2×300", crown["materials_cost"] == 3100, str(crown.get("materials_cost")))
check("الربح المتوقع = 96900", crown["estimated_profit"] == 96900, str(crown.get("estimated_profit")))
check("الوصفة تحمل الكمية المتوفرة", crown["materials"][0]["available_quantity"] == 10, str(crown["materials"]))

r = client.post("/api/treatment-catalog", headers=A, json={"name": "تلبيسة زركونيوم", "price": 5})
check("رفض اسم حالة مكرر", r.status_code == 400, r.text)

r = client.post("/api/treatment-catalog", headers=A, json={"name": "حشوة", "price": -1})
check("رفض تسعيرة سالبة", r.status_code == 400, r.text)

r = client.post("/api/treatment-catalog", headers=A, json={"name": "حشوة", "price": 20000})
filling = r.json()
check("حالة بلا مواد", r.status_code == 201 and filling["materials"] == [], r.text)

# عزل العيادات
r = client.get("/api/treatment-catalog", headers=B)
check("عيادة أخرى لا ترى لائحة غيرها", r.json() == [], r.text)
r = client.patch("/api/treatment-catalog/%d" % crown["id"], headers=B, json={"price": 1})
check("تعديل حالة عيادة أخرى = 404", r.status_code == 404, r.text)

# مادة عيادة أخرى في وصفة = 404 (fail closed)
r = client.post("/api/treatment-catalog", headers=B, json={"name": "سرقة", "price": 1, "materials": [{"inventory_item_id": zirc, "quantity": 1}]})
check("مادة عيادة أخرى في وصفة = 404", r.status_code == 404, r.text)

# --- 3. فاتورة من حالة جاهزة مع خصم المواد -----------------------------
pid = make_patient(A, "مريض أول")
r = client.post(
    "/api/patients/%d/invoices" % pid,
    headers=A,
    json={
        "title": crown["name"],
        "total_cost": crown["price"],
        "catalog_item_id": crown["id"],
        "materials": [
            {"inventory_item_id": zirc, "quantity": 1},
            {"inventory_item_id": anes, "quantity": 2},
        ],
    },
)
check("إنشاء فاتورة من حالة", r.status_code == 201, r.text)
inv = r.json()
check("تكلفة مواد الفاتورة = 3100", inv["materials_cost"] == 3100, str(inv.get("materials_cost")))
check("صافي ربح الفاتورة = 96900", inv["net_profit"] == 96900, str(inv.get("net_profit")))
check("الفاتورة مرتبطة بالحالة", inv["catalog_item_id"] == crown["id"], str(inv.get("catalog_item_id")))
check("خُصم الزركونيوم 10→9", stock(zirc, A)["quantity"] == 9, str(stock(zirc, A)))
check("خُصم المخدر 4→2", stock(anes, A)["quantity"] == 2, str(stock(anes, A)))

# --- 4. الكمية غير الكافية توقف كل شيء (ذرية) --------------------------
before_zirc = stock(zirc, A)["quantity"]
before_anes = stock(anes, A)["quantity"]
r = client.post(
    "/api/patients/%d/invoices" % pid,
    headers=A,
    json={
        "title": "فاتورة فاشلة",
        "total_cost": 1000,
        "materials": [
            {"inventory_item_id": zirc, "quantity": 1},
            {"inventory_item_id": anes, "quantity": 99},
        ],
    },
)
check("رفض كمية أكبر من المتوفر", r.status_code == 400, r.text)
check("الرسالة تسمّي المادة", "مخدر" in r.json().get("detail", ""), r.text)
check("لا خصم جزئي للزركونيوم", stock(zirc, A)["quantity"] == before_zirc, str(stock(zirc, A)))
check("لا خصم جزئي للمخدر", stock(anes, A)["quantity"] == before_anes, str(stock(anes, A)))
invoices = client.get("/api/patients/%d/invoices" % pid, headers=A).json()
check("لم تُحفظ الفاتورة الفاشلة", all(i["title"] != "فاتورة فاشلة" for i in invoices), str(len(invoices)))

# --- 5. تجميد التكلفة: تغيير سعر المادة لا يمسّ فاتورة قديمة ------------
client.put("/api/inventory/%d" % zirc, headers=A, json={"unit_cost": 999999})
again = client.get("/api/patients/%d/invoices" % pid, headers=A).json()[0]
check("تكلفة الفاتورة مجمّدة بعد تغيير سعر المادة", again["materials_cost"] == 3100, str(again["materials_cost"]))
client.put("/api/inventory/%d" % zirc, headers=A, json={"unit_cost": 2500})

# تجميد سعر الحالة
client.patch("/api/treatment-catalog/%d" % crown["id"], headers=A, json={"price": 500000})
again = client.get("/api/patients/%d/invoices" % pid, headers=A).json()[0]
check("تكلفة الفاتورة مجمّدة بعد تغيير سعر الحالة", again["total_cost"] == 100000, str(again["total_cost"]))
client.patch("/api/treatment-catalog/%d" % crown["id"], headers=A, json={"price": 100000})

# --- 6. إضافة/حذف مادة على فاتورة قائمة --------------------------------
r = client.post(
    "/api/patients/%d/invoices/%d/materials" % (pid, inv["id"]),
    headers=A,
    json=[{"item_name": "مخدر", "quantity": 1}],
)
check("إضافة مادة بالاسم على فاتورة قائمة", r.status_code == 201, r.text)
check("التكلفة صارت 3400", r.json()["materials_cost"] == 3400, str(r.json()["materials_cost"]))
check("خُصم المخدر 2→1", stock(anes, A)["quantity"] == 1, str(stock(anes, A)))
added_usage_id = sorted(r.json()["materials"], key=lambda m: m["id"])[-1]["id"]

r = client.post(
    "/api/patients/%d/invoices/%d/materials" % (pid, inv["id"]),
    headers=A,
    json=[{"inventory_item_id": zirc, "quantity": 1, "unit_cost": 7}],
)
check("تجاوز السعر لهذه الفاتورة وحدها", r.json()["materials_cost"] == 3407, str(r.json()["materials_cost"]))
check("سعر المادة العام لم يتغيّر", stock(zirc, A)["unit_cost"] == 2500, str(stock(zirc, A)))
override_usage_id = sorted(r.json()["materials"], key=lambda m: m["id"])[-1]["id"]

r = client.delete("/api/patients/%d/invoices/%d/materials/%d" % (pid, inv["id"], added_usage_id), headers=A)
check("حذف سطر مادة", r.status_code == 200 and r.json()["materials_cost"] == 3107, r.text)
check("أُرجع المخدر 1→2", stock(anes, A)["quantity"] == 2, str(stock(anes, A)))

r = client.delete("/api/patients/%d/invoices/%d/materials/%d" % (pid, inv["id"], override_usage_id), headers=B)
check("حذف سطر من عيادة أخرى = 404", r.status_code == 404, r.text)
client.delete("/api/patients/%d/invoices/%d/materials/%d" % (pid, inv["id"], override_usage_id), headers=A)

# --- 7. حذف الفاتورة يُرجع كل موادها -----------------------------------
pid2 = make_patient(A, "مريض ثانٍ")
r = client.post(
    "/api/patients/%d/invoices" % pid2,
    headers=A,
    json={"title": "مؤقتة", "total_cost": 1000, "materials": [{"inventory_item_id": zirc, "quantity": 2}]},
)
temp_inv = r.json()["id"]
check("خُصم قبل الحذف", stock(zirc, A)["quantity"] == 7, str(stock(zirc, A)))
r = client.delete("/api/patients/%d/invoices/%d" % (pid2, temp_inv), headers=A)
check("حذف الفاتورة نجح", r.status_code == 200, r.text)
check("أُرجعت المواد بعد حذف الفاتورة", stock(zirc, A)["quantity"] == 9, str(stock(zirc, A)))

# --- 8. حذف حالة مستخدَمة مرفوض، والتعطيل بديل -------------------------
r = client.delete("/api/treatment-catalog/%d" % crown["id"], headers=A)
check("رفض حذف حالة مستخدَمة", r.status_code == 400, r.text)
r = client.patch("/api/treatment-catalog/%d" % crown["id"], headers=A, json={"is_active": False})
check("تعطيل الحالة", r.status_code == 200 and r.json()["is_active"] is False, r.text)
r = client.get("/api/treatment-catalog?include_inactive=false", headers=A)
check("المعطّلة تختفي من قائمة الاختيار", all(i["id"] != crown["id"] for i in r.json()), r.text)
r = client.get("/api/treatment-catalog", headers=A)
check("المعطّلة تظهر في صفحة الإدارة", any(i["id"] == crown["id"] for i in r.json()), r.text)
r = client.delete("/api/treatment-catalog/%d" % filling["id"], headers=A)
check("حذف حالة غير مستخدَمة ينجح", r.status_code == 200, r.text)

# --- 9. الوصفة: None لا تمسّها، [] تفرغها ------------------------------
r = client.patch("/api/treatment-catalog/%d" % crown["id"], headers=A, json={"notes": "ملاحظة"})
check("تعديل بلا materials يبقي الوصفة", len(r.json()["materials"]) == 2, str(r.json()["materials"]))
r = client.patch("/api/treatment-catalog/%d" % crown["id"], headers=A, json={"materials": []})
check("قائمة فارغة تفرغ الوصفة", r.json()["materials"] == [], str(r.json()["materials"]))
r = client.patch(
    "/api/treatment-catalog/%d" % crown["id"],
    headers=A,
    json={"materials": [{"inventory_item_id": zirc, "quantity": 3}]},
)
check("إعادة كتابة الوصفة", len(r.json()["materials"]) == 1 and r.json()["materials"][0]["quantity"] == 3, r.text)

# --- 10. حذف مادة من المخزن لا يكسر شيئاً ------------------------------
r = client.post("/api/inventory", headers=A, json={"item_name": "قابلة للحذف", "quantity": 5, "unit_cost": 100})
doomed = r.json()["id"]
client.patch("/api/treatment-catalog/%d" % crown["id"], headers=A, json={"materials": [{"inventory_item_id": zirc, "quantity": 3}, {"inventory_item_id": doomed, "quantity": 1}]})
r = client.post(
    "/api/patients/%d/invoices" % pid2,
    headers=A,
    json={"title": "فاتورة بمادة ستُحذف", "total_cost": 5000, "materials": [{"inventory_item_id": doomed, "quantity": 1}]},
)
doomed_inv = r.json()["id"]
r = client.delete("/api/inventory/%d" % doomed, headers=A)
check("حذف مادة مستهلَكة ينجح", r.status_code == 200, r.text)
rows = client.get("/api/patients/%d/invoices" % pid2, headers=A).json()
target = [i for i in rows if i["id"] == doomed_inv][0]
check("تكلفة الفاتورة بقيت بعد حذف المادة", target["materials_cost"] == 100, str(target["materials_cost"]))
check("اسم المادة بقي مقروءاً", target["materials"][0]["item_name"] == "قابلة للحذف", str(target["materials"]))
r = client.get("/api/treatment-catalog", headers=A).json()
crown_now = [i for i in r if i["id"] == crown["id"]][0]
orphan = [m for m in crown_now["materials"] if m["inventory_item_id"] is None]
check("وصفة المادة المحذوفة تبقى بلا مخزون", len(orphan) == 1 and orphan[0]["available_quantity"] is None, str(crown_now["materials"]))

# حذف فاتورة موادها مادة محذوفة لا ينفجر
r = client.delete("/api/patients/%d/invoices/%d" % (pid2, doomed_inv), headers=A)
check("حذف فاتورة بمادة محذوفة لا ينفجر", r.status_code == 200, r.text)

# --- 11. حذف المريض (طبقة FK السادسة) ----------------------------------
r = client.delete("/api/patients/%d" % pid, headers=A)
check("حذف مريض له مواد مستهلَكة ينجح", r.status_code == 200, r.text)
db = database.SessionLocal()
try:
    left = db.query(models.InvoiceMaterialUsage).filter(models.InvoiceMaterialUsage.patient_id == pid).count()
finally:
    db.close()
check("لم تبقَ أسطر استهلاك يتيمة", left == 0, str(left))

# --- 12. تقرير الربحية -------------------------------------------------
pid3 = make_patient(A, "مريض ثالث")
client.post(
    "/api/patients/%d/invoices" % pid3,
    headers=A,
    json={"title": "تلبيسة", "total_cost": 100000, "catalog_item_id": crown["id"], "materials": [{"inventory_item_id": zirc, "quantity": 1}]},
)
client.post("/api/patients/%d/invoices" % pid3, headers=A, json={"title": "يدوية", "total_cost": 10000})
r = client.get("/api/treatment-catalog/profit-report?all_time=true", headers=A)
check("تقرير الربحية يعمل", r.status_code == 200, r.text)
report = r.json()
named = [row for row in report["items"] if row["catalog_item_id"] == crown["id"]]
manual = [row for row in report["items"] if row["catalog_item_id"] is None]
check("سطر للحالة الجاهزة", len(named) == 1 and named[0]["materials_cost"] == 2500, str(report["items"]))
check("سطر جامع للفواتير اليدوية", len(manual) == 1, str(report["items"]))
check(
    "صافي الإجمالي = المفوتر - المواد",
    abs(report["totals"]["net_profit"] - (report["totals"]["billed"] - report["totals"]["materials_cost"])) < 0.01,
    str(report["totals"]),
)

# --- 13. الدفعات لم تتأثر (انحدار) -------------------------------------
inv3 = client.get("/api/patients/%d/invoices" % pid3, headers=A).json()
target = [i for i in inv3 if i["title"] == "تلبيسة"][0]
r = client.post("/api/patients/%d/invoices/%d/payments" % (pid3, target["id"]), headers=A, json={"amount": 40000})
check("تسجيل دفعة ما زال يعمل", r.status_code == 200, r.text)
check("الدفعة لا تمسّ تكلفة المواد", r.json()["materials_cost"] == 2500, str(r.json()["materials_cost"]))
check("المتبقي صحيح", r.json()["remaining_amount"] == 60000, str(r.json()["remaining_amount"]))

# --- 14. كشف حساب الطبيب المساعد يعرض تكلفة المواد ---------------------
db = database.SessionLocal()
try:
    u = db.query(models.User).filter(models.User.email == "a@clinic.test").first()
    u.tier = "premium_plus"
    db.commit()
finally:
    db.close()
r = client.post("/api/clinic-doctors", headers=A, json={"full_name": "د. مساعد", "commission_percent": 40})
check("إنشاء طبيب مساعد", r.status_code in (200, 201), r.text)
assoc = r.json()["id"]
pid4 = make_patient(A, "مريض الطبيب المساعد")
r = client.post(
    "/api/patients/%d/invoices" % pid4,
    headers=A,
    json={"title": "تلبيسة", "total_cost": 50000, "clinic_doctor_id": assoc, "materials": [{"inventory_item_id": zirc, "quantity": 1}]},
)
check("فاتورة لطبيب مساعد بمواد", r.status_code == 201, r.text)
inv4 = r.json()["id"]
client.post("/api/patients/%d/invoices/%d/payments" % (pid4, inv4), headers=A, json={"amount": 10000})
r = client.get("/api/clinic-doctors/%d/statement?all_time=true" % assoc, headers=A)
check("كشف الحساب يعمل", r.status_code == 200, r.text)
st = r.json()
check("تكلفة المواد في كشف الحساب = 2500", st["period"]["materials_cost"] == 2500, str(st["period"]))
check("سطر المادة ظاهر", len(st["materials"]) == 1 and st["materials"][0]["item_name"] == "زركونيوم", str(st["materials"]))
check("النسبة ما زالت على المحصّل كاملاً (لا حسم)", st["period"]["doctor_share"] == 4000, str(st["period"]))
check("حصة العيادة = المحصّل - حصة الطبيب", st["period"]["clinic_share"] == 6000, str(st["period"]))

# --- 15. حارس الاشتراك --------------------------------------------------
P = make_user("pending@clinic.test", tier="pending_activation")
r = client.get("/api/treatment-catalog", headers=P)
check("حساب غير مفعّل ممنوع من اللائحة", r.status_code in (402, 403), "%s %s" % (r.status_code, r.text))

# ------------------------------------------------------------------
print("")
print("نجح: %d" % len(PASSED))
for f in FAILED:
    print("  فشل: %s" % f)
print("فشل: %d" % len(FAILED))
sys.exit(1 if FAILED else 0)
