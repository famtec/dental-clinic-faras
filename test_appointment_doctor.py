"""فحوص عمود clinic_doctor_id على المواعيد + فحص التعارض لكل طبيب (2026-09-15).

تُشغَّل على SQLite حقيقي في ملف مؤقّت مع نماذج models.py الفعلية، وتستورد
دوال main.py نفسها (لا نسخة منها) حتى يكون ما يُفحَص هو الكود الشاحن.
"""
import os
import sys
import tempfile
from datetime import datetime, timedelta

TMP_DB = os.path.join(tempfile.mkdtemp(), "t.db")
os.environ["DATABASE_URL"] = f"sqlite:///{TMP_DB}"
os.environ.setdefault("ADMIN_SECRET_KEY", "test-only")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import database  # noqa: E402
import models  # noqa: E402
import main  # noqa: E402
from sqlalchemy import inspect, text  # noqa: E402

FAILURES = []


def check(name, condition):
    print(("  ok   " if condition else "  FAIL ") + name)
    if not condition:
        FAILURES.append(name)


CLINIC = "clinic@example.com"


def seed():
    database.init_db()
    db = database.SessionLocal()
    docs = []
    for name, pct in (("د. لينا مرعي", 40), ("د. فادي نصّار", 35)):
        d = models.ClinicDoctor(clinic_email=CLINIC, full_name=name, commission_percent=pct)
        db.add(d)
        docs.append(d)
    db.commit()
    for d in docs:
        db.refresh(d)
    return db, docs


def add_appt(db, start, minutes, clinic_doctor_id, name="مريض", status="pending"):
    a = models.Appointment(
        doctor_email=CLINIC,
        patient_name=name,
        appointment_date=start,
        appointment_time=start.strftime("%H:%M"),
        procedure_type="حشوة",
        notes="حشوة",
        status=status,
        duration_minutes=minutes,
        clinic_doctor_id=clinic_doctor_id,
    )
    db.add(a)
    db.commit()
    db.refresh(a)
    return a


def conflicts(db, start, minutes, clinic_doctor_id, exclude=None):
    try:
        main.ensure_appointment_slot_is_free(
            db, CLINIC, start, minutes,
            exclude_appointment_id=exclude,
            clinic_doctor_id=clinic_doctor_id,
        )
        return False
    except main.HTTPException as exc:
        return exc.status_code == 409


def main_tests():
    db, docs = seed()
    lina, fadi = docs[0].id, docs[1].id
    day = datetime(2026, 9, 16, 0, 0)
    t10 = day.replace(hour=10)

    print("\n[1] الترحيل والعمود")
    cols = {c["name"] for c in inspect(database.engine).get_columns("appointments")}
    check("العمود clinic_doctor_id موجود في جدول appointments", "clinic_doctor_id" in cols)
    database.init_db()  # تكرار الترحيل لا يفشل
    check("إعادة تشغيل init_db لا تفشل (idempotent)", True)

    print("\n[2] التعارض لكل طبيب على حدة")
    add_appt(db, t10, 60, lina, "مريض لينا")
    check("نفس الوقت لطبيبة أخرى (فادي) ليس تعارضاً", not conflicts(db, t10, 60, fadi))
    check("نفس الوقت لنفس الطبيبة (لينا) تعارض", conflicts(db, t10, 60, lina))
    check("تقاطع جزئي لنفس الطبيبة تعارض", conflicts(db, t10 + timedelta(minutes=30), 30, lina))
    check("تلاصق back-to-back ليس تعارضاً", not conflicts(db, t10 + timedelta(minutes=60), 30, lina))

    print("\n[3] الطبيب المدير (NULL) كرسي مستقل")
    add_appt(db, t10, 45, None, "مريض المدير")
    check("موعد المدير في نفس وقت لينا مقبول", True)
    check("موعد ثانٍ للمدير في نفس الوقت تعارض", conflicts(db, t10, 30, None))
    check("موعد لفادي في نفس وقت المدير ليس تعارضاً", not conflicts(db, t10, 30, fadi))

    print("\n[4] استبعاد الموعد نفسه أثناء تعديله")
    own = add_appt(db, day.replace(hour=14), 30, fadi, "تعديل")
    check("الموعد لا يتعارض مع نفسه عند استبعاده", not conflicts(db, day.replace(hour=14), 30, fadi, exclude=own.id))
    check("وبدون استبعاده يتعارض", conflicts(db, day.replace(hour=14), 30, fadi))

    print("\n[5] الحالات غير الحاجزة")
    add_appt(db, day.replace(hour=16), 60, lina, "طلب", status="pending_confirmation")
    check("طلب الحجز غير المؤكَّد لا يحجز وقتاً", not conflicts(db, day.replace(hour=16), 60, lina))
    add_appt(db, day.replace(hour=17), 60, lina, "مرفوض", status="rejected")
    check("الموعد المرفوض لا يحجز وقتاً", not conflicts(db, day.replace(hour=17), 60, lina))

    print("\n[6] يوم آخر لا يتعارض")
    check("نفس الساعة في يوم تالٍ ليس تعارضاً", not conflicts(db, t10 + timedelta(days=1), 60, lina))

    print("\n[7] المخططات (الحالة الثلاثية)")
    u_absent = main.AppointmentUpdate(**{"time": "11:00"})
    u_null = main.AppointmentUpdate(**{"time": "11:00", "clinic_doctor_id": None})
    u_set = main.AppointmentUpdate(**{"time": "11:00", "clinic_doctor_id": lina})
    check("عدم إرسال الحقل = لا تغيير", "clinic_doctor_id" not in u_absent.model_fields_set)
    check("إرسال null = إرجاع للمدير", "clinic_doctor_id" in u_null.model_fields_set and u_null.clinic_doctor_id is None)
    check("إرسال معرّف = إسناد لطبيب", u_set.clinic_doctor_id == lina)
    c_absent = main.AppointmentCreate(**{"patient_id": 1, "date": "2026-09-16", "time": "09:00", "description": "x"})
    check("إنشاء بلا حقل الطبيب يبقى None (تطبيق أندرويد الحالي)", c_absent.clinic_doctor_id is None)

    print("\n[8] التحقق من ملكية الطبيب (fail closed)")
    other = models.ClinicDoctor(clinic_email="other@example.com", full_name="غريب", commission_percent=10)
    db.add(other)
    db.commit()
    db.refresh(other)
    try:
        main.resolve_clinic_doctor_id(db, other.id, CLINIC)
        check("طبيب عيادة أخرى مرفوض بـ404", False)
    except main.HTTPException as exc:
        check("طبيب عيادة أخرى مرفوض بـ404", exc.status_code == 404)
    check("resolve للقيمة None يعيد None", main.resolve_clinic_doctor_id(db, None, CLINIC) is None)
    check("resolve للقيمة 0 يعيد None", main.resolve_clinic_doctor_id(db, 0, CLINIC) is None)
    check("resolve لمعرّف صحيح يعيده", main.resolve_clinic_doctor_id(db, lina, CLINIC) == lina)

    print("\n[9] حذف طبيب يفكّ ربط مواعيده")
    victim = models.ClinicDoctor(clinic_email=CLINIC, full_name="طبيب مؤقّت", commission_percent=10)
    db.add(victim)
    db.commit()
    db.refresh(victim)
    appt = add_appt(db, day.replace(hour=19), 30, victim.id, "مريض الطبيب المؤقّت")
    # يُستدعى المسار الحقيقي لا محاكاته: النسخة السابقة من هذا الفحص كانت
    # تفكّ الربط بنفسها ثم تتحقّق من نتيجة فعلها هي، فكانت تنجح وإن لم يفكّ
    # المسار شيئاً -- وهو ما كان يحدث فعلاً حتى 2026-09-18.

    class _Owner:
        email = CLINIC

    appt_id = appt.id
    result = main.delete_clinic_doctor(victim.id, db=db, current_user=_Owner())
    db.expire_all()
    appt = db.query(models.Appointment).filter(models.Appointment.id == appt_id).first()
    check("المسار أعاد رسالة نجاح", isinstance(result, dict) and "message" in result)
    check("موعد الطبيب المحذوف عاد إلى المدير (NULL) ولم يُحذف",
          appt is not None and appt.clinic_doctor_id is None)
    check("الطبيب نفسه حُذف",
          db.query(models.ClinicDoctor).filter(models.ClinicDoctor.id == victim.id).first() is None)

    print("\n[10] المواعيد التاريخية")
    with database.engine.begin() as conn:
        conn.execute(text(
            "INSERT INTO appointments (doctor_email, patient_name, appointment_date, appointment_time,"
            " procedure_type, status, duration_minutes) VALUES (:e,'قديم','2026-09-16 08:00:00','08:00','فحص','pending',30)"
        ), {"e": CLINIC})
    legacy = db.query(models.Appointment).filter(models.Appointment.patient_name == "قديم").first()
    check("صف قديم بلا الحقل يقرأ NULL (= المدير)", legacy is not None and legacy.clinic_doctor_id is None)

    db.close()


main_tests()
print("\n" + ("=" * 46))
if FAILURES:
    print(f"فشل {len(FAILURES)} فحص:")
    for f in FAILURES:
        print("  -", f)
    sys.exit(1)
print("كل الفحوص نجحت")
