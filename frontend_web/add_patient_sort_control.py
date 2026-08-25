#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
إضافة زر/قائمة فرز لقائمة المرضى في index.html -- فرز حسب الاسم أو تاريخ
الميلاد (لا يوجد حقل "تاريخ تسجيل" منفصل للمريض في قاعدة البيانات حالياً،
فتاريخ الميلاد هو الحقل الزمني الوحيد المتاح لكل مريض).

ماذا يضيف هذا السكربت بالضبط:
  1. قائمة منسدلة (select) بجانب حقل البحث وزر "إضافة مريض جديد"، بثلاثة
     خيارات: الترتيب الافتراضي (كما وصل من السيرفر)، فرز حسب الاسم (أبجدياً)،
     فرز حسب تاريخ الميلاد (الأقدم أولاً -- المرضى بلا تاريخ ميلاد مسجَّل
     يُوضعون تلقائياً في نهاية القائمة بدل التسبب بخطأ).
  2. دالة sortPatientsList() تُطبَّق تلقائياً داخل renderPatients() الموجودة
     أصلاً، فيبقى الفرز متوافقاً مع البحث الحالي (يُصفّي ثم يُفرز، أو العكس --
     كلاهما مطبَّق معاً بلا تعارض).
  3. عند تغيير الاختيار في القائمة، تُعاد القائمة الحالية (المُصفّاة إن وُجد
     بحث) بالترتيب الجديد فوراً دون طلب بيانات إضافية من السيرفر.

شغّل هذا الملف من داخل مجلد frontend_web نفسه:
    python add_patient_sort_control.py

ملاحظة تقنية: يعمل هذا السكربت على مستوى البايتات مباشرة (read_bytes/write_bytes)
ليحافظ تماماً على نهايات الأسطر الأصلية (CRLF) في index.html. مستقل تماماً عن
سكربتي إصلاح اسم الطبيب وإصلاح حقل البحث -- لا تعارض بينهم، يمكن تشغيلهم
بأي ترتيب.
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "index.html"

PATCHES = []

# --- 1. عنصر الواجهة (select) بجانب حقل البحث --------------------------------
PATCHES.append((
    "عنصر الواجهة (قائمة الفرز)",
    (
        '          <div class="relative w-full sm:w-64 md:w-72 lg:w-80">\r\n'
        '            <input id="searchInput" type="search" placeholder="🔍 ابحث عن مريض..." class="w-full rounded-2xl border border-slate-300 bg-white py-3 pr-10 pl-4 text-sm outline-none focus:border-indigo-500 focus:ring-4 focus:ring-indigo-100" />\r\n'
        '          </div>'
    ),
    (
        '          <div class="relative w-full sm:w-64 md:w-72 lg:w-80">\r\n'
        '            <input id="searchInput" type="search" placeholder="🔍 ابحث عن مريض..." class="w-full rounded-2xl border border-slate-300 bg-white py-3 pr-10 pl-4 text-sm outline-none focus:border-indigo-500 focus:ring-4 focus:ring-indigo-100" />\r\n'
        '          </div>\r\n'
        '          <select id="patientSortSelect" class="w-full rounded-2xl border border-slate-300 bg-white py-3 px-4 text-sm font-semibold text-slate-600 outline-none focus:border-indigo-500 focus:ring-4 focus:ring-indigo-100 sm:w-auto" title="فرز قائمة المرضى">\r\n'
        '            <option value="default">↕️ الترتيب الافتراضي</option>\r\n'
        '            <option value="name">🔤 فرز حسب: الاسم</option>\r\n'
        '            <option value="birth_date">🎂 فرز حسب: تاريخ الميلاد</option>\r\n'
        '          </select>'
    ),
))

# --- 2. مرجع العنصر في JS ----------------------------------------------------
PATCHES.append((
    "مرجع عنصر الفرز في JS",
    "    const searchInput = document.getElementById('searchInput');",
    (
        "    const searchInput = document.getElementById('searchInput');\r\n"
        "    const patientSortSelect = document.getElementById('patientSortSelect');"
    ),
))

# --- 3. دالة الفرز + تطبيقها داخل renderPatients -----------------------------
PATCHES.append((
    "دالة الفرز وتطبيقها في renderPatients",
    (
        '    function renderPatients(patients, query=""){\r\n'
        '      const sourcePatients = Array.isArray(patients) ? patients : [];'
    ),
    (
        '    // فرز قائمة المرضى حسب الاختيار في patientSortSelect (2026-08-25) --\r\n'
        '    // "الاسم" ترتيب أبجدي عربي، و"تاريخ الميلاد" الأقدم أولاً (المرضى بلا\r\n'
        '    // تاريخ ميلاد مسجَّل يُوضعون في نهاية القائمة بدل التسبب بخطأ أو ترتيب\r\n'
        '    // عشوائي). "الترتيب الافتراضي" يُبقي ترتيب وصول البيانات من السيرفر كما هو.\r\n'
        '    function sortPatientsList(patients, sortMode) {\r\n'
        '      const list = Array.isArray(patients) ? patients.slice() : [];\r\n'
        "      if (sortMode === 'name') {\r\n"
        "        list.sort((a, b) => String(a.full_name || '').localeCompare(String(b.full_name || ''), 'ar'));\r\n"
        "      } else if (sortMode === 'birth_date') {\r\n"
        '        list.sort((a, b) => {\r\n'
        '          const dateA = a.birth_date ? new Date(a.birth_date).getTime() : Infinity;\r\n'
        '          const dateB = b.birth_date ? new Date(b.birth_date).getTime() : Infinity;\r\n'
        '          return dateA - dateB;\r\n'
        '        });\r\n'
        '      }\r\n'
        '      return list;\r\n'
        '    }\r\n'
        '\r\n'
        '    function renderPatients(patients, query=""){\r\n'
        "      const sortMode = patientSortSelect ? patientSortSelect.value : 'default';\r\n"
        '      const sourcePatients = sortPatientsList(Array.isArray(patients) ? patients : [], sortMode);'
    ),
))

# --- 4. مستمع تغيير اختيار الفرز ---------------------------------------------
PATCHES.append((
    "مستمع تغيير الفرز",
    (
        "    searchInput.addEventListener('input', function(){\r\n"
        '      const query = this.value.trim();\r\n'
        '      renderPatients(allPatients, query);\r\n'
        '    });'
    ),
    (
        "    searchInput.addEventListener('input', function(){\r\n"
        '      const query = this.value.trim();\r\n'
        '      renderPatients(allPatients, query);\r\n'
        '    });\r\n'
        '\r\n'
        '    if (patientSortSelect) {\r\n'
        "      patientSortSelect.addEventListener('change', function(){\r\n"
        '        renderPatients(allPatients, searchInput.value.trim());\r\n'
        '      });\r\n'
        '    }'
    ),
))


def main():
    if not TARGET.exists():
        print(f"[x] لم أجد index.html بجانب هذا الملف بالضبط ({TARGET}).")
        print("    تأكد أنك تشغّل هذا السكربت من داخل مجلد frontend_web نفسه.")
        sys.exit(1)

    raw = TARGET.read_bytes()
    already_applied = 0
    applied = 0

    for label, old_text, new_text in PATCHES:
        old_needle = old_text.encode("utf-8")
        new_needle = new_text.encode("utf-8")

        if new_needle in raw:
            print(f"[.] {label}: مُطبَّق مسبقاً -- تخطّي.")
            already_applied += 1
            continue

        if old_needle not in raw:
            print(f"[x] {label}: لم أجد النص المتوقع بالشكل تماماً. توقفت دون تعديل الملف.")
            print("    أرسل لي محتوى الجزء المعني الحالي من index.html لأحدّث الإصلاح.")
            sys.exit(1)

        raw = raw.replace(old_needle, new_needle, 1)
        applied += 1
        print(f"[v] {label}: تم التطبيق.")

    if applied == 0:
        print("\n[v] كل التعديلات مُطبَّقة مسبقاً على index.html -- لا حاجة لأي شيء.")
        return

    backup_path = TARGET.with_name(TARGET.name + ".pre-patient-sort-feature.bak")
    backup_path.write_bytes(TARGET.read_bytes())
    TARGET.write_bytes(raw)

    print(f"\n[v] تم تحديث index.html بنجاح ({applied} تعديلاً جديداً).")
    print(f"    نسخة احتياطية من قبل التعديل: {backup_path.name}")
    print("\nالخطوة التالية:")
    print("    git add index.html")
    print('    git commit -m "إضافة زر فرز قائمة المرضى (الاسم / تاريخ الميلاد)"')
    print("    git push")
    print("(Render سينشر تلقائياً -- أو اضغط Manual Deploy إن لم يبدأ خلال دقيقة).")


if __name__ == "__main__":
    main()
