#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
إصلاح حقل "ابحث عن مريض..." في index.html الذي لا يُصفّي القائمة إطلاقاً.

المشكلة بالتفصيل:
  دالة renderPatients() كانت تمرّ على كل المرضى (sourcePatients.forEach) وتُنشئ
  صفاً/بطاقة لكل واحد منهم دائماً بلا استثناء -- الفرق الوحيد عند وجود نص بحث
  هو تلوين الصفوف المطابقة بخلفية خضراء فاتحة (matched ? ... : ...)، لكن
  الصفوف غير المطابقة كانت تبقى ظاهرة كلها أيضاً. كانت هناك حتى رسالة توضّح
  هذا صراحة عند عدم وجود أي تطابق: "لا توجد مطابقة لهذا البحث، لكن القائمة
  الكاملة ما زالت ظاهرة" -- أي أن القائمة لا تُصفّى أبداً بغض النظر عمّا يُكتب.

  الدليل الإضافي: كانت هناك دالة filterPatients() معرَّفة بالكامل في الملف
  (تُرجع نسخة مُصفَّاة فعلياً من قائمة المرضى) لكنها غير مُستخدَمة في أي مكان
  إطلاقاً -- ما يؤكد أن التصفية الفعلية سقطت سهواً أثناء تعديل سابق لدالة
  renderPatients(), وبقيت آلية التلوين فقط بدلاً منها.

الإصلاح: عند وجود نص بحث فعلي، يتم الآن تخطي (return) أي مريض غير مطابق قبل
إنشاء صف الجدول أو بطاقة الموبايل الخاصة به -- فتُصفَّى القائمة فعلياً بدل أن
تُلوَّن فقط. عند عدم وجود نص بحث (الحقل فارغ) تظهر القائمة كاملة كما كانت
تماماً دون أي تغيير في هذه الحالة.

شغّل هذا الملف من داخل مجلد frontend_web نفسه:
    python fix_patient_search_not_filtering.py

ملاحظة تقنية: يعمل هذا السكربت على مستوى البايتات مباشرة (read_bytes/write_bytes)
ليحافظ تماماً على نهايات الأسطر الأصلية (CRLF) في index.html، ولا يغيّر أي سطر
آخر في الملف. يعمل بشكل مستقل تماماً عن سكربتي إصلاح main.py وإصلاح اسم الطبيب
القديم -- لا تعارض بينهم إطلاقاً.
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "index.html"

OLD_BLOCK = (
    "      sourcePatients.forEach(patient => {\r\n"
    "        const tr = document.createElement('tr');\r\n"
    "        const matched = isPatientMatch(patient, normalizedQuery);\r\n"
    "        tr.className = matched"
)

NEW_BLOCK = (
    "      sourcePatients.forEach(patient => {\r\n"
    "        const matched = isPatientMatch(patient, normalizedQuery);\r\n"
    "\r\n"
    "        // فلترة فعلية عند وجود نص بحث: نعرض فقط المرضى المطابقين فعلاً بدل\r\n"
    "        // عرض القائمة كاملة وتمييز المطابق منها بلون فقط -- هذا كان الخلل\r\n"
    "        // الفعلي (دالة filterPatients() المُعرَّفة بالأعلى كانت غير مُستخدَمة\r\n"
    "        // إطلاقاً): حقل البحث كان \"يُبرز\" الصفوف المطابقة فقط دون أن يُخفي\r\n"
    "        // بقية الصفوف، فبدا للمستخدم أن البحث لا يعمل -- إصلاح 2026-08-25.\r\n"
    "        if (normalizedQuery && !matched) return;\r\n"
    "\r\n"
    "        const tr = document.createElement('tr');\r\n"
    "        tr.className = matched"
)


def main():
    if not TARGET.exists():
        print(f"[x] لم أجد index.html بجانب هذا الملف بالضبط ({TARGET}).")
        print("    تأكد أنك تشغّل هذا السكربت من داخل مجلد frontend_web نفسه.")
        sys.exit(1)

    raw = TARGET.read_bytes()
    old_needle = OLD_BLOCK.encode("utf-8")
    new_needle = NEW_BLOCK.encode("utf-8")

    if new_needle in raw:
        print("[v] index.html يحتوي مسبقاً على النسخة المُصلَحة -- لا حاجة لأي تعديل.")
        return

    if old_needle not in raw:
        print("[x] لم أجد نص دالة renderPatients() بالشكل المتوقع تماماً في index.html.")
        print("    قد يكون الملف تغيّر عن النسخة المعروفة لي. لم يُعدَّل أي شيء.")
        print("    أرسل لي محتوى دالة renderPatients() الحالية لأحدّث الإصلاح.")
        sys.exit(1)

    backup_path = TARGET.with_name(TARGET.name + ".pre-patient-search-fix.bak")
    backup_path.write_bytes(raw)

    new_raw = raw.replace(old_needle, new_needle, 1)
    TARGET.write_bytes(new_raw)

    print("[v] تم إصلاح index.html بنجاح.")
    print(f"    نسخة احتياطية من قبل التعديل: {backup_path.name}")
    print("\nالتغيير المُطبَّق: حقل البحث يُصفّي قائمة المرضى فعلياً الآن بدل تلوينها فقط.")
    print("\nالخطوة التالية:")
    print("    git add index.html")
    print('    git commit -m "إصلاح حقل بحث المرضى في index.html ليُصفّي القائمة فعلياً"')
    print("    git push")
    print("(Render سينشر تلقائياً -- أو اضغط Manual Deploy إن لم يبدأ خلال دقيقة).")


if __name__ == "__main__":
    main()
