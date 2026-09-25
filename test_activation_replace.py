# -*- coding: utf-8 -*-
"""فحوص أكواد التفعيل (2026-09-25): الاستبدال بدل التكديس، المعاينة قبل
الإدخال، الرمز الدائم، التعطيل الإداري، وتقاعد أكواد الزرع العامة.

تُشغَّل على SQLite حقيقي عبر FastAPI TestClient -- نفس نمط
test_patient_doctor.py.
"""
import os
import sys
import tempfile
from datetime import datetime, timedelta

DB_PATH = os.path.join(tempfile.mkdtemp(), "test_activation_replace.db")
os.environ["DATABASE_URL"] = "sqlite:///" + DB_PATH.replace("\\", "/")
os.environ.setdefault("ADMIN_SECRET_KEY", "test-only")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient  # noqa: E402

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


def add_key(code, tier, days=30, **extra):
    db = database.SessionLocal()
    try:
        db.add(models.ActivationKey(key_code=code, intended_tier=tier, duration_days=days, **extra))
        db.commit()
    finally:
        db.close()


def get_key(code):
    db = database.SessionLocal()
    try:
        return db.query(models.ActivationKey).filter(models.ActivationKey.key_code == code).first()
    finally:
        db.close()


def get_user(email):
    db = database.SessionLocal()
    try:
        return db.query(models.User).filter(models.User.email == email).first()
    finally:
        db.close()


def set_user(email, **fields):
    db = database.SessionLocal()
    try:
        user = db.query(models.User).filter(models.User.email == email).first()
        for k, v in fields.items():
            setattr(user, k, v)
        db.commit()
    finally:
        db.close()


def days_left(user):
    return (user.subscription_expires_at - datetime.utcnow()).total_seconds() / 86400


database.init_db()

EMAIL = "replace@test.dev"

print("1) التسجيل برمز Premium Plus")
add_key("PP-AAAA", "premium_plus", 30)
r = client.post("/api/auth/register", json={
    "doctor_name": "د. اختبار", "email": EMAIL, "password": "secret123", "activation_code": "PP-AAAA"})
check("التسجيل ينجح", r.status_code == 200, r.text)
check("يوم الاستهلاك مختوم على الرمز الأول", get_key("PP-AAAA").used_at is not None)

print("2) رمز Premium فوق Premium Plus ساري -- يحلّ محلّه")
add_key("PM-BBBB", "premium", 30)
r = client.post("/api/auth/upgrade-tier", json={"activation_code": "PM-BBBB", "email": EMAIL})
check("الترقية تنجح", r.status_code == 200, r.text)
body = r.json()
check("الاستجابة تذكر إلغاء الرمز السابق", body.get("previous_code_cancelled") is True, str(body))
user = get_user(EMAIL)
check("الباقة = باقة الرمز الجديد (Premium) حتى لو أقل", user.tier == "premium", user.tier)
check("المدة من اليوم لا تراكمية (~30 لا ~60)", 29 < days_left(user) <= 30.01, str(days_left(user)))
old = get_key("PP-AAAA")
check("الرمز القديم ملغى", old.revoked_at is not None)
check("الرمز القديم يذكر من حلّ محلّه", old.replaced_by_code == "PM-BBBB", str(old.replaced_by_code))
check("الرمز الجديد غير ملغى", get_key("PM-BBBB").revoked_at is None)

print("3) تجديد بعد انتهاء الاشتراك -- لا إلغاء لشيء")
set_user(EMAIL, subscription_expires_at=datetime.utcnow() - timedelta(days=2), tier="expired_subscription")
db = database.SessionLocal()
try:
    k = db.query(models.ActivationKey).filter(models.ActivationKey.key_code == "PM-BBBB").first()
    k.used_at = datetime.utcnow() - timedelta(days=32)
    db.commit()
finally:
    db.close()
add_key("PM-CCCC", "premium", 30)
r = client.post("/api/activate", json={"email": EMAIL, "activation_key": "PM-CCCC"})
check("التجديد ينجح", r.status_code == 200, r.text)
check("لا إلغاء عند اشتراك منتهٍ", r.json().get("previous_code_cancelled") is False, r.text)
check("الرمز المنتهي طبيعياً لا يُعلَّم ملغى", get_key("PM-BBBB").revoked_at is None)
user = get_user(EMAIL)
check("المدة 30 يوماً من اليوم", 29 < days_left(user) <= 30.01, str(days_left(user)))

print("4) رمز قديم بلا يوم استهلاك (قبل الترحيل) على اشتراك سارٍ -- يُلغى")
add_key("OLD-LEGACY", "premium", 365, is_used=True, used_by_email=EMAIL)
add_key("PP-DDDD", "premium_plus", 30)
r = client.post("/api/activate", json={"email": EMAIL, "activation_key": "PP-DDDD"})
check("التفعيل ينجح", r.status_code == 200, r.text)
check("الاستجابة تذكر الإلغاء", r.json().get("previous_code_cancelled") is True, r.text)
check("الرمز القديم بلا used_at أُلغي", get_key("OLD-LEGACY").revoked_at is not None)
check("الرمز السابق الساري (PM-CCCC) أُلغي", get_key("PM-CCCC").replaced_by_code == "PP-DDDD")
check("الباقة صارت Premium Plus", get_user(EMAIL).tier == "premium_plus")

print("5) رمز مستخدم لا يُقبل مرتين")
r = client.post("/api/auth/upgrade-tier", json={"activation_code": "PP-DDDD", "email": EMAIL})
check("الرفض 400", r.status_code == 400, r.text)

print("6) الجرد الإداري")
r = client.get("/api/admin/activation-keys", headers={"X-Admin-Secret": os.environ["ADMIN_SECRET_KEY"]})
check("الجرد يعمل", r.status_code == 200, r.text[:200])
data = r.json()
items = {i["key_code"]: i for i in data["keys"]}
check("الجرد يعرض الإلغاء", items["PP-AAAA"]["replaced_by_code"] == "PM-BBBB" and items["PP-AAAA"]["revoked_at"])
check("ملخّص الملغاة = 3", data["summary"].get("revoked") == 3, str(data["summary"]))

ADMIN = {"X-Admin-Secret": os.environ["ADMIN_SECRET_KEY"]}

print("7) المعاينة قبل الإدخال")
add_key("PM-EEEE", "premium", 30)
r = client.post("/api/auth/activation-preview", json={"activation_code": "PM-EEEE", "email": EMAIL})
check("المعاينة تعمل", r.status_code == 200, r.text)
p = r.json()
check("تحذّر من إلغاء الاشتراك السارٍ", p["will_cancel_previous"] is True, str(p))
check("الرسالة تذكر المدة المتبقية", "يتبقّى" in (p["message"] or "") and "يُلغى" in p["message"], str(p["message"]))
check("المعاينة لا تستهلك الرمز", get_key("PM-EEEE").is_used is False)
r = client.post("/api/auth/activation-preview", json={"activation_code": "PM-EEEE", "email": "nobody@test.dev"})
check("بلا حساب: لا تحذير", r.status_code == 200 and r.json()["will_cancel_previous"] is False, r.text)
r = client.post("/api/auth/activation-preview", json={"activation_code": "PP-DDDD", "email": EMAIL})
check("المعاينة ترفض الرمز المستهلك", r.status_code == 400, r.text)

print("8) الرمز الدائم")
r = client.post("/api/admin/renewal-keys/generate", headers=ADMIN,
                json={"tier": "premium_plus", "count": 1, "duration_days": 36500})
check("توليد رمز دائم", r.status_code == 200, r.text)
life_code = r.json()["generated_keys"][0]
r = client.post("/api/auth/activation-preview", json={"activation_code": life_code, "email": EMAIL})
check("المعاينة تصفه دائماً", r.json()["lifetime"] is True and "دائم" in r.json()["message"], r.text)
r = client.post("/api/auth/upgrade-tier", json={"activation_code": life_code, "email": EMAIL})
check("تفعيل الدائم", r.status_code == 200, r.text)
headers = {"Authorization": "Bearer " + main.create_session_token(EMAIL)}
r = client.get("/api/auth/profile", headers=headers)
check("الملف يعلن اشتراكاً دائماً", r.status_code == 200 and r.json().get("subscription_lifetime") is True, r.text[:300])
r = client.post("/api/auth/activation-preview", json={"activation_code": "PM-EEEE", "email": EMAIL})
check("التحذير فوق الدائم يقول «اشتراك دائم»", "لديك اشتراك دائم" in (r.json()["message"] or ""), r.text)

print("9) التعطيل الإداري")
add_key("PM-LEAK1", "premium", 30)
r = client.post("/api/admin/activation-keys/revoke", headers=ADMIN,
                json={"codes": ["pm-leak1", "PP-DDDD", "NO-SUCH"]})
check("مسار التعطيل يعمل", r.status_code == 200, r.text)
body = r.json()
check("عُطّل غير المستهلك وحده", body["revoked"] == 1 and body["skipped_used"] == 1 and body["not_found"] == 1, str(body))
r = client.post("/api/auth/upgrade-tier", json={"activation_code": "PM-LEAK1", "email": EMAIL})
check("المعطَّل مرفوض عند الترقية", r.status_code == 400, r.text)
r = client.post("/api/activate", json={"email": EMAIL, "activation_key": "PM-LEAK1"})
check("المعطَّل مرفوض عند التفعيل", r.status_code == 400, r.text)
r = client.post("/api/auth/register", json={
    "doctor_name": "x", "email": "leak@test.dev", "password": "secret123", "activation_code": "PM-LEAK1"})
check("المعطَّل مرفوض عند التسجيل", r.status_code == 400, r.text)
r = client.get("/api/admin/activation-keys", headers=ADMIN)
summ = r.json()["summary"]
items = {i["key_code"]: i for i in r.json()["keys"]}
check("المعطَّل لا يُعدّ متاحاً", summ["disabled"] == 1, str(summ))

print("10) أكواد الزرع العامة تتعطّل عند الإقلاع")
add_key("TEST-PREMIUM-ZZZ", "premium", 365)
add_key("FARAS-VIP-ZZZ", "premium", 999)
add_key("FARAS-VIP-USED", "premium", 999, is_used=True, used_by_email=EMAIL)
main.retire_public_seed_activation_keys()
check("TEST-* غير المستخدم عُطّل", get_key("TEST-PREMIUM-ZZZ").revoked_at is not None)
check("FARAS-* غير المستخدم عُطّل", get_key("FARAS-VIP-ZZZ").revoked_at is not None)
check("المستخدم منها لم يُمسّ", get_key("FARAS-VIP-USED").revoked_at is None)
check("لم يعد يُزرع شيء", get_key("TEST-STANDARD-30") is None)

print()
print("passed:", len(PASSED), " failed:", len(FAILED))
for f in FAILED:
    print("  -", f)
sys.exit(1 if FAILED else 0)
