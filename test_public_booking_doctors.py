"""فحوص صفحة الحجز العامة في عيادة متعددة الأطباء (2026-09-22).

قرار المستخدم: المريض يرى الخانة متاحة إن تفرّغ فيها أي طبيب، والعيادة تحدّد
الطبيب عند قبول الطلب. تُشغَّل على SQLite حقيقي مع models.py الفعلية وتستدعي
مسارات main.py نفسها (لا نسخة منها).
"""
import os
import sys
import tempfile
from datetime import date, datetime, timedelta

TMP_DB = os.path.join(tempfile.mkdtemp(), "t.db")
os.environ["DATABASE_URL"] = f"sqlite:///{TMP_DB}"
os.environ.setdefault("ADMIN_SECRET_KEY", "test-only")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import database  # noqa: E402
import models  # noqa: E402
import main  # noqa: E402

FAILURES = []


def check(name, condition):
    print(("  ok   " if condition else "  FAIL ") + name)
    if not condition:
        FAILURES.append(name)


# يوم عمل بعيد في المستقبل حتى لا يُسقط فلتر "الأوقات الماضية" أي خانة.
DAY = date.today() + timedelta(days=14)
while DAY.weekday() != 0:  # الاثنين
    DAY += timedelta(days=1)


def at(hhmm, day=DAY):
    h, m = (int(x) for x in hhmm.split(":"))
    return datetime.combine(day, datetime.min.time()).replace(hour=h, minute=m)


def make_clinic(db, email, slug, tier):
    user = models.User(
        email=email,
        hashed_password="x",
        doctor_name="د. المدير",
        tier=tier,
        is_active=True,
        subscription_expires_at=datetime.now() + timedelta(days=30),
        booking_slug=slug,
        public_booking_enabled=True,
        work_days="0,1,2,3,4,5,6",
        work_start_time="09:00",
        work_end_time="12:00",
        slot_duration_minutes=30,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def add_doctor(db, clinic, name, active=True):
    d = models.ClinicDoctor(clinic_email=clinic.email, full_name=name, commission_percent=30, is_active=active)
    db.add(d)
    db.commit()
    db.refresh(d)
    return d


def add_appt(db, clinic, hhmm, minutes, doctor_id, status="pending", name="مريض"):
    start = at(hhmm)
    a = models.Appointment(
        doctor_email=clinic.email,
        patient_name=name,
        appointment_date=start,
        appointment_time=hhmm,
        procedure_type="فحص",
        status=status,
        duration_minutes=minutes,
        clinic_doctor_id=doctor_id,
    )
    db.add(a)
    db.commit()
    db.refresh(a)
    return a


def slots(db, clinic):
    return main.compute_available_slots_for_date(db, clinic, DAY)


def public_book(db, clinic, hhmm, name):
    """يستدعي مسار الحجز العام الحقيقي، ويعيد (نجح؟, كود الخطأ)."""
    req = main.PublicBookingRequest(date=DAY.isoformat(), time=hhmm, patient_name=name, patient_phone="0999000111")
    try:
        main.create_public_booking_request(clinic.booking_slug, req, db=db)
        return True, None
    except main.HTTPException as exc:
        return False, exc.status_code


def respond(db, clinic, appointment_id, payload):
    req = main.AppointmentRespondRequest(**payload)
    try:
        result = main.respond_to_booking_request(appointment_id, req, db=db, current_user=clinic)
        return result, None
    except main.HTTPException as exc:
        return None, exc


def run():
    database.init_db()
    db = database.SessionLocal()

    # -------------------------------------------------------------
    print("\n[1] عيادة الطبيب الواحد -- لا تغيير في السلوك")
    solo = make_clinic(db, "solo@example.com", "solo", "premium")
    base = slots(db, solo)
    check("كل خانات 09:00–11:30 متاحة في يوم فارغ", base == ["09:00", "09:30", "10:00", "10:30", "11:00", "11:30"])
    add_appt(db, solo, "10:00", 60, None)
    check("موعد المدير 10:00–11:00 يُخفي 10:00 و10:30", "10:00" not in slots(db, solo) and "10:30" not in slots(db, solo))
    ok, _ = public_book(db, solo, "09:00", "طالب أول")
    check("طلب حجز عام على 09:00 يُقبل", ok)
    check("طلب معلّق واحد يُخفي خانته (طبيب واحد مقابل طلب واحد)", "09:00" not in slots(db, solo))
    ok, code = public_book(db, solo, "09:00", "طالب ثانٍ")
    check("طلب ثانٍ على نفس الخانة مرفوض بـ409", not ok and code == 409)

    # -------------------------------------------------------------
    print("\n[2] عيادة متعددة الأطباء (Premium Plus) -- الخانة متاحة إن تفرّغ أي طبيب")
    plus = make_clinic(db, "plus@example.com", "plus", "premium_plus")
    lina = add_doctor(db, plus, "د. لينا")
    fadi = add_doctor(db, plus, "د. فادي")
    add_appt(db, plus, "10:00", 60, None, name="مريض المدير")
    check("المدير مشغول 10:00 لكن لينا وفادي متفرّغان => 10:00 ظاهرة", "10:00" in slots(db, plus))
    add_appt(db, plus, "10:00", 30, lina.id, name="مريض لينا")
    check("المدير ولينا مشغولان وفادي متفرّغ => 10:00 ما زالت ظاهرة", "10:00" in slots(db, plus))
    add_appt(db, plus, "10:00", 30, fadi.id, name="مريض فادي")
    check("الثلاثة مشغولون => 10:00 مخفية", "10:00" not in slots(db, plus))
    check("10:30: المدير مشغول (حتى 11:00) لكن لينا وفادي متفرّغان => ظاهرة", "10:30" in slots(db, plus))

    # -------------------------------------------------------------
    print("\n[3] ثلاثة مرضى على خانة فيها طبيبان متفرّغان")
    # 10:30: المدير مشغول، لينا وفادي متفرّغان => سعة 2
    ok1, _ = public_book(db, plus, "10:30", "مريض 1")
    check("الطلب الأول على 10:30 يُقبل", ok1)
    check("بعد طلب واحد: 10:30 ما زالت ظاهرة (طبيبان مقابل طلب)", "10:30" in slots(db, plus))
    ok2, _ = public_book(db, plus, "10:30", "مريض 2")
    check("الطلب الثاني على 10:30 يُقبل", ok2)
    check("بعد طلبين: 10:30 مخفية (طبيبان مقابل طلبين)", "10:30" not in slots(db, plus))
    ok3, code3 = public_book(db, plus, "10:30", "مريض 3")
    check("الطلب الثالث مرفوض بـ409", not ok3 and code3 == 409)

    # -------------------------------------------------------------
    print("\n[4] الطبيب المعطّل والباقة")
    plus2 = make_clinic(db, "plus2@example.com", "plus2", "premium_plus")
    add_doctor(db, plus2, "د. متوقّف", active=False)
    add_appt(db, plus2, "09:00", 30, None)
    check("طبيب معطّل لا يُحسب مرشّحاً => 09:00 مخفية", "09:00" not in slots(db, plus2))
    downgraded = make_clinic(db, "down@example.com", "down", "premium")
    add_doctor(db, downgraded, "د. من باقة سابقة")
    add_appt(db, downgraded, "09:00", 30, None)
    check("عيادة Premium عادية لها طبيب مسجّل => لا يُحسب مرشّحاً", "09:00" not in slots(db, downgraded))
    check("قائمة مرشّحي Premium عادية = المدير وحده", main.list_booking_candidate_doctors(db, downgraded) == [None])
    check("مرشّحو Plus = المدير ثم الأطباء بترتيب المعرّف",
          main.list_booking_candidate_doctors(db, plus) == [None, lina.id, fadi.id])

    # -------------------------------------------------------------
    print("\n[5] القبول بلا طبيب (تطبيق أندرويد الحالي) -- تعيين تلقائي")
    reqs = (
        db.query(models.Appointment)
        .filter(models.Appointment.doctor_email == plus.email, models.Appointment.status == "pending_confirmation")
        .order_by(models.Appointment.id.asc())
        .all()
    )
    r1, r2 = reqs[0], reqs[1]
    result, err = respond(db, plus, r1.id, {"decision": "accept"})
    db.refresh(r1)
    check("القبول الأول نجح", err is None and result["status"] == "pending")
    check("المدير مشغول 10:30 => عُيّنت لينا (أول مساعد متفرّغ)", r1.clinic_doctor_id == lina.id)
    result, err = respond(db, plus, r2.id, {"decision": "accept"})
    db.refresh(r2)
    check("القبول الثاني نجح وعُيّن فادي", err is None and r2.clinic_doctor_id == fadi.id)

    # طلب ثالث يُدرَج يدوياً (سباق: وصل قبل تحديث الخانات) ولا أحد متفرّغ.
    late = add_appt(db, plus, "10:30", 30, None, status="pending_confirmation", name="متأخر")
    _, err = respond(db, plus, late.id, {"decision": "accept"})
    db.refresh(late)
    check("لا طبيب متفرّغ => 409", err is not None and err.status_code == 409)
    check("والطلب يبقى معلّقاً بلا تغيير", late.status == "pending_confirmation")
    _, err = respond(db, plus, late.id, {"decision": "reject"})
    db.refresh(late)
    check("ويمكن رفضه بعدها بلا أي فحص", err is None and late.status == "rejected")

    # -------------------------------------------------------------
    print("\n[6] القبول بطبيب محدَّد (الموقع)")
    req = add_appt(db, plus, "11:00", 30, None, status="pending_confirmation", name="اختيار")
    _, err = respond(db, plus, req.id, {"decision": "accept", "clinic_doctor_id": fadi.id})
    db.refresh(req)
    check("قبول مع فادي => أُسند لفادي", err is None and req.clinic_doctor_id == fadi.id)

    req2 = add_appt(db, plus, "11:00", 30, None, status="pending_confirmation", name="تعارض")
    _, err = respond(db, plus, req2.id, {"decision": "accept", "clinic_doctor_id": fadi.id})
    db.refresh(req2)
    check("فادي صار مشغولاً 11:00 => 409 برسالة التعارض المفصّلة",
          err is not None and err.status_code == 409 and "محجوز" in str(err.detail))
    check("والطلب باقٍ معلّقاً", req2.status == "pending_confirmation")
    _, err = respond(db, plus, req2.id, {"decision": "accept", "clinic_doctor_id": None})
    db.refresh(req2)
    check("null صريحة = المدير، والمدير متفرّغ 11:00 => قُبل له",
          err is None and req2.status == "pending" and req2.clinic_doctor_id is None)

    inactive = add_doctor(db, plus, "د. معطّلة", active=False)
    req3 = add_appt(db, plus, "11:30", 30, None, status="pending_confirmation", name="معطّل")
    _, err = respond(db, plus, req3.id, {"decision": "accept", "clinic_doctor_id": inactive.id})
    check("إسناد لطبيب معطّل مرفوض بـ400", err is not None and err.status_code == 400)
    stranger = add_doctor(db, solo, "غريب من عيادة أخرى")
    _, err = respond(db, plus, req3.id, {"decision": "accept", "clinic_doctor_id": stranger.id})
    check("إسناد لطبيب عيادة أخرى مرفوض بـ404", err is not None and err.status_code == 404)

    # -------------------------------------------------------------
    print("\n[7] الخلل القديم: القبول كان يتجاهل التعارض حتى في عيادة الطبيب الواحد")
    solo_req = (
        db.query(models.Appointment)
        .filter(models.Appointment.doctor_email == solo.email, models.Appointment.status == "pending_confirmation")
        .first()
    )
    add_appt(db, solo, "09:00", 30, None, name="أُضيف يدوياً قبل القبول")
    _, err = respond(db, solo, solo_req.id, {"decision": "accept"})
    db.refresh(solo_req)
    check("قبول طلب على وقت صار محجوزاً => 409 (كان يُقبل بصمت)", err is not None and err.status_code == 409)
    check("والرسالة تسمّي المريض الحاجز", err is not None and "أُضيف يدوياً قبل القبول" in str(err.detail))
    check("والطلب يبقى معلّقاً", solo_req.status == "pending_confirmation")

    free_req = add_appt(db, solo, "11:30", 30, None, status="pending_confirmation", name="وقت حرّ")
    result, err = respond(db, solo, free_req.id, {"decision": "accept"})
    db.refresh(free_req)
    check("قبول طلب على وقت حرّ في عيادة الطبيب الواحد يعمل كما كان",
          err is None and free_req.status == "pending" and free_req.clinic_doctor_id is None)
    check("والاستجابة تحمل clinic_doctor_id", "clinic_doctor_id" in result)

    # -------------------------------------------------------------
    print("\n[8] المخطط")
    absent = main.AppointmentRespondRequest(decision="accept")
    explicit_null = main.AppointmentRespondRequest(decision="accept", clinic_doctor_id=None)
    check("غياب الحقل لا يظهر في model_fields_set (تعيين تلقائي)", "clinic_doctor_id" not in absent.model_fields_set)
    check("null الصريحة تظهر فيه (= المدير)", "clinic_doctor_id" in explicit_null.model_fields_set)

    db.close()


run()
print("\n" + ("=" * 46))
if FAILURES:
    print(f"فشل {len(FAILURES)} فحص:")
    for f in FAILURES:
        print("  -", f)
    sys.exit(1)
print("كل الفحوص نجحت")
