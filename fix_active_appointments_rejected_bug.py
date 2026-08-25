#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
إصلاح خطأ منطقي في عدّاد "المواعيد النشطة" (active_appointments) داخل
GET /api/patients/stats -- اكتُشف أثناء التحقق النهائي من نشر 306b083.

المشكلة بالتفصيل:
  المنطق الحالي:

      is_upcoming = appointment_date is not None and appointment_date >= now
      is_pending  = appointment_status in {"pending", "upcoming", "pending_confirmation"}
      if is_upcoming or is_pending:
          active_appointments += 1

  بما أن الشرط "or" -- أي موعد تاريخه اليوم أو في المستقبل (is_upcoming=True)
  يُحسب كـ"نشط" بغض النظر عن حالته الفعلية. هذا يعني أن موعداً تم **رفضه**
  فعلياً (status="rejected") لكن تاريخه لم يمر بعد سيُحسب خطأً ضمن "المواعيد
  النشطة" -- وهو ما لوحظ فعلياً أثناء الفحص: موعدان بحالة "rejected" بتاريخ
  اليوم (25 أغسطس) ظهرا في العدّاد رغم أن الطبيب رفضهما فعلياً.

  ملاحظة: نفس الملف main.py يحتوي تعليقاً بالفعل (بالقرب من دالة إتاحة
  الأوقات المحجوزة) يوضّح أن "rejected" و"no_show" حالتان لا تشغلان الوقت
  ولا تعتبران نشطتين -- لذا الإصلاح هنا متّسق تماماً مع افتراض بقية الكود.

الإصلاح: استبعاد أي موعد بحالة "rejected" أو "no_show" من العدّ فوراً (قبل
فحص التاريخ)، بغض النظر عن تاريخه.

شغّل هذا الملف من داخل نفس مجلد main.py (جذر المشروع):
    python fix_active_appointments_rejected_bug.py

(يمكن تشغيله بأي ترتيب بالنسبة لسكربت fix_patient_response_500.py -- الاثنان
يعدّلان أجزاء مختلفة تماماً من main.py ولا يتعارضان.)

ملاحظة تقنية: يعمل هذا السكربت على مستوى البايتات مباشرة (read_bytes/write_bytes)
ليحافظ تماماً على نهايات الأسطر الأصلية (CRLF) في main.py، ولا يغيّر أي سطر
آخر في الملف.
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "main.py"

OLD_BLOCK = (
    "        for appointment in appointments:\r\n"
    "            appointment_status = (appointment.status or \"\").strip().lower()\r\n"
    "            appointment_date = appointment.appointment_date\r\n"
    "            is_upcoming = appointment_date is not None and appointment_date >= now\r\n"
    "            is_pending = appointment_status in {\"pending\", \"upcoming\", \"pending_confirmation\"}\r\n"
    "\r\n"
    "            if is_upcoming or is_pending:\r\n"
    "                active_appointments += 1"
)

NEW_BLOCK = (
    "        for appointment in appointments:\r\n"
    "            appointment_status = (appointment.status or \"\").strip().lower()\r\n"
    "\r\n"
    "            # \"rejected\" و\"no_show\" حالتان نهائيتان -- لا تُحسبان ضمن المواعيد\r\n"
    "            # النشطة أبداً حتى لو كان appointment_date لا يزال اليوم أو في\r\n"
    "            # المستقبل (مثال: طبيب يرفض حجزاً ليوم غد يبقى \"مرفوضاً\" فوراً، لا\r\n"
    "            # \"نشطاً\" حتى يمر تاريخ الغد) -- إصلاح 2026-08-25.\r\n"
    "            if appointment_status in {\"rejected\", \"no_show\"}:\r\n"
    "                continue\r\n"
    "\r\n"
    "            appointment_date = appointment.appointment_date\r\n"
    "            is_upcoming = appointment_date is not None and appointment_date >= now\r\n"
    "            is_pending = appointment_status in {\"pending\", \"upcoming\", \"pending_confirmation\"}\r\n"
    "\r\n"
    "            if is_upcoming or is_pending:\r\n"
    "                active_appointments += 1"
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
        print("[x] لم أجد نص حلقة عدّ active_appointments بالشكل المتوقع تماماً في main.py.")
        print("    قد يكون الملف تغيّر عن النسخة المعروفة لي. لم يُعدَّل أي شيء.")
        print("    أرسل لي محتوى دالة get_patient_stats الحالية لأحدّث الإصلاح.")
        sys.exit(1)

    backup_path = TARGET.with_name("main.py.pre-active-appointments-fix.bak")
    backup_path.write_bytes(raw)

    new_raw = raw.replace(old_needle, new_needle, 1)
    TARGET.write_bytes(new_raw)

    print("[v] تم إصلاح main.py بنجاح.")
    print(f"    نسخة احتياطية من قبل التعديل: {backup_path.name}")
    print("\nالتغيير المُطبَّق: تجاهل أي موعد بحالة rejected/no_show فوراً في عدّاد active_appointments.")
    print("\nالخطوة التالية:")
    print("    git add main.py")
    print('    git commit -m "إصلاح عدّ المواعيد المرفوضة ضمن active_appointments"')
    print("    git push")
    print("(Render سينشر تلقائياً -- أو اضغط Manual Deploy إن لم يبدأ خلال دقيقة).")


if __name__ == "__main__":
    main()
