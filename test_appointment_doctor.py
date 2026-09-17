"""فحص تكامل حقيقي: عمود الطبيب المنفّذ على المواعيد + فحص التعارض لكل طبيب."""
import os, sys, tempfile
os.environ.setdefault("SECRET_KEY", "test-secret-key-0123456789")
os.environ.setdefault("DATABASE_URL", "sqlite:///" + os.path.join(tempfile.mkdtemp(), "t.db"))

import models, database, main
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import sessionmaker
from datetime import datetime, date
from fastapi import HTTPException

fails = []
def ok(cond, label):
    print(("PASS  " if cond else "FAIL  ") + label)
    if not cond: fails.append(label)

# --- قاعدة بيانات نظيفة ---
eng = create_engine("sqlite:///" + os.path.join(tempfile.mkdtemp(), "live.db"))
models.Base.metadata.create_all(eng)
S = sessionmaker(bind=eng)
db = S()

ok("clinic_doctor_id" in {c["name"] for c in inspect(eng).get_columns("appointments")},
   "1. العمود clinic_doctor_id أُنشئ في جدول المواعيد")

# --- ترحيل على جدول قديم بلا العمود ---
old_eng = create_engine("sqlite:///" + os.path.join(tempfile.mkdtemp(), "old.db"))
with old_eng.begin() as c:
    c.execute(text("CREATE TABLE appointments (id INTEGER PRIMARY KEY, patient_name VARCHAR, "
                   "appointment_time VARCHAR, procedure_type VARCHAR, status VARCHAR, "
                   "appointment_date DATETIME, duration_minutes INTEGER NOT NULL DEFAULT 30)"))
    c.execute(text("INSERT INTO appointments (patient_name, appointment_time, procedure_type, status, "
                   "appointment_date) VALUES ('مريض قديم','09:00','حشوة','pending','2026-09-17 09:00:00')"))
insp = inspect(old_eng)
if "clinic_doctor_id" not in {c["name"] for c in insp.get_columns("appointments")}:
    with old_eng.begin() as c:
        c.execute(text("ALTER TABLE appointments ADD COLUMN clinic_doctor_id INTEGER"))
with old_eng.begin() as c:
    row = c.execute(text("SELECT patient_name, clinic_doctor_id, duration_minutes FROM appointments")).fetchone()
ok(row[1] is None and row[2] == 30, "2. الموعد القديم بعد الترحيل: clinic_doctor_id = NULL ومدته 30 بلا تعبئة يدوية")

# --- أطباء عيادتين ---
lina = models.ClinicDoctor(clinic_email="a@c.com", full_name="د. لينا مرعي", commission_percent=40)
fadi = models.ClinicDoctor(clinic_email="a@c.com", full_name="د. فادي نصّار", commission_percent=35)
other = models.ClinicDoctor(clinic_email="b@c.com", full_name="طبيب عيادة أخرى", commission_percent=50)
db.add_all([lina, fadi, other]); db.commit()

def appt(name, hh, dur, doc_id, status="pending", email="a@c.com"):
    a = models.Appointment(
        doctor_email=email, patient_name=name, appointment_time=hh, procedure_type="علاج",
        status=status, duration_minutes=dur, clinic_doctor_id=doc_id,
        appointment_date=datetime.fromisoformat("2026-09-17T%s:00" % hh),
    )
    db.add(a); db.commit(); db.refresh(a); return a

a_lina = appt("مريض لينا", "10:00", 60, lina.id)

# --- الخلل المُصلَح: طبيبان في نفس الساعة ---
try:
    main.ensure_appointment_slot_is_free(
        db, "a@c.com", datetime.fromisoformat("2026-09-17T10:00:00"), 60, clinic_doctor_id=fadi.id)
    ok(True, "3. ‼️ فادي يستطيع استقبال مريض 10:00 بينما لينا مشغولة (الخلل المُصلَح)")
except HTTPException as e:
    ok(False, "3. فادي مُنِع بلا سبب: " + str(e.detail))

# --- التعارض ضمن نفس الطبيب ما زال يُمنَع ---
try:
    main.ensure_appointment_slot_is_free(
        db, "a@c.com", datetime.fromisoformat("2026-09-17T10:30:00"), 30, clinic_doctor_id=lina.id)
    ok(False, "4. تعارض لينا مع نفسها لم يُمنَع")
except HTTPException as e:
    ok(e.status_code == 409 and "محجوز" in e.detail and "11:00" in e.detail,
       "4. تعارض لينا مع نفسها يُمنَع بـ409 ويقترح 11:00 — " + e.detail[:70])

# --- التلاصق back-to-back ليس تعارضاً ---
try:
    main.ensure_appointment_slot_is_free(
        db, "a@c.com", datetime.fromisoformat("2026-09-17T11:00:00"), 30, clinic_doctor_id=lina.id)
    ok(True, "5. موعد ملاصق 11:00 بعد موعد ينتهي 11:00 ليس تعارضاً")
except HTTPException as e:
    ok(False, "5. التلاصق اعتُبر تعارضاً: " + str(e.detail))

# --- عيادة الطبيب الواحد: NULL يتعارض مع NULL (لا انحدار) ---
a_mgr = appt("مريض المدير", "13:00", 60, None)
try:
    main.ensure_appointment_slot_is_free(
        db, "a@c.com", datetime.fromisoformat("2026-09-17T13:15:00"), 30, clinic_doctor_id=None)
    ok(False, "6. موعدا المدير المتقاطعان لم يُمنَعا (انحدار على عيادة الطبيب الواحد)")
except HTTPException as e:
    ok(e.status_code == 409, "6. لا انحدار: موعدان متقاطعان للمدير (NULL) ما زالا مرفوضين")

# --- موعد المدير لا يمنع لينا والعكس ---
try:
    main.ensure_appointment_slot_is_free(
        db, "a@c.com", datetime.fromisoformat("2026-09-17T13:00:00"), 60, clinic_doctor_id=lina.id)
    ok(True, "7. موعد المدير 13:00 لا يمنع لينا في نفس الساعة")
except HTTPException as e:
    ok(False, "7. " + str(e.detail))

# --- استبعاد الموعد نفسه عند تعديله ---
try:
    main.ensure_appointment_slot_is_free(
        db, "a@c.com", datetime.fromisoformat("2026-09-17T10:00:00"), 90,
        exclude_appointment_id=a_lina.id, clinic_doctor_id=lina.id)
    ok(True, "8. تمديد موعد لينا نفسه إلى 90 دقيقة لا يتعارض مع نفسه")
except HTTPException as e:
    ok(False, "8. " + str(e.detail))

# --- عزل العيادات في العمود الجديد ---
try:
    main.resolve_appointment_clinic_doctor(db, "a@c.com", other.id)
    ok(False, "9. قُبِل طبيب من عيادة أخرى (ثغرة عزل)")
except HTTPException as e:
    ok(e.status_code == 404, "9. طبيب عيادة أخرى مرفوض بـ404 (العزل سليم)")
ok(main.resolve_appointment_clinic_doctor(db, "a@c.com", None) is None, "10. None = الطبيب المدير، مقبول")
ok(main.resolve_appointment_clinic_doctor(db, "a@c.com", lina.id) == lina.id, "10b. طبيب العيادة نفسها مقبول")

# --- الحالة الثلاثية في AppointmentUpdate ---
u_none = main.AppointmentUpdate(**{"clinic_doctor_id": None})
u_absent = main.AppointmentUpdate(**{"time": "11:00"})
u_set = main.AppointmentUpdate(**{"clinic_doctor_id": lina.id})
ok("clinic_doctor_id" in u_none.model_fields_set, "11. null صريحة تُقرأ كتعديل حقيقي (إرجاع للمدير)")
ok("clinic_doctor_id" not in u_absent.model_fields_set, "12. غياب الحقل لا يُقرأ كتعديل")
ok("clinic_doctor_id" in u_set.model_fields_set and u_set.clinic_doctor_id == lina.id, "13. تعيين طبيب يُقرأ صحيحاً")

# --- AppointmentCreate الافتراضي (عميل قديم / تطبيق أندرويد) ---
c_old = main.AppointmentCreate(**{"patient_id": 1, "date": "2026-09-17", "time": "09:00", "description": "حشوة"})
ok(c_old.clinic_doctor_id is None, "14. عميل قديم لا يرسل الحقل -> الموعد للمدير (لا كسر للتطبيق)")

# --- الحالات غير الحاجزة ---
appt("طلب حجز", "15:00", 30, lina.id, status="pending_confirmation")
try:
    main.ensure_appointment_slot_is_free(
        db, "a@c.com", datetime.fromisoformat("2026-09-17T15:00:00"), 30, clinic_doctor_id=lina.id)
    ok(True, "15. طلب الحجز غير المؤكَّد لا يحجز وقتاً (كما قبل التعديل)")
except HTTPException as e:
    ok(False, "15. " + str(e.detail))

# --- AppointmentResponse يحمل الحقلين ---
f = main.AppointmentResponse.model_fields
ok("clinic_doctor_id" in f and "clinic_doctor_name" in f, "16. استجابة الموعد تحمل معرّف الطبيب واسمه")

print()
print("=" * 62)
print("فشل %d من %d" % (len(fails), 16 + len(fails)) if fails else "كل الفحوص نجحت")
for x in fails: print("  -", x)
sys.exit(1 if fails else 0)
