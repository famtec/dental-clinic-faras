#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
إصلاح مشكلة "اسم الطبيب الخاطئ/القديم" الذي يظهر في أعلى الصفحات (index.html
وغيرها) عند الدخول إليها، ولا يُصحَّح إلا بعد زيارة صفحة "حسابي" ثم العودة.

المشكلة بالتفصيل:
  كل صفحة (index.html, appointments.html, finance.html, inventory.html,
  patient_record.html, contact_developer.html) تعرض اسم الطبيب في الأعلى من
  قيمة مخزَّنة محلياً فقط:

      const doctorName = localStorage.getItem('doctor_name');
      titleElement.textContent = doctorName ? `عيادة ${doctorName}` : ...;

  هذه القيمة تُكتب فقط عند تسجيل الدخول (login.html) أو عند زيارة صفحة
  "حسابي" (profile.html، التي تجلب البيانات الطازجة من GET /api/auth/profile
  وتُحدِّث localStorage.doctor_name فوراً). أي صفحة أخرى لا تُحدِّثها أبداً --
  فإن كانت القيمة المخزَّنة قديمة (مثلاً بعد تبديل الحساب على نفس المتصفح، أو
  بعد تعديل الاسم من "حسابي" في جلسة سابقة لم تُحفظ محلياً لأي سبب)، تبقى
  الصفحات الأخرى تعرض الاسم القديم إلى أن تُزار "حسابي" فتُصلحه من جديد --
  وهذا بالضبط ما لوحظ.

الإصلاح: كل صفحة من الستة أصبحت الآن تجلب اسم الطبيب الحقيقي من
GET /api/auth/profile بشكل غير حاجب (async، لا يُبطئ عرض الصفحة) فور
تحميلها، وتُحدِّث كلاً من localStorage والعنوان المعروض فوراً بالقيمة
الصحيحة -- تماماً بنفس الآلية التي تستخدمها "حسابي" أصلاً، بدل انتظار زيارة
تلك الصفحة تحديداً لتصحيح الاسم. القيمة المخزَّنة تبقى تُعرض فوراً كحالة أولية
مؤقتة ريثما يصل رد السيرفر (لا فرق ملحوظ في السرعة)، ثم تُستبدَل بالقيمة
الصحيحة بمجرد وصول الرد.

صفحة contact_developer.html مُعالَجة بحذر إضافي لأنها الوحيدة بين الست التي لا
تتطلب تسجيل دخول إجبارياً (يمكن الوصول إليها كزائر غير مسجَّل) -- الإصلاح هناك
يتحقق أولاً من وجود بريد طبيب مسجَّل قبل أي محاولة جلب، فلا يحدث أي طلب شبكة
إضافي أو أي خطأ لزائر غير مسجَّل الدخول.

شغّل هذا الملف من داخل مجلد frontend_web نفسه:
    python fix_stale_doctor_name.py

ملاحظة تقنية: يعمل هذا السكربت على مستوى البايتات مباشرة (read_bytes/write_bytes)
ليحافظ تماماً على نهايات الأسطر الأصلية (CRLF) وأسلوب المسافات/التبويب (tabs
مقابل spaces) الخاص بكل ملف على حدة، ولا يغيّر أي سطر آخر غير المقصود.
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

# كل عنصر: (اسم الملف، النص القديم، النص الجديد)
PATCHES = []

# ---------------------------------------------------------------------------
# index.html -- مسافتان لكل مستوى تعشيش، 4 مسافات كمستوى أساسي
# ---------------------------------------------------------------------------
PATCHES.append((
    "index.html",
    (
        "    if (titleElement) {\r\n"
        "      titleElement.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب';\r\n"
        "    }\r\n"
        "    if (mobileClinicTitle) {\r\n"
        "      mobileClinicTitle.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب';\r\n"
        "    }\r\n"
        "    renderTierBadge();"
    ),
    (
        "    if (titleElement) {\r\n"
        "      titleElement.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب';\r\n"
        "    }\r\n"
        "    if (mobileClinicTitle) {\r\n"
        "      mobileClinicTitle.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب';\r\n"
        "    }\r\n"
        "    renderTierBadge();\r\n"
        "\r\n"
        "    // تحديث اسم الطبيب من السيرفر مباشرة عند كل تحميل صفحة (2026-08-25) --\r\n"
        "    // القيمة المخزَّنة في localStorage أعلاه قد تكون قديمة (حساب آخر استخدم\r\n"
        "    // نفس المتصفح، أو اسم عُدِّل ولم يُزَر بعدها \"حسابي\") ولا تُحدَّث تلقائياً\r\n"
        "    // إلا عند زيارة تلك الصفحة تحديداً. هذا يجلب الاسم الصحيح دائماً دون\r\n"
        "    // انتظارها، مع إبقاء القيمة المخزَّنة كعرض فوري مؤقت ريثما يصل الرد.\r\n"
        "    async function refreshDoctorNameFromServer() {\r\n"
        "      try {\r\n"
        "        const response = await fetch(apiUrl('/api/auth/profile'), { headers: getDoctorAuthHeaders() });\r\n"
        "        if (!response.ok) return;\r\n"
        "        const profile = await response.json();\r\n"
        "        const freshName = (profile.doctor_name || '').trim();\r\n"
        "        if (!freshName) return;\r\n"
        "        localStorage.setItem('doctor_name', freshName);\r\n"
        "        if (titleElement) titleElement.textContent = `عيادة ${freshName}`;\r\n"
        "        if (mobileClinicTitle) mobileClinicTitle.textContent = `عيادة ${freshName}`;\r\n"
        "      } catch (err) {\r\n"
        "        // تجاهل: يبقى الاسم المخزَّن محلياً معروضاً كما هو عند انقطاع الشبكة\r\n"
        "      }\r\n"
        "    }\r\n"
        "    refreshDoctorNameFromServer();"
    ),
))

# ---------------------------------------------------------------------------
# appointments.html -- 4 مسافات لكل مستوى، 8 مسافات كمستوى أساسي
# ---------------------------------------------------------------------------
PATCHES.append((
    "appointments.html",
    (
        "        if (titleElement) {\r\n"
        "            titleElement.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب المعتمد';\r\n"
        "        }\r\n"
        "        if (mobileClinicTitle) {\r\n"
        "            mobileClinicTitle.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب المعتمد';\r\n"
        "        }\r\n"
        "        renderTierBadge();"
    ),
    (
        "        if (titleElement) {\r\n"
        "            titleElement.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب المعتمد';\r\n"
        "        }\r\n"
        "        if (mobileClinicTitle) {\r\n"
        "            mobileClinicTitle.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب المعتمد';\r\n"
        "        }\r\n"
        "        renderTierBadge();\r\n"
        "\r\n"
        "        // تحديث اسم الطبيب من السيرفر مباشرة عند كل تحميل صفحة (2026-08-25) --\r\n"
        "        // انظر نفس التعليق في index.html لتفاصيل المشكلة الأصلية.\r\n"
        "        async function refreshDoctorNameFromServer() {\r\n"
        "            try {\r\n"
        "                const response = await fetch(apiUrl('/api/auth/profile'), { headers: getDoctorAuthHeaders() });\r\n"
        "                if (!response.ok) return;\r\n"
        "                const profile = await response.json();\r\n"
        "                const freshName = (profile.doctor_name || '').trim();\r\n"
        "                if (!freshName) return;\r\n"
        "                localStorage.setItem('doctor_name', freshName);\r\n"
        "                if (titleElement) titleElement.textContent = `عيادة ${freshName}`;\r\n"
        "                if (mobileClinicTitle) mobileClinicTitle.textContent = `عيادة ${freshName}`;\r\n"
        "            } catch (err) {\r\n"
        "                // تجاهل: يبقى الاسم المخزَّن محلياً معروضاً كما هو عند انقطاع الشبكة\r\n"
        "            }\r\n"
        "        }\r\n"
        "        refreshDoctorNameFromServer();"
    ),
))

# ---------------------------------------------------------------------------
# finance.html -- Tabs
# ---------------------------------------------------------------------------
PATCHES.append((
    "finance.html",
    (
        "\t\tconst doctorName = localStorage.getItem('doctor_name') || localStorage.getItem('user_name');\r\n"
        "\t\tclinicTitle.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب المعتمد';\r\n"
        "\t\tif (mobileClinicTitle) {\r\n"
        "\t\t\tmobileClinicTitle.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب المعتمد';\r\n"
        "\t\t}\r\n"
        "\t\trenderTierBadge();"
    ),
    (
        "\t\tconst doctorName = localStorage.getItem('doctor_name') || localStorage.getItem('user_name');\r\n"
        "\t\tclinicTitle.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب المعتمد';\r\n"
        "\t\tif (mobileClinicTitle) {\r\n"
        "\t\t\tmobileClinicTitle.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب المعتمد';\r\n"
        "\t\t}\r\n"
        "\t\trenderTierBadge();\r\n"
        "\r\n"
        "\t\t// تحديث اسم الطبيب من السيرفر مباشرة عند كل تحميل صفحة (2026-08-25) --\r\n"
        "\t\t// انظر نفس التعليق في index.html لتفاصيل المشكلة الأصلية.\r\n"
        "\t\tasync function refreshDoctorNameFromServer() {\r\n"
        "\t\t\ttry {\r\n"
        "\t\t\t\tconst response = await fetch(apiUrl('/api/auth/profile'), { headers: getDoctorAuthHeaders() });\r\n"
        "\t\t\t\tif (!response.ok) return;\r\n"
        "\t\t\t\tconst profile = await response.json();\r\n"
        "\t\t\t\tconst freshName = (profile.doctor_name || '').trim();\r\n"
        "\t\t\t\tif (!freshName) return;\r\n"
        "\t\t\t\tlocalStorage.setItem('doctor_name', freshName);\r\n"
        "\t\t\t\tif (clinicTitle) clinicTitle.textContent = `عيادة ${freshName}`;\r\n"
        "\t\t\t\tif (mobileClinicTitle) mobileClinicTitle.textContent = `عيادة ${freshName}`;\r\n"
        "\t\t\t} catch (err) {\r\n"
        "\t\t\t\t// تجاهل: يبقى الاسم المخزَّن محلياً معروضاً كما هو عند انقطاع الشبكة\r\n"
        "\t\t\t}\r\n"
        "\t\t}\r\n"
        "\t\trefreshDoctorNameFromServer();"
    ),
))

# ---------------------------------------------------------------------------
# inventory.html -- Tabs
# ---------------------------------------------------------------------------
PATCHES.append((
    "inventory.html",
    (
        "\t\t\tif (clinicTitle) {\r\n"
        "\t\t\t\tclinicTitle.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب';\r\n"
        "\t\t\t}\r\n"
        "\t\t\tif (mobileClinicTitle) {\r\n"
        "\t\t\t\tmobileClinicTitle.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب';\r\n"
        "\t\t\t}\r\n"
        "\t\t\trenderTierBadge();"
    ),
    (
        "\t\t\tif (clinicTitle) {\r\n"
        "\t\t\t\tclinicTitle.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب';\r\n"
        "\t\t\t}\r\n"
        "\t\t\tif (mobileClinicTitle) {\r\n"
        "\t\t\t\tmobileClinicTitle.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب';\r\n"
        "\t\t\t}\r\n"
        "\t\t\trenderTierBadge();\r\n"
        "\r\n"
        "\t\t\t// تحديث اسم الطبيب من السيرفر مباشرة عند كل تحميل صفحة (2026-08-25) --\r\n"
        "\t\t\t// انظر نفس التعليق في index.html لتفاصيل المشكلة الأصلية.\r\n"
        "\t\t\ttry {\r\n"
        "\t\t\t\tconst response = await fetch(apiUrl('/api/auth/profile'), { headers: getDoctorAuthHeaders() });\r\n"
        "\t\t\t\tif (response.ok) {\r\n"
        "\t\t\t\t\tconst profile = await response.json();\r\n"
        "\t\t\t\t\tconst freshName = (profile.doctor_name || '').trim();\r\n"
        "\t\t\t\t\tif (freshName) {\r\n"
        "\t\t\t\t\t\tlocalStorage.setItem('doctor_name', freshName);\r\n"
        "\t\t\t\t\t\tif (clinicTitle) clinicTitle.textContent = `عيادة ${freshName}`;\r\n"
        "\t\t\t\t\t\tif (mobileClinicTitle) mobileClinicTitle.textContent = `عيادة ${freshName}`;\r\n"
        "\t\t\t\t\t}\r\n"
        "\t\t\t\t}\r\n"
        "\t\t\t} catch (err) {\r\n"
        "\t\t\t\t// تجاهل: يبقى الاسم المخزَّن محلياً معروضاً كما هو عند انقطاع الشبكة\r\n"
        "\t\t\t}"
    ),
))

# ---------------------------------------------------------------------------
# patient_record.html -- 4 مسافات كمستوى أساسي
# ---------------------------------------------------------------------------
PATCHES.append((
    "patient_record.html",
    (
        "    if (clinicTitle) {\r\n"
        "            clinicTitle.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب المعتمد';\r\n"
        "    }\r\n"
        "    if (mobileClinicTitle) {\r\n"
        "            mobileClinicTitle.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب المعتمد';\r\n"
        "    }"
    ),
    (
        "    if (clinicTitle) {\r\n"
        "            clinicTitle.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب المعتمد';\r\n"
        "    }\r\n"
        "    if (mobileClinicTitle) {\r\n"
        "            mobileClinicTitle.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب المعتمد';\r\n"
        "    }\r\n"
        "\r\n"
        "    // تحديث اسم الطبيب من السيرفر مباشرة عند كل تحميل صفحة (2026-08-25) --\r\n"
        "    // انظر نفس التعليق في index.html لتفاصيل المشكلة الأصلية.\r\n"
        "    async function refreshDoctorNameFromServer() {\r\n"
        "      try {\r\n"
        "        const response = await fetch(apiUrl('/api/auth/profile'), { headers: getDoctorAuthHeaders() });\r\n"
        "        if (!response.ok) return;\r\n"
        "        const profile = await response.json();\r\n"
        "        const freshName = (profile.doctor_name || '').trim();\r\n"
        "        if (!freshName) return;\r\n"
        "        localStorage.setItem('doctor_name', freshName);\r\n"
        "        if (clinicTitle) clinicTitle.textContent = `عيادة ${freshName}`;\r\n"
        "        if (mobileClinicTitle) mobileClinicTitle.textContent = `عيادة ${freshName}`;\r\n"
        "      } catch (err) {\r\n"
        "        // تجاهل: يبقى الاسم المخزَّن محلياً معروضاً كما هو عند انقطاع الشبكة\r\n"
        "      }\r\n"
        "    }\r\n"
        "    refreshDoctorNameFromServer();"
    ),
))

# ---------------------------------------------------------------------------
# contact_developer.html -- Tabs، صفحة تُزار أحياناً بلا تسجيل دخول
# ---------------------------------------------------------------------------
PATCHES.append((
    "contact_developer.html",
    (
        "\t\tif (titleElement) {\r\n"
        "\t\t\ttitleElement.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب المعتمد';\r\n"
        "\t\t}"
    ),
    (
        "\t\tif (titleElement) {\r\n"
        "\t\t\ttitleElement.textContent = doctorName ? `عيادة ${doctorName}` : 'عيادة الطبيب المعتمد';\r\n"
        "\t\t}\r\n"
        "\r\n"
        "\t\t// تحديث اسم الطبيب من السيرفر مباشرة عند كل تحميل صفحة (2026-08-25) --\r\n"
        "\t\t// هذه الصفحة قد تُزار بلا تسجيل دخول (زائر مجهول)، لذا نتحقق أولاً من\r\n"
        "\t\t// وجود بريد طبيب مسجَّل قبل أي محاولة جلب -- لا نفرض تسجيل الدخول هنا.\r\n"
        "\t\tasync function refreshDoctorNameFromServer() {\r\n"
        "\t\t\tconst email = (localStorage.getItem('user_email') || '').trim();\r\n"
        "\t\t\tif (!email) return;\r\n"
        "\t\t\ttry {\r\n"
        "\t\t\t\tconst token = (localStorage.getItem('authToken') || '').trim();\r\n"
        "\t\t\t\tconst headers = { 'X-Doctor-Email': email };\r\n"
        "\t\t\t\tif (token) headers.Authorization = token.startsWith('Bearer ') ? token : `Bearer ${token}`;\r\n"
        "\t\t\t\tconst response = await fetch(apiUrl('/api/auth/profile'), { headers });\r\n"
        "\t\t\t\tif (!response.ok) return;\r\n"
        "\t\t\t\tconst profile = await response.json();\r\n"
        "\t\t\t\tconst freshName = (profile.doctor_name || '').trim();\r\n"
        "\t\t\t\tif (!freshName) return;\r\n"
        "\t\t\t\tlocalStorage.setItem('doctor_name', freshName);\r\n"
        "\t\t\t\tif (titleElement) titleElement.textContent = `عيادة ${freshName}`;\r\n"
        "\t\t\t} catch (err) {\r\n"
        "\t\t\t\t// تجاهل: يبقى الاسم المخزَّن محلياً معروضاً كما هو عند انقطاع الشبكة\r\n"
        "\t\t\t}\r\n"
        "\t\t}\r\n"
        "\t\trefreshDoctorNameFromServer();"
    ),
))


def main():
    fixed = []
    skipped = []
    errors = []

    for filename, old_text, new_text in PATCHES:
        target = HERE / filename
        if not target.exists():
            errors.append((filename, "الملف غير موجود في هذا المجلد"))
            continue

        raw = target.read_bytes()
        old_needle = old_text.encode("utf-8")
        new_needle = new_text.encode("utf-8")

        if new_needle in raw:
            skipped.append((filename, "مُصلَح مسبقاً"))
            continue

        if old_needle not in raw:
            errors.append((filename, "لم يُعثر على النص المتوقع بالشكل تماماً -- قد يكون الملف تغيّر"))
            continue

        backup_path = target.with_name(target.name + ".pre-doctor-name-fix.bak")
        backup_path.write_bytes(raw)

        new_raw = raw.replace(old_needle, new_needle, 1)
        target.write_bytes(new_raw)
        fixed.append(filename)

    print(f"[v] تم إصلاح {len(fixed)} ملفاً:")
    for name in fixed:
        print(f"    - {name}")

    if skipped:
        print(f"\n[.] تم تخطي {len(skipped)} ملفاً (مُصلَح مسبقاً):")
        for name, reason in skipped:
            print(f"    - {name}: {reason}")

    if errors:
        print(f"\n[x] تعذّر إصلاح {len(errors)} ملفاً:")
        for name, reason in errors:
            print(f"    - {name}: {reason}")

    if fixed:
        print("\nالخطوة التالية:")
        print("    git add " + " ".join(fixed))
        print('    git commit -m "إصلاح اسم الطبيب القديم/الخاطئ في أعلى الصفحات"')
        print("    git push")
        print("(Render سينشر تلقائياً -- أو اضغط Manual Deploy إن لم يبدأ خلال دقيقة).")

    if errors:
        sys.exit(1)


if __name__ == "__main__":
    main()
