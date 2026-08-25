#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
إصلاح خطأ 500 Internal Server Error في GET /api/patients (ظهر بعد نشر
الإصلاح 306b083 مباشرة، عند إنشاء أول مريض حقيقي عبر نظام الحجز الجديد).

المشكلة بالتفصيل:
  دالة find_or_create_patient_for_booking() (الإصلاح الذي نشرناه للتو) تُنشئ
  سجل مريض جديد دون تحديد قيمة لحقل birth_date -- فيبقى None في قاعدة البيانات،
  وهذا سلوك طبيعي ومتوقع (لا يُعرف تاريخ ميلاد المريض من نموذج الحجز العام).

  لكن نموذج الرد PatientCreate (المُعرَّف في main.py، ويرثه PatientResponse
  المستخدم في GET /api/patients) يكتب الحقل هكذا:

      birth_date: date = None
      gender: str = None

  وهذا خطأ شائع في الانتقال من Pydantic v1 إلى v2: في v1 كانت القيمة
  الافتراضية None كافية لجعل الحقل اختيارياً ضمنياً. لكن في v2 (المستخدم في
  هذا المشروع) يجب تصريح النوع بوضوح كـ Optional[date] وإلا فإن أي محاولة
  لإرجاع قيمة None فعلية من قاعدة البيانات تفشل بخطأ تحقق (ValidationError)
  يظهر للمستخدم كـ "Internal Server Error" -- وهذا بالضبط ما يحدث الآن مع أي
  مريض ليس له تاريخ ميلاد مسجّل (وأغلب المرضى القادمين من نظام الحجز العام لن
  يكون لديهم ذلك).

  ملاحظة: gender مضبوط دائماً على "Male" من دالة الحجز، فلن يسبب Crash فورياً
  بنفس الطريقة، لكنه يحمل نفس الخطأ البرمجي تماماً وقد يسبب نفس المشكلة لاحقاً
  (مثلاً لأي مريض قديم أُدخل يدوياً دون تحديد الجنس) -- لذلك يُصلَح الآن أيضاً
  كإجراء وقائي ضمن نفس الإصلاح.

الإصلاح: تغيير الحقلين ضمن class PatientCreate فقط إلى:

      birth_date: Optional[date] = None
      gender: Optional[str] = None

  (Optional[str] و Optional[date] موجودتان مسبقاً كاستيراد في أعلى main.py
  ضمن "from typing import Optional" و "from datetime import date" -- لا حاجة
  لأي استيراد إضافي.)

شغّل هذا الملف من داخل نفس مجلد main.py (جذر المشروع):
    python fix_patient_response_500.py

ملاحظة تقنية: يعمل هذا السكربت على مستوى البايتات مباشرة (read_bytes/write_bytes)
ليحافظ تماماً على نهايات الأسطر الأصلية (CRLF) في main.py، ولا يغيّر أي سطر
آخر في الملف.
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "main.py"

OLD_BLOCK = (
    "class PatientCreate(BaseModel):\r\n"
    "    doctor_name: Optional[str] = None\r\n"
    "    doctor_email: Optional[str] = None\r\n"
    "    full_name: str\r\n"
    "    phone: str\r\n"
    "    birth_date: date = None\r\n"
    "    gender: str = None\r\n"
    "    medical_history: Optional[str] = None\r\n"
    "    total_treatment_cost: float = 0.0"
)

NEW_BLOCK = (
    "class PatientCreate(BaseModel):\r\n"
    "    doctor_name: Optional[str] = None\r\n"
    "    doctor_email: Optional[str] = None\r\n"
    "    full_name: str\r\n"
    "    phone: str\r\n"
    "    birth_date: Optional[date] = None\r\n"
    "    gender: Optional[str] = None\r\n"
    "    medical_history: Optional[str] = None\r\n"
    "    total_treatment_cost: float = 0.0"
)


def main():
    if not TARGET.exists():
        print(f"[x] لم أجد main.py بجانب هذا الملف بالضبط ({TARGET}).")
        print("    تأكد أنك تشغّل هذا السكربت من داخل جذر المشروع (نفس مجلد main.py).")
        sys.exit(1)

    raw = TARGET.read_bytes()
    old_needle = OLD_BLOCK.encode("utf-8")
    new_needle = NEW_BLOCK.encode("utf-8")

    if new_needle in raw:
        print("[v] main.py يحتوي مسبقاً على النسخة المُصلَحة -- لا حاجة لأي تعديل.")
        return

    if old_needle not in raw:
        print("[x] لم أجد نص class PatientCreate بالشكل المتوقع تماماً في main.py.")
        print("    قد يكون الملف تغيّر عن النسخة المعروفة لي. لم يُعدَّل أي شيء.")
        print("    أرسل لي محتوى class PatientCreate الحالي لأحدّث الإصلاح.")
        sys.exit(1)

    backup_path = TARGET.with_name("main.py.pre-patient-500-fix.bak")
    backup_path.write_bytes(raw)

    new_raw = raw.replace(old_needle, new_needle, 1)
    TARGET.write_bytes(new_raw)

    print("[v] تم إصلاح main.py بنجاح.")
    print(f"    نسخة احتياطية من قبل التعديل: {backup_path.name}")
    print("\nالتغيير المُطبَّق داخل class PatientCreate:")
    print("    birth_date: date = None       ->  birth_date: Optional[date] = None")
    print("    gender: str = None            ->  gender: Optional[str] = None")
    print("\nالخطوة التالية:")
    print("    git add main.py")
    print('    git commit -m "إصلاح خطأ 500 في GET /api/patients بسبب birth_date/gender غير Optional"')
    print("    git push")
    print("(Render سينشر تلقائياً -- أو اضغط Manual Deploy إن لم يبدأ خلال دقيقة).")


if __name__ == "__main__":
    main()
