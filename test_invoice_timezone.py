# -*- coding: utf-8 -*-
"""توقيت فواتير العلاج (2026-09-25): الفاتورة الجديدة بتوقيت دمشق كالدفعات،
والقديمة (المختومة بتوقيت غرينتش) تُزاح +3 ساعات مرة واحدة فقط مهما أُعيد
تشغيل الخادم."""
import os
import sys
import tempfile
from datetime import datetime, timedelta

DB_PATH = os.path.join(tempfile.mkdtemp(), "test_invoice_timezone.db")
os.environ["DATABASE_URL"] = "sqlite:///" + DB_PATH.replace("\\", "/")
os.environ.setdefault("ADMIN_SECRET_KEY", "test-only")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import text  # noqa: E402

import database  # noqa: E402
import main  # noqa: E402
import models  # noqa: E402

PASSED = []
FAILED = []


def check(name, condition, extra=""):
    print(("  ok   " if condition else "  FAIL ") + name)
    (PASSED if condition else FAILED).append(name if condition else "%s  %s" % (name, extra))


def invoice_created_at(invoice_id):
    with database.engine.connect() as connection:
        value = connection.execute(
            text("SELECT created_at FROM treatment_invoices WHERE id = :id"), {"id": invoice_id}
        ).scalar()
    return value if isinstance(value, datetime) else datetime.fromisoformat(str(value))


print("1) قاعدة قديمة: فاتورة مختومة بتوقيت غرينتش قبل الإصلاح")
database.Base.metadata.create_all(bind=database.engine)
with database.engine.begin() as connection:
    connection.execute(text(
        "INSERT INTO users (email, hashed_password, doctor_name, tier, is_active) "
        "VALUES ('tz@test.dev', 'x', 'د. توقيت', 'premium_plus', 1)"
    ))
    connection.execute(text(
        "INSERT INTO patients (full_name, phone, doctor_email) VALUES ('مريض', '0999', 'tz@test.dev')"
    ))
    connection.execute(text(
        "INSERT INTO treatment_invoices (patient_id, doctor_email, title, total_cost, created_at) "
        "VALUES (1, 'tz@test.dev', 'قديمة', 1000, '2026-08-31 22:30:00')"
    ))

database.init_db()
old = invoice_created_at(1)
check("أول تشغيل يُزيحها +3 ساعات (إلى 1 أيلول بتوقيت دمشق)", old == datetime(2026, 9, 1, 1, 30), str(old))
database.init_db()
database.init_db()
check("إعادة التشغيل لا تُزيحها مرة ثانية", invoice_created_at(1) == datetime(2026, 9, 1, 1, 30), str(invoice_created_at(1)))
with database.engine.connect() as connection:
    marks = connection.execute(text("SELECT COUNT(*) FROM data_fixes WHERE name = 'invoice_created_at_damascus'")).scalar()
check("علامة الإصلاح مسجّلة مرة واحدة", marks == 1, str(marks))

print("2) الفاتورة الجديدة بتوقيت دمشق")
db = database.SessionLocal()
db.query(models.User).filter(models.User.email == "tz@test.dev").update(
    {models.User.subscription_expires_at: datetime.utcnow() + timedelta(days=30),
     models.User.hashed_password: main.hash_password("pass-1234")}
)
db.commit()
db.close()
client = TestClient(main.app)
H = {"Authorization": "Bearer " + main.create_session_token("tz@test.dev")}
r = client.post("/api/patients/1/invoices", headers=H, json={"title": "جديدة", "total_cost": 500})
check("إنشاء فاتورة", r.status_code in (200, 201), r.text)
new_id = r.json()["id"]
created = invoice_created_at(new_id)
now_damascus = main._damascus_now()
check("وقتها = الآن بتوقيت دمشق (±2 دقيقة)", abs((created - now_damascus).total_seconds()) < 120,
      f"{created} vs {now_damascus}")
r = client.post(f"/api/patients/1/invoices/{new_id}/payments", headers=H, json={"amount": 100})
payment_time = datetime.fromisoformat(r.json()["payments"][0]["created_at"])
check("الفاتورة ودفعتها بنفس التوقيت (فرق أقل من دقيقتين)", abs((payment_time - created).total_seconds()) < 120,
      f"{payment_time} vs {created}")
check("الفاتورة القديمة لم تتغيّر بإنشاء الجديدة", invoice_created_at(1) == datetime(2026, 9, 1, 1, 30))

print()
print("passed: %d  failed: %d" % (len(PASSED), len(FAILED)))
for name in FAILED:
    print("FAILED:", name)
sys.exit(1 if FAILED else 0)
