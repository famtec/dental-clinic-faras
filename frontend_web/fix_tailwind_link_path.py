#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
إصلاح سريع لمسار tailwind.css بعد تشغيل apply_tailwind_production_build.py.

المشكلة: الرابط <link rel="stylesheet" href="tailwind.css" /> نسبي (relative)،
وهذا يعمل بشكل صحيح لكل الصفحات المخدَّمة مباشرة من الجذر مثل /login.html أو
/index.html. لكن booking.html تُخدَّم أيضاً عبر مسار حجز عام مختلف العمق وهو
/d/{slug} (مثال: /d/dr-sewar) -- وفي هذا المسار، المتصفح يحسب الرابط النسبي
"tailwind.css" بالنسبة لمجلد /d/ وليس الجذر /، فيطلب bin مسار خاطئ /d/tailwind.css
ولا يجد ملف CSS حقيقياً، فتظهر صفحة الحجز العامة بلا أي تنسيق إطلاقاً.

الإصلاح: استبدال الرابط النسبي بمسار مطلق (absolute) يبدأ بـ "/" في كل الصفحات
الاثنتي عشرة دفعة واحدة -- بنفس الأسلوب المستخدم أصلاً لملف api-config.js في
الكود (src="/api-config.js")، حتى تعمل الصفحات بشكل صحيح بغض النظر عن أي مسار
تُخدَّم منه مستقبلاً.

شغّل هذا الملف من داخل مجلد frontend_web نفسه (نفس مكان السكربت السابق):
    python fix_tailwind_link_path.py
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

OLD_TAG = '<link rel="stylesheet" href="tailwind.css" />'
NEW_TAG = '<link rel="stylesheet" href="/tailwind.css" />'

HTML_FILES = [
    "index.html", "appointments.html", "finance.html", "inventory.html",
    "patient_record.html", "profile.html", "qr.html", "booking.html",
    "contact_developer.html", "login.html", "landing.html", "register.html",
]


def main():
    fixed = []
    skipped = []

    for name in HTML_FILES:
        path = HERE / name
        if not path.exists():
            skipped.append((name, "الملف غير موجود"))
            continue

        raw = path.read_bytes()
        needle = OLD_TAG.encode("utf-8")

        if needle not in raw:
            already_fixed = NEW_TAG.encode("utf-8") in raw
            reason = "مُصلَح مسبقاً" if already_fixed else "لم يُعثر على الرابط المتوقع فيه"
            skipped.append((name, reason))
            continue

        new_raw = raw.replace(needle, NEW_TAG.encode("utf-8"), 1)
        path.write_bytes(new_raw)
        fixed.append(name)

    print(f"[v] تم إصلاح {len(fixed)} ملفاً:")
    for name in fixed:
        print(f"    - {name}")

    if skipped:
        print(f"\n[!] تم تخطي {len(skipped)} ملفاً:")
        for name, reason in skipped:
            print(f"    - {name}: {reason}")

    print("\nبعد هذا: افتح رابط الحجز العام (/d/...) وتأكد أن التنسيق ظهر بشكل صحيح،")
    print("ثم git push ونشر يدوي على Render كالمعتاد.")


if __name__ == "__main__":
    main()
