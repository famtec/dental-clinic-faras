#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
يبني نسخة إنتاجية من Tailwind CSS (بدل cdn.tailwindcss.com التطويري) ثم يستبدل
سطر تحميل الـ CDN بوسم <link> يشير للملف المبني، في كل صفحات الموقع دفعة واحدة.

شغّل هذا الملف من داخل مجلد frontend_web نفسه:
    python apply_tailwind_production_build.py

المتطلبات على جهازك:
  - Node.js مثبّت (يشمل npm و npx). تحقق بتشغيل: node -v
    إن لم يكن مثبتاً، حمّله من https://nodejs.org (نسخة LTS تكفي) ثم أعد فتح
    الطرفية (Terminal/PowerShell) بعد التثبيت.
  - اتصال إنترنت عادي (لتحميل حزمة tailwindcss عبر npx في أول تشغيل فقط،
    التشغيلات اللاحقة تستخدم النسخة المحمّلة محلياً في ذاكرة npx المؤقتة).

ماذا يفعل هذا الملف بالضبط:
  1. يبني frontend_web/tailwind.css (نسخة مصغّرة/minified، تحتوي فقط على
     الأصناف (classes) المستخدمة فعلياً في ملفات HTML/JS -- حسب الإعداد في
     tailwind.config.js المرفق بجانب هذا الملف).
  2. يتحقق أن الملف الناتج معقول الحجم (وليس شبه فارغ) قبل أي خطوة أخرى --
     حماية من نشر تعديلات لو فشل البناء بصمت أو لم يجد الأصناف بسبب مسار خاطئ.
  3. فقط بعد نجاح البناء والتحقق: يأخذ نسخة احتياطية (بامتداد
     .pre-tailwind-cdn.bak) من كل صفحة HTML، ثم يستبدل سطر
     <script src="https://cdn.tailwindcss.com"></script> بوسم
     <link rel="stylesheet" href="tailwind.css" /> في كل صفحة.
  4. لا يلمس أي ملف HTML إطلاقاً إن فشلت الخطوة 1 أو 2 -- الموقع يبقى يعمل
     بالـ CDN القديم كما هو تماماً حتى تُصلح المشكلة وتعيد التشغيل. لا يوجد
     أي احتمال لنشر موقع "بلا أي تنسيق" لأن التعديل على HTML لا يحدث إلا بعد
     التأكد أن tailwind.css الفعلي جاهز وسليم.

بعد التشغيل بنجاح -- مهم جداً قبل الرفع للسيرفر:
  افتح الموقع محلياً (أو على الأقل بضع صفحات رئيسية: index, appointments,
  booking) وتأكد بصرياً أن كل شيء يبدو طبيعياً تماماً كما كان. إن لاحظت أي
  عنصر فقد تنسيقه، أخبرني بالضبط أي صفحة/عنصر ولن يستغرق تعديل الإعداد وقتاً.
  فقط بعد التأكد البصري: نفّذ git add / git commit / git push، ثم اضغط
  "Manual Deploy" في لوحة Render (النشر ليس تلقائياً في هذا المشروع).
"""

import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIG = HERE / "tailwind.config.js"
INPUT_CSS = HERE / "tailwind-input.css"
OUTPUT_CSS = HERE / "tailwind.css"

# ناتج بناء حقيقي لموقع بهذا الحجم (12 صفحة تستخدم عشرات أصناف Tailwind لكل
# منها) يتجاوز هذا الرقم بمراحل عادة. أي رقم أقل من هذا يعني على الأغلب فشلاً
# صامتاً في مسح ملفات المحتوى (content paths في tailwind.config.js) وليس بناءً
# ناجحاً فعلياً -- لذلك نتوقف هنا تماماً ولا نلمس أي HTML.
MIN_EXPECTED_BYTES = 5_000

CDN_TAG = '<script src="https://cdn.tailwindcss.com"></script>'
PROD_TAG = '<link rel="stylesheet" href="tailwind.css" />'

HTML_FILES = [
    "index.html", "appointments.html", "finance.html", "inventory.html",
    "patient_record.html", "profile.html", "qr.html", "booking.html",
    "contact_developer.html", "login.html", "landing.html", "register.html",
]


def check_node():
    node = shutil.which("node")
    npx = shutil.which("npx")
    if not node or not npx:
        print("[x] لم يتم العثور على Node.js/npx في PATH.")
        print("    ثبّت Node.js (نسخة LTS) من https://nodejs.org، أعد فتح الطرفية، ثم أعد تشغيل هذا الملف.")
        sys.exit(1)
    version = subprocess.run([node, "-v"], capture_output=True, text=True).stdout.strip()
    print(f"[v] Node.js موجود: {version}")


def build_css():
    if not CONFIG.exists() or not INPUT_CSS.exists():
        print(f"[x] لم أجد {CONFIG.name} أو {INPUT_CSS.name} بجانب هذا الملف بالضبط.")
        print(f"    تأكد أن الملفات الثلاثة (هذا الملف + {CONFIG.name} + {INPUT_CSS.name}) في نفس المجلد frontend_web.")
        sys.exit(1)

    print("[.] جاري بناء tailwind.css (أول تشغيل قد يستغرق دقيقة أو دقيقتين لتحميل الحزمة عبر npx)...")
    cmd = (
        f'npx --yes tailwindcss@3 '
        f'-c "{CONFIG}" -i "{INPUT_CSS}" -o "{OUTPUT_CSS}" --minify'
    )
    result = subprocess.run(cmd, cwd=str(HERE), capture_output=True, text=True, shell=True)

    if result.returncode != 0:
        print("[x] فشل أمر بناء Tailwind. لم يُعدَّل أي ملف HTML. المخرجات:")
        print(result.stdout)
        print(result.stderr)
        sys.exit(1)

    if not OUTPUT_CSS.exists():
        print("[x] لم يُنشأ tailwind.css رغم عدم ظهور خطأ صريح -- توقفت دون تعديل أي HTML.")
        sys.exit(1)

    size = OUTPUT_CSS.stat().st_size
    print(f"[v] تم إنشاء tailwind.css بحجم {size:,} بايت.")

    if size < MIN_EXPECTED_BYTES:
        print(f"[x] الحجم أصغر بكثير من المتوقع (أقل من {MIN_EXPECTED_BYTES:,} بايت).")
        print("    هذا يشير غالباً إلى أن tailwind.config.js لم يجد ملفات HTML لمسحها.")
        print("    تأكد أنك تشغّل هذا الملف من داخل مجلد frontend_web نفسه، ثم أعد المحاولة.")
        print("    لم يُعدَّل أي ملف HTML.")
        sys.exit(1)

    return size


def patch_html_files():
    patched = []
    skipped = []
    for name in HTML_FILES:
        path = HERE / name
        if not path.exists():
            skipped.append((name, "الملف غير موجود في هذا المجلد"))
            continue

        raw = path.read_bytes()
        needle = CDN_TAG.encode("utf-8")
        if needle not in raw:
            skipped.append((name, "لم يُعثر على سطر CDN فيه (ربما عُدّل مسبقاً)"))
            continue

        backup_path = path.with_name(path.name + ".pre-tailwind-cdn.bak")
        backup_path.write_bytes(raw)

        new_raw = raw.replace(needle, PROD_TAG.encode("utf-8"), 1)
        path.write_bytes(new_raw)
        patched.append(name)

    return patched, skipped


def main():
    print("=" * 64)
    check_node()
    build_css()
    print("-" * 64)
    print("[.] جاري تحديث ملفات HTML لتشير إلى النسخة الإنتاجية...")
    patched, skipped = patch_html_files()

    print(f"\n[v] تم تحديث {len(patched)} ملفاً:")
    for name in patched:
        print(f"    - {name}")

    if skipped:
        print(f"\n[!] تم تخطي {len(skipped)} ملفاً:")
        for name, reason in skipped:
            print(f"    - {name}: {reason}")

    print("\n" + "=" * 64)
    print("تم البناء والتحديث بنجاح.")
    print("افتح الموقع محلياً الآن وتأكد بصرياً أن كل صفحة تبدو طبيعية تماماً")
    print("قبل git push والنشر اليدوي على Render.")
    print("النسخ الاحتياطية بامتداد .pre-tailwind-cdn.bak -- احذفها بعد التأكد أن كل شيء سليم.")


if __name__ == "__main__":
    main()
