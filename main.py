from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form, Header, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, RedirectResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from sqlalchemy import func
from sqlalchemy.orm import Session
from typing import List, Optional, Literal
import csv
import io
import json
import re
from pydantic import AliasChoices, BaseModel, Field, ConfigDict
from datetime import date, datetime, timedelta
from decimal import Decimal, InvalidOperation
import os
from uuid import uuid4
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token, service_account
import models
import database
import os
import uvicorn
import asyncio
import requests
import secrets
import string
import hmac
import hashlib
import base64
import time
from zoneinfo import ZoneInfo
from pydantic import BaseModel
app = FastAPI(title="Dental Clinic API")

# معرّف عميل Google الرسمي (بدون أي رموز إضافية مثل ":" في البداية، وإلا يفشل التحقق بخطأ invalid_client)
GOOGLE_CLIENT_ID = "446271578356-qju6aml2tiqbd2v6p23utrfb7nosketm.apps.googleusercontent.com"

# مفتاح إداري سرّي لتوليد أكواد التجديد الشهرية عبر /api/admin/renewal-keys/generate
# فقط -- **يجب** ضبطه كمتغيّر بيئة حقيقي (ADMIN_SECRET_KEY) في إعدادات Render قبل
# الإطلاق التجاري؛ القيمة الافتراضية بالأسفل معروفة للجميع ولا تصلح للإنتاج.
ADMIN_SECRET_KEY = os.getenv("ADMIN_SECRET_KEY", "change-me-fares-admin-2026")

# مفتاح توقيع جلسات الدخول (توكن شبيه بـ JWT، HMAC-SHA256، بلا أي اعتماد
# خارجي) -- **يجب** ضبطه كمتغيّر بيئة حقيقي (SESSION_SECRET_KEY) في إعدادات
# Render قبل الإطلاق التجاري؛ القيمة الافتراضية بالأسفل معروفة للجميع ولا
# تصلح للإنتاج. أي تغيير لهذا المفتاح يُبطل فوراً كل جلسات الدخول الحالية
# لكل الأطباء (يضطرون لإعادة تسجيل الدخول مرة واحدة فقط) -- هذا متوقع وآمن،
# وليس خللاً (2026-08-23).
SESSION_SECRET_KEY = os.getenv("SESSION_SECRET_KEY", "change-me-fares-session-2026")
SESSION_TOKEN_TTL_SECONDS = 60 * 60 * 24 * 30  # صلاحية 30 يوماً لكل جلسة دخول

# ملاحظة معمارية (2026-09-01): بيانات اعتماد Green API لم تعد متغيّري بيئة
# عامّين للمنصة كلها -- كل طبيب يربط حساب Green API/واتساب الخاص به من صفحة
# "حسابي" (users.green_api_instance_id/green_api_token، انظر models.py)،
# ويُقرآن دائماً من سجل الطبيب نفسه عبر send_whatsapp_message_for_doctor()
# بالأسفل. هذا يمنع تصاعد تكلفة/إدارة حساب Green API واحد مشترك مع كل طبيب
# جديد ينضم للمنصة، ويجعل رسائل كل عيادة تصل لمرضاها من رقم عيادتها الفعلي.

# بيانات اعتماد Firebase Cloud Messaging لإرسال إشعارات Push لتطبيق الطبيب على
# أندرويد (اختياري -- إن تُركت فارغة، send_push_notification_to_doctor ترجع بصمت
# دون أي محاولة اتصال أو خطأ). FIREBASE_SERVICE_ACCOUNT_JSON هو محتوى ملف
# JSON الكامل لحساب خدمة Firebase (Service Account) كنص واحد، وليس مساراً لملف.
FIREBASE_PROJECT_ID = os.getenv("FIREBASE_PROJECT_ID", "")
FIREBASE_SERVICE_ACCOUNT_JSON = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON", "")

UPLOADS_DIR = "uploads"
os.makedirs(UPLOADS_DIR, exist_ok=True)
ARCHIVE_UPLOADS_DIR = os.path.join(UPLOADS_DIR, "patient_xrays")
os.makedirs(ARCHIVE_UPLOADS_DIR, exist_ok=True)
AVATAR_UPLOADS_DIR = os.path.join(UPLOADS_DIR, "avatars")
os.makedirs(AVATAR_UPLOADS_DIR, exist_ok=True)


def seed_default_activation_key() -> None:
    db = database.SessionLocal()
    try:
        db.execute(
            text("DELETE FROM activation_keys WHERE key_code = :old_key"),
            {"old_key": "FARAS-30DAYS-2026"},
        )

        activation_keys = [
            ("TEST-STANDARD-30", 30),
            ("TEST-STANDARD-A1B2C3", 30),
            ("TEST-STANDARD-D4E5F6", 30),
            ("TEST-STANDARD-G7H8J9", 30),
            ("TEST-STANDARD-K2L4M6", 30),
            ("TEST-STANDARD-N8P3Q5", 30),
            ("TEST-STANDARD-R7S1T4", 30),
            ("TEST-STANDARD-U6V2W8", 30),
            ("TEST-STANDARD-X3Y5Z7", 30),

            ("TEST-PREMIUM-365", 365),
            ("TEST-PREMIUM-1A2B3C", 365),
            ("TEST-PREMIUM-4D5E6F", 365),
            ("TEST-PREMIUM-7G8H9J", 365),
            ("TEST-PREMIUM-K3L6M9", 365),
            ("TEST-PREMIUM-N2P5Q8", 365),
            ("TEST-PREMIUM-R4S7T1", 365),
            ("TEST-PREMIUM-U8V6W3", 365),
            ("TEST-PREMIUM-X5Y2Z9", 365),

            ("FARAS-VIP-999", 999),
            ("FARAS-VIP-9A8B7C", 999),
            ("FARAS-VIP-6D5E4F", 999),
            ("FARAS-VIP-3G2H1J", 999),
            ("FARAS-VIP-K9L8M7", 999),
            ("FARAS-VIP-N6P5Q4", 999),
            ("FARAS-VIP-R3S2T1", 999),
        ]

        for key_code, duration_days in activation_keys:
            existing_key = (
                db.query(models.ActivationKey)
                .filter_by(key_code=key_code)
                .first()
            )

            if existing_key is None:
                db.add(
                    models.ActivationKey(
                        key_code=key_code,
                        duration_days=duration_days,
                        is_used=False,
                        used_by_email=None,
                    )
                )

        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


# --- محرّك تجديد الاشتراك الشهري (Renewal Retention Engine) ---------------

def generate_renewal_activation_code(tier: str = "premium") -> str:
    # يولّد كوداً عشوائياً عالي الإنتروبيا بصيغة "PM-xxxxxxxxxxxxx" (فخمة/شهرية)
    # أو "STD-xxxxxxxxxxxxx" (قياسية)، باستخدام وحدة secrets (وليس random العادية)
    # لأنه سيُستخدم كتوكن دفع فعلي -- يجب ألا يكون قابلاً للتخمين.
    prefix = "PM" if tier == "premium" else "STD"
    alphabet = string.ascii_letters + string.digits
    suffix = "".join(secrets.choice(alphabet) for _ in range(13))
    return f"{prefix}-{suffix}"


def sweep_expired_subscriptions() -> int:
    # انتقال استباقي وجماعي: يبحث عن كل حساب "premium"/"standard" تجاوز تاريخ
    # انتهاء اشتراكه، ويحوّل عمود tier إلى "expired_subscription" مباشرة --
    # بدون حذف أو حظر الحساب، وبدون أي تأثير على جداول المرضى/المواعيد/المخزون.
    # هذا مجرّد تحسين استباقي (best-effort): بما أن خطة Render المجانية تُسبت
    # الخدمة بالكامل عند عدم وجود طلبات واردة، فإن هذه الحلقة الدورية لن تعمل
    # أثناء السبات -- الحارس الفعلي والموثوق 100% هو الفحص الكسول (lazy) داخل
    # ensure_user_subscription_is_active() الذي يعمل عند أي طلب API فعلي، بغض
    # النظر عمّا إذا كانت هذه الحلقة قد عملت أم لا.
    db = database.SessionLocal()
    try:
        now = datetime.utcnow()
        expired_users = (
            db.query(models.User)
            .filter(models.User.subscription_expires_at.isnot(None))
            .filter(models.User.subscription_expires_at < now)
            .filter(models.User.tier.in_(["premium", "standard"]))
            .all()
        )
        for expired_user in expired_users:
            expired_user.tier = "expired_subscription"
            expired_user.is_active = False

        if expired_users:
            db.commit()
        return len(expired_users)
    except Exception:
        db.rollback()
        return 0
    finally:
        db.close()


@app.on_event("startup")
def on_startup() -> None:
    models.Base.metadata.create_all(bind=database.engine)

    migration_db = database.SessionLocal()
    try:
        migration_db.execute(
            text("ALTER TABLE patients ADD COLUMN IF NOT EXISTS total_treatment_cost FLOAT DEFAULT 0.0;")
        )
        migration_db.commit()
    except Exception:
        migration_db.rollback()
    finally:
        migration_db.close()

    activation_keys_migration_db = database.SessionLocal()
    try:
        activation_keys_migration_db.execute(
            text("ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS intended_tier VARCHAR;")
        )
        activation_keys_migration_db.commit()
    except Exception:
        activation_keys_migration_db.rollback()
    finally:
        activation_keys_migration_db.close()

    # أعمدة تتبّع نشاط الطبيب + تذكير الخمول اليومي (2026-09-05) -- انظر
    # models.py (تعريف الأعمدة) و database.py (نسخة SQLite المحلية). الثلاثة
    # nullable بالكامل، وتنفيذ هذه الكتلة آمن ومتكرّر بلا أي أثر جانبي.
    activity_migration_db = database.SessionLocal()
    try:
        for migration_statement in (
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMP;",
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS web_push_token VARCHAR;",
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS last_idle_reminder_at TIMESTAMP;",
        ):
            activity_migration_db.execute(text(migration_statement))
        activity_migration_db.commit()
    except Exception:
        activity_migration_db.rollback()
    finally:
        activity_migration_db.close()

    # Keep legacy SQLite-safe migration checks for existing local environments.
    database.init_db()
    seed_default_activation_key()

    # انتقال استباقي فوري عند إقلاع الخادم لأي اشتراكات كانت قد انتهت أثناء
    # فترة السبات (خارج ساعات العمل، أو انقطاع الخدمة). بعدها تتولى الحلقة
    # الدورية بالأسفل (وأيضاً الفحص الكسول عند كل طلب) بقية العمل.
    try:
        expired_count = sweep_expired_subscriptions()
        if expired_count:
            print(f"🔄 [RENEWAL ENGINE] تم نقل {expired_count} حساباً إلى expired_subscription عند الإقلاع.")
    except Exception as exc:
        print(f"⚠️ [RENEWAL ENGINE] فشل الفحص الاستباقي عند الإقلاع: {exc}")


# --- Keep-alive ping ضد سبات Render المجاني ---
# Render المجاني يوقف الخدمة بعد 15 دقيقة بلا طلبات واردة، لكنه يمنحك 750 ساعة تشغيل
# شهرياً فقط لكامل الحساب (الشهر الواحد فيه ~744 ساعة تقريباً!). لذلك إبقاء السيرفر
# مستيقظاً 24/7 عبر بينغ دائم يستهلك كامل الرصيد الشهري تقريباً بمفرده، وأي تجاوز بسيط
# يوقف كل خدماتك المجانية على Render حتى الشهر القادم. الحل: نرسل نبضة كل 10 دقائق
# فقط خلال ساعات عمل العيادة، ونتركه ينام خارجها (عدّل الساعات والمنطقة الزمنية بالأسفل
# حسب دوامك الفعلي).
KEEP_ALIVE_URL = "https://dental-clinic-faras.onrender.com/health"
KEEP_ALIVE_INTERVAL_SECONDS = 10 * 60  # أقل من مهلة السبات (15 دقيقة) عند Render
KEEP_ALIVE_TIMEZONE = ZoneInfo("Asia/Damascus")
KEEP_ALIVE_START_HOUR = 8   # 8:00 صباحاً بتوقيت العيادة — عدّل حسب دوامك
KEEP_ALIVE_END_HOUR = 22    # 10:00 مساءً بتوقيت العيادة — عدّل حسب دوامك


def _is_within_clinic_hours() -> bool:
    current_hour = datetime.now(KEEP_ALIVE_TIMEZONE).hour
    return KEEP_ALIVE_START_HOUR <= current_hour < KEEP_ALIVE_END_HOUR


async def _keep_render_alive_loop() -> None:
    while True:
        await asyncio.sleep(KEEP_ALIVE_INTERVAL_SECONDS)
        if not _is_within_clinic_hours():
            continue
        try:
            # نستخدم asyncio.to_thread لأن requests.get متزامنة (blocking) ولا نريدها
            # أن توقف حلقة الأحداث الرئيسية بينما تخدم طلبات أخرى في نفس اللحظة.
            await asyncio.to_thread(requests.get, KEEP_ALIVE_URL, timeout=10)
            print("⏰ [KEEP ALIVE] تم إرسال نبضة تنشيط بنجاح.")
        except Exception as exc:
            print(f"⚠️ [KEEP ALIVE] فشل إرسال النبضة: {exc}")

        try:
            expired_count = await asyncio.to_thread(sweep_expired_subscriptions)
            if expired_count:
                print(f"🔄 [RENEWAL ENGINE] تم نقل {expired_count} حساباً إلى expired_subscription.")
        except Exception as exc:
            print(f"⚠️ [RENEWAL ENGINE] فشل الفحص الدوري: {exc}")


@app.on_event("startup")
async def _start_keep_alive_task() -> None:
    asyncio.create_task(_keep_render_alive_loop())


# --- محرك تذكيرات واتساب التلقائية للمواعيد (أُضيف 2026-08-23) ---
# يفحص دورياً المواعيد المستحقة خلال REMINDER_LEAD_HOURS ساعة تقريباً ولم يُرسَل
# لها تذكير بعد، ويرسل رسالة واتساب تلقائية عبر Green API (green-api.com).
# لا يعمل هذا المحرك فعلياً لطبيب معيّن إلا بعد أن يربط ذاك الطبيب حساب Green
# API/واتساب الخاص به من صفحة "حسابي" (2026-09-01، انظر
# send_whatsapp_message_for_doctor) -- طالما لم يربطه بعد، الإرسال له يُتجاهَل
# بصمت دون أي محاولة اتصال أو خطأ.
REMINDER_LEAD_HOURS = int(os.getenv("REMINDER_LEAD_HOURS", "24"))
REMINDER_WINDOW_HOURS = 1  # نافذة التقاط بساعة على كل جهة، لتفادي تفويت موعد بسبب فارق توقيت التشغيل
REMINDER_CHECK_INTERVAL_SECONDS = 30 * 60


def normalize_whatsapp_phone(phone: str | None) -> str:
    # نفس منطق normalizeWhatsappPhone المستخدم في frontend_web/patient_record.html
    # (التذكير اليدوي الحالي) -- يُبقي الاثنين متطابقين بالسلوك.
    raw = (phone or "").strip()
    if not raw:
        return ""

    digits = re.sub(r"\D", "", raw)
    if not digits:
        return ""

    if digits.startswith("00"):
        digits = digits[2:]

    if digits.startswith("0"):
        digits = f"963{digits[1:]}"
    elif not digits.startswith("963") and len(digits) == 9:
        digits = f"963{digits}"

    return digits


def send_whatsapp_message_via_green_api(instance_id: str | None, token: str | None, phone: str, message: str) -> bool:
    # مستوى منخفض بلا معرفة بأي طبيب -- يستقبل بيانات اعتماد Green API صراحة
    # بدل قراءتها من متغيّرات بيئة عامة (2026-09-01). استخدم
    # send_whatsapp_message_for_doctor() بالأسفل في أي كود جديد بدل هذه مباشرة.
    if not instance_id or not token:
        return False

    normalized_phone = normalize_whatsapp_phone(phone)
    if not normalized_phone:
        return False

    url = f"https://api.green-api.com/waInstance{instance_id}/sendMessage/{token}"
    payload = {"chatId": f"{normalized_phone}@c.us", "message": message}

    try:
        response = requests.post(url, json=payload, timeout=15)
        return response.status_code == 200
    except Exception as exc:
        print(f"⚠️ [WHATSAPP REMINDER] فشل إرسال الرسالة عبر Green API: {exc}")
        return False


def send_whatsapp_message_for_doctor(doctor: "models.User | None", phone: str, message: str) -> bool:
    # نقطة الدخول الموحّدة الوحيدة التي يجب أن يستخدمها أي كود بالمشروع لإرسال
    # واتساب -- تقرأ بيانات اعتماد Green API الخاصة بهذا الطبيب تحديداً
    # (users.green_api_instance_id/green_api_token) بدل أي إعداد مشترك للمنصة.
    # ترجع False بصمت (بلا أي استثناء) إن لم يربط الطبيب حساب واتساب خاص به
    # بعد -- نفس نمط best-effort المتّبع بكل ميزات واتساب بالمشروع.
    if doctor is None:
        return False

    return send_whatsapp_message_via_green_api(
        getattr(doctor, "green_api_instance_id", None),
        getattr(doctor, "green_api_token", None),
        phone,
        message,
    )


_firebase_credentials_cache: dict = {"credentials": None}


def _get_firebase_access_token() -> str | None:
    if not FIREBASE_SERVICE_ACCOUNT_JSON:
        return None
    try:
        if _firebase_credentials_cache["credentials"] is None:
            service_account_info = json.loads(FIREBASE_SERVICE_ACCOUNT_JSON)
            _firebase_credentials_cache["credentials"] = service_account.Credentials.from_service_account_info(
                service_account_info,
                scopes=["https://www.googleapis.com/auth/firebase.messaging"],
            )
        credentials = _firebase_credentials_cache["credentials"]
        credentials.refresh(google_requests.Request())
        return credentials.token
    except Exception as exc:
        print(f"⚠️ [PUSH NOTIFICATION] فشل تجهيز رمز الدخول لـ Firebase: {exc}")
        return None


def send_push_to_token(
    token: str | None,
    title: str,
    body: str,
    data: dict | None = None,
    channel_id: str | None = None,
    click_link: str | None = None,
) -> bool:
    """جوهر إرسال إشعار Push واحد إلى رمز جهاز واحد عبر FCM v1 -- مصدر الحقيقة
    الوحيد لكل إشعارات المشروع (أُخرجت من send_push_notification_to_doctor في
    2026-09-05 عندما صار للطبيب أكثر من سطح واحد: تطبيق أندرويد + متصفح الموقع).
    أي تعديل مستقبلي على شكل رسالة FCM يكفي تطبيقه هنا مرة واحدة -- نفس المبدأ
    المطبَّق في resolve_activation_key_tier بعد خلل تصنيف أكواد التفعيل.

    best-effort بالكامل مثل send_whatsapp_message_via_green_api تماماً: لا يُطلق
    أي استثناء ولا يوقف أي عملية لو فشل الإرسال أو لم تُضبط بيانات Firebase أو
    لم يسجّل الطبيب أي جهاز بعد.

    channel_id: قناة إشعارات أندرويد (يسمح للطبيب بكتم "تذكيرات العيادة" وحدها
    دون أن يفقد إشعارات "حجوزات جديدة"). إن تُركت فارغة يستخدم أندرويد القناة
    الافتراضية المعرّفة في AndroidManifest.xml.
    click_link: الرابط الذي يُفتح عند الضغط على إشعار المتصفح (Web Push فقط --
    أندرويد يوجَّه عبر حقل data["type"] داخل التطبيق).
    """
    token_value = (token or "").strip() if isinstance(token, str) else ""
    if not token_value:
        return False
    if not FIREBASE_PROJECT_ID or not FIREBASE_SERVICE_ACCOUNT_JSON:
        return False

    access_token = _get_firebase_access_token()
    if not access_token:
        return False

    url = f"https://fcm.googleapis.com/v1/projects/{FIREBASE_PROJECT_ID}/messages:send"

    android_config: dict = {"priority": "high"}
    if channel_id:
        android_config["notification"] = {"channel_id": channel_id}

    webpush_config: dict = {
        "notification": {
            "icon": f"{PRODUCTION_SITE_URL}/favicon.png",
            "badge": f"{PRODUCTION_SITE_URL}/favicon.png",
        }
    }
    if click_link:
        webpush_config["fcm_options"] = {"link": click_link}

    payload = {
        "message": {
            "token": token_value,
            "notification": {"title": title, "body": body},
            "data": {str(key): str(value) for key, value in (data or {}).items()},
            "android": android_config,
            "webpush": webpush_config,
        }
    }

    try:
        response = requests.post(
            url,
            json=payload,
            headers={"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"},
            timeout=10,
        )
        return response.status_code == 200
    except Exception as exc:
        print(f"⚠️ [PUSH NOTIFICATION] فشل إرسال إشعار Push: {exc}")
        return False


def send_push_notification_to_doctor(
    doctor,
    title: str,
    body: str,
    data: dict | None = None,
    channel_id: str | None = None,
    click_link: str | None = None,
) -> bool:
    # إشعار Push فوري لتطبيق الطبيب على أندرويد عند وصول حجز جديد (أُضيف
    # 2026-08-24). بقي هذا الغلاف بنفس اسمه وسلوكه بالضبط بعد إعادة هيكلة
    # 2026-09-05 (جهاز التطبيق وحده، fcm_token) حتى لا يتغيّر أي شيء في مسار
    # إشعار الحجز الجديد -- الإرسال لكل أسطح الطبيب يتم عبر الدالة التالية.
    if not doctor:
        return False
    return send_push_to_token(
        getattr(doctor, "fcm_token", None),
        title,
        body,
        data=data,
        channel_id=channel_id,
        click_link=click_link,
    )


def send_push_to_all_doctor_devices(
    doctor,
    title: str,
    body: str,
    data: dict | None = None,
    channel_id: str | None = None,
    click_link: str | None = None,
) -> int:
    """يرسل نفس الإشعار لكل أسطح الطبيب المسجَّلة (تطبيق أندرويد + متصفح
    الموقع)، ويُرجع عدد الأسطح التي وصلها فعلاً. الطبيب قد يستخدم الاثنين معاً،
    ورمز كلٍّ منهما مخزَّن في عمود مستقل (fcm_token / web_push_token)."""
    if not doctor:
        return 0

    delivered = 0
    for device_token in (getattr(doctor, "fcm_token", None), getattr(doctor, "web_push_token", None)):
        if send_push_to_token(
            device_token,
            title,
            body,
            data=data,
            channel_id=channel_id,
            click_link=click_link,
        ):
            delivered += 1

    return delivered


def send_due_appointment_reminders() -> int:
    db = database.SessionLocal()
    sent_count = 0
    try:
        now = datetime.now(KEEP_ALIVE_TIMEZONE).replace(tzinfo=None)
        window_start = now + timedelta(hours=REMINDER_LEAD_HOURS - REMINDER_WINDOW_HOURS)
        window_end = now + timedelta(hours=REMINDER_LEAD_HOURS + REMINDER_WINDOW_HOURS)

        due_appointments = (
            db.query(models.Appointment)
            .filter(
                models.Appointment.reminder_sent.is_(False),
                models.Appointment.appointment_date.isnot(None),
                models.Appointment.appointment_date >= window_start,
                models.Appointment.appointment_date <= window_end,
                models.Appointment.status != "no_show",
            )
            .all()
        )

        # كاش بسيط بذاكرة العملية لتفادي إعادة جلب نفس الطبيب من القاعدة لكل موعد
        # ضمن نفس الدورة (عدة مواعيد مستحقة لنفس الطبيب أمر شائع).
        doctors_by_email: dict[str, models.User] = {}

        for appointment in due_appointments:
            patient = None
            if appointment.patient_id:
                # حماية إضافية (defense in depth): حتى لو كان patient_id محفوظاً،
                # نتحقق أن doctor_email للمريض يطابق doctor_email الموعد قبل
                # استخدامه -- لا يجوز إطلاقاً أن يصل تذكير عن مريض لا يخص نفس الطبيب.
                patient = (
                    db.query(models.Patient)
                    .filter(
                        models.Patient.id == appointment.patient_id,
                        models.Patient.doctor_email == appointment.doctor_email,
                    )
                    .first()
                )
            if not patient and appointment.patient_name:
                # مواعيد قديمة أُنشئت قبل إضافة patient_id -- مطابقة احتياطية بالاسم،
                # ويجب أن تتطابق doctor_email أيضاً حتى لا يُرسَل تذكير لمريض بنفس
                # الاسم يتبع لطبيب آخر تماماً (2026-08-23).
                patient = (
                    db.query(models.Patient)
                    .filter(
                        models.Patient.full_name == appointment.patient_name,
                        models.Patient.doctor_email == appointment.doctor_email,
                    )
                    .first()
                )

            if not patient or not patient.phone:
                continue

            if not appointment.doctor_email:
                continue
            doctor = doctors_by_email.get(appointment.doctor_email)
            if doctor is None:
                doctor = db.query(models.User).filter(models.User.email == appointment.doctor_email).first()
                if doctor is not None:
                    doctors_by_email[appointment.doctor_email] = doctor
            if doctor is None:
                continue

            doctor_label = (patient.doctor_name or "").strip() or "عيادتك الرقمية"
            appointment_date_label = appointment.appointment_date.strftime("%Y-%m-%d") if appointment.appointment_date else ""
            appointment_time_label = appointment.appointment_time or ""
            patient_label = (patient.full_name or appointment.patient_name or "المريض").strip()

            message = (
                f"مرحباً سيد/ة {patient_label}، نذكركم بموعدكم في عيادة {doctor_label} غداً "
                f"بتاريخ {appointment_date_label} الساعة {appointment_time_label}. "
                "نتمنى لكم دوام الصحة والعافية. 🦷✨"
            )

            was_sent = send_whatsapp_message_for_doctor(doctor, patient.phone, message)
            if was_sent:
                appointment.reminder_sent = True
                sent_count += 1

        if sent_count:
            db.commit()
    except Exception as exc:
        db.rollback()
        print(f"⚠️ [WHATSAPP REMINDER] فشل فحص المواعيد المستحقة: {exc}")
    finally:
        db.close()

    return sent_count


async def _appointment_reminder_loop() -> None:
    while True:
        await asyncio.sleep(REMINDER_CHECK_INTERVAL_SECONDS)
        if not _is_within_clinic_hours():
            continue
        try:
            sent_count = await asyncio.to_thread(send_due_appointment_reminders)
            if sent_count:
                print(f"📲 [WHATSAPP REMINDER] تم إرسال {sent_count} تذكير واتساب تلقائي.")
        except Exception as exc:
            print(f"⚠️ [WHATSAPP REMINDER] خطأ غير متوقع بحلقة التذكيرات: {exc}")


@app.on_event("startup")
async def _start_appointment_reminder_task() -> None:
    asyncio.create_task(_appointment_reminder_loop())


# --- نظام استرجاع المرضى التلقائي (Patient Recall Engine) -- أُضيف 2026-09-01 ---
# الميزة الأقوى للاحتفاظ بالمرضى ورفع دخل العيادة: يفحص دورياً مرضى كل طبيب
# (Premium فقط) الذين مرّت مدة RECALL_INTERVAL_DAYS يوماً منذ آخر زيارة فعلية
# (موعد بحالة "checked_in") لهم دون أن يحجزوا موعداً جديداً بعدها، ويرسل لهم
# تلقائياً رسالة واتساب تذكيرية بأهمية المتابعة الدورية مع رابط الحجز المباشر.
# مثل محرك تذكيرات المواعيد أعلاه تماماً، هذا المحرك best-effort بالكامل: طالما
# الطبيب لم يربط حساب Green API/واتساب الخاص به بعد من صفحة "حسابي"،
# send_whatsapp_message_for_doctor ترجع False بصمت ولا يُحدَّث last_recall_sent_at.
RECALL_INTERVAL_DAYS = int(os.getenv("RECALL_INTERVAL_DAYS", "180"))
RECALL_CHECK_INTERVAL_SECONDS = int(os.getenv("RECALL_CHECK_INTERVAL_SECONDS", str(6 * 60 * 60)))
PRODUCTION_SITE_URL = os.getenv("PRODUCTION_SITE_URL", "https://dental-clinic-faras.onrender.com")


def get_recall_candidates(db: Session, doctor_email: str, interval_days: int) -> list[dict]:
    """يُرجع قائمة مرضى هذا الطبيب المستحقين لتذكير استرجاع: لديهم زيارة فعلية
    واحدة على الأقل (موعد "checked_in")، مرّت عليها interval_days يوماً أو أكثر،
    وليس لديهم حالياً موعد قادم محجوز (pending/pending_confirmation) بعدها --
    فلا داعي لتذكير مريض حجز موعده أصلاً. مُرتَّبة تنازلياً حسب عدد أيام التأخر."""
    now = datetime.utcnow()
    cutoff = now - timedelta(days=interval_days)

    last_visit_subquery = (
        db.query(
            models.Appointment.patient_id.label("patient_id"),
            func.max(models.Appointment.appointment_date).label("last_visit_date"),
        )
        .filter(
            models.Appointment.doctor_email == doctor_email,
            models.Appointment.status == "checked_in",
            models.Appointment.patient_id.isnot(None),
            models.Appointment.appointment_date.isnot(None),
        )
        .group_by(models.Appointment.patient_id)
        .subquery()
    )

    upcoming_patient_ids = {
        row[0]
        for row in (
            db.query(models.Appointment.patient_id)
            .filter(
                models.Appointment.doctor_email == doctor_email,
                models.Appointment.status.in_(["pending", "pending_confirmation"]),
                models.Appointment.appointment_date.isnot(None),
                models.Appointment.appointment_date >= now,
                models.Appointment.patient_id.isnot(None),
            )
            .all()
        )
    }

    rows = (
        db.query(models.Patient, last_visit_subquery.c.last_visit_date)
        .join(last_visit_subquery, last_visit_subquery.c.patient_id == models.Patient.id)
        .filter(
            models.Patient.doctor_email == doctor_email,
            last_visit_subquery.c.last_visit_date <= cutoff,
        )
        .all()
    )

    candidates = []
    for patient, last_visit_date in rows:
        if patient.id in upcoming_patient_ids:
            continue
        candidates.append(
            {
                "patient": patient,
                "last_visit_date": last_visit_date,
                "days_since_last_visit": (now - last_visit_date).days,
            }
        )

    candidates.sort(key=lambda candidate: candidate["days_since_last_visit"], reverse=True)
    return candidates


def build_recall_whatsapp_message(doctor: "models.User", patient: "models.Patient") -> str:
    doctor_label = (getattr(doctor, "clinic_name", None) or doctor.doctor_name or "").strip() or "عيادتك الرقمية"
    patient_label = (patient.full_name or "").strip() or "عزيزنا المريض"

    booking_line = ""
    if doctor.public_booking_enabled and doctor.booking_slug:
        booking_line = f"\nيمكنكم حجز موعدكم مباشرة عبر هذا الرابط: {PRODUCTION_SITE_URL}/d/{doctor.booking_slug}"

    return (
        f"مرحباً سيد/ة {patient_label}، مرّت فترة منذ آخر زيارة لكم إلى عيادة {doctor_label}. "
        f"نذكّركم بأهمية المتابعة الدورية للحفاظ على صحة أسنانكم.{booking_line}\n"
        "نتمنى لكم دوام الصحة والعافية. 🦷✨"
    )


def send_recall_message_to_patient(db: Session, doctor: "models.User", patient: "models.Patient") -> bool:
    if not patient.phone:
        return False

    message = build_recall_whatsapp_message(doctor, patient)
    was_sent = send_whatsapp_message_for_doctor(doctor, patient.phone, message)
    if was_sent:
        patient.last_recall_sent_at = datetime.utcnow()
        db.commit()

    return was_sent


def send_due_recall_messages() -> int:
    db = database.SessionLocal()
    sent_count = 0
    try:
        now = datetime.utcnow()
        recall_cooldown_cutoff = now - timedelta(days=RECALL_INTERVAL_DAYS)

        # الاسترجاع التلقائي (بلا أي إجراء من الطبيب) حصري لباقة Premium -- نفس
        # منطق باقي مزايا Premium الحصرية بالمشروع (require_premium_user_by_email).
        doctors = db.query(models.User).filter(models.User.tier == "premium").all()

        for doctor in doctors:
            if not doctor.email or not doctor.is_active:
                continue
            # لا إرسال لأي طبيب انتهى اشتراكه فعلياً، حتى لو بقيت قيمة tier "premium"
            # بانتظار دورة sweep_expired_subscriptions التالية.
            if doctor.subscription_expires_at and doctor.subscription_expires_at < now:
                continue

            candidates = get_recall_candidates(db, doctor.email, RECALL_INTERVAL_DAYS)
            for candidate in candidates:
                patient = candidate["patient"]
                if patient.last_recall_sent_at and patient.last_recall_sent_at > recall_cooldown_cutoff:
                    continue  # أُرسلت له رسالة استرجاع خلال نفس فترة RECALL_INTERVAL_DAYS بالفعل
                if send_recall_message_to_patient(db, doctor, patient):
                    sent_count += 1
    except Exception as exc:
        db.rollback()
        print(f"⚠️ [PATIENT RECALL] فشل فحص مرضى الاسترجاع: {exc}")
    finally:
        db.close()

    return sent_count


async def _patient_recall_loop() -> None:
    while True:
        await asyncio.sleep(RECALL_CHECK_INTERVAL_SECONDS)
        if not _is_within_clinic_hours():
            continue
        try:
            sent_count = await asyncio.to_thread(send_due_recall_messages)
            if sent_count:
                print(f"📲 [PATIENT RECALL] تم إرسال {sent_count} رسالة استرجاع مريض تلقائية.")
        except Exception as exc:
            print(f"⚠️ [PATIENT RECALL] خطأ غير متوقع بحلقة الاسترجاع: {exc}")


@app.on_event("startup")
async def _start_patient_recall_task() -> None:
    asyncio.create_task(_patient_recall_loop())


# --- محرّك تذكير الطبيب الخامل (Doctor Idle Reminder) -- أُضيف 2026-09-05 ---
# طلب صريح من مالك المنصة: إن لم يفتح الطبيب الموقع ولا التطبيق في يومٍ ما،
# يصله إشعار تذكيري عند الساعة 1 ظهراً بتوقيت العيادة يدعوه للعودة إلى نظامه.
# يعتمد كلياً على users.last_active_at التي تُختم مركزياً في touch_user_activity
# بالأسفل، ويرسل عبر send_push_to_all_doctor_devices إلى تطبيق أندرويد ومتصفح
# الموقع معاً.
#
# لماذا الحلقة موثوقة رغم أن Render المجاني ينام؟ لأن _keep_render_alive_loop
# بالأعلى يُبقي الخدمة مستيقظة من KEEP_ALIVE_START_HOUR (8ص) إلى
# KEEP_ALIVE_END_HOUR (10م) بتوقيت دمشق، والساعة 1 ظهراً تقع داخل هذه النافذة
# بوضوح. **إن غُيّرت ساعة التذكير مستقبلاً إلى خارج تلك النافذة فلن تعمل
# إطلاقاً** -- لا تنسَ توسيع نافذة keep-alive معها.
IDLE_REMINDER_HOUR = int(os.getenv("IDLE_REMINDER_HOUR", "13"))  # 1 ظهراً بتوقيت KEEP_ALIVE_TIMEZONE
IDLE_REMINDER_CHECK_INTERVAL_SECONDS = int(os.getenv("IDLE_REMINDER_CHECK_INTERVAL_SECONDS", str(15 * 60)))
# احترام أيام عطلة الطبيب (users.work_days) -- قرار المالك: لا نزعجه في يوم
# عطلته. اضبط المتغيّر إلى "0" لتعطيل هذا الاحترام وإرسال التذكير كل يوم.
IDLE_REMINDER_RESPECT_WORK_DAYS = os.getenv("IDLE_REMINDER_RESPECT_WORK_DAYS", "1").strip().lower() not in ("0", "false", "no")
# قناة إشعارات أندرويد مستقلة عن قناة الحجوزات (new_booking_channel) حتى يقدر
# الطبيب كتم التذكيرات وحدها دون أن يفقد إشعار وصول حجز جديد. يجب أن تطابق
# القيمة نفسها في dental_app/lib/services/push_notification_service.dart.
IDLE_REMINDER_CHANNEL_ID = "clinic_reminder_channel"


def _local_now_naive() -> datetime:
    return datetime.now(KEEP_ALIVE_TIMEZONE).replace(tzinfo=None)


def _start_of_local_today() -> datetime:
    return _local_now_naive().replace(hour=0, minute=0, second=0, microsecond=0)


def _arabic_count_phrase(count: int, singular: str, dual: str, plural: str, accusative: str) -> str:
    """صياغة عربية سليمة للعدد داخل نص الإشعار: "موعد واحد" / "موعدان" /
    "3 مواعيد" / "12 موعداً" -- بدل "3 موعد" الركيكة."""
    if count == 1:
        return singular
    if count == 2:
        return dual
    if 3 <= count <= 10:
        return f"{count} {plural}"
    return f"{count} {accusative}"


def is_doctor_working_today(doctor: "models.User", today: date) -> bool:
    """users.work_days أرقام مفصولة بفواصل بترميز date.weekday() نفسه
    (الاثنين=0 .. الأحد=6)، وهو نفس الترميز المستخدم في صفحة الحجز العامة.
    إن لم يضبط الطبيب أيام دوامه إطلاقاً نعتبر كل الأيام أيام عمل -- لا نكتم
    التذكير عنه بسبب حقل لم يملأه أصلاً."""
    raw_work_days = (getattr(doctor, "work_days", None) or "").strip()
    if not raw_work_days:
        return True

    work_day_numbers = set()
    for part in raw_work_days.split(","):
        part = part.strip()
        if part.isdigit():
            work_day_numbers.add(int(part))

    if not work_day_numbers:
        return True

    return today.weekday() in work_day_numbers


def build_idle_reminder_message(db: Session, doctor: "models.User") -> tuple[str, str]:
    """نص التذكير يُبنى من بيانات الطبيب الفعلية اليوم وليس نصاً ثابتاً --
    "لديك 3 مواعيد اليوم وطلب حجز واحد بانتظار ردّك" أقوى بكثير من رسالة
    تسويقية عامة، وتعطي الطبيب سبباً حقيقياً لفتح النظام فوراً."""
    normalized_tier = (getattr(doctor, "tier", None) or "").strip().lower()

    # منتهي الاشتراك: نص مختلف تماماً -- تذكيره بمواعيد لا يستطيع رؤيتها أصلاً
    # إحباط، والرسالة الصحيحة له هي التجديد.
    if normalized_tier == "expired_subscription":
        return (
            "اشتراكك في عيادتك الرقمية منتهٍ ⏳",
            "مواعيدك وسجلات مرضاك وتقاريرك المالية محفوظة كما تركتها تماماً. "
            "جدّد اشتراكك لتستعيد الوصول إليها فوراً.",
        )

    today_start = _start_of_local_today()
    today_end = today_start + timedelta(days=1)

    appointments_today = (
        db.query(func.count(models.Appointment.id))
        .filter(
            models.Appointment.doctor_email == doctor.email,
            models.Appointment.appointment_date >= today_start,
            models.Appointment.appointment_date < today_end,
            models.Appointment.status.notin_(["rejected", "pending_confirmation"]),
        )
        .scalar()
        or 0
    )

    pending_requests = (
        db.query(func.count(models.Appointment.id))
        .filter(
            models.Appointment.doctor_email == doctor.email,
            models.Appointment.status == "pending_confirmation",
        )
        .scalar()
        or 0
    )

    message_parts = []
    if appointments_today:
        message_parts.append(
            "لديك " + _arabic_count_phrase(appointments_today, "موعد واحد", "موعدان", "مواعيد", "موعداً") + " اليوم"
        )
    if pending_requests:
        message_parts.append(
            _arabic_count_phrase(pending_requests, "طلب حجز واحد", "طلبا حجز", "طلبات حجز", "طلب حجز")
            + " بانتظار ردّك"
        )

    if message_parts:
        return ("عيادتك بانتظارك 🦷", " و".join(message_parts) + ". افتح عيادتك الرقمية وألقِ نظرة سريعة.")

    return (
        "عيادتك بانتظارك 🦷",
        "لم تفتح عيادتك الرقمية اليوم. دقيقة واحدة تكفي لمراجعة مواعيدك وتسجيل ما استجدّ على مرضاك.",
    )


def get_idle_doctors(db: Session) -> list["models.User"]:
    """الأطباء المستحقون لتذكير خمول الآن، حسب القواعد المتفق عليها:
    نشط، فعّل حسابه يوماً ما، لديه جهاز مسجَّل واحد على الأقل، اليوم ليس يوم
    عطلته، لم يفتح النظام منذ منتصف ليلة اليوم المحلي، ولم يصله تذكير اليوم."""
    today_start = _start_of_local_today()
    today = today_start.date()

    idle_doctors = []
    for doctor in db.query(models.User).filter(models.User.is_active.is_(True)).all():
        if not doctor.email:
            continue

        # حساب لم يُفعَّل يوماً ليس "خاملاً" -- هو ببساطة لم يبدأ بعد، وإشعاره
        # إزعاج بلا معنى (قرار صريح من المالك 2026-09-05).
        normalized_tier = (doctor.tier or "").strip().lower()
        if normalized_tier in ("", "pending_activation"):
            continue

        # بلا أي جهاز مسجَّل لا يوجد إلى أين نرسل أصلاً -- نتخطاه قبل أي استعلام
        # إضافي بدل محاولة إرسال فاشلة مؤكدة.
        if not getattr(doctor, "fcm_token", None) and not getattr(doctor, "web_push_token", None):
            continue

        if IDLE_REMINDER_RESPECT_WORK_DAYS and not is_doctor_working_today(doctor, today):
            continue

        last_active_at = getattr(doctor, "last_active_at", None)
        if last_active_at and last_active_at >= today_start:
            continue  # فتح النظام اليوم فعلاً، لا داعي للتذكير

        last_reminder_at = getattr(doctor, "last_idle_reminder_at", None)
        if last_reminder_at and last_reminder_at >= today_start:
            continue  # وصله تذكير اليوم بالفعل -- حارس عدم التكرار

        idle_doctors.append(doctor)

    return idle_doctors


def send_idle_reminder_to_doctor(db: Session, doctor: "models.User") -> bool:
    title, body = build_idle_reminder_message(db, doctor)
    delivered_devices = send_push_to_all_doctor_devices(
        doctor,
        title,
        body,
        data={"type": "idle_reminder"},
        channel_id=IDLE_REMINDER_CHANNEL_ID,
        # وجهة الضغط على إشعار المتصفح: صفحة المواعيد -- نص التذكير نفسه
        # مبني على مواعيد اليوم وطلبات الحجز المعلّقة، وهي نفس وجهة الإشعار
        # في تطبيق أندرويد (تبويب "المواعيد") فيبقى السلوك واحداً على السطحين.
        click_link=f"{PRODUCTION_SITE_URL}/appointments.html",
    )

    # لا نختم last_idle_reminder_at إلا إذا وصل الإشعار فعلاً إلى سطح واحد على
    # الأقل -- وإلا لأسكتنا التذكير ليوم كامل بسبب عطل مؤقت في Firebase.
    if not delivered_devices:
        return False

    doctor.last_idle_reminder_at = _local_now_naive()
    db.commit()
    return True


def send_due_idle_reminders() -> int:
    db = database.SessionLocal()
    sent_count = 0
    try:
        for doctor in get_idle_doctors(db):
            if send_idle_reminder_to_doctor(db, doctor):
                sent_count += 1
    except Exception as exc:
        db.rollback()
        print(f"⚠️ [IDLE REMINDER] فشل فحص الأطباء الخاملين: {exc}")
    finally:
        db.close()

    return sent_count


async def _idle_reminder_loop() -> None:
    while True:
        await asyncio.sleep(IDLE_REMINDER_CHECK_INTERVAL_SECONDS)
        if datetime.now(KEEP_ALIVE_TIMEZONE).hour != IDLE_REMINDER_HOUR:
            continue
        try:
            sent_count = await asyncio.to_thread(send_due_idle_reminders)
            if sent_count:
                print(f"🔔 [IDLE REMINDER] تم إرسال {sent_count} تذكير للأطباء الخاملين اليوم.")
        except Exception as exc:
            print(f"⚠️ [IDLE REMINDER] خطأ غير متوقع بحلقة التذكير: {exc}")


@app.on_event("startup")
async def _start_idle_reminder_task() -> None:
    asyncio.create_task(_idle_reminder_loop())


# 2. تفعيل نظام CORS للسماح لموقع الويب وتطبيق الأندرويد بالاتصال بالـ API دون قيود أمنية ومتصفح
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# 3. بناء مخطط (Schema) لاستقبال بيانات المريض عبر الـ API وتدقيقها (Pydantic)
class PatientCreate(BaseModel):
    doctor_name: Optional[str] = None
    doctor_email: Optional[str] = None
    full_name: str
    phone: str
    birth_date: Optional[date] = None
    gender: Optional[str] = None
    medical_history: Optional[str] = None
    total_treatment_cost: float = 0.0


class PatientUpdate(BaseModel):
    doctor_name: Optional[str] = None
    full_name: Optional[str] = None
    phone: Optional[str] = None
    medical_history: Optional[str] = None
    # 2026-08-25: لم يكن هذا المسار يقبل birth_date إطلاقاً من قبل -- وهذا هو
    # السبب الفعلي وراء بقاء "العمر" ثابتاً دائماً بعد الحفظ في patient_record.html:
    # العمر ليس عموداً مخزَّناً بل يُحسب دائماً من birth_date، وكل مريض جديد
    # يُنشأ حالياً من index.html بتاريخ ميلاد ثابت مزروع "2000-01-01" (لا يوجد
    # حقل عمر/تاريخ ميلاد حقيقي في نموذج "إضافة مريض")، وبما أن هذا المسار لم
    # يكن يقبل تعديل birth_date كان أي تعديل لاحق للعمر من صفحة المريض يُهمَل
    # بصمت من طرف الخادم مهما أُعيد الحفظ. الحل: نسمح بتعديل birth_date هنا،
    # وpatient_record.html يحسب birth_date تقريبياً من العمر المُدخَل (1 يناير
    # من سنة الميلاد الموافقة) قبل الإرسال بدل إرسال حقل "age" غير موجود أصلاً.
    birth_date: Optional[date] = None
    # total_treatment_cost أُزيل من هنا عمداً (2026-08-25) -- التكلفة لم تعد
    # حقلاً واحداً قابلاً للاستبدال، بل فواتير علاج مستقلة (انظر
    # TreatmentInvoiceCreate + /api/patients/{id}/invoices بالأسفل). العمود
    # الخام في قاعدة البيانات (patients.total_treatment_cost) يبقى بلا حذف
    # لأغراض تاريخية فقط ولم يعد يُقرأ لأي حساب رصيد فعلي.


class PatientChartUpdate(BaseModel):
    chart_state: dict[str, str] | str


PALMER_TOOTH_KEY_PATTERN = re.compile(r"^(UR|UL|LR|LL)[1-8]$")


def normalize_palmer_chart_state(chart_state: dict[str, str] | str) -> dict[str, str]:
    if isinstance(chart_state, str):
        raw_value = chart_state.strip()
        if not raw_value:
            raise HTTPException(status_code=400, detail="Chart state cannot be empty")

        try:
            parsed_state = json.loads(raw_value)
        except json.JSONDecodeError:
            raise HTTPException(
                status_code=400,
                detail="Chart state must be a valid JSON object",
            )
    else:
        parsed_state = chart_state

    if not isinstance(parsed_state, dict):
        raise HTTPException(status_code=400, detail="Chart state must be a JSON object")

    normalized_state: dict[str, str] = {}
    for key, value in parsed_state.items():
        normalized_key = str(key).strip().upper()
        if not PALMER_TOOTH_KEY_PATTERN.fullmatch(normalized_key):
            raise HTTPException(
                status_code=400,
                detail=(
                    "Palmer tooth keys are required (UR1-UR8, UL1-UL8, LR1-LR8, LL1-LL8)"
                ),
            )

        normalized_state[normalized_key] = "" if value is None else str(value)

    return normalized_state


class PatientResponse(PatientCreate):
    id: int
    chart_state: Optional[str] = None
    paid_amount: float = 0.0
    model_config = ConfigDict(from_attributes=True)


class AppointmentCreate(BaseModel):
    patient_id: int
    date: str = Field(validation_alias=AliasChoices("date", "appointment_date"))
    time: str = Field(validation_alias=AliasChoices("time", "appointment_time"))
    description: str = Field(validation_alias=AliasChoices("description", "notes", "procedure_type"))
    patient_name: Optional[str] = None
    status: str = "Pending"


class AppointmentUpdate(BaseModel):
    appointment_date: Optional[datetime] = None
    appointment_time: Optional[str] = None
    description: Optional[str] = None


class AppointmentStatusUpdate(BaseModel):
    status: Literal["checked_in", "no_show", "pending"]


class AppointmentResponse(BaseModel):
    id: int
    patient_name: Optional[str] = None
    appointment_date: Optional[datetime] = None
    appointment_time: Optional[str] = None
    procedure_type: Optional[str] = None
    notes: Optional[str] = None
    status: str
    patient_id: Optional[int] = None
    # هاتف صاحب طلب الحجز العام (2026-08-23) -- يظهر فقط لطلبات booking.html
    patient_phone: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)


class TreatmentCreate(BaseModel):
    patient_id: int
    tooth_number: int
    treatment_type: str
    notes: Optional[str] = None
    color: Optional[str] = None


class TreatmentResponse(BaseModel):
    id: int
    patient_id: int
    tooth_number: int
    treatment_type: str
    notes: Optional[str] = None
    color: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)


class ExpenseCreate(BaseModel):
    amount: Decimal
    description: str
    type: str = "expense"
    patient_id: Optional[int] = None
    doctor_name: Optional[str] = None
    # يربط دفعة مريض (type="income") بفاتورة علاج محددة (2026-08-25) -- مطلوب
    # إلزامياً عند وجود patient_id مع type="income" (انظر create_expense
    # أدناه)، لضمان أن كل دفعة مرتبطة دائماً بفاتورة مستقلة ولا تتكرر مشكلة
    # تداخل الحسابات القديمة.
    invoice_id: Optional[int] = None
    # 2026-08-25: تاريخ فعلي اختياري للحركة (لتسجيل حركة قديمة بتاريخها الحقيقي
    # بدل ختمها تلقائياً بتاريخ اليوم)، وتصنيف اختياري كـ"رصيد افتتاحي/سابق"
    # يُستبعد من تقارير الأشهر المحددة -- انظر شرح كامل عند get_finance_summary().
    transaction_date: Optional[datetime] = None
    is_opening_balance: bool = False
    # 2026-08-24: ربط تلقائي اختياري بين مصروف "شراء مادة" ومخزن المواد --
    # انظر create_expense() ومذكرة dental_project_finance_inventory_link.
    add_to_inventory: bool = False
    inventory_item_name: Optional[str] = None
    inventory_quantity: Optional[int] = None


class ExpenseResponse(BaseModel):
    id: int
    amount: Decimal
    type: str
    patient_id: Optional[int] = None
    description: str
    doctor_name: Optional[str] = None
    created_at: datetime
    is_opening_balance: bool = False
    inventory_synced: bool = False
    inventory_item_id: Optional[int] = None
    inventory_action: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)


class FinancialTransactionResponse(BaseModel):
    id: int
    patient_id: Optional[int] = None
    doctor_name: Optional[str] = None
    amount: Decimal
    type: str
    description: str
    created_at: datetime
    is_opening_balance: bool = False
    model_config = ConfigDict(from_attributes=True)


class FinancialTransactionUpdate(BaseModel):
    amount: float
    description: str
    # 2026-08-25: تصحيح يدوي لاحق لتصنيف/تاريخ حركة مسجّلة مسبقاً (مثال: دفعة
    # قديمة سُجّلت بالخطأ بتاريخ اليوم بدل تصنيفها كرصيد افتتاحي). كلاهما
    # اختياري تماماً؛ تُرك None يعني "لا تغيير".
    is_opening_balance: Optional[bool] = None
    transaction_date: Optional[datetime] = None


# ====================================================================
# فواتير العلاج المستقلة (Treatment Invoices) -- 2026-08-25
# ====================================================================
# انظر شرح models.TreatmentInvoice لسياق كامل. هذه المخططات تخدم ثلاثة
# مسارات جديدة: عرض فواتير مريض، إنشاء فاتورة جديدة، وتسجيل دفعة على فاتورة
# محددة.
class TreatmentInvoiceCreate(BaseModel):
    title: str
    total_cost: float


# 2026-08-29: يسمح بتصحيح التكلفة الإجمالية لفاتورة علاج موجودة (مثلاً عند
# خطأ إدخال) دون المساس بدفعاتها المسجَّلة -- انظر
# PATCH /api/patients/{patient_id}/invoices/{invoice_id} بالأسفل.
class TreatmentInvoiceUpdate(BaseModel):
    total_cost: float


class TreatmentInvoicePaymentCreate(BaseModel):
    amount: float
    description: Optional[str] = None
    # 2026-08-25: نفس الحقلين الاختياريين في ExpenseCreate أعلاه، لنفس السبب --
    # انظر شرح كامل عند get_finance_summary().
    transaction_date: Optional[datetime] = None
    is_opening_balance: bool = False


class TreatmentInvoicePaymentResponse(BaseModel):
    id: int
    amount: float
    description: str
    created_at: datetime
    is_opening_balance: bool = False
    model_config = ConfigDict(from_attributes=True)


class TreatmentInvoiceResponse(BaseModel):
    id: int
    patient_id: int
    title: str
    total_cost: float
    paid_amount: float
    remaining_amount: float
    status: str
    created_at: datetime
    payments: List[TreatmentInvoicePaymentResponse] = []
    model_config = ConfigDict(from_attributes=True)


class PatientStatsResponse(BaseModel):
    total_patients: int
    active_appointments: int
    pending_balances: float


class PrescriptionCreate(BaseModel):
    patient_id: int
    medications: str
    instructions: str


class PrescriptionResponse(BaseModel):
    id: int
    patient_id: int
    medications: str
    instructions: str
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class InventoryItemCreate(BaseModel):
    item_name: str
    quantity: int
    min_alert_quantity: int = 5


class InventoryItemResponse(BaseModel):
    id: int
    doctor_email: str
    item_name: str
    quantity: int
    min_alert_quantity: int
    updated_at: datetime
    model_config = ConfigDict(from_attributes=True)


class PatientXRayResponse(BaseModel):
    id: int
    patient_id: int
    file_name: Optional[str] = None
    file_url: str
    description: Optional[str] = None
    file_type: Optional[str] = None
    uploaded_at: datetime
    image_url: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)


class VisitTreatmentCreate(BaseModel):
    tooth_number: int
    procedure: str
    cost: Decimal
    notes: Optional[str] = None


class VisitCreate(BaseModel):
    patient_id: int
    diagnosis: str
    total_cost: Decimal
    amount_paid: Decimal
    treatments: List[VisitTreatmentCreate] = Field(default_factory=list)


class VisitResponse(BaseModel):
    id: int
    patient_id: int
    diagnosis: str
    total_cost: Decimal
    amount_paid: Decimal
    treatments: List[TreatmentResponse]
    model_config = ConfigDict(from_attributes=True)


class LoginRequest(BaseModel):
    email: str
    password: str


class RegisterRequest(BaseModel):
    doctor_name: str
    email: str
    password: str
    activation_code: str


class GoogleLoginRequest(BaseModel):
    credential: str


class LoginResponse(BaseModel):
    token: str
    doctor_name: Optional[str] = None
    email: Optional[str] = None
    tier: str
    subscription_active: bool


class UpgradeTierRequest(BaseModel):
    activation_code: str
    email: Optional[str] = None
    doctor_name: Optional[str] = None


def ensure_user_subscription_is_active(user: models.User, db: Session | None = None) -> None:
    now = datetime.utcnow()

    # 🔒 سد ثغرة "الحساب الوهمي المفعّل": أي حساب تحمل قيمة tier فيه شكل
    # باقة نشطة (standard/premium) لكن لم يمرّ إطلاقاً بمسار دفع حقيقي
    # (كل مسارات الدفع الحقيقية -- /api/auth/register و /api/activate و
    # /api/auth/upgrade-tier -- تضبط subscription_expires_at دائماً لتاريخ
    # مستقبلي حقيقي) يُعامل كأنه لم يُفعّل إطلاقاً، بصرف النظر عن قيمة tier
    # المخزّنة. هذا يغلق تلقائياً أي حساب قديم تسرّب بباقة مجانية قبل
    # إصلاح هذه الثغرة (مثال: حسابات Google القديمة التي كانت تُنشأ قبل
    # إجبار tier="pending_activation" على الحسابات الجديدة).
    normalized_tier_check = (user.tier or "").strip().lower()
    if normalized_tier_check in ("standard", "premium") and user.subscription_expires_at is None:
        if (user.tier or "").strip().lower() != "pending_activation" or user.is_active:
            user.tier = "pending_activation"
            user.is_active = False
            if db is not None:
                try:
                    db.commit()
                    db.refresh(user)
                except Exception:
                    db.rollback()

        raise HTTPException(
            status_code=402,
            detail="حسابك بانتظار التفعيل. يرجى إدخال كود تفعيل صالح عبر /api/activate قبل استخدام هذه الميزة.",
        )

    subscription_expired = (
        user.subscription_expires_at is not None
        and user.subscription_expires_at < now
    )

    if subscription_expired:
        # الانتقال التلقائي (Lifecycle transition): لا حذف ولا حظر صريح --
        # فقط عمود tier يتحول إلى "expired_subscription" ليعكس الحقيقة. كل
        # بيانات العيادة (مرضى/مواعيد/مخزون/ملفات) تبقى كما هي تماماً في
        # قاعدة البيانات؛ فقط الوصول عبر الـ API يُمنع حتى التجديد.
        if (user.tier or "").strip().lower() != "expired_subscription":
            user.tier = "expired_subscription"
            user.is_active = False
            if db is not None:
                try:
                    db.commit()
                    db.refresh(user)
                except Exception:
                    db.rollback()

        raise HTTPException(
            status_code=403,
            detail=(
                "انتهت صلاحية باقتك الحالية. لا تقلق أبداً، جميع سجلات مرضاك ومواعيدك "
                "ومخزون عيادتك محفوظة بأمان تام داخل السيرفر ولن تضيع مطلقاً. يرجى إدخال "
                "كود التجديد الشهري لاستعادة كامل صلاحيات الإدارة فوراً."
            ),
        )

    if not user.is_active:
        raise HTTPException(
            status_code=403,
            detail="عذراً، حسابك غير مُفعَّل حالياً. يرجى التواصل مع المهندس فارس حلاوي.",
        )


# ============================================================================
# تشفير كلمات السر + توكنات الجلسة الموقّعة (2026-08-23)
# ============================================================================
# مشكلة أمنية جوهرية كانت موجودة: كلمات السر تُخزَّن نصاً صريحاً (plaintext) في
# users.hashed_password ويُقارَن معها مباشرة بـ ==، وهوية الطبيب في كل طلب لاحق
# بعد تسجيل الدخول كانت تُستنتَج فقط من هيدر X-Doctor-Email أو من هيدر
# Authorization المُعامَل حرفياً كأنه البريد الإلكتروني -- بلا أي تحقق تشفيري.
# هذا يعني أن أي طرف يعرف بريد طبيب آخر (بدون معرفة كلمة سره) كان يقدر ينتحل
# هويته بطلب مباشر للـ API (curl/Postman). الحل: تشفير حقيقي لكلمات السر
# (PBKDF2-HMAC-SHA256 عبر مكتبة hashlib القياسية، بلا أي اعتماد خارجي جديد)،
# وتوكن جلسة موقّع (بنية مطابقة لـ JWT: header.payload.signature بترميز
# base64url، وتوقيع HMAC-SHA256 بمفتاح السيرفر السرّي) يُصدَر فقط عند تسجيل
# دخول ناجح فعلياً، ويُتحقق من توقيعه وصلاحيته في كل طلب لاحق.

PASSWORD_HASH_PREFIX = "pbkdf2_sha256"
PASSWORD_HASH_ITERATIONS = 260_000


def hash_password(plain_password: str) -> str:
    salt = os.urandom(16)
    derived_key = hashlib.pbkdf2_hmac(
        "sha256", plain_password.encode("utf-8"), salt, PASSWORD_HASH_ITERATIONS
    )
    return (
        f"{PASSWORD_HASH_PREFIX}${PASSWORD_HASH_ITERATIONS}$"
        f"{base64.b64encode(salt).decode('ascii')}${base64.b64encode(derived_key).decode('ascii')}"
    )


def is_legacy_plaintext_hash(stored_value: str | None) -> bool:
    # أي قيمة قديمة لا تطابق تنسيق الهاش الجديد تُعامَل كنص صريح قديم (من قبل
    # 2026-08-23) -- يُتحقق منها بمقارنة مباشرة عند تسجيل الدخول فقط، ثم
    # تُرقَّى شفافياً إلى هاش آمن فور نجاح التحقق (بلا أي تدخل من الطبيب).
    return not (stored_value or "").startswith(f"{PASSWORD_HASH_PREFIX}$")


def verify_password(plain_password: str, stored_hash: str) -> bool:
    try:
        prefix, iterations_str, salt_b64, hash_b64 = (stored_hash or "").split("$")
        if prefix != PASSWORD_HASH_PREFIX:
            return False
        iterations = int(iterations_str)
        salt = base64.b64decode(salt_b64)
        expected_key = base64.b64decode(hash_b64)
        actual_key = hashlib.pbkdf2_hmac("sha256", plain_password.encode("utf-8"), salt, iterations)
        return hmac.compare_digest(actual_key, expected_key)
    except Exception:
        return False


def _b64url_encode(raw_bytes: bytes) -> str:
    return base64.urlsafe_b64encode(raw_bytes).rstrip(b"=").decode("ascii")


def _b64url_decode(encoded_value: str) -> bytes:
    padding_needed = (-len(encoded_value)) % 4
    return base64.urlsafe_b64decode(encoded_value + ("=" * padding_needed))


def create_session_token(email: str) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    issued_at = int(time.time())
    payload = {
        "sub": (email or "").strip().lower(),
        "iat": issued_at,
        "exp": issued_at + SESSION_TOKEN_TTL_SECONDS,
    }
    header_b64 = _b64url_encode(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    payload_b64 = _b64url_encode(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    signing_input = f"{header_b64}.{payload_b64}".encode("ascii")
    signature = hmac.new(SESSION_SECRET_KEY.encode("utf-8"), signing_input, hashlib.sha256).digest()
    return f"{header_b64}.{payload_b64}.{_b64url_encode(signature)}"


def verify_session_token(token: str) -> str | None:
    try:
        header_b64, payload_b64, signature_b64 = (token or "").split(".")
        signing_input = f"{header_b64}.{payload_b64}".encode("ascii")
        expected_signature = hmac.new(SESSION_SECRET_KEY.encode("utf-8"), signing_input, hashlib.sha256).digest()
        actual_signature = _b64url_decode(signature_b64)
        if not hmac.compare_digest(expected_signature, actual_signature):
            return None

        payload = json.loads(_b64url_decode(payload_b64))
        if int(payload.get("exp", 0)) < int(time.time()):
            return None

        verified_email = (payload.get("sub") or "").strip().lower()
        return verified_email or None
    except Exception:
        return None


def _extract_bearer_token(authorization: str | None) -> str:
    value = (authorization or "").strip()
    if value.lower().startswith("bearer "):
        value = value[7:].strip()
    return value


def require_premium_user_by_email(db: Session, authorization: str | None) -> models.User:
    verified_email = verify_session_token(_extract_bearer_token(authorization))
    if not verified_email:
        raise HTTPException(status_code=401, detail="جلستك غير صالحة أو منتهية. يرجى تسجيل الدخول مجدداً.")

    user = db.query(models.User).filter(models.User.email == verified_email).first()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")

    if user.tier != "premium":
        raise HTTPException(
            status_code=403,
            detail="هذه الميزة المحاسبية المتقدمة لإدارة المستودع متاحة حصرياً للباقة الفخمة (Premium).",
        )

    ensure_user_subscription_is_active(user, db)
    return user


# --- ختم آخر نشاط للطبيب (أُضيف 2026-09-05) ---
# نقطة الحقيقة الوحيدة لسؤال "متى آخر مرة فتح فيها هذا الطبيب النظام؟"، ويعتمد
# عليها كلياً محرّك تذكير الخمول بالأعلى. تُستدعى من get_current_doctor_user
# وحدها -- وهي النقطة التي يمرّ منها كل طلب موثّق في المشروع، من الموقع ومن
# تطبيق أندرويد على حدّ سواء -- فلم نحتج أي تعديل في الواجهة الأمامية ولا في
# التطبيق لتغذية هذه القيمة، ولن ينسى أي مسار جديد يُضاف مستقبلاً ختمَها.
#
# الـ throttle مقصود وضروري: بدونه يتحوّل كل طلب قراءة عادي إلى كتابة في
# القاعدة -- الصفحة الواحدة في الموقع تُطلق عدة طلبات عند فتحها، و
# notification-badge.js وحده يستدعي الـ API كل 4 ثوانٍ من كل تبويب مفتوح.
# best-effort بالكامل: أي فشل هنا يُبتلع بصمت ولا يمنع الطبيب من العمل.
ACTIVITY_STAMP_THROTTLE_SECONDS = int(os.getenv("ACTIVITY_STAMP_THROTTLE_SECONDS", str(10 * 60)))


def touch_user_activity(db: Session, user: "models.User") -> None:
    try:
        now = datetime.now(KEEP_ALIVE_TIMEZONE).replace(tzinfo=None)
        last_active_at = getattr(user, "last_active_at", None)
        if last_active_at and (now - last_active_at).total_seconds() < ACTIVITY_STAMP_THROTTLE_SECONDS:
            return
        user.last_active_at = now
        db.commit()
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass


def get_current_doctor_user(
    db: Session,
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
) -> models.User:
    # ملاحظة أمنية هامة (2026-08-23): الهوية تُستخرج الآن حصراً من توكن جلسة
    # موقّع من السيرفر (عبر /api/auth/login أو /api/auth/register أو
    # /api/auth/google)، وليس من هيدر X-Doctor-Email الخام -- ذاك الهيدر يبقى
    # في التوقيع فقط للتوافق مع أي كود قديم يرسله، لكنه بلا أي أثر على تحديد
    # الهوية بعد اليوم. لا يجوز إطلاقاً العودة للثقة بهذا الهيدر مباشرة.
    verified_email = verify_session_token(_extract_bearer_token(authorization))
    if not verified_email:
        raise HTTPException(status_code=401, detail="جلستك غير صالحة أو منتهية. يرجى تسجيل الدخول مجدداً.")

    user = db.query(models.User).filter(models.User.email == verified_email).first()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")

    # يكفي ختم النشاط هنا: كل مسار موثّق في المشروع يمرّ من هذه الدالة، مباشرة
    # أو عبر require_active_doctor_user/require_premium_user_by_email.
    touch_user_activity(db, user)
    return user


def require_active_doctor_user(
    db: Session = Depends(database.get_db),
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
) -> models.User:
    # الحارس الفعلي (من طرف السيرفر) لجدار الحماية التجاري: يُستخدم على كل
    # مسار يخدم بيانات المرضى/المواعيد/المالية/الروشتات، وليس فقط شاشة القفل
    # في الواجهة الأمامية -- فتلك الشاشة يمكن تجاوزها بسهولة بطلب مباشر إلى
    # الـ API (curl/Postman/تعطيل الجافاسكربت). هذه الدالة تمنع ذلك فعلياً.
    user = get_current_doctor_user(db, doctor_email=doctor_email, authorization=authorization)

    normalized_tier = (user.tier or "").strip().lower()
    if normalized_tier in ("", "pending_activation"):
        raise HTTPException(
            status_code=402,
            detail="حسابك بانتظار التفعيل. يرجى إدخال كود تفعيل صالح عبر /api/activate قبل استخدام هذه الميزة.",
        )

    ensure_user_subscription_is_active(user, db)
    return user


@app.get("/health")
def health_check():
    return {"status": "ok"}


def resolve_activation_key_tier(activation_key: "models.ActivationKey", activation_code: str) -> str:
    """يحدّد فئة (premium/standard) كود تفعيل واحد -- نقطة الحقيقة الوحيدة
    المستخدمة الآن من الأماكن الثلاثة التي تحتاج هذا التصنيف: التسجيل
    (register_user)، الترقية الفورية (upgrade_user_tier)، والتفعيل/التجديد
    (activate_account). قبل 2026-08-30 كان كل مسار يعيد تنفيذ نفس المنطق
    بشكل منفصل ومتفاوت، وهذا بالضبط ما سبّب خللاً حقيقياً: كود Premium شهري
    صحيح بصيغة "PM-...." رُفض في مسار الترقية وأُسيء تصنيفه في مسار
    التسجيل، لأن عمود intended_tier لم يكن يُفحَص إلا في مسار
    التفعيل/التجديد وحده. أي تعديل مستقبلي على قواعد التصنيف (بادئة جديدة،
    فئة جديدة، ...) يكفي تطبيقه هنا مرة واحدة بدل ثلاث مرات متفرقة.

    يُفضَّل عمود intended_tier الصريح إن وُجد (كل الأكواد الحديثة المولَّدة
    عبر /api/admin/renewal-keys/generate تضبطه)، ويُلجَأ للتخمين النصي
    القديم فقط للأكواد القديمة التي لا تملك هذا العمود إطلاقاً.
    """
    explicit_tier = (getattr(activation_key, "intended_tier", None) or "").strip().lower()
    if explicit_tier in ("premium", "standard"):
        return explicit_tier

    upper_code = activation_code.upper()
    is_premium = (
        activation_key.duration_days >= 365
        or "-Y-" in upper_code
        or "PREMIUM" in upper_code
        or "VIP" in upper_code
        or upper_code.startswith("PRM-")
    )
    return "premium" if is_premium else "standard"


@app.post("/api/auth/register")
def register_user(register_request: RegisterRequest, db: Session = Depends(database.get_db)):
    try:
        normalized_email = register_request.email.strip().lower()
        activation_code = register_request.activation_code.strip()

        if not normalized_email:
            raise HTTPException(status_code=400, detail="البريد الإلكتروني مطلوب.")

        # مطابقة غير حساسة لحالة الأحرف (2026-08-23): الأكواد المولَّدة عبر
        # generate_renewal_activation_code() تحتوي أحرفاً كبيرة وصغيرة معاً
        # (string.ascii_letters)، وكانت المطابقة السابقة حساسة لحالة الأحرف
        # (==) بينما حقل الإدخال في register.html يحوّل كل شيء تلقائياً إلى
        # أحرف كبيرة (toUpperCase) فور الكتابة/اللصق -- مما كان يرفض أي كود
        # حقيقي يحتوي حرفاً صغيراً واحداً على الأقل (وهذا يشمل تقريباً كل
        # الأكواد الفعلية). المطابقة الآن تتجاهل حالة الأحرف بالكامل.
        activation_key = (
            db.query(models.ActivationKey)
            .filter(func.lower(models.ActivationKey.key_code) == activation_code.lower())
            .first()
        )

        if not activation_key or activation_key.is_used:
            raise HTTPException(
                status_code=400,
                detail="كود التفعيل خاطئ، منتهي، أو تم استخدامه مسبقاً! يرجى التواصل مع المهندس فارس حلاوي لشراء كود جديد.",
            )

        # نقطة الحقيقة الوحيدة لتصنيف الكود -- انظر resolve_activation_key_tier
        # أعلاه (2026-08-30: كانت هذه الفحوصات مكررة ومتفاوتة بين ثلاثة مسارات
        # مختلفة، وهذا بالضبط ما سبّب رفض/إساءة تصنيف كود Premium شهري حقيقي).
        user_tier = resolve_activation_key_tier(activation_key, activation_code)

        existing_user = db.query(models.User).filter(models.User.email == normalized_email).first()
        if existing_user:
            raise HTTPException(status_code=400, detail="هذا البريد الإلكتروني مُسجل مسبقًا.")

        subscription_expires_at = datetime.utcnow() + timedelta(days=activation_key.duration_days)

        new_user = models.User(
            doctor_name=register_request.doctor_name,
            email=normalized_email,
            hashed_password=hash_password(register_request.password),
            tier=user_tier,
            subscription_expires_at=subscription_expires_at,
            is_active=True,
        )

        activation_key.is_used = True
        activation_key.used_by_email = normalized_email

        db.add(new_user)
        db.commit()
        db.refresh(new_user)
    except HTTPException:
        db.rollback()
        raise
    except (TypeError, ValueError, AttributeError):
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر معالجة بيانات التسجيل. يرجى التحقق من الحقول المدخلة.")
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="حدث خطأ أثناء تنفيذ التسجيل. يرجى المحاولة مرة أخرى.")

    try:
        return {
            "message": "تم إنشاء الحساب بنجاح.",
            "doctor_name": new_user.doctor_name,
            "email": new_user.email,
            "tier": new_user.tier,
            "token": create_session_token(new_user.email),
            "subscription_expires_at": subscription_expires_at.isoformat(),
        }
    except Exception:
        raise HTTPException(status_code=400, detail="تم إنشاء الحساب لكن تعذر تجهيز الاستجابة بشكل صحيح.")


# المخطط البرمجي الصارم لاستقبال بيانات الدخول التقليدي
class LoginRequest(BaseModel):
    email: str
    password: str

@app.post("/api/auth/login")
def login_user(login_request: LoginRequest, db: Session = Depends(database.get_db)):
    # 1. تنظيف البريد الإلكتروني وتحويله لأحرف صغيرة لمطابقة الحسابات
    normalized_email = login_request.email.strip().lower()
    
    if not normalized_email or not login_request.password:
        raise HTTPException(status_code=400, detail="يرجى ملء جميع الحقول المطلوبة!")
        
    # 2. الاستعلام عن الطبيب في قاعدة بيانات Supabase الأبدية
    user = db.query(models.User).filter(models.User.email == normalized_email).first()
    if not user:
        raise HTTPException(status_code=401, detail="البريد الإلكتروني أو كلمة المرور غير صحيحة!")

    # 3. تحقق حقيقي من كلمة المرور عبر الهاش الآمن (2026-08-23) -- مع دعم
    # ترحيل شفاف للحسابات القديمة المخزّنة نصاً صريحاً (plaintext): إن كانت
    # كلمة السر المخزّنة بالتنسيق القديم، تُقارَن مباشرة كما كانت، وفور نجاح
    # المطابقة تُرقَّى فوراً إلى هاش PBKDF2 آمن ويُحفظ التغيير -- بلا أي تدخل
    # مطلوب من الطبيب ودون أن يلاحظ أي فرق في تجربة الاستخدام.
    if is_legacy_plaintext_hash(user.hashed_password):
        if user.hashed_password != login_request.password:
            raise HTTPException(status_code=401, detail="البريد الإلكتروني أو كلمة المرور غير صحيحة!")
        try:
            user.hashed_password = hash_password(login_request.password)
            db.commit()
        except Exception:
            db.rollback()
    else:
        if not verify_password(login_request.password, user.hashed_password):
            raise HTTPException(status_code=401, detail="البريد الإلكتروني أو كلمة المرور غير صحيحة!")

    # 3ب. نفس حارس الاشتراك المستخدم في مسار Google -- كان مسار تسجيل
    # الدخول اليدوي هذا يرجع نجاح لأي حساب مطابق كلمة المرور مهما كانت
    # حالة اشتراكه، مما كان يُمكّن أي حساب قديم/غير مفعّل من الدخول طالما
    # يعرف كلمة المرور فقط.
    ensure_user_subscription_is_active(user, db)

    try:
        # 4. العبور المحاسبي الآمن وإرجاع قاموس JSON صافي ومطابق 100% للـ Frontend،
        # مع توكن جلسة موقّع حقيقي (2026-08-23) يحل محل الاعتماد على البريد
        # الإلكتروني الخام كإثبات هوية في كل طلب لاحق.
        return {
            "status": "success",
            "email": user.email,
            "tier": user.tier or "pending_activation",
            "doctor_name": user.doctor_name,
            "token": create_session_token(user.email),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"خطأ في معالجة الجلسة السحابية: {e}")


# مسار تسجيل الدخول عبر Google - تحقق حقيقي من التوكن + منع أي دخول مجاني بلا اشتراك فعلي
@app.post("/api/auth/google", response_model=LoginResponse)
def google_login(google_request: GoogleLoginRequest, db: Session = Depends(database.get_db)):
    try:
        token_payload = id_token.verify_oauth2_token(
            google_request.credential,
            google_requests.Request(),
            GOOGLE_CLIENT_ID,
        )
    except Exception:
        raise HTTPException(status_code=401, detail="تعذر التحقق من حساب Google.")

    if not token_payload.get("email_verified"):
        raise HTTPException(status_code=401, detail="بريد Google غير موثق.")

    email = str(token_payload.get("email", "")).strip().lower()
    if not email:
        raise HTTPException(status_code=401, detail="تعذر قراءة البريد من حساب Google.")

    full_name = str(token_payload.get("name", "")).strip()
    if not full_name:
        given_name = str(token_payload.get("given_name", "")).strip()
        family_name = str(token_payload.get("family_name", "")).strip()
        full_name = f"{given_name} {family_name}".strip()

    user = db.query(models.User).filter(models.User.email == email).first()

    if not user:
        # حساب جديد كلياً عبر Google: لا يُمنح أي وصول مجاني أو باقة نشطة تلقائياً.
        # يُنشأ بحالة "غير مفعّل" تماماً مثل التسجيل اليدوي، ويجب عليه إدخال كود تفعيل مدفوع
        # عبر /api/auth/upgrade-tier أو /api/activate قبل أن يصبح حسابه نشطاً.
        try:
            fallback_doctor_name = full_name or email.split("@")[0]
            user = models.User(
                doctor_name=fallback_doctor_name,
                email=email,
                hashed_password=f"google-oauth-{uuid4().hex}",
                tier="pending_activation",
                is_active=False,
                subscription_expires_at=None,
            )
            db.add(user)
            db.commit()
            db.refresh(user)
        except Exception:
            db.rollback()
            raise HTTPException(status_code=400, detail="تعذر إنشاء الحساب تلقائياً عبر Google.")

        raise HTTPException(
            status_code=402,
            detail="تم إنشاء حسابك عبر Google بنجاح، لكنه بانتظار التفعيل. يرجى إدخال كود تفعيل صالح لتفعيل الاشتراك.",
        )

    try:
        user_updated = False
        if full_name and not (user.doctor_name or "").strip():
            user.doctor_name = full_name
            user_updated = True

        if user_updated:
            db.commit()
            db.refresh(user)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر تحديث بيانات حساب Google.")

    # لا نمنح أي رتبة تلقائياً هنا - نتحقق فقط من أن اشتراكه الحالي (إن وُجد) ما زال فعالاً
    ensure_user_subscription_is_active(user, db)

    return LoginResponse(
        token=create_session_token(user.email),
        doctor_name=user.doctor_name,
        email=user.email,
        tier=user.tier or "pending_activation",
        subscription_active=True,
    )


@app.post("/api/auth/upgrade-tier")
def upgrade_user_tier(upgrade_request: UpgradeTierRequest, db: Session = Depends(database.get_db)):
    activation_code = upgrade_request.activation_code.strip()
    normalized_email = (upgrade_request.email or "").strip().lower()
    doctor_name = (upgrade_request.doctor_name or "").strip()

    if not activation_code:
        raise HTTPException(status_code=400, detail="كود الترقية مطلوب.")

    # مطابقة غير حساسة لحالة الأحرف (2026-08-23) -- انظر نفس الملاحظة في
    # register_user أعلاه.
    activation_key = (
        db.query(models.ActivationKey)
        .filter(func.lower(models.ActivationKey.key_code) == activation_code.lower())
        .first()
    )

    if not activation_key or activation_key.is_used:
        raise HTTPException(status_code=400, detail="كود الترقية غير صالح أو مستخدم مسبقاً.")

    # نقطة الحقيقة الوحيدة لتصنيف الكود -- انظر resolve_activation_key_tier
    # أعلاه (2026-08-30: كانت هذه الفحوصات مكررة ومتفاوتة بين ثلاثة مسارات
    # مختلفة، وهذا بالضبط ما سبّب رفض كود Premium شهري حقيقي هنا تحديداً).
    if resolve_activation_key_tier(activation_key, activation_code) != "premium":
        raise HTTPException(status_code=400, detail="هذا الكود لا يفعّل باقة Premium.")

    user = None
    if normalized_email:
        user = db.query(models.User).filter(models.User.email == normalized_email).first()

    if user is None and doctor_name:
        user = db.query(models.User).filter(models.User.doctor_name == doctor_name).first()

    if user is None:
        raise HTTPException(status_code=404, detail="تعذر تحديد الحساب المطلوب ترقيته.")

    now = datetime.utcnow()
    base_date = user.subscription_expires_at if user.subscription_expires_at and user.subscription_expires_at > now else now

    try:
        user.tier = "premium"
        user.subscription_expires_at = base_date + timedelta(days=activation_key.duration_days)
        user.is_active = True

        activation_key.is_used = True
        activation_key.used_by_email = user.email

        db.commit()
        db.refresh(user)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر تنفيذ الترقية حالياً. حاول مرة أخرى.")

    return {
        "message": "تمت ترقية الحساب إلى Premium بنجاح.",
        "doctor_name": user.doctor_name,
        "email": user.email,
        "tier": user.tier,
        "subscription_expires_at": user.subscription_expires_at.isoformat() if user.subscription_expires_at else None,
    }


class DoctorProfileUpdate(BaseModel):
    doctor_name: Optional[str] = None
    email: Optional[str] = None
    clinic_name: Optional[str] = None
    clinic_address: Optional[str] = None
    clinic_phone: Optional[str] = None
    password: Optional[str] = None


def serialize_doctor_profile(user: models.User) -> dict:
    subscription_active = (
        user.subscription_expires_at is not None
        and user.subscription_expires_at >= datetime.utcnow()
    )
    return {
        "doctor_name": user.doctor_name,
        "email": user.email,
        # ثغرة أُصلحت (2026-08-23): كان هذا الحقل يرجع user.hashed_password
        # (قيمة الهاش PBKDF2 الفعلية) للواجهة الأمامية باسم "password"، فكانت
        # صفحة "حسابي" تعرضها كأنها كلمة السر الحقيقية القابلة للقراءة -- لم تعد
        # كلمة السر تُرجَع للواجهة إطلاقاً بعد اليوم، بل مؤشر بسيط فقط.
        "has_password": bool(user.hashed_password),
        "tier": user.tier,
        "clinic_name": user.clinic_name,
        "clinic_address": user.clinic_address,
        "clinic_phone": user.clinic_phone,
        "avatar_url": user.avatar_url,
        "is_active": user.is_active,
        "subscription_active": subscription_active,
        "subscription_expires_at": user.subscription_expires_at.isoformat() if user.subscription_expires_at else None,
    }


# صفحة "حسابي" (profile.html): تُستخدم get_current_doctor_user وليس
# require_active_doctor_user عمداً في مساري GET/PUT التاليين -- حساب الطبيب
# المعلَّق (pending_activation) أو المنتهي الاشتراك (expired_subscription) يجب
# أن يبقى قادراً على عرض/تعديل بياناته الأساسية (مثل كلمة السر أو اسم العيادة)
# حتى وهو محظور عن باقي ميزات النظام، بدل أن يُقفَل خارج حسابه بالكامل.
@app.get("/api/auth/profile")
def get_doctor_profile(
    db: Session = Depends(database.get_db),
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
):
    user = get_current_doctor_user(db, doctor_email=doctor_email, authorization=authorization)
    return serialize_doctor_profile(user)


@app.put("/api/auth/profile")
def update_doctor_profile(
    profile_update: DoctorProfileUpdate,
    db: Session = Depends(database.get_db),
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
):
    user = get_current_doctor_user(db, doctor_email=doctor_email, authorization=authorization)

    if profile_update.doctor_name is not None:
        trimmed_name = profile_update.doctor_name.strip()
        if not trimmed_name:
            raise HTTPException(status_code=400, detail="اسم الطبيب لا يمكن أن يكون فارغاً.")
        user.doctor_name = trimmed_name

    if profile_update.email is not None:
        normalized_new_email = profile_update.email.strip().lower()
        if not normalized_new_email:
            raise HTTPException(status_code=400, detail="البريد الإلكتروني لا يمكن أن يكون فارغاً.")
        if normalized_new_email != user.email:
            existing_user = (
                db.query(models.User)
                .filter(models.User.email == normalized_new_email, models.User.id != user.id)
                .first()
            )
            if existing_user:
                raise HTTPException(status_code=400, detail="هذا البريد الإلكتروني مُستخدَم من حساب آخر.")
            user.email = normalized_new_email

    if profile_update.clinic_name is not None:
        user.clinic_name = profile_update.clinic_name.strip() or None

    if profile_update.clinic_address is not None:
        user.clinic_address = profile_update.clinic_address.strip() or None

    if profile_update.clinic_phone is not None:
        user.clinic_phone = profile_update.clinic_phone.strip() or None

    if profile_update.password is not None:
        trimmed_password = profile_update.password.strip()
        if not trimmed_password:
            raise HTTPException(status_code=400, detail="كلمة السر لا يمكن أن تكون فارغة.")
        # ثغرة أُصلحت (2026-08-23): كان هذا المسار يخزّن كلمة السر الجديدة كنص
        # صريح مباشرة (يتجاوز hash_password تماماً)، ما يفرغ نظام الهاش المطبَّق
        # على /api/auth/login و/api/auth/register من أي قيمة أمنية بمجرد أن يغيّر
        # الطبيب كلمة سره ولو مرة واحدة من صفحة "حسابي".
        user.hashed_password = hash_password(trimmed_password)

    try:
        db.commit()
        db.refresh(user)
    except HTTPException:
        db.rollback()
        raise
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر حفظ التعديلات. حاول مرة أخرى.")

    return serialize_doctor_profile(user)



# ====================================================================
# إعدادات صفحة الحجز العامة (public booking page) -- 2026-08-23
# كل طبيب يقدر يفعّل رابطاً عاماً خاصاً فيه (site.com/d/<booking_slug>) يسمح
# لأي مريض بحجز موعد مباشرة بلا تسجيل دخول ولا اتصال هاتفي. هذا القسم يضبط
# إعدادات ذاك الرابط فقط -- المسارات العامة نفسها (بلا مصادقة) موجودة بالأسفل
# قرب نهاية الملف قبل app.mount.
# ====================================================================
BOOKING_SLUG_PATTERN = re.compile(r"^[a-z][a-z0-9-]{2,39}$")
VALID_WORK_DAYS = set(range(7))  # Monday=0 .. Sunday=6 (نفس ترميز date.weekday())


def slugify_booking_candidate(raw_value: str) -> str:
    # يحوّل أي نص يُدخله الطبيب إلى صيغة صالحة كرابط عام (أحرف إنكليزية صغيرة،
    # أرقام، وشرطات فقط) -- لا يترجم النص العربي، بل يستخرج الأجزاء الصالحة منه.
    lowered = (raw_value or "").strip().lower()
    slug = re.sub(r"[^a-z0-9]+", "-", lowered).strip("-")
    return slug[:40]


class BookingSettingsUpdate(BaseModel):
    booking_slug: Optional[str] = None
    public_booking_enabled: Optional[bool] = None
    work_days: Optional[List[int]] = None
    work_start_time: Optional[str] = None
    work_end_time: Optional[str] = None
    slot_duration_minutes: Optional[int] = None
    clinic_phone: Optional[str] = None


def serialize_booking_settings(user: models.User) -> dict:
    work_days_list: list[int] = []
    if user.work_days:
        for part in user.work_days.split(","):
            part = part.strip()
            if part.isdigit() and int(part) in VALID_WORK_DAYS:
                work_days_list.append(int(part))
    return {
        "booking_slug": user.booking_slug,
        "public_booking_enabled": bool(user.public_booking_enabled),
        "work_days": sorted(work_days_list),
        "work_start_time": user.work_start_time,
        "work_end_time": user.work_end_time,
        "slot_duration_minutes": user.slot_duration_minutes,
        "clinic_phone": user.clinic_phone,
        "booking_url_path": f"/d/{user.booking_slug}" if user.booking_slug else None,
    }


@app.get("/api/auth/booking-settings")
def get_booking_settings(
    db: Session = Depends(database.get_db),
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
):
    user = get_current_doctor_user(db, doctor_email=doctor_email, authorization=authorization)
    return serialize_booking_settings(user)


@app.put("/api/auth/booking-settings")
def update_booking_settings(
    settings_update: BookingSettingsUpdate,
    db: Session = Depends(database.get_db),
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
):
    user = get_current_doctor_user(db, doctor_email=doctor_email, authorization=authorization)

    if settings_update.booking_slug is not None:
        candidate_slug = slugify_booking_candidate(settings_update.booking_slug)
        if not candidate_slug or not BOOKING_SLUG_PATTERN.fullmatch(candidate_slug):
            raise HTTPException(
                status_code=400,
                detail="الرابط يجب أن يبدأ بحرف إنكليزي، ويتكوّن من 3-40 حرفاً/رقماً/شرطة فقط (مثال: dr-fares).",
            )
        existing_owner = (
            db.query(models.User)
            .filter(models.User.booking_slug == candidate_slug, models.User.id != user.id)
            .first()
        )
        if existing_owner:
            raise HTTPException(status_code=400, detail="هذا الرابط مُستخدَم من طبيب آخر، يرجى اختيار رابط مختلف.")
        user.booking_slug = candidate_slug

    if settings_update.work_days is not None:
        cleaned_days = sorted({day for day in settings_update.work_days if day in VALID_WORK_DAYS})
        user.work_days = ",".join(str(day) for day in cleaned_days) if cleaned_days else None

    if settings_update.work_start_time is not None:
        trimmed_start = settings_update.work_start_time.strip()
        if trimmed_start and (len(trimmed_start) != 5 or trimmed_start[2] != ":"):
            raise HTTPException(status_code=400, detail="صيغة وقت البدء غير صالحة. المتوقع HH:MM")
        user.work_start_time = trimmed_start or None

    if settings_update.work_end_time is not None:
        trimmed_end = settings_update.work_end_time.strip()
        if trimmed_end and (len(trimmed_end) != 5 or trimmed_end[2] != ":"):
            raise HTTPException(status_code=400, detail="صيغة وقت الانتهاء غير صالحة. المتوقع HH:MM")
        user.work_end_time = trimmed_end or None

    if settings_update.slot_duration_minutes is not None:
        if settings_update.slot_duration_minutes < 5 or settings_update.slot_duration_minutes > 240:
            raise HTTPException(status_code=400, detail="مدة الموعد يجب أن تكون بين 5 و240 دقيقة.")
        user.slot_duration_minutes = settings_update.slot_duration_minutes

    if settings_update.clinic_phone is not None:
        user.clinic_phone = settings_update.clinic_phone.strip() or None

    if settings_update.public_booking_enabled is not None:
        if settings_update.public_booking_enabled:
            # لا يجوز تفعيل الرابط العام قبل ضبط الحد الأدنى من الإعدادات
            # الضرورية لحساب مواعيد متاحة فعلية -- رابط بلا إعدادات كاملة
            # سيعرض للمريض صفحة بلا أي وقت متاح إطلاقاً.
            if not user.booking_slug:
                raise HTTPException(status_code=400, detail="يجب اختيار رابط عام (Slug) قبل تفعيل صفحة الحجز.")
            if not user.work_days:
                raise HTTPException(status_code=400, detail="يجب تحديد أيام العمل قبل تفعيل صفحة الحجز.")
            if not user.work_start_time or not user.work_end_time:
                raise HTTPException(status_code=400, detail="يجب تحديد وقت بدء وانتهاء الدوام قبل تفعيل صفحة الحجز.")
        user.public_booking_enabled = bool(settings_update.public_booking_enabled)

    try:
        db.commit()
        db.refresh(user)
    except HTTPException:
        db.rollback()
        raise
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر حفظ إعدادات الحجز. حاول مرة أخرى.")

    return serialize_booking_settings(user)


# ====================================================================
# ربط حساب واتساب/Green API الخاص بكل طبيب (profile.html "حسابي") -- 2026-09-01
# ====================================================================
# كل طبيب يربط حساب Green API الخاص بعيادته من هنا (idInstance/apiTokenInstance
# من console.green-api.com بعد مسح رمز QR)، بدل الاعتماد على حساب مشترك واحد
# للمنصة كلها -- انظر شرح القرار المعماري كاملاً عند models.User.green_api_instance_id.
# تُستخدَم بيانات الاعتماد هذه من قِبل كل ميزات واتساب بالمشروع (تذكير
# المواعيد، إشعارات طلبات الحجز، استرجاع المرضى) عبر send_whatsapp_message_for_doctor().
def mask_green_api_token(token: str | None) -> str | None:
    if not token:
        return None
    trimmed = token.strip()
    if len(trimmed) <= 4:
        return "••••"
    return f"••••{trimmed[-4:]}"


def serialize_whatsapp_settings(user: models.User) -> dict:
    return {
        "connected": bool(user.green_api_instance_id and user.green_api_token),
        "green_api_instance_id": user.green_api_instance_id,
        # التوكن الفعلي لا يُرجَع أبداً للواجهة الأمامية بعد الحفظ (نفس منطق
        # كلمة السر بـ serialize_doctor_profile) -- فقط آخر 4 خانات منه للتأكيد
        # البصري أن هناك قيمة محفوظة فعلاً دون كشفها كاملة.
        "green_api_token_masked": mask_green_api_token(user.green_api_token),
    }


class WhatsAppSettingsUpdate(BaseModel):
    green_api_instance_id: Optional[str] = None
    green_api_token: Optional[str] = None


@app.get("/api/auth/whatsapp-settings")
def get_whatsapp_settings(
    db: Session = Depends(database.get_db),
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
):
    user = get_current_doctor_user(db, doctor_email=doctor_email, authorization=authorization)
    return serialize_whatsapp_settings(user)


@app.put("/api/auth/whatsapp-settings")
def update_whatsapp_settings(
    settings_update: WhatsAppSettingsUpdate,
    db: Session = Depends(database.get_db),
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
):
    user = get_current_doctor_user(db, doctor_email=doctor_email, authorization=authorization)

    # قيمة نصية فارغة تعني فك الربط عمداً (إعادة الحقل لـ NULL)، وليس تجاهل
    # التحديث -- نفس نمط clinic_phone/clinic_name بـ update_doctor_profile أعلاه.
    if settings_update.green_api_instance_id is not None:
        user.green_api_instance_id = settings_update.green_api_instance_id.strip() or None

    if settings_update.green_api_token is not None:
        user.green_api_token = settings_update.green_api_token.strip() or None

    try:
        db.commit()
        db.refresh(user)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر حفظ إعدادات واتساب. حاول مرة أخرى.")

    return serialize_whatsapp_settings(user)


class WhatsAppTestMessageRequest(BaseModel):
    phone: Optional[str] = None


@app.post("/api/auth/whatsapp-settings/test")
def send_whatsapp_test_message(
    test_request: WhatsAppTestMessageRequest,
    db: Session = Depends(database.get_db),
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
):
    user = get_current_doctor_user(db, doctor_email=doctor_email, authorization=authorization)

    if not user.green_api_instance_id or not user.green_api_token:
        raise HTTPException(status_code=400, detail="يرجى حفظ بيانات Green API أولاً قبل إرسال رسالة تجريبية.")

    target_phone = (test_request.phone or user.clinic_phone or "").strip()
    if not target_phone:
        raise HTTPException(
            status_code=400,
            detail="أدخل رقم هاتف لإرسال الرسالة التجريبية إليه، أو احفظ رقم واتساب العيادة أولاً.",
        )

    doctor_label = (user.clinic_name or user.doctor_name or "").strip() or "عيادتك الرقمية"
    message = f"✅ رسالة تجريبية من {doctor_label} -- تم ربط حساب واتساب عيادتك بنجاح مع نظام عيادتي الرقمية!"

    was_sent = send_whatsapp_message_for_doctor(user, target_phone, message)
    if not was_sent:
        return {
            "sent": False,
            "message": "تعذر إرسال الرسالة. تأكد من صحة idInstance/apiTokenInstance وأن حالة الـ Instance \"مصرَّح\" (Authorized) على console.green-api.com.",
        }

    return {"sent": True, "message": f"تم إرسال رسالة تجريبية بنجاح إلى {target_phone}."}


def validate_avatar_file(file: UploadFile) -> str:
    original_name = file.filename or "avatar"
    _, ext = os.path.splitext(original_name)
    ext = ext.lower()

    allowed_extensions = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp"}
    if ext not in allowed_extensions:
        raise HTTPException(status_code=400, detail="صيغة الصورة غير مدعومة. يرجى استخدام PNG أو JPG أو WEBP.")

    expected_mime = allowed_extensions[ext]
    actual_mime = (file.content_type or "").lower().strip()
    if actual_mime and actual_mime not in {expected_mime, "application/octet-stream"}:
        raise HTTPException(status_code=400, detail="صيغة الملف غير صالحة. يرجى رفع صورة فقط.")

    return ext


@app.post("/api/auth/avatar")
async def upload_doctor_avatar(
    file: UploadFile = File(...),
    db: Session = Depends(database.get_db),
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
):
    user = get_current_doctor_user(db, doctor_email=doctor_email, authorization=authorization)

    ext = validate_avatar_file(file)
    unique_filename = f"avatar_{user.id}_{uuid4().hex}{ext}"
    saved_path = os.path.join(AVATAR_UPLOADS_DIR, unique_filename)
    avatar_url = f"/uploads/avatars/{unique_filename}"

    try:
        content = await file.read()
        with open(saved_path, "wb") as output_file:
            output_file.write(content)

        user.avatar_url = avatar_url
        db.commit()
        db.refresh(user)
    except HTTPException:
        db.rollback()
        raise
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر رفع صورة الحساب. حاول مرة أخرى.")

    return {"message": "تم تحديث صورة الحساب بنجاح.", "avatar_url": user.avatar_url}


class DeviceTokenRequest(BaseModel):
    # كلا الحقلين اختياري منذ 2026-09-05: تطبيق أندرويد يرسل fcm_token وحده
    # (توافق كامل مع النسخة المنشورة الحالية، بلا أي تعديل مطلوب فيها)، وموقع
    # الويب يرسل web_push_token وحده. تمرير سلسلة فارغة "" لأحدهما يعني إلغاء
    # تسجيل ذاك السطح تحديداً (الطبيب أوقف إشعارات المتصفح مثلاً)، أما عدم
    # تمرير الحقل إطلاقاً (None) فلا يمسّ القيمة المخزَّنة له.
    fcm_token: Optional[str] = None
    web_push_token: Optional[str] = None


# تسجيل رمز جهاز Firebase Cloud Messaging لأسطح الطبيب (أُضيف 2026-08-24،
# ووُسّع لإشعارات متصفح الموقع في 2026-09-05) -- يُستدعى مرة بعد كل تسجيل دخول
# ناجح في التطبيق، وعند تفعيل إشعارات المتصفح من صفحة "حسابي". نستخدم
# get_current_doctor_user (وليس require_active_doctor_user) على غرار مسارات
# الحساب/الأفاتار، حتى يقدر طبيب بانتظار التفعيل يسجّل جهازه أيضاً.
@app.post("/api/auth/register-device")
def register_device_token(
    payload: DeviceTokenRequest,
    db: Session = Depends(database.get_db),
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
):
    user = get_current_doctor_user(db, doctor_email=doctor_email, authorization=authorization)

    app_token = payload.fcm_token.strip() if isinstance(payload.fcm_token, str) else None
    web_token = payload.web_push_token.strip() if isinstance(payload.web_push_token, str) else None

    if app_token is None and web_token is None:
        raise HTTPException(status_code=400, detail="fcm_token أو web_push_token مطلوب.")

    try:
        if app_token is not None:
            user.fcm_token = app_token or None
        if web_token is not None:
            user.web_push_token = web_token or None
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر حفظ رمز الجهاز حالياً.")

    return {
        "message": "تم تسجيل الجهاز لاستقبال الإشعارات بنجاح.",
        "app_push_enabled": bool(user.fcm_token),
        "web_push_enabled": bool(user.web_push_token),
    }


# 4. مسار إرسال (حفظ) مريض جديد في النظام [POST]
@app.post("/api/patients", response_model=PatientResponse)
def create_patient(
    patient: PatientCreate,
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(database.get_db),
):
    # ملاحظة أمنية هامة: كان هذا المسار سابقاً "يفشل بأمان مفتوح" -- أي فشل في
    # التحقق من الهوية (get_current_doctor_user) كان يُبتلع بصمت عبر
    # except HTTPException، ويستمر في إنشاء المريض بأي اسم طبيب يُرسله الطالب
    # في جسم الطلب، بلا أي مصادقة حقيقية. الآن: أي فشل في التحقق من الهوية أو
    # حالة التفعيل/الاشتراك يوقف الطلب فوراً (fail closed) بدلاً من المتابعة.
    current_user = require_active_doctor_user(db=db, doctor_email=doctor_email, authorization=authorization)

    # 2026-08-29: بطلب الدكتور -- منع تسجيل مريض بنفس الاسم مرتين لنفس الطبيب
    # (خطأ إدخال شائع: الطبيب أو السكرتيرة يعيدون إدخال نفس المريض بالغلط).
    # المقارنة نصية بعد trim + توحيد حالة الأحرف حتى لا يمر "احمد علي" و"  احمد علي "
    # كسجلَّين مختلفين، ومحصورة بمرضى نفس الطبيب فقط (doctor_email) حتى لا يُمنع
    # طبيبان مختلفان من تسجيل مريضين بنفس الاسم الشائع في عيادتين مختلفتين.
    # هذا فحص احتياطي على مستوى الخادم بالإضافة إلى الفحص الفوري في index.html --
    # نفس نمط المقارنة المستخدم في find_or_create_patient_for_booking أعلاه.
    resolved_full_name = (patient.full_name or "").strip()
    if resolved_full_name:
        existing_doctor_patients = (
            db.query(models.Patient)
            .filter(models.Patient.doctor_email == current_user.email)
            .all()
        )
        for existing_patient in existing_doctor_patients:
            if (existing_patient.full_name or "").strip().lower() == resolved_full_name.lower():
                raise HTTPException(
                    status_code=409,
                    detail="الاسم موجود مسبقاً في قائمة المرضى.",
                )

    resolved_doctor_name = (patient.doctor_name or "").strip()
    if not resolved_doctor_name:
        resolved_doctor_name = (current_user.doctor_name or current_user.email or "").strip()

    db_patient = models.Patient(
        doctor_name=resolved_doctor_name or None,
        doctor_email=current_user.email,
        full_name=resolved_full_name or patient.full_name,
        phone=patient.phone,
        birth_date=patient.birth_date if patient.birth_date else None,
        gender=patient.gender if patient.gender else "Male",
        medical_history=patient.medical_history,
        total_treatment_cost=float(patient.total_treatment_cost or 0.0),
    )
    db.add(db_patient)
    db.commit()
    db.refresh(db_patient)
    return db_patient


# يربط (أو ينشئ عند الحاجة) سجل مريض حقيقي عند قبول طلب حجز وارد من صفحة
# الحجز العامة booking.html -- انظر التعليق في respond_to_booking_request أعلاه
# لسياق سبب إضافة هذه الدالة (2026-08-25). المطابقة تعتمد على رقم الهاتف بعد
# تطبيعه بنفس normalize_whatsapp_phone المستخدمة لإشعارات واتساب، حتى لا يُنشأ
# سجل مريض مكرر لنفس الشخص إن حجز أكثر من مرة بصيغ مختلفة لنفس الرقم
# (0.. أو 963.. أو 00963..)، ومحصورة بنفس الطبيب (doctor_email) دائماً.
def find_or_create_patient_for_booking(
    db: Session,
    doctor: "models.User",
    patient_name: str,
    patient_phone: str | None,
) -> int | None:
    normalized_target = normalize_whatsapp_phone(patient_phone)

    if normalized_target:
        candidates = (
            db.query(models.Patient)
            .filter(models.Patient.doctor_email == doctor.email)
            .all()
        )
        for candidate in candidates:
            if normalize_whatsapp_phone(candidate.phone) == normalized_target:
                return candidate.id

    db_patient = models.Patient(
        doctor_name=(doctor.doctor_name or doctor.email or "").strip() or None,
        doctor_email=doctor.email,
        full_name=(patient_name or "").strip() or "مريض بدون اسم",
        phone=(patient_phone or "").strip() or "غير متوفر",
        gender="Male",
    )
    db.add(db_patient)
    db.flush()  # للحصول على db_patient.id دون إنهاء المعاملة الحالية (commit يتم لاحقاً في المستدعي)
    return db_patient.id


# 5. مسار جلب قائمة جميع المرضى المخزنين في العيادة [GET]
@app.get("/api/patients", response_model=List[PatientResponse])
def get_all_patients(
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(database.get_db),
):
    user = require_active_doctor_user(db=db, doctor_email=doctor_email, authorization=authorization)

    # عزل صارم حسب doctor_email فقط (الحقل الرسمي، غير قابل للتلاعب من العميل) --
    # لا يوجد أي fallback لعرض مرضى بلا مالك أو مرضى طبيب آخر (2026-08-23).
    patients = (
        db.query(models.Patient)
        .filter(models.Patient.doctor_email == user.email)
        .all()
    )

    patient_ids = [patient.id for patient in patients]
    paid_amount_by_patient_id: dict[int, Decimal] = {}
    # 2026-08-25: "total_treatment_cost" هنا لم يعد يُقرأ من العمود الخام
    # المفرد patients.total_treatment_cost (كان هذا مصدر مشكلة تداخل
    # الحسابات) -- بل يُحسب كمجموع كل فواتير العلاج (treatment_invoices)
    # المستقلة لهذا المريض، مفتوحة كانت أو مغلقة. الشكل الظاهري لهذا الحقل في
    # الاستجابة (اسمه ونوعه) لم يتغيّر إطلاقاً حتى لا يُكسر أي كود قائم يقرأه
    # (index.html يستخدمه كـ fallback عند فشل /api/patients/stats).
    total_cost_by_patient_id: dict[int, Decimal] = {}

    if patient_ids:
        income_rows = (
            db.query(
                models.FinancialTransaction.patient_id,
                func.coalesce(func.sum(models.FinancialTransaction.amount), 0).label("total_paid"),
            )
            .filter(models.FinancialTransaction.patient_id.in_(patient_ids))
            .filter(models.FinancialTransaction.type == "income")
            .filter(models.FinancialTransaction.amount > 0)
            .group_by(models.FinancialTransaction.patient_id)
            .all()
        )

        paid_amount_by_patient_id = {
            patient_id: Decimal(str(total_paid or 0))
            for patient_id, total_paid in income_rows
            if patient_id is not None
        }

        invoice_cost_rows = (
            db.query(
                models.TreatmentInvoice.patient_id,
                func.coalesce(func.sum(models.TreatmentInvoice.total_cost), 0).label("total_cost"),
            )
            .filter(models.TreatmentInvoice.patient_id.in_(patient_ids))
            .group_by(models.TreatmentInvoice.patient_id)
            .all()
        )
        total_cost_by_patient_id = {
            patient_id: Decimal(str(total_cost or 0))
            for patient_id, total_cost in invoice_cost_rows
            if patient_id is not None
        }

    response_payload: list[dict] = []
    for patient in patients:
        paid_amount = paid_amount_by_patient_id.get(patient.id, Decimal("0"))
        if paid_amount < 0:
            paid_amount = Decimal("0")

        total_treatment_cost = total_cost_by_patient_id.get(patient.id, Decimal("0"))
        if total_treatment_cost < 0:
            total_treatment_cost = Decimal("0")

        response_payload.append(
            {
                "id": patient.id,
                "doctor_name": patient.doctor_name,
                "doctor_email": patient.doctor_email,
                "full_name": patient.full_name,
                "phone": patient.phone,
                "birth_date": patient.birth_date,
                "gender": patient.gender,
                "medical_history": patient.medical_history,
                "total_treatment_cost": float(total_treatment_cost),
                "chart_state": getattr(patient, "chart_state", None),
                "paid_amount": float(paid_amount),
            }
        )

    return response_payload


@app.get("/api/patients/stats", response_model=PatientStatsResponse)
def get_patient_stats(
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(database.get_db),
):
    # NOTE: this route MUST be declared before "/api/patients/{patient_id}"
    # (see that route further down this file). FastAPI/Starlette match routes
    # in registration order, and "{patient_id}" is a plain string path
    # parameter with no int converter in the path template -- so if this
    # route were declared afterward, a GET to /api/patients/stats would be
    # captured by get_patient() instead, which does int("stats"), fails,
    # and raises HTTPException(404, detail="المريض غير موجود")
    # -- which is exactly the "Patient Not Found" popup this route used to
    # trigger. Do not move this back below get_patient().
    user = require_active_doctor_user(db=db, doctor_email=doctor_email, authorization=authorization)

    # عزل صارم حسب doctor_email فقط، بلا أي fallback (2026-08-23).
    patients = (
        db.query(models.Patient)
        .filter(models.Patient.doctor_email == user.email)
        .all()
    )

    # Step 1: Safe patient ID extraction -- only IDs of patients that are
    # currently active and actually belong to this doctor (or are legacy
    # unassigned patients). Any patient_id NOT in this list (e.g. an
    # orphaned financial_transactions row left behind by a deleted patient)
    # can never contribute to the sums below.
    patient_ids = [patient.id for patient in patients]

    try:
        now = datetime.utcnow()
        active_appointments = 0
        # ملاحظة (2026-08-25): سابقاً كان هذا العدّاد يتجاهل أي موعد لا يطابق اسمه
        # اسم مريض موجود مسبقاً في جدول patients (عبر قاموس patient_names محلي كان
        # يُبنى هنا) -- وهو فحص كان مقصوداً أصلاً لحماية جمع المستحقات المالية (Step 1/2 بالأسفل)
        # من صفوف مالية يتيمة، لكنه امتد بالخطأ ليشمل عدّ المواعيد أيضاً. بما أنّ كل
        # طلب حجز وارد عبر صفحة الحجز العامة booking.html لا يُربط بسجل مريض فعلي إلا
        # بعد أن يقبله الطبيب (انظر find_or_create_patient_for_booking في
        # respond_to_booking_request)، كانت كل الطلبات الجديدة (pending_confirmation)
        # تختفي من هذه الإحصائية رغم ظهورها في لوحة "طلبات حجز جديدة" على
        # appointments.html -- وهذا هو سبب التباين الذي رُصد أثناء فحص الموقع. الفلترة
        # الصحيحة والكافية هنا هي doctor_email فقط (كما بالأسفل)، وأضفنا أيضاً
        # pending_confirmation إلى حالات "المعلّقة" لأنها أكثر الحالات وضوحاً كـ"معلّقة".
        appointments = (
            db.query(models.Appointment)
            .filter(models.Appointment.doctor_email == user.email)
            .all()
        )
        for appointment in appointments:
            appointment_status = (appointment.status or "").strip().lower()

            # "rejected" و"no_show" حالتان نهائيتان -- لا تُحسبان ضمن المواعيد
            # النشطة أبداً حتى لو كان appointment_date لا يزال اليوم أو في
            # المستقبل (مثال: طبيب يرفض حجزاً ليوم غد يبقى "مرفوضاً" فوراً، لا
            # "نشطاً" حتى يمر تاريخ الغد) -- إصلاح 2026-08-25.
            if appointment_status in {"rejected", "no_show"}:
                continue

            appointment_date = appointment.appointment_date
            is_upcoming = appointment_date is not None and appointment_date >= now
            is_pending = appointment_status in {"pending", "upcoming", "pending_confirmation"}

            if is_upcoming or is_pending:
                active_appointments += 1

        pending_balances = Decimal("0.00")
        if patient_ids:
            # 2026-08-25: هذا هو الإصلاح الجذري لمشكلة "تداخل الحسابات" --
            # سابقاً كان المتبقي = total_treatment_cost (حقل واحد قابل
            # للاستبدال) ناقص مجموع كل دفعات المريض التاريخية بلا أي فصل بين
            # جولات العلاج، فإذا سُدّدت جولة علاج قديمة بالكامل ثم فُتحت جولة
            # جديدة بتكلفة مختلفة، كانت الدفعات القديمة "تبتلع" تكلفة الجولة
            # الجديدة في هذا الحساب. الآن: كل فاتورة علاج (treatment_invoices)
            # تُحسب بمفردها (max(تكلفتها - دفعاتها المرتبطة بها فقط, 0))، ثم
            # تُجمع فقط الفواتير المفتوحة فعلياً -- تسديد فاتورة قديمة بالكامل
            # لا يترك أي أثر على حساب أي فاتورة جديدة.
            invoice_rows = (
                db.query(models.TreatmentInvoice.id, models.TreatmentInvoice.patient_id, models.TreatmentInvoice.total_cost)
                .filter(models.TreatmentInvoice.patient_id.in_(patient_ids))
                .all()
            )
            invoice_ids = [row[0] for row in invoice_rows]

            paid_by_invoice_id: dict[int, Decimal] = {}
            if invoice_ids:
                invoice_payment_rows = (
                    db.query(
                        models.FinancialTransaction.invoice_id,
                        func.coalesce(func.sum(models.FinancialTransaction.amount), 0).label("paid"),
                    )
                    .filter(models.FinancialTransaction.invoice_id.in_(invoice_ids))
                    .filter(models.FinancialTransaction.type.in_(["income", "received"]))
                    .filter(models.FinancialTransaction.amount > 0)
                    .group_by(models.FinancialTransaction.invoice_id)
                    .all()
                )
                paid_by_invoice_id = {
                    invoice_id: Decimal(str(paid or 0))
                    for invoice_id, paid in invoice_payment_rows
                    if invoice_id is not None
                }

            for invoice_id, _patient_id, total_cost in invoice_rows:
                invoice_total_cost = Decimal(str(total_cost or 0))
                if invoice_total_cost < 0:
                    invoice_total_cost = Decimal("0")

                invoice_paid = paid_by_invoice_id.get(invoice_id, Decimal("0"))
                if invoice_paid < 0:
                    invoice_paid = Decimal("0")

                # Prevent overpayments or corrupted values from creating negative debt.
                pending_balances += max(invoice_total_cost - invoice_paid, Decimal("0"))

        return {
            "total_patients": len(patients),
            "active_appointments": active_appointments,
            "pending_balances": float(pending_balances),
        }
    except Exception:
        # Step 3: Fallback exception boundary -- never let a corrupted
        # transaction/appointment row surface as a 500 (or a stray 404) toast
        # on the dashboard. total_patients is still accurate since the
        # doctor-scoped patient query above already succeeded; only the
        # appointment/balance calculation is defended here. Auth failures
        # from get_current_doctor_user() above are NOT caught -- those should
        # still surface as real 401s, not a silently "successful" zeroed
        # payload.
        return {
            "total_patients": len(patients),
            "active_appointments": 0,
            "pending_balances": 0.0,
        }


@app.get("/api/patients/{patient_id}", response_model=PatientResponse)
def get_patient(
    patient_id: str,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    try:
        patient_id_int = int(patient_id)
    except (TypeError, ValueError):
        raise HTTPException(status_code=404, detail="المريض غير موجود")

    try:
        patient = (
            db.query(models.Patient)
            .filter(models.Patient.id == patient_id_int, models.Patient.doctor_email == current_user.email)
            .first()
        )
    except Exception:
        raise HTTPException(status_code=404, detail="المريض غير موجود")

    if not patient:
        raise HTTPException(status_code=404, detail="المريض غير موجود")

    # 2026-08-25: نفس منطق get_all_patients أعلاه -- total_treatment_cost
    # يُحسب من مجموع فواتير العلاج المستقلة بدل قراءة العمود الخام المجمّد،
    # حتى تبقى استجابة هذا المسار متسقة مع بقية الـ API بعد فصل الحسابات.
    invoice_total_cost = (
        db.query(func.coalesce(func.sum(models.TreatmentInvoice.total_cost), 0))
        .filter(models.TreatmentInvoice.patient_id == patient_id_int)
        .scalar()
    )
    paid_total = (
        db.query(func.coalesce(func.sum(models.FinancialTransaction.amount), 0))
        .filter(models.FinancialTransaction.patient_id == patient_id_int)
        .filter(models.FinancialTransaction.type == "income")
        .filter(models.FinancialTransaction.amount > 0)
        .scalar()
    )

    return {
        "id": patient.id,
        "doctor_name": patient.doctor_name,
        "doctor_email": patient.doctor_email,
        "full_name": patient.full_name,
        "phone": patient.phone,
        "birth_date": patient.birth_date,
        "gender": patient.gender,
        "medical_history": patient.medical_history,
        "total_treatment_cost": float(max(Decimal(str(invoice_total_cost or 0)), Decimal("0"))),
        "chart_state": getattr(patient, "chart_state", None),
        "paid_amount": float(max(Decimal(str(paid_total or 0)), Decimal("0"))),
    }


@app.delete("/api/patients/{patient_id}")
def delete_patient(
    patient_id: int,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    patient = (
        db.query(models.Patient)
        .filter(models.Patient.id == patient_id, models.Patient.doctor_email == current_user.email)
        .first()
    )
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    # لا بد من تفريغ/فك ربط كل الصفوف في الجداول الأخرى التي تحمل مفتاحاً
    # خارجياً (FK) نحو patients.id ولا تملك علاقة cascade في نموذج Patient
    # (models.py) -- وإلا يرفض Postgres حذف صف patients بانتهاك قيد الـ FK
    # (IntegrityError)، وهذا هو السبب الفعلي وراء فشل حذف بعض المرضى برسالة
    # "تعذر حذف المريض. يرجى المحاولة لاحقاً" لأي مريض لديه صور شعاعية/ملفات
    # أرشيف، أو حركات مالية، أو مواعيد مرتبطة به عبر Appointment.patient_id
    # (هذا الربط أُضيف 2026-08-23 لمحرك تذكيرات واتساب ولم يكن موجوداً من قبل).
    xray_records = (
        db.query(models.PatientXRay)
        .filter(models.PatientXRay.patient_id == patient_id)
        .all()
    )
    xray_file_urls = [
        (record.file_url or record.image_url or "").strip() for record in xray_records
    ]

    try:
        db.query(models.Visit).filter(models.Visit.patient_id == patient_id).delete(synchronize_session=False)
        db.query(models.Treatment).filter(models.Treatment.patient_id == patient_id).delete(synchronize_session=False)
        db.query(models.PatientXRay).filter(models.PatientXRay.patient_id == patient_id).delete(synchronize_session=False)
        # يجب حذف financial_transactions (تشير إلى treatment_invoices عبر
        # invoice_id) قبل حذف treatment_invoices نفسها، وإلا يرفض Postgres
        # حذف صف treatment_invoices بانتهاك قيد الـ FK -- تماماً نفس درس قصة
        # حذف المريض ثلاثية الطبقات الموثقة أعلاه، وهذه طبقتها الرابعة
        # (2026-08-25): fواتير العلاج الجديدة لها FK نحو patients.id أيضاً ولا
        # نعتمد على cascade الـ ORM وحده لحذفها.
        db.query(models.FinancialTransaction).filter(models.FinancialTransaction.patient_id == patient_id).delete(synchronize_session=False)
        db.query(models.TreatmentInvoice).filter(models.TreatmentInvoice.patient_id == patient_id).delete(synchronize_session=False)
        # لا نحذف المواعيد نفسها (قد تكون سجلاً تاريخياً يريد الطبيب الاحتفاظ
        # به) -- فقط نفك ربطها بهذا المريض المحذوف، لأن Appointment.patient_name
        # حقل نصي مستقل أصلاً ولا يعتمد على وجود صف patients ليبقى مقروءاً.
        db.query(models.Appointment).filter(models.Appointment.patient_id == patient_id).update(
            {models.Appointment.patient_id: None}, synchronize_session=False
        )
        db.delete(patient)
        db.commit()
    except Exception:
        db.rollback()
        raise

    # حذف الملفات الفعلية للصور الشعاعية بعد نجاح حذف الصفوف من قاعدة
    # البيانات فقط (نفس نمط delete_patient_archive أعلاه).
    for file_url in xray_file_urls:
        if file_url.startswith("/uploads/"):
            physical_path = file_url[len("/uploads/"):]
            full_path = os.path.join(UPLOADS_DIR, physical_path)
            if os.path.exists(full_path):
                try:
                    os.remove(full_path)
                except OSError:
                    pass

    return {"message": "Patient deleted successfully"}


@app.put("/api/patients/{patient_id}", response_model=PatientResponse)
def update_patient(
    patient_id: int,
    patient_update: PatientUpdate,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    patient = (
        db.query(models.Patient)
        .filter(models.Patient.id == patient_id, models.Patient.doctor_email == current_user.email)
        .first()
    )
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    try:
        if patient_update.doctor_name is not None:
            patient.doctor_name = patient_update.doctor_name
        if patient_update.full_name is not None:
            patient.full_name = patient_update.full_name
        if patient_update.phone is not None:
            patient.phone = patient_update.phone
        if patient_update.medical_history is not None:
            patient.medical_history = patient_update.medical_history
        if patient_update.birth_date is not None:
            patient.birth_date = patient_update.birth_date
        # لم يعد هذا المسار يقبل تعديل التكلفة الإجمالية مباشرة (2026-08-25) --
        # التكلفة تُدار الآن حصراً عبر فواتير علاج مستقلة، انظر
        # POST /api/patients/{patient_id}/invoices بالأسفل.

        db.commit()
        db.refresh(patient)
    except Exception:
        db.rollback()
        raise

    return patient


def _serialize_invoice(invoice: "models.TreatmentInvoice", payments: list) -> dict:
    paid_amount = sum((Decimal(str(p.amount)) for p in payments), Decimal("0"))
    total_cost = Decimal(str(invoice.total_cost or 0))
    if total_cost < 0:
        total_cost = Decimal("0")
    remaining_amount = max(total_cost - paid_amount, Decimal("0"))
    return {
        "id": invoice.id,
        "patient_id": invoice.patient_id,
        "title": invoice.title,
        "total_cost": float(total_cost),
        "paid_amount": float(paid_amount),
        "remaining_amount": float(remaining_amount),
        "status": "closed" if remaining_amount <= 0 else "open",
        "created_at": invoice.created_at,
        "payments": [
            {
                "id": p.id,
                "amount": float(p.amount),
                "description": p.description,
                "created_at": p.created_at,
                "is_opening_balance": bool(getattr(p, "is_opening_balance", False)),
            }
            for p in sorted(payments, key=lambda p: (p.created_at, p.id), reverse=True)
        ],
    }


def _get_owned_patient_or_404(db: Session, patient_id: int, doctor_email: str) -> "models.Patient":
    patient = (
        db.query(models.Patient)
        .filter(models.Patient.id == patient_id, models.Patient.doctor_email == doctor_email)
        .first()
    )
    if not patient:
        raise HTTPException(status_code=404, detail="المريض غير موجود")
    return patient


# ====================================================================
# فواتير العلاج المستقلة -- 2026-08-25 (الحل الجذري لمشكلة تداخل الحسابات)
# ====================================================================
# بدل تعديل patients.total_treatment_cost (رقم واحد قابل للاستبدال، فتختلط
# فيه تكلفة العلاج الجديد بمدفوعات العلاج القديم)، كل جولة علاج جديدة تُنشأ
# هنا كفاتورة (TreatmentInvoice) مستقلة تماماً بتكلفتها ودفعاتها الخاصة.
# "الحالة" (مفتوحة/مغلقة) تُشتق دائماً من مقارنة التكلفة بمجموع الدفعات
# المرتبطة بها تحديداً، ولا تُخزَّن كعمود منفصل، فلا يمكن أن تتضارب مع
# الحسابات الفعلية.
@app.get("/api/patients/{patient_id}/invoices", response_model=List[TreatmentInvoiceResponse])
def get_patient_invoices(
    patient_id: int,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    _get_owned_patient_or_404(db, patient_id, current_user.email)

    invoices = (
        db.query(models.TreatmentInvoice)
        .filter(models.TreatmentInvoice.patient_id == patient_id)
        .order_by(models.TreatmentInvoice.created_at.desc(), models.TreatmentInvoice.id.desc())
        .all()
    )

    invoice_ids = [invoice.id for invoice in invoices]
    payments_by_invoice_id: dict[int, list] = {}
    if invoice_ids:
        payment_rows = (
            db.query(models.FinancialTransaction)
            .filter(models.FinancialTransaction.invoice_id.in_(invoice_ids))
            .all()
        )
        for payment in payment_rows:
            payments_by_invoice_id.setdefault(payment.invoice_id, []).append(payment)

    return [
        _serialize_invoice(invoice, payments_by_invoice_id.get(invoice.id, []))
        for invoice in invoices
    ]


@app.post("/api/patients/{patient_id}/invoices", response_model=TreatmentInvoiceResponse, status_code=201)
def create_patient_invoice(
    patient_id: int,
    invoice_create: TreatmentInvoiceCreate,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    _get_owned_patient_or_404(db, patient_id, current_user.email)

    title = (invoice_create.title or "").strip()
    if not title:
        raise HTTPException(status_code=400, detail="عنوان فاتورة العلاج مطلوب")
    if invoice_create.total_cost is None or invoice_create.total_cost < 0:
        raise HTTPException(status_code=400, detail="التكلفة الإجمالية يجب أن تكون رقماً صحيحاً أكبر من أو يساوي صفر")

    try:
        db_invoice = models.TreatmentInvoice(
            patient_id=patient_id,
            doctor_email=current_user.email,
            title=title,
            total_cost=Decimal(str(invoice_create.total_cost)),
        )
        db.add(db_invoice)
        db.commit()
        db.refresh(db_invoice)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر إنشاء فاتورة العلاج الآن. حاول مرة أخرى.")

    return _serialize_invoice(db_invoice, [])


# 2026-08-29: تصحيح التكلفة الإجمالية لفاتورة علاج قائمة (مثلاً بعد خطأ إدخال
# عند إنشائها) دون التأثير على الدفعات المسجَّلة عليها -- "المتبقي" و"الحالة"
# يُعاد اشتقاقهما تلقائياً من _serialize_invoice() بعد الحفظ.
@app.patch("/api/patients/{patient_id}/invoices/{invoice_id}", response_model=TreatmentInvoiceResponse)
def update_patient_invoice_cost(
    patient_id: int,
    invoice_id: int,
    invoice_update: TreatmentInvoiceUpdate,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    _get_owned_patient_or_404(db, patient_id, current_user.email)

    invoice = (
        db.query(models.TreatmentInvoice)
        .filter(
            models.TreatmentInvoice.id == invoice_id,
            models.TreatmentInvoice.patient_id == patient_id,
            models.TreatmentInvoice.doctor_email == current_user.email,
        )
        .first()
    )
    if not invoice:
        raise HTTPException(status_code=404, detail="فاتورة العلاج غير موجودة")

    if invoice_update.total_cost is None or invoice_update.total_cost < 0:
        raise HTTPException(status_code=400, detail="التكلفة الإجمالية يجب أن تكون رقماً صحيحاً أكبر من أو يساوي صفر")

    try:
        invoice.total_cost = Decimal(str(invoice_update.total_cost))
        db.commit()
        db.refresh(invoice)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر تحديث التكلفة الإجمالية الآن. حاول مرة أخرى.")

    invoice_payments = (
        db.query(models.FinancialTransaction)
        .filter(models.FinancialTransaction.invoice_id == invoice.id)
        .all()
    )
    return _serialize_invoice(invoice, invoice_payments)


# 2026-08-29: حذف فاتورة علاج بالكامل (بدل تصحيح تكلفتها فقط أعلاه) -- مثلاً
# فاتورة أُنشئت بالخطأ من الأساس. models.TreatmentInvoice.payments معرَّفة
# بـ cascade="all, delete-orphan"، فـ db.delete(invoice) (حذف عبر الـ ORM
# وليس Query.delete() الخام) يحذف تلقائياً كل FinancialTransaction المرتبطة
# بها (invoice_id) بلا حاجة لتنظيف يدوي -- نفس نمط تنظيف الـ FK المعتمد في
# delete_patient() أعلاه. تنبيه: هذا يحذف كل الدفعات المسجَّلة على الفاتورة
# أيضاً بلا رجعة، والواجهة يجب أن تُحذّر المستخدم من ذلك قبل الاستدعاء.
@app.delete("/api/patients/{patient_id}/invoices/{invoice_id}", status_code=200)
def delete_patient_invoice(
    patient_id: int,
    invoice_id: int,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    _get_owned_patient_or_404(db, patient_id, current_user.email)

    invoice = (
        db.query(models.TreatmentInvoice)
        .filter(
            models.TreatmentInvoice.id == invoice_id,
            models.TreatmentInvoice.patient_id == patient_id,
            models.TreatmentInvoice.doctor_email == current_user.email,
        )
        .first()
    )
    if not invoice:
        raise HTTPException(status_code=404, detail="فاتورة العلاج غير موجودة")

    try:
        db.delete(invoice)
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر حذف فاتورة العلاج الآن. حاول مرة أخرى.")

    return {"message": "تم حذف فاتورة العلاج بنجاح"}


@app.post("/api/patients/{patient_id}/invoices/{invoice_id}/payments", response_model=TreatmentInvoiceResponse)
def register_invoice_payment(
    patient_id: int,
    invoice_id: int,
    payment: TreatmentInvoicePaymentCreate,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    patient = _get_owned_patient_or_404(db, patient_id, current_user.email)

    invoice = (
        db.query(models.TreatmentInvoice)
        .filter(
            models.TreatmentInvoice.id == invoice_id,
            models.TreatmentInvoice.patient_id == patient_id,
            models.TreatmentInvoice.doctor_email == current_user.email,
        )
        .first()
    )
    if not invoice:
        raise HTTPException(status_code=404, detail="فاتورة العلاج غير موجودة")

    if payment.amount is None or payment.amount <= 0:
        raise HTTPException(status_code=400, detail="قيمة الدفعة يجب أن تكون أكبر من صفر")

    # 2026-08-25: تاريخ فعلي اختياري -- يسمح بتسجيل دفعة قديمة بتاريخها الحقيقي
    # بدل ختمها تلقائياً بتاريخ اليوم (انظر شرح كامل عند get_finance_summary()).
    transaction_date = None
    if payment.transaction_date is not None:
        transaction_date = payment.transaction_date
        if transaction_date.tzinfo is not None:
            transaction_date = transaction_date.replace(tzinfo=None)
        if transaction_date > datetime.utcnow():
            raise HTTPException(status_code=400, detail="تاريخ الدفعة لا يمكن أن يكون في المستقبل")

    description = (payment.description or "").strip() or f"دفعة على فاتورة: {invoice.title}"

    try:
        db_payment = models.FinancialTransaction(
            patient_id=patient_id,
            doctor_name=(patient.doctor_name or current_user.doctor_name or current_user.email),
            doctor_email=current_user.email,
            amount=Decimal(str(payment.amount)),
            type="income",
            description=description,
            invoice_id=invoice.id,
            is_opening_balance=bool(payment.is_opening_balance),
        )
        if transaction_date is not None:
            db_payment.created_at = transaction_date
        db.add(db_payment)
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر تسجيل الدفعة الآن. حاول مرة أخرى.")

    invoice_payments = (
        db.query(models.FinancialTransaction)
        .filter(models.FinancialTransaction.invoice_id == invoice.id)
        .all()
    )
    return _serialize_invoice(invoice, invoice_payments)


@app.put("/api/patients/{patient_id}/chart", response_model=PatientResponse)
def update_patient_chart(
    patient_id: int,
    chart_update: PatientChartUpdate,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    patient = (
        db.query(models.Patient)
        .filter(models.Patient.id == patient_id, models.Patient.doctor_email == current_user.email)
        .first()
    )
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    normalized_chart_state = normalize_palmer_chart_state(chart_update.chart_state)
    chart_state_value = json.dumps(normalized_chart_state, ensure_ascii=False)

    try:
        patient.chart_state = chart_state_value
        db.commit()
        db.refresh(patient)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر حفظ حالة المخطط السني حالياً. حاول مرة أخرى.")

    return patient


# 6. مسار لحجز موعد جديد لمريض [POST]
@app.post("/api/appointments", response_model=AppointmentResponse, status_code=201)
def create_appointment(
    appointment: AppointmentCreate,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    patient = (
        db.query(models.Patient)
        .filter(models.Patient.id == appointment.patient_id, models.Patient.doctor_email == current_user.email)
        .first()
    )
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    date_value = (appointment.date or "").strip()
    time_value = (appointment.time or "").strip()
    description_value = (appointment.description or "").strip()
    if not date_value or not time_value or not description_value:
        raise HTTPException(status_code=400, detail="Date, time, and description are required")

    normalized_time = time_value if len(time_value) == 5 else time_value[:5]
    if len(normalized_time) != 5 or normalized_time[2] != ":":
        raise HTTPException(status_code=400, detail="Invalid time format. Expected HH:MM")

    date_component = date_value
    if "T" in date_component:
        try:
            parsed_date = datetime.fromisoformat(date_component.replace("Z", "+00:00"))
            date_component = parsed_date.date().isoformat()
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format")

    try:
        appointment_date_time = datetime.fromisoformat(f"{date_component}T{normalized_time}:00")
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date/time format")

    db_appointment = models.Appointment(
        patient_id=appointment.patient_id,
        doctor_email=current_user.email,
        patient_name=patient.full_name or appointment.patient_name or "",
        appointment_date=appointment_date_time,
        appointment_time=normalized_time,
        procedure_type=description_value,
        notes=description_value,
        status=(appointment.status or "pending").strip().lower() or "pending",
    )

    try:
        db.add(db_appointment)
        db.commit()
        db.refresh(db_appointment)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر إنشاء الموعد حالياً. حاول مرة أخرى.")

    return {
        "id": db_appointment.id,
        "patient_id": appointment.patient_id,
        "patient_name": db_appointment.patient_name,
        "appointment_date": db_appointment.appointment_date,
        "appointment_time": db_appointment.appointment_time,
        "procedure_type": db_appointment.procedure_type,
        "notes": db_appointment.notes,
        "status": db_appointment.status,
    }


@app.put("/api/appointments/{appointment_id}", response_model=AppointmentResponse, status_code=200)
def update_appointment(
    appointment_id: int,
    appointment_update: AppointmentUpdate,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    appointment = (
        db.query(models.Appointment)
        .filter(models.Appointment.id == appointment_id, models.Appointment.doctor_email == current_user.email)
        .first()
    )
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")

    has_any_update = any(
        value is not None
        for value in (
            appointment_update.appointment_date,
            appointment_update.appointment_time,
            appointment_update.description,
        )
    )
    if not has_any_update:
        raise HTTPException(status_code=400, detail="No appointment fields provided for update")

    try:
        if appointment_update.appointment_date is not None:
            appointment.appointment_date = appointment_update.appointment_date
        if appointment_update.appointment_time is not None:
            appointment.appointment_time = appointment_update.appointment_time.strip()
        if appointment_update.description is not None:
            appointment.notes = appointment_update.description.strip()

        db.commit()
        db.refresh(appointment)
        return appointment
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر تحديث الموعد حالياً. حاول مرة أخرى.")


@app.put("/api/appointments/{appointment_id}/status", status_code=200)
def update_appointment_status(
    appointment_id: int,
    status_update: AppointmentStatusUpdate,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    appointment = (
        db.query(models.Appointment)
        .filter(models.Appointment.id == appointment_id, models.Appointment.doctor_email == current_user.email)
        .first()
    )
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")

    try:
        appointment.status = status_update.status.strip().lower()
        db.commit()
        db.refresh(appointment)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر تحديث حالة الموعد حالياً. حاول مرة أخرى.")

    return {
        "message": "Appointment status updated successfully",
        "appointment_id": appointment.id,
        "status": appointment.status,
    }


class AppointmentRespondRequest(BaseModel):
    decision: Literal["accept", "reject"]


# مسار قبول/رفض طلب حجز وارد من صفحة الحجز العامة (booking.html) -- 2026-08-23.
# لا يُستخدَم إطلاقاً لتعديل حالة المواعيد العادية (لهذا مسار /status أعلاه)،
# بل فقط للردّ على طلبات بحالة "pending_confirmation" تحديداً.
@app.put("/api/appointments/{appointment_id}/respond", status_code=200)
def respond_to_booking_request(
    appointment_id: int,
    respond_request: AppointmentRespondRequest,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    appointment = (
        db.query(models.Appointment)
        .filter(models.Appointment.id == appointment_id, models.Appointment.doctor_email == current_user.email)
        .first()
    )
    if not appointment:
        raise HTTPException(status_code=404, detail="طلب الحجز غير موجود")

    if appointment.status != "pending_confirmation":
        raise HTTPException(status_code=400, detail="تم الرد على هذا الطلب مسبقاً.")

    new_status = "pending" if respond_request.decision == "accept" else "rejected"

    try:
        appointment.status = new_status
        # عند قبول طلب حجز عام لم يكن مرتبطاً بأي سجل مريض بعد (patient_id فارغ) --
        # وهي حال كل طلب وارد عبر booking.html -- نربطه الآن بسجل مريض حقيقي، حتى
        # يظهر في "قائمة المرضى" ويصبح ممكناً فتح ملف طبي شامل له (مخطط أسنان،
        # زيارات، وصفات، أرشيف أشعة) عبر patient_record.html. قبل هذا الإصلاح كان
        # patient_id يبقى NULL إلى الأبد لكل مريض قادم عبر رابط الحجز العام (2026-08-25).
        if new_status == "pending" and not appointment.patient_id:
            appointment.patient_id = find_or_create_patient_for_booking(
                db,
                doctor=current_user,
                patient_name=appointment.patient_name,
                patient_phone=appointment.patient_phone,
            )
        db.commit()
        db.refresh(appointment)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر تحديث حالة الطلب حالياً. حاول مرة أخرى.")

    # إشعار المريض عبر واتساب بقرار الطبيب (best-effort -- لا يوقف الرد لو فشل الإرسال)
    if appointment.patient_phone:
        doctor_label = (current_user.doctor_name or "").strip() or "العيادة"
        appointment_date_label = appointment.appointment_date.strftime("%Y-%m-%d") if appointment.appointment_date else ""
        if new_status == "pending":
            patient_message = (
                f"مرحباً {appointment.patient_name}، تم قبول طلب حجزكم لدى {doctor_label} "
                f"بتاريخ {appointment_date_label} الساعة {appointment.appointment_time}. بانتظاركم! 🦷✨"
            )
        else:
            patient_message = (
                f"مرحباً {appointment.patient_name}، نأسف لإبلاغكم أن {doctor_label} لم يتمكن من "
                f"تأكيد موعدكم بتاريخ {appointment_date_label} الساعة {appointment.appointment_time}. "
                "يرجى التواصل مع العيادة أو تجربة موعد آخر عبر رابط الحجز."
            )
        send_whatsapp_message_for_doctor(current_user, appointment.patient_phone, patient_message)

    return {
        "message": "تم إرسال الرد بنجاح.",
        "appointment_id": appointment.id,
        "status": appointment.status,
    }


@app.delete("/api/appointments/{appointment_id}", status_code=200)
def delete_appointment(
    appointment_id: int,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    appointment = (
        db.query(models.Appointment)
        .filter(models.Appointment.id == appointment_id, models.Appointment.doctor_email == current_user.email)
        .first()
    )
    if not appointment:
        raise HTTPException(status_code=404, detail="الموعد غير موجود")

    try:
        db.delete(appointment)
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر حذف الموعد حالياً. حاول مرة أخرى.")

    return {"message": "تم حذف الموعد بنجاح"}


# مسار لجلب عدد طلبات الحجز الواردة عبر صفحة الحجز العامة (booking.html) التي
# لا تزال بانتظار رد الطبيب (status = pending_confirmation) -- يُستخدم لإظهار
# شارة تنبيه حمراء متوهجة فوق زر "المواعيد اليومية" في شريط التنقل عند تصفح
# أي صفحة أخرى غير صفحة المواعيد نفسها (انظر notification-badge.js في
# frontend_web، 2026-08-30).
@app.get("/api/appointments/pending-count")
def get_pending_appointments_count(
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    count = (
        db.query(models.Appointment)
        .filter(
            models.Appointment.doctor_email == current_user.email,
            models.Appointment.status == "pending_confirmation",
        )
        .count()
    )
    return {"count": count}


# 7. مسار لجلب قائمة بجميع المواعيد المحجوزة [GET]
@app.get("/api/appointments", response_model=List[AppointmentResponse])
def get_all_appointments(
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    return (
        db.query(models.Appointment)
        .filter(models.Appointment.doctor_email == current_user.email)
        .all()
    )


# 8. مسار لتسجيل زيارة علاجية جديدة لمريض مع تفاصيل الأسنان [POST]
@app.post("/api/visits", response_model=VisitResponse)
def create_visit(
    visit: VisitCreate,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    patient = (
        db.query(models.Patient)
        .filter(models.Patient.id == visit.patient_id, models.Patient.doctor_email == current_user.email)
        .first()
    )
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    db_visit = models.Visit(
        patient_id=visit.patient_id,
        diagnosis=visit.diagnosis,
        total_cost=visit.total_cost,
        amount_paid=visit.amount_paid,
    )
    db.add(db_visit)
    db.commit()
    db.refresh(db_visit)

    for treatment_data in visit.treatments:
        db_treatment = models.Treatment(
            patient_id=visit.patient_id,
            tooth_number=treatment_data.tooth_number,
            treatment_type=treatment_data.procedure,
            notes=treatment_data.notes,
            color=None,
        )
        db.add(db_treatment)

    db.commit()
    db.refresh(db_visit)

    created_treatments = db.query(models.Treatment).filter(models.Treatment.patient_id == db_visit.patient_id).all()
    return {
        "id": db_visit.id,
        "patient_id": db_visit.patient_id,
        "diagnosis": db_visit.diagnosis,
        "total_cost": db_visit.total_cost,
        "amount_paid": db_visit.amount_paid,
        "treatments": [
            {
                "id": treatment.id,
                "tooth_number": treatment.tooth_number,
                "procedure": treatment.treatment_type,
                "cost": Decimal("0.00"),
                "notes": treatment.notes,
                "color": treatment.color,
            }
            for treatment in created_treatments
        ],
    }


@app.post("/api/treatments", response_model=TreatmentResponse)
def create_treatment(
    treatment: TreatmentCreate,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    patient = (
        db.query(models.Patient)
        .filter(models.Patient.id == treatment.patient_id, models.Patient.doctor_email == current_user.email)
        .first()
    )
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    db_treatment = models.Treatment(
        patient_id=treatment.patient_id,
        tooth_number=treatment.tooth_number,
        treatment_type=treatment.treatment_type,
        notes=treatment.notes,
        color=treatment.color,
    )
    db.add(db_treatment)
    db.commit()
    db.refresh(db_treatment)
    return db_treatment


@app.post("/api/finance", response_model=ExpenseResponse)
@app.post("/api/finance/expenses", response_model=ExpenseResponse)
def create_expense(
    expense: ExpenseCreate,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    if expense.amount <= 0:
        raise HTTPException(status_code=400, detail="قيمة المصروف يجب أن تكون أكبر من صفر.")

    description = expense.description.strip()
    if not description:
        raise HTTPException(status_code=400, detail="وصف المصروف مطلوب.")

    transaction_type = expense.type.strip().lower()
    if transaction_type not in {"income", "expense"}:
        raise HTTPException(status_code=400, detail="نوع العملية يجب أن يكون income أو expense.")

    # ملاحظة: transaction_type يجب أن يُحسب هنا -- قبل فحص expense.patient_id
    # أسفله الذي يعتمد عليه لإلزامية invoice_id.

    if expense.patient_id is not None:
        patient = (
            db.query(models.Patient)
            .filter(models.Patient.id == expense.patient_id, models.Patient.doctor_email == current_user.email)
            .first()
        )
        if not patient:
            raise HTTPException(status_code=404, detail="Patient not found")

        # 2026-08-25: أي دفعة مريض (type="income") يجب أن تُربط إلزامياً بفاتورة
        # علاج مستقلة موجودة فعلاً -- هذا هو التصحيح الجذري لمشكلة "تداخل
        # الحسابات" التي كانت تحدث عندما يُفتح علاج جديد بتكلفة جديدة بينما
        # المدفوع القديم لا يزال محسوباً معه كرقم تراكمي واحد. لا نسمح بعد الآن
        # بإنشاء دفعة مريض غير مرتبطة بفاتورة محددة عبر هذا المسار المشترك.
        if transaction_type == "income":
            if expense.invoice_id is None:
                raise HTTPException(status_code=400, detail="يجب اختيار فاتورة العلاج المرتبطة بهذه الدفعة")
            invoice = (
                db.query(models.TreatmentInvoice)
                .filter(
                    models.TreatmentInvoice.id == expense.invoice_id,
                    models.TreatmentInvoice.patient_id == expense.patient_id,
                    models.TreatmentInvoice.doctor_email == current_user.email,
                )
                .first()
            )
            if not invoice:
                raise HTTPException(status_code=404, detail="فاتورة العلاج غير موجودة")

    # 2026-08-24: ربط تلقائي اختياري -- عند تسجيل مصروف لشراء مادة، يمكن للطبيب
    # طلب إضافتها/تحديث كميتها في مخزن المواد بنفس العملية، بدل الانتقال يدوياً إلى
    # inventory.html وإدخالها هناك من جديد. الربط متاح فقط لمصروفات (type=expense)
    # ولحسابات الباقة premium فقط -- نفس تسقيف صفحة المخزن نفسها (require_premium_user_by_email)
    # -- وإن طُلب الربط من حساب standard لا نفشل حفظ المصروف، فقط نتجاهل الربط بصمت.
    # 2026-08-25: تاريخ فعلي اختياري -- انظر شرح كامل عند get_finance_summary().
    transaction_date = None
    if expense.transaction_date is not None:
        transaction_date = expense.transaction_date
        if transaction_date.tzinfo is not None:
            transaction_date = transaction_date.replace(tzinfo=None)
        if transaction_date > datetime.utcnow():
            raise HTTPException(status_code=400, detail="تاريخ الحركة لا يمكن أن يكون في المستقبل")

    sync_to_inventory = bool(expense.add_to_inventory) and transaction_type == "expense" and current_user.tier == "premium"

    inventory_item_name = None
    inventory_quantity_to_add = None
    if sync_to_inventory:
        inventory_item_name = (expense.inventory_item_name or "").strip()
        if not inventory_item_name:
            raise HTTPException(status_code=400, detail="اسم المادة مطلوب لإضافتها إلى مخزن المواد.")
        if expense.inventory_quantity is None or expense.inventory_quantity <= 0:
            raise HTTPException(status_code=400, detail="الكمية المضافة إلى المخزن يجب أن تكون أكبر من صفر.")
        inventory_quantity_to_add = expense.inventory_quantity

    try:
        db_expense = models.FinancialTransaction(
            patient_id=expense.patient_id,
            doctor_name=expense.doctor_name,
            doctor_email=current_user.email,
            amount=expense.amount,
            type=transaction_type,
            description=description,
            invoice_id=expense.invoice_id,
            is_opening_balance=bool(expense.is_opening_balance),
        )
        if transaction_date is not None:
            db_expense.created_at = transaction_date
        db.add(db_expense)

        inventory_item = None
        inventory_action = None
        if sync_to_inventory:
            inventory_item = (
                db.query(models.InventoryItem)
                .filter(
                    models.InventoryItem.doctor_email == current_user.email,
                    func.lower(models.InventoryItem.item_name) == inventory_item_name.lower(),
                )
                .first()
            )
            if inventory_item:
                inventory_item.quantity = inventory_item.quantity + inventory_quantity_to_add
                inventory_item.updated_at = datetime.utcnow()
                inventory_action = "updated"
            else:
                inventory_item = models.InventoryItem(
                    doctor_email=current_user.email,
                    item_name=inventory_item_name,
                    quantity=inventory_quantity_to_add,
                    min_alert_quantity=5,
                )
                db.add(inventory_item)
                inventory_action = "created"

        db.commit()
        db.refresh(db_expense)
        if sync_to_inventory and inventory_item is not None:
            db.refresh(inventory_item)

        return ExpenseResponse(
            id=db_expense.id,
            amount=db_expense.amount,
            type=db_expense.type,
            patient_id=db_expense.patient_id,
            description=db_expense.description,
            doctor_name=db_expense.doctor_name,
            created_at=db_expense.created_at,
            is_opening_balance=db_expense.is_opening_balance,
            inventory_synced=sync_to_inventory and inventory_item is not None,
            inventory_item_id=(inventory_item.id if inventory_item is not None else None),
            inventory_action=inventory_action,
        )
    except HTTPException:
        db.rollback()
        raise
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر حفظ المصروف حالياً. حاول مرة أخرى.")


def _damascus_now():
    return datetime.now(KEEP_ALIVE_TIMEZONE).replace(tzinfo=None)


def _month_bounds(year: int, month: int):
    start = datetime(year, month, 1)
    if month == 12:
        end = datetime(year + 1, 1, 1)
    else:
        end = datetime(year, month + 1, 1)
    return start, end


def _day_bounds(year: int, month: int, day: int):
    # حدود يوم واحد [00:00, اليوم التالي 00:00) بنفس أسلوب _month_bounds.
    start = datetime(year, month, day)
    return start, start + timedelta(days=1)


def _resolve_finance_period(year, month, day, all_time):
    """يوحّد حساب نطاق التقرير المالي بين /api/finance/summary و
    /api/finance/transactions حتى لا تنحرف القائمة عن المجاميع المعروضة
    فوقها. يعيد (start, end, resolved_year, resolved_month, resolved_day)
    و(None, None, ...) في وضع all_time."""
    if all_time:
        return None, None, None, None, None

    now_local = _damascus_now()
    resolved_year = year if year is not None else now_local.year
    resolved_month = month if month is not None else now_local.month
    if resolved_month < 1 or resolved_month > 12:
        raise HTTPException(status_code=400, detail="الشهر يجب أن يكون رقماً بين 1 و 12.")

    resolved_day = day
    if resolved_day is not None:
        try:
            start, end = _day_bounds(resolved_year, resolved_month, resolved_day)
        except ValueError:
            raise HTTPException(status_code=400, detail="اليوم المطلوب غير صالح لهذا الشهر.")
    else:
        start, end = _month_bounds(resolved_year, resolved_month)

    return start, end, resolved_year, resolved_month, resolved_day


@app.get("/api/finance/summary")
def get_finance_summary(
    year: Optional[int] = Query(None),
    month: Optional[int] = Query(None),
    # 2026-09-02: أُعيد هذا المعامل بعد اكتشاف أن الواجهة (finance.html) ترسل
    # day عند اختيار "اليوم" بينما الدالة هنا لم تكن تستقبله إطلاقاً --
    # وFastAPI يتجاهل أي معامل غير معرّف بصمت، فكان خيار "اليوم" يعرض
    # مجاميع الشهر كامل بلا أي رسالة خطأ.
    day: Optional[int] = Query(None),
    all_time: bool = Query(False),
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    # 2026-08-24: التقارير المالية أصبحت شهرية افتراضياً بدل مجموع تراكمي منذ
    # بداية الاستخدام -- إن لم يُرسل year/month يُستخدم الشهر الحالي بتوقيت
    # KEEP_ALIVE_TIMEZONE (نفس منطقة "اليوم/الآن" المعتمدة في باقي الملف)،
    # وإن أُرسل all_time=true يعود السلوك القديم (إجمالي كل الحركات).
    income_query = (
        db.query(func.coalesce(func.sum(models.FinancialTransaction.amount), 0))
        .filter(models.FinancialTransaction.type == "income")
        .filter(models.FinancialTransaction.doctor_email == current_user.email)
    )
    expense_query = (
        db.query(func.coalesce(func.sum(models.FinancialTransaction.amount), 0))
        .filter(models.FinancialTransaction.type == "expense")
        .filter(models.FinancialTransaction.doctor_email == current_user.email)
    )

    period_start, period_end, resolved_year, resolved_month, resolved_day = _resolve_finance_period(
        year, month, day, all_time
    )
    if not all_time:
        month_start, month_end = period_start, period_end
        # 2026-08-25: أي حركة is_opening_balance=True (رصيد افتتاحي/سابق مُرحّل)
        # تُستبعد دوماً من تقرير شهر محدد -- لا تنتمي فعلياً لهذا الشهر، انظر
        # شرح كامل عند FinancialTransaction.is_opening_balance في models.py.
        # في وضع all_time=true تبقى محتسبة (لا فلترة هنا) لأنها أموال حقيقية
        # فعلاً محصّلة.
        income_query = income_query.filter(
            models.FinancialTransaction.created_at >= month_start,
            models.FinancialTransaction.created_at < month_end,
            models.FinancialTransaction.is_opening_balance.is_(False),
        )
        expense_query = expense_query.filter(
            models.FinancialTransaction.created_at >= month_start,
            models.FinancialTransaction.created_at < month_end,
            models.FinancialTransaction.is_opening_balance.is_(False),
        )

    total_income = income_query.scalar()
    total_expenses = expense_query.scalar()

    income_value = Decimal(total_income or 0)
    expenses_value = Decimal(total_expenses or 0)
    net_profit = income_value - expenses_value

    # 2026-08-25: مجموع كل الأرصدة الافتتاحية/السابقة المُرحّلة (تراكمي كلي دوماً،
    # بصرف النظر عن الشهر/السنة المطلوبة) -- يُعرض بشكل منفصل تماماً في الواجهة
    # كرقم توضيحي، ولا يدخل إطلاقاً في total_income أو net_profit أعلاه.
    opening_balance_total = (
        db.query(func.coalesce(func.sum(models.FinancialTransaction.amount), 0))
        .filter(models.FinancialTransaction.type == "income")
        .filter(models.FinancialTransaction.doctor_email == current_user.email)
        .filter(models.FinancialTransaction.is_opening_balance.is_(True))
        .scalar()
    )
    opening_balance_value = Decimal(opening_balance_total or 0)

    return {
        "total_income": float(income_value),
        "total_expenses": float(expenses_value),
        "net_profit": float(net_profit),
        "total_revenue": float(income_value),
        "opening_balance_income": float(opening_balance_value),
        "all_time": all_time,
        "year": resolved_year,
        "month": resolved_month,
        "day": resolved_day,
    }


@app.get("/api/finance/transactions", response_model=List[FinancialTransactionResponse])
def list_finance_transactions(
    year: Optional[int] = Query(None),
    month: Optional[int] = Query(None),
    day: Optional[int] = Query(None),
    all_time: bool = Query(False),
    limit: int = Query(10, ge=1, le=100),
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    """آخر الحركات المالية للفترة نفسها التي يعرضها /api/finance/summary.

    الصفحة المالية كانت تعرض ثلاثة مجاميع فقط بلا أي وسيلة لرؤية الحركات
    التي كوّنتها -- والوسيلة الوحيدة المتاحة كانت /api/finance/backup الذي
    يُنزّل كل المرضى والمواعيد والحركات كملف CSV، وهو ثقيل جداً لعرض خمسة
    أسطر في الواجهة.

    يستخدم نفس _resolve_finance_period ونفس استثناء is_opening_balance
    المعتمدين في المجاميع، فلا يمكن أن تعرض القائمة حركات خارج الفترة
    المعروضة فوقها.
    """
    period_start, period_end, _, _, _ = _resolve_finance_period(year, month, day, all_time)

    query = db.query(models.FinancialTransaction).filter(
        models.FinancialTransaction.doctor_email == current_user.email
    )

    if not all_time:
        query = query.filter(
            models.FinancialTransaction.created_at >= period_start,
            models.FinancialTransaction.created_at < period_end,
            models.FinancialTransaction.is_opening_balance.is_(False),
        )

    transactions = (
        query.order_by(
            models.FinancialTransaction.created_at.desc(),
            models.FinancialTransaction.id.desc(),
        )
        .limit(limit)
        .all()
    )

    return transactions


@app.get("/api/finance/available-months")
def get_finance_available_months(
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    # قائمة الأشهر (سنة/شهر) التي فيها حركات مالية فعلية لهذا الطبيب، لبناء
    # قائمة اختيار الأشهر في صفحة finance.html -- الشهر الحالي يُضاف دائماً
    # حتى لو لم تُسجَّل فيه أي حركة بعد، ليبقى قابلاً للاختيار دوماً.
    timestamps = (
        db.query(models.FinancialTransaction.created_at)
        .filter(models.FinancialTransaction.doctor_email == current_user.email)
        .all()
    )

    seen = set()
    for (created_at,) in timestamps:
        if created_at is not None:
            seen.add((created_at.year, created_at.month))

    now_local = _damascus_now()
    seen.add((now_local.year, now_local.month))

    months = [{"year": y, "month": m} for (y, m) in sorted(seen, reverse=True)]

    return {"months": months}


@app.get("/api/finance/patient/{patient_id}", response_model=List[FinancialTransactionResponse])
def get_patient_financial_transactions(
    patient_id: int,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    patient = (
        db.query(models.Patient)
        .filter(models.Patient.id == patient_id, models.Patient.doctor_email == current_user.email)
        .first()
    )
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    return (
        db.query(models.FinancialTransaction)
        .filter(models.FinancialTransaction.patient_id == patient_id)
        .filter(models.FinancialTransaction.type == "income")
        .filter(models.FinancialTransaction.doctor_email == current_user.email)
        .order_by(models.FinancialTransaction.created_at.desc())
        .all()
    )


@app.put("/api/finance/transaction/{transaction_id}", status_code=200)
def update_financial_transaction(
    transaction_id: int,
    transaction_update: FinancialTransactionUpdate,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    transaction = (
        db.query(models.FinancialTransaction)
        .filter(
            models.FinancialTransaction.id == transaction_id,
            models.FinancialTransaction.doctor_email == current_user.email,
        )
        .first()
    )
    if not transaction:
        raise HTTPException(status_code=404, detail="الدفعة المالية غير موجودة")

    description = transaction_update.description.strip()
    if not description:
        raise HTTPException(status_code=400, detail="وصف الدفعة مطلوب")
    if transaction_update.amount <= 0:
        raise HTTPException(status_code=400, detail="قيمة الدفعة يجب أن تكون أكبر من صفر")

    # 2026-08-25: تصحيح يدوي اختياري لتاريخ/تصنيف الحركة -- انظر شرح كامل عند
    # get_finance_summary(). يسمح للطبيب بتصحيح حركة قديمة سُجّلت بالخطأ.
    new_transaction_date = None
    if transaction_update.transaction_date is not None:
        new_transaction_date = transaction_update.transaction_date
        if new_transaction_date.tzinfo is not None:
            new_transaction_date = new_transaction_date.replace(tzinfo=None)
        if new_transaction_date > datetime.utcnow():
            raise HTTPException(status_code=400, detail="تاريخ الحركة لا يمكن أن يكون في المستقبل")

    try:
        transaction.amount = Decimal(str(transaction_update.amount))
        transaction.description = description
        if transaction_update.is_opening_balance is not None:
            transaction.is_opening_balance = bool(transaction_update.is_opening_balance)
        if new_transaction_date is not None:
            transaction.created_at = new_transaction_date
        db.commit()
        db.refresh(transaction)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر تحديث الدفعة المالية حالياً. حاول مرة أخرى.")

    return {"message": "تم تحديث الدفعة المالية بنجاح"}


@app.delete("/api/finance/transaction/{transaction_id}", status_code=200)
def delete_financial_transaction(
    transaction_id: int,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    transaction = (
        db.query(models.FinancialTransaction)
        .filter(
            models.FinancialTransaction.id == transaction_id,
            models.FinancialTransaction.doctor_email == current_user.email,
        )
        .first()
    )
    if not transaction:
        raise HTTPException(status_code=404, detail="الدفعة المالية غير موجودة")

    try:
        db.delete(transaction)
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر حذف الدفعة المالية حالياً. حاول مرة أخرى.")

    return {"message": "تم حذف الدفعة المالية بنجاح"}


@app.get("/api/finance/backup")
def export_finance_backup(
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(database.get_db),
):
    user = require_active_doctor_user(db=db, doctor_email=doctor_email, authorization=authorization)
    doctor_name = (user.doctor_name or "").strip()
    if not doctor_name:
        doctor_name = user.email

    # عزل صارم حسب doctor_email فقط (2026-08-23) بدل المطابقة النصية الهشة على
    # doctor_name، والتي كانت عرضة لتصادم الأسماء بين طبيبين مختلفين.
    patients = (
        db.query(models.Patient)
        .filter(models.Patient.doctor_email == user.email)
        .order_by(models.Patient.id.asc())
        .all()
    )
    patient_name_to_id = {
        (patient.full_name or "").strip().lower(): patient.id
        for patient in patients
        if (patient.full_name or "").strip()
    }

    transactions = (
        db.query(models.FinancialTransaction)
        .filter(models.FinancialTransaction.doctor_email == user.email)
        .order_by(models.FinancialTransaction.created_at.asc(), models.FinancialTransaction.id.asc())
        .all()
    )

    filtered_appointments = (
        db.query(models.Appointment)
        .filter(models.Appointment.doctor_email == user.email)
        .order_by(models.Appointment.id.asc())
        .all()
    )

    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow([
        "record_type",
        "record_id",
        "patient_id",
        "patient_name",
        "patient_phone",
        "doctor_name",
        "birth_date",
        "gender",
        "medical_history",
        "appointment_date",
        "appointment_time",
        "appointment_status",
        "transaction_amount",
        "transaction_type",
        "transaction_description",
        "created_at",
    ])

    for patient in patients:
        writer.writerow([
            "patient",
            patient.id,
            patient.id,
            patient.full_name or "",
            # 2026-08-29: رقم الهاتف كان مفقوداً تماماً من النسخة الاحتياطية القديمة
            # (لم يكن ضمن الأعمدة إطلاقاً)، فكان أي مريض يُسترجَع يعود بلا رقم هاتف
            # رغم أن العمود phone إلزامي (NOT NULL) في قاعدة البيانات. أُضيف هنا
            # بناءً على طلب المستخدم صراحة حتى تصبح النسخة الاحتياطية كاملة فعلاً.
            patient.phone or "",
            doctor_name,
            patient.birth_date.isoformat() if patient.birth_date else "",
            patient.gender or "",
            patient.medical_history or "",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
        ])

    for transaction in transactions:
        linked_patient_name = ""
        if transaction.patient_id is not None:
            linked_patient = next((patient for patient in patients if patient.id == transaction.patient_id), None)
            if linked_patient is not None:
                linked_patient_name = linked_patient.full_name or ""

        writer.writerow([
            "financial_transaction",
            transaction.id,
            transaction.patient_id or "",
            linked_patient_name,
            "",
            transaction.doctor_name or doctor_name,
            "",
            "",
            "",
            "",
            "",
            "",
            str(transaction.amount),
            transaction.type or "",
            transaction.description or "",
            transaction.created_at.isoformat() if transaction.created_at else "",
        ])

    for appointment in filtered_appointments:
        appointment_patient_id = patient_name_to_id.get((appointment.patient_name or "").strip().lower(), "")
        writer.writerow([
            "appointment",
            appointment.id,
            appointment_patient_id,
            appointment.patient_name or "",
            appointment.patient_phone or "",
            doctor_name,
            "",
            "",
            "",
            appointment.appointment_date.isoformat() if appointment.appointment_date else "",
            appointment.appointment_time or "",
            appointment.status or "",
            "",
            "",
            appointment.notes or appointment.procedure_type or "",
            appointment.appointment_date.isoformat() if appointment.appointment_date else "",
        ])

    csv_bytes = buffer.getvalue().encode("utf-8-sig")
    buffer.close()

    response = StreamingResponse(
        iter([csv_bytes]),
        media_type="text/csv",
    )
    response.headers["Content-Disposition"] = 'attachment; filename="dental_backup_2026.csv"'
    return response


# 2026-08-29: زر "نسخة احتياطية" في patient_record.html كان أحادي الاتجاه
# فقط (تصدير CSV للتنزيل) دون أي مسار لاستيراد هذا الملف مرة أخرى -- لاحظ
# المستخدم هذا الخلل بنفسه. هذا المسار يقبل نفس ملف الـ CSV الناتج عن
# export_finance_backup أعلاه ويعيد استيراده بمنطق "دمج فقط" (لا حذف ولا
# استبدال لأي بيانات موجودة حالياً في الحساب، بناءً على طلب المستخدم صراحة):
# - المرضى: يُعاد إدخال أي مريض غير موجود حالياً (مطابقة بالاسم الكامل)، بما
#   في ذلك رقم الهاتف (عمود patient_phone، أُضيف 2026-08-29 بناءً على طلب
#   المستخدم بعد أن كان مفقوداً من تنسيق النسخة الاحتياطية الأصلي). ملفات
#   نسخ احتياطية قديمة صُدِّرت قبل هذه الإضافة تبقى مقبولة (لا تملك هذا العمود
#   إطلاقاً)، وفي تلك الحالة فقط -- أو إن كان الحقل فارغاً في الملف نفسه --
#   يعود رقم الهاتف فارغاً (عمود phone إلزامي NOT NULL) ويُذكَر اسم المريض في
#   الاستجابة ليكمل الطبيب رقمه يدوياً.
# - المواعيد والمعاملات المالية: تُضاف فقط إن لم يوجد سجل مطابق تماماً (نفس
#   المريض/التاريخ/الوقت للمواعيد، ونفس المبلغ/النوع/الوصف/التاريخ للمعاملات)
#   لتفادي التكرار عند استيراد نفس الملف أكثر من مرة بالخطأ.
@app.post("/api/finance/restore")
async def restore_finance_backup(
    file: UploadFile = File(...),
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(database.get_db),
):
    user = require_active_doctor_user(db=db, doctor_email=doctor_email, authorization=authorization)
    doctor_name = (user.doctor_name or "").strip() or user.email

    raw_bytes = await file.read()
    try:
        text_content = raw_bytes.decode("utf-8-sig")
    except UnicodeDecodeError:
        raise HTTPException(
            status_code=400,
            detail="تعذّرت قراءة الملف. تأكد أنه ملف CSV صالح ناتج عن زر (نسخة احتياطية).",
        )

    reader = csv.DictReader(io.StringIO(text_content))
    required_columns = {
        "record_type", "patient_name", "birth_date", "gender", "medical_history",
        "appointment_date", "appointment_time", "appointment_status",
        "transaction_amount", "transaction_type", "transaction_description", "created_at",
    }
    if not reader.fieldnames or not required_columns.issubset(set(reader.fieldnames)):
        raise HTTPException(
            status_code=400,
            detail="صيغة الملف غير متوافقة مع تنسيق النسخة الاحتياطية لهذا النظام.",
        )

    rows = list(reader)

    # -- خطوة 1: المرضى -- خريطة اسم(بأحرف صغيرة) -> كائن Patient لاستخدامها
    # لاحقاً في ربط المواعيد/المعاملات، ولمنع إعادة إدخال مريض موجود أصلاً.
    existing_patients = (
        db.query(models.Patient).filter(models.Patient.doctor_email == user.email).all()
    )
    name_to_patient = {
        (p.full_name or "").strip().lower(): p for p in existing_patients if (p.full_name or "").strip()
    }

    patients_added = 0
    patients_skipped_existing = 0
    patients_missing_phone: list[str] = []

    for row in rows:
        if (row.get("record_type") or "").strip() != "patient":
            continue
        full_name = (row.get("patient_name") or "").strip()
        if not full_name:
            continue
        name_key = full_name.lower()
        if name_key in name_to_patient:
            patients_skipped_existing += 1
            continue

        birth_date_value = None
        raw_birth = (row.get("birth_date") or "").strip()
        if raw_birth:
            try:
                birth_date_value = date.fromisoformat(raw_birth)
            except ValueError:
                birth_date_value = None

        # 2026-08-29: عمود patient_phone أُضيف إلى تنسيق النسخة الاحتياطية بناءً
        # على طلب المستخدم -- لكن نُبقي التوافق مع ملفات نسخ احتياطية قديمة
        # صُدِّرت قبل هذه الإضافة ولا تملك هذا العمود إطلاقاً (row.get يعيد None
        # حينها بأمان). phone يبقى عمود إلزامي (NOT NULL) في قاعدة البيانات، فإن
        # لم يتوفر رقم فعلي (ملف قديم، أو عمود فارغ) نضطر لقيمة فارغة مؤقتة
        # ونُعيد اسم هذا المريض في الاستجابة ليكمل الطبيب رقمه يدوياً.
        phone_value = (row.get("patient_phone") or "").strip()

        new_patient = models.Patient(
            doctor_name=doctor_name,
            doctor_email=user.email,
            full_name=full_name,
            phone=phone_value,
            birth_date=birth_date_value,
            gender=(row.get("gender") or "").strip() or None,
            medical_history=(row.get("medical_history") or "").strip() or None,
        )
        db.add(new_patient)
        db.flush()
        name_to_patient[name_key] = new_patient
        patients_added += 1
        if not phone_value:
            patients_missing_phone.append(full_name)

    # -- خطوة 2: المواعيد -- مفتاح تكرار: (اسم المريض، تاريخ الموعد، وقته) --
    existing_appointment_keys = {
        (
            (a.patient_name or "").strip().lower(),
            a.appointment_date.isoformat() if a.appointment_date else "",
            (a.appointment_time or "").strip(),
        )
        for a in db.query(models.Appointment).filter(models.Appointment.doctor_email == user.email).all()
    }

    appointments_added = 0
    appointments_skipped_existing = 0

    for row in rows:
        if (row.get("record_type") or "").strip() != "appointment":
            continue
        patient_name = (row.get("patient_name") or "").strip()
        raw_date = (row.get("appointment_date") or "").strip()
        appointment_time = (row.get("appointment_time") or "").strip()
        dedup_key = (patient_name.lower(), raw_date, appointment_time)
        if dedup_key in existing_appointment_keys:
            appointments_skipped_existing += 1
            continue

        appointment_date_value = None
        if raw_date:
            try:
                appointment_date_value = datetime.fromisoformat(raw_date)
            except ValueError:
                appointment_date_value = None

        linked_patient = name_to_patient.get(patient_name.lower()) if patient_name else None
        # عمود transaction_description في صفوف المواعيد يحمل notes/procedure_type
        # المدموجين معاً (هكذا صُدِّرا أصلاً في export_finance_backup أعلاه).
        procedure_value = (row.get("transaction_description") or "").strip() or "غير محدد"

        new_appointment = models.Appointment(
            doctor_email=user.email,
            patient_name=patient_name or "مريض غير معروف",
            appointment_date=appointment_date_value,
            appointment_time=appointment_time or "00:00",
            procedure_type=procedure_value,
            status=(row.get("appointment_status") or "").strip() or "pending",
            patient_id=linked_patient.id if linked_patient else None,
            patient_phone=(row.get("patient_phone") or "").strip() or None,
        )
        db.add(new_appointment)
        existing_appointment_keys.add(dedup_key)
        appointments_added += 1

    # -- خطوة 3: المعاملات المالية -- مفتاح تكرار: (المبلغ، النوع، الوصف، تاريخ الإنشاء) --
    existing_transaction_keys = {
        (
            str(t.amount),
            (t.type or "").strip().lower(),
            (t.description or "").strip(),
            t.created_at.isoformat() if t.created_at else "",
        )
        for t in db.query(models.FinancialTransaction)
        .filter(models.FinancialTransaction.doctor_email == user.email)
        .all()
    }

    transactions_added = 0
    transactions_skipped_existing = 0

    for row in rows:
        if (row.get("record_type") or "").strip() != "financial_transaction":
            continue
        amount_raw = (row.get("transaction_amount") or "").strip()
        if not amount_raw:
            continue
        try:
            amount_value = Decimal(amount_raw)
        except (InvalidOperation, ValueError):
            continue

        type_value = (row.get("transaction_type") or "").strip() or "expense"
        description_value = (row.get("transaction_description") or "").strip()
        created_at_raw = (row.get("created_at") or "").strip()

        dedup_key = (str(amount_value), type_value.lower(), description_value, created_at_raw)
        if dedup_key in existing_transaction_keys:
            transactions_skipped_existing += 1
            continue

        created_at_value = None
        if created_at_raw:
            try:
                created_at_value = datetime.fromisoformat(created_at_raw)
            except ValueError:
                created_at_value = None

        patient_name = (row.get("patient_name") or "").strip()
        linked_patient = name_to_patient.get(patient_name.lower()) if patient_name else None

        new_transaction = models.FinancialTransaction(
            patient_id=linked_patient.id if linked_patient else None,
            doctor_name=doctor_name,
            doctor_email=user.email,
            amount=amount_value,
            type=type_value,
            description=description_value or "معاملة مستوردة من نسخة احتياطية",
            created_at=created_at_value or datetime.utcnow(),
        )
        db.add(new_transaction)
        existing_transaction_keys.add(dedup_key)
        transactions_added += 1

    db.commit()

    return {
        "patients_added": patients_added,
        "patients_skipped_existing": patients_skipped_existing,
        "patients_missing_phone": patients_missing_phone,
        "appointments_added": appointments_added,
        "appointments_skipped_existing": appointments_skipped_existing,
        "transactions_added": transactions_added,
        "transactions_skipped_existing": transactions_skipped_existing,
    }


@app.post("/api/prescriptions", response_model=PrescriptionResponse, status_code=201)
def create_prescription(
    prescription: PrescriptionCreate,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    patient = (
        db.query(models.Patient)
        .filter(models.Patient.id == prescription.patient_id, models.Patient.doctor_email == current_user.email)
        .first()
    )
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    medications_value = (prescription.medications or "").strip()
    instructions_value = (prescription.instructions or "").strip()
    if not medications_value or not instructions_value:
        raise HTTPException(status_code=400, detail="Medications and instructions are required")

    try:
        db_prescription = models.Prescription(
            patient_id=prescription.patient_id,
            medications=medications_value,
            instructions=instructions_value,
        )
        db.add(db_prescription)
        db.commit()
        db.refresh(db_prescription)
        return db_prescription
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر حفظ الوصفة الطبية حالياً. حاول مرة أخرى.")


@app.get("/api/prescriptions/patient/{patient_id}", response_model=List[PrescriptionResponse])
def get_patient_prescriptions(
    patient_id: int,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    patient = (
        db.query(models.Patient)
        .filter(models.Patient.id == patient_id, models.Patient.doctor_email == current_user.email)
        .first()
    )
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    return (
        db.query(models.Prescription)
        .filter(models.Prescription.patient_id == patient_id)
        .order_by(models.Prescription.created_at.desc())
        .all()
    )


class PrescriptionUpdate(BaseModel):
    medications: Optional[str] = None
    instructions: Optional[str] = None


@app.put("/api/prescriptions/{prescription_id}", response_model=PrescriptionResponse)
def update_prescription(
    prescription_id: int,
    prescription_update: PrescriptionUpdate,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    prescription = (
        db.query(models.Prescription)
        .join(models.Patient, models.Patient.id == models.Prescription.patient_id)
        .filter(models.Prescription.id == prescription_id, models.Patient.doctor_email == current_user.email)
        .first()
    )
    if not prescription:
        raise HTTPException(status_code=404, detail="الوصفة الطبية غير موجودة")

    medications_value = None
    if prescription_update.medications is not None:
        medications_value = prescription_update.medications.strip()
        if not medications_value:
            raise HTTPException(status_code=400, detail="الأدوية مطلوبة")

    instructions_value = None
    if prescription_update.instructions is not None:
        instructions_value = prescription_update.instructions.strip()
        if not instructions_value:
            raise HTTPException(status_code=400, detail="التعليمات مطلوبة")

    try:
        if medications_value is not None:
            prescription.medications = medications_value
        if instructions_value is not None:
            prescription.instructions = instructions_value
        db.commit()
        db.refresh(prescription)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر تحديث الوصفة الطبية حالياً. حاول مرة أخرى.")

    return prescription


@app.delete("/api/prescriptions/{prescription_id}", status_code=200)
def delete_prescription(
    prescription_id: int,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    prescription = (
        db.query(models.Prescription)
        .join(models.Patient, models.Patient.id == models.Prescription.patient_id)
        .filter(models.Prescription.id == prescription_id, models.Patient.doctor_email == current_user.email)
        .first()
    )
    if not prescription:
        raise HTTPException(status_code=404, detail="الوصفة الطبية غير موجودة")

    try:
        db.delete(prescription)
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر حذف الوصفة الطبية حالياً. حاول مرة أخرى.")

    return {"message": "تم حذف الوصفة الطبية بنجاح"}


@app.post("/api/inventory", response_model=InventoryItemResponse, status_code=201)
def create_inventory_item(
    item: InventoryItemCreate,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(database.get_db),
):
    user = require_premium_user_by_email(db, authorization)

    item_name = (item.item_name or "").strip()
    if not item_name:
        raise HTTPException(status_code=400, detail="اسم المادة مطلوب")
    if item.quantity < 0:
        raise HTTPException(status_code=400, detail="الكمية يجب أن تكون صفراً أو أكثر")
    if item.min_alert_quantity < 0:
        raise HTTPException(status_code=400, detail="حد التنبيه الأدنى يجب أن يكون صفراً أو أكثر")

    try:
        db_item = models.InventoryItem(
            doctor_email=user.email,
            item_name=item_name,
            quantity=item.quantity,
            min_alert_quantity=item.min_alert_quantity,
        )
        db.add(db_item)
        db.commit()
        db.refresh(db_item)
        return db_item
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر حفظ مادة المستودع حالياً. حاول مرة أخرى.")


@app.get("/api/inventory", response_model=List[InventoryItemResponse])
def get_inventory_items(
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(database.get_db),
):
    user = require_premium_user_by_email(db, authorization)

    return (
        db.query(models.InventoryItem)
        .filter(models.InventoryItem.doctor_email == user.email)
        .order_by(models.InventoryItem.updated_at.desc(), models.InventoryItem.id.desc())
        .all()
    )


class InventoryItemUpdate(BaseModel):
    item_name: Optional[str] = None
    quantity: Optional[int] = None
    min_alert_quantity: Optional[int] = None


@app.put("/api/inventory/{item_id}", response_model=InventoryItemResponse)
def update_inventory_item(
    item_id: int,
    item_update: InventoryItemUpdate,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(database.get_db),
):
    user = require_premium_user_by_email(db, authorization)

    item = (
        db.query(models.InventoryItem)
        .filter(models.InventoryItem.id == item_id, models.InventoryItem.doctor_email == user.email)
        .first()
    )
    if not item:
        raise HTTPException(status_code=404, detail="مادة المستودع غير موجودة")

    if item_update.item_name is not None:
        item_name = item_update.item_name.strip()
        if not item_name:
            raise HTTPException(status_code=400, detail="اسم المادة مطلوب")
        item.item_name = item_name

    if item_update.quantity is not None:
        if item_update.quantity < 0:
            raise HTTPException(status_code=400, detail="الكمية يجب أن تكون صفراً أو أكثر")
        item.quantity = item_update.quantity

    if item_update.min_alert_quantity is not None:
        if item_update.min_alert_quantity < 0:
            raise HTTPException(status_code=400, detail="حد التنبيه الأدنى يجب أن يكون صفراً أو أكثر")
        item.min_alert_quantity = item_update.min_alert_quantity

    try:
        db.commit()
        db.refresh(item)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر تحديث مادة المستودع حالياً. حاول مرة أخرى.")

    return item


@app.delete("/api/inventory/{item_id}", status_code=200)
def delete_inventory_item(
    item_id: int,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(database.get_db),
):
    user = require_premium_user_by_email(db, authorization)

    item = (
        db.query(models.InventoryItem)
        .filter(models.InventoryItem.id == item_id, models.InventoryItem.doctor_email == user.email)
        .first()
    )
    if not item:
        raise HTTPException(status_code=404, detail="مادة المستودع غير موجودة")

    try:
        db.delete(item)
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر حذف مادة المستودع حالياً. حاول مرة أخرى.")

    return {"message": "تم حذف مادة المستودع بنجاح"}


# --- واجهات API لنظام استرجاع المرضى التلقائي (Patient Recall Engine) -- 2026-09-01 ---
# ميزة Premium حصرية: تعرض للطبيب قائمة مرضاه المستحقين لتذكير متابعة (راجع
# get_recall_candidates أعلاه)، وتسمح له بإرسال رسالة استرجاع فورية لمريض واحد
# أو لكل المستحقين دفعة واحدة، بالإضافة لمحرك الإرسال التلقائي الدوري بلا أي
# تدخل من الطبيب (send_due_recall_messages أعلاه).
class RecallPatientEntry(BaseModel):
    patient_id: int
    full_name: str
    phone: str
    last_visit_date: Optional[datetime] = None
    days_since_last_visit: int
    last_recall_sent_at: Optional[datetime] = None


class RecallDuePatientsResponse(BaseModel):
    count: int
    interval_days: int
    patients: List[RecallPatientEntry]


@app.get("/api/recall/due-patients", response_model=RecallDuePatientsResponse)
def get_due_recall_patients(
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(database.get_db),
):
    user = require_premium_user_by_email(db, authorization)

    candidates = get_recall_candidates(db, user.email, RECALL_INTERVAL_DAYS)
    patients_payload = [
        RecallPatientEntry(
            patient_id=candidate["patient"].id,
            full_name=candidate["patient"].full_name or "",
            phone=candidate["patient"].phone or "",
            last_visit_date=candidate["last_visit_date"],
            days_since_last_visit=candidate["days_since_last_visit"],
            last_recall_sent_at=candidate["patient"].last_recall_sent_at,
        )
        for candidate in candidates
    ]

    return RecallDuePatientsResponse(
        count=len(patients_payload),
        interval_days=RECALL_INTERVAL_DAYS,
        patients=patients_payload,
    )


@app.post("/api/recall/send/{patient_id}")
def send_single_recall_message(
    patient_id: int,
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(database.get_db),
):
    user = require_premium_user_by_email(db, authorization)

    patient = (
        db.query(models.Patient)
        .filter(models.Patient.id == patient_id, models.Patient.doctor_email == user.email)
        .first()
    )
    if not patient:
        raise HTTPException(status_code=404, detail="المريض غير موجود")
    if not patient.phone:
        raise HTTPException(status_code=400, detail="لا يوجد رقم هاتف مسجّل لهذا المريض")

    # إرسال يدوي بطلب صريح من الطبيب -- لا يخضع لسقف RECALL_INTERVAL_DAYS
    # (cooldown) المطبَّق فقط على المحرك التلقائي send_due_recall_messages.
    was_sent = send_recall_message_to_patient(db, user, patient)
    if not was_sent:
        return {
            "sent": False,
            "message": "تعذر إرسال رسالة واتساب الآن -- تأكد من إعداد خدمة واتساب (Green API) من إعدادات الحساب.",
        }

    return {"sent": True, "message": f"تم إرسال رسالة الاسترجاع لـ {patient.full_name} بنجاح."}


class RecallSendAllResponse(BaseModel):
    attempted: int
    sent: int
    failed: int


@app.post("/api/recall/send-all", response_model=RecallSendAllResponse)
def send_all_recall_messages(
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(database.get_db),
):
    user = require_premium_user_by_email(db, authorization)

    candidates = get_recall_candidates(db, user.email, RECALL_INTERVAL_DAYS)
    attempted = len(candidates)
    sent = 0
    for candidate in candidates:
        if send_recall_message_to_patient(db, user, candidate["patient"]):
            sent += 1

    return RecallSendAllResponse(attempted=attempted, sent=sent, failed=attempted - sent)


@app.get("/api/patients/{patient_id}/treatments", response_model=List[TreatmentResponse])
def get_patient_treatments(
    patient_id: int,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    patient = (
        db.query(models.Patient)
        .filter(models.Patient.id == patient_id, models.Patient.doctor_email == current_user.email)
        .first()
    )
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    return db.query(models.Treatment).filter(models.Treatment.patient_id == patient_id).all()


ARCHIVE_FILE_MAP = {
    ".png": ("image", "image/png"),
    ".jpg": ("image", "image/jpeg"),
    ".jpeg": ("image", "image/jpeg"),
    ".pdf": ("pdf", "application/pdf"),
}


def normalize_archive_record(record: models.PatientXRay) -> dict:
    file_url = (record.file_url or record.image_url or "").strip()
    file_name = (record.file_name or os.path.basename(file_url) or f"archive_{record.id}").strip()
    file_type = (record.file_type or "").strip().lower()

    if not file_type:
      _, ext = os.path.splitext(file_name.lower())
      file_type = ARCHIVE_FILE_MAP.get(ext, ("image" if ext in {".png", ".jpg", ".jpeg"} else ""))[0]

    return {
        "id": record.id,
        "patient_id": record.patient_id,
        "file_name": file_name,
        "file_url": file_url,
        "description": record.description,
        "file_type": file_type or "image",
        "uploaded_at": record.uploaded_at,
        "image_url": record.image_url or file_url,
    }


def validate_archive_file(file: UploadFile) -> tuple[str, str]:
    original_name = file.filename or "medical_archive"
    _, ext = os.path.splitext(original_name)
    ext = ext.lower()

    if ext not in ARCHIVE_FILE_MAP:
        raise HTTPException(status_code=400, detail="Only PNG, JPG, JPEG, and PDF files are allowed")

    expected_type, expected_mime = ARCHIVE_FILE_MAP[ext]
    actual_mime = (file.content_type or "").lower().strip()
    if actual_mime and actual_mime not in {expected_mime, "application/octet-stream"}:
        raise HTTPException(status_code=400, detail="Invalid file type. Please upload an image or PDF document.")

    return original_name, expected_type


@app.post("/api/patients/{patient_id}/archive", response_model=PatientXRayResponse, status_code=201)
@app.post("/api/patients/{patient_id}/xrays", response_model=PatientXRayResponse, status_code=201)
async def upload_patient_archive(
    patient_id: int,
    file: UploadFile = File(...),
    description: str = Form(""),
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    patient = (
        db.query(models.Patient)
        .filter(models.Patient.id == patient_id, models.Patient.doctor_email == current_user.email)
        .first()
    )
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    original_name, file_type = validate_archive_file(file)
    _, ext = os.path.splitext(original_name)
    ext = ext.lower()
    unique_filename = f"archive_{patient_id}_{uuid4().hex}{ext}"
    saved_path = os.path.join(ARCHIVE_UPLOADS_DIR, unique_filename)
    file_url = f"/uploads/patient_xrays/{unique_filename}"

    try:
        content = await file.read()
        with open(saved_path, "wb") as output_file:
            output_file.write(content)

        db_xray = models.PatientXRay(
            patient_id=patient_id,
            image_url=file_url,
            file_name=original_name,
            file_url=file_url,
            description=description.strip() or None,
            file_type=file_type,
        )
        db.add(db_xray)
        db.commit()
        db.refresh(db_xray)
        return normalize_archive_record(db_xray)
    except Exception:
        db.rollback()
        if os.path.exists(saved_path):
            try:
                os.remove(saved_path)
            except OSError:
                pass
        raise HTTPException(status_code=400, detail="تعذر رفع الملف الطبي حالياً. حاول مرة أخرى.")
    finally:
        await file.close()


@app.get("/api/patients/{patient_id}/archive", response_model=List[PatientXRayResponse])
@app.get("/api/patients/{patient_id}/xrays", response_model=List[PatientXRayResponse])
def get_patient_archive(
    patient_id: int,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    patient = (
        db.query(models.Patient)
        .filter(models.Patient.id == patient_id, models.Patient.doctor_email == current_user.email)
        .first()
    )
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    archive_records = (
        db.query(models.PatientXRay)
        .filter(models.PatientXRay.patient_id == patient_id)
        .order_by(models.PatientXRay.uploaded_at.desc())
        .all()
    )

    return [normalize_archive_record(record) for record in archive_records]


class PatientArchiveUpdate(BaseModel):
    description: Optional[str] = None


@app.put("/api/patients/{patient_id}/archive/{archive_id}", response_model=PatientXRayResponse)
@app.put("/api/patients/{patient_id}/xrays/{archive_id}", response_model=PatientXRayResponse)
def update_patient_archive(
    patient_id: int,
    archive_id: int,
    archive_update: PatientArchiveUpdate,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    owned_patient = (
        db.query(models.Patient)
        .filter(models.Patient.id == patient_id, models.Patient.doctor_email == current_user.email)
        .first()
    )
    if not owned_patient:
        raise HTTPException(status_code=404, detail="الملف الطبي غير موجود")

    record = (
        db.query(models.PatientXRay)
        .filter(models.PatientXRay.id == archive_id, models.PatientXRay.patient_id == patient_id)
        .first()
    )
    if not record:
        raise HTTPException(status_code=404, detail="الملف الطبي غير موجود")

    try:
        if archive_update.description is not None:
            record.description = archive_update.description.strip() or None
        db.commit()
        db.refresh(record)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر تحديث الملف الطبي حالياً. حاول مرة أخرى.")

    return normalize_archive_record(record)


@app.delete("/api/patients/{patient_id}/archive/{archive_id}", status_code=200)
@app.delete("/api/patients/{patient_id}/xrays/{archive_id}", status_code=200)
def delete_patient_archive(
    patient_id: int,
    archive_id: int,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(require_active_doctor_user),
):
    owned_patient = (
        db.query(models.Patient)
        .filter(models.Patient.id == patient_id, models.Patient.doctor_email == current_user.email)
        .first()
    )
    if not owned_patient:
        raise HTTPException(status_code=404, detail="الملف الطبي غير موجود")

    record = (
        db.query(models.PatientXRay)
        .filter(models.PatientXRay.id == archive_id, models.PatientXRay.patient_id == patient_id)
        .first()
    )
    if not record:
        raise HTTPException(status_code=404, detail="الملف الطبي غير موجود")

    file_url = (record.file_url or record.image_url or "").strip()

    try:
        db.delete(record)
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر حذف الملف الطبي حالياً. حاول مرة أخرى.")

    if file_url.startswith("/uploads/"):
        physical_path = file_url[len("/uploads/"):]
        full_path = os.path.join(UPLOADS_DIR, physical_path)
        if os.path.exists(full_path):
            try:
                os.remove(full_path)
            except OSError:
                pass

    return {"message": "تم حذف الملف الطبي بنجاح"}


# المخطط البرمجي لاستقبال طلب التفعيل من الـ Frontend
class ActivationRequest(BaseModel):
    email: str
    activation_key: str


# ملاحظة هامة: أي مسار @app.* يجب أن يُعرَّف قبل app.mount("/", ...) بالأسفل،
# لأن التركيب المثبت على "/" يلتقط كل الطلبات غير المطابقة لمسار سابق، فأي مسار
# يُعرَّف بعده يصبح ميتاً تماماً ولا يتم الوصول إليه أبداً.
#
# مسار مزدوج الغرض (dual-purpose) بتصميم صريح: نفس هذا المسار يُستخدم لكلا
# الحالتين التاليتين بلا أي فرع منطقي مختلف -- فالعملية الفعلية على قاعدة
# البيانات متطابقة تماماً في الحالتين (ترقية عمود tier + تمديد
# subscription_expires_at + تعليم الكود كمُستخدَم)، والفرق الوحيد هو رسالة
# النجاح المعروضة للطبيب:
#   1) "تفعيل أول مرة": حساب بحالة pending_activation (تسجيل Google جديد لم
#      يفعّل بعد) أو حساب جديد من التسجيل اليدوي.
#   2) "تجديد اشتراك": حساب بحالة expired_subscription (انتهت باقته الشهرية/
#      السنوية) -- يعود فوراً إلى premium/standard دون فقدان أي بيانات إطلاقاً،
#      لأن جدول users لم يُحذف منه أي صف قط طوال دورة الحياة هذه.
@app.post("/api/activate")
def activate_account(request: ActivationRequest, db: Session = Depends(database.get_db)):
    normalized_email = (request.email or "").strip().lower()
    activation_code = (request.activation_key or "").strip()

    if not normalized_email or not activation_code:
        raise HTTPException(status_code=400, detail="البريد الإلكتروني وكود التفعيل مطلوبان.")

    # 1. البحث عن كود التفعيل الحقيقي في قاعدة البيانات (بدلاً من قائمة مكررة ومليئة بأخطاء إملائية)
    # مطابقة غير حساسة لحالة الأحرف (2026-08-23) -- انظر نفس الملاحظة في
    # register_user أعلاه.
    activation_key = (
        db.query(models.ActivationKey)
        .filter(func.lower(models.ActivationKey.key_code) == activation_code.lower())
        .first()
    )
    if not activation_key or activation_key.is_used:
        raise HTTPException(status_code=400, detail="كود التفعيل خاطئ، منتهي، أو تم استخدامه مسبقاً!")

    # نقطة الحقيقة الوحيدة لتصنيف الكود -- انظر resolve_activation_key_tier أعلاه
    # (2026-08-30: هذا المنطق نُقل إلى دالة مشتركة بعد أن تسبّب تكراره بشكل
    # متفاوت في مسارين آخرين برفض/إساءة تصنيف كود Premium شهري حقيقي).
    target_tier = resolve_activation_key_tier(activation_key, activation_code)

    # 2. البحث عن الطبيب المستهدف في جدول قاعدة البيانات لتعديل رتبته
    user = db.query(models.User).filter(models.User.email == normalized_email).first()
    if not user:
        raise HTTPException(status_code=404, detail="حساب الطبيب المستهدف غير موجود!")

    previous_tier = (user.tier or "").strip().lower()
    is_renewal = previous_tier == "expired_subscription"

    try:
        # 3. ترقية الحساب فعلياً مع ضبط تاريخ انتهاء الاشتراك وتفعيل الحساب،
        # وتعليم الكود كمُستخدَم حتى لا يُعاد استخدامه من قِبل شخص آخر
        now = datetime.utcnow()
        base_date = user.subscription_expires_at if user.subscription_expires_at and user.subscription_expires_at > now else now

        user.tier = target_tier
        user.subscription_expires_at = base_date + timedelta(days=activation_key.duration_days)
        user.is_active = True

        activation_key.is_used = True
        activation_key.used_by_email = normalized_email

        db.commit()
        db.refresh(user)

        if is_renewal:
            success_message = (
                f"🎉 تم تجديد اشتراكك بنجاح والعودة فوراً إلى باقة ({target_tier})! "
                "جميع سجلات مرضاك ومواعيدك ومخزون عيادتك كما تركتها تماماً."
            )
        else:
            success_message = f"تم تفعيل عيادتك الرقمية بنجاح وترقيتها إلى باقة ({target_tier})!"

        return {
            "status": "success",
            "message": success_message,
            "is_renewal": is_renewal,
            "user_tier": user.tier,
            "subscription_expires_at": user.subscription_expires_at.isoformat() if user.subscription_expires_at else None,
        }
    except Exception:
        db.rollback()
        raise HTTPException(status_code=500, detail="فشل تحديث قاعدة البيانات السحابية. حاول مرة أخرى.")


@app.post("/api/admin/idle-reminders/run")
def admin_run_idle_reminders(
    x_admin_secret: str | None = Header(default=None, alias="X-Admin-Secret"),
    dry_run: bool = Query(default=False),
):
    # مسار إداري لاختبار محرّك تذكير الخمول فوراً دون انتظار الساعة 1 ظهراً
    # (2026-09-05). يتجاوز شرط الساعة وحده -- كل بقية القواعد تُطبَّق كما هي
    # حرفياً (الأطباء المستحقون، احترام أيام العطلة، حارس التذكير الواحد يومياً).
    # dry_run=true يُرجع قائمة من كان سيصله التذكير دون إرسال أي شيء فعلياً،
    # وهي الطريقة الآمنة للتحقق قبل أول تشغيل حقيقي.
    if not x_admin_secret or x_admin_secret != ADMIN_SECRET_KEY:
        raise HTTPException(status_code=401, detail="مفتاح الإدارة السرّي مفقود أو غير صحيح.")

    if dry_run:
        db = database.SessionLocal()
        try:
            candidates = get_idle_doctors(db)
            preview = []
            for doctor in candidates:
                title, body = build_idle_reminder_message(db, doctor)
                preview.append(
                    {
                        "email": doctor.email,
                        "tier": doctor.tier,
                        "last_active_at": doctor.last_active_at.isoformat() if doctor.last_active_at else None,
                        "app_push": bool(doctor.fcm_token),
                        "web_push": bool(doctor.web_push_token),
                        "title": title,
                        "body": body,
                    }
                )
            return {"dry_run": True, "candidates": len(preview), "doctors": preview}
        finally:
            db.close()

    sent_count = send_due_idle_reminders()
    return {"dry_run": False, "sent": sent_count}


class RenewalKeyGenerateRequest(BaseModel):
    tier: Literal["premium", "standard"] = "premium"
    duration_days: int = 30
    count: int = 1


@app.post("/api/admin/renewal-keys/generate")
def generate_renewal_keys(
    request: RenewalKeyGenerateRequest,
    x_admin_secret: str | None = Header(default=None, alias="X-Admin-Secret"),
    db: Session = Depends(database.get_db),
):
    # مسار إداري فقط لمطوّر المنصة (فارس) لتوليد أكواد تجديد شهرية جديدة عند
    # الطلب، بدل الاعتماد على قائمة ثابتة في الكود يجب إعادة النشر لتحديثها.
    # محمي بمفتاح سرّي في الهيدر -- **اضبط ADMIN_SECRET_KEY كمتغيّر بيئة حقيقي
    # على Render قبل الاستخدام الفعلي**، القيمة الافتراضية معروفة وغير آمنة.
    if not x_admin_secret or x_admin_secret != ADMIN_SECRET_KEY:
        raise HTTPException(status_code=401, detail="مفتاح الإدارة السرّي مفقود أو غير صحيح.")

    if request.count < 1 or request.count > 20:
        raise HTTPException(status_code=400, detail="يمكن توليد بين 1 و20 كوداً في كل مرة.")
    if request.duration_days < 1:
        raise HTTPException(status_code=400, detail="مدة الكود يجب أن تكون يوماً واحداً على الأقل.")

    generated_keys: list[str] = []
    try:
        for _ in range(request.count):
            # إعادة المحاولة نادراً ما تلزم (فضاء الاحتمالات ~62^13) لكنها موجودة
            # كحماية إضافية ضد أي تصادم عرضي مع كود موجود مسبقاً.
            for _attempt in range(5):
                candidate_code = generate_renewal_activation_code(request.tier)
                exists = (
                    db.query(models.ActivationKey)
                    .filter(func.lower(models.ActivationKey.key_code) == candidate_code.lower())
                    .first()
                )
                if not exists:
                    break
            else:
                raise HTTPException(status_code=500, detail="تعذر توليد كود فريد، حاول مرة أخرى.")

            db.add(
                models.ActivationKey(
                    key_code=candidate_code,
                    duration_days=request.duration_days,
                    intended_tier=request.tier,
                    is_used=False,
                    used_by_email=None,
                )
            )
            generated_keys.append(candidate_code)

        db.commit()
    except HTTPException:
        db.rollback()
        raise
    except Exception:
        db.rollback()
        raise HTTPException(status_code=500, detail="تعذر حفظ الأكواد الجديدة في قاعدة البيانات.")

    return {
        "generated_keys": generated_keys,
        "tier": request.tier,
        "duration_days": request.duration_days,
    }


class AdminPasswordResetRequest(BaseModel):
    email: str
    new_password: str


@app.post("/api/admin/reset-password")
def admin_reset_password(
    request: AdminPasswordResetRequest,
    x_admin_secret: str | None = Header(default=None, alias="X-Admin-Secret"),
    db: Session = Depends(database.get_db),
):
    # مسار إداري فقط لمطوّر المنصة (فارس) لإعادة تعيين كلمة مرور طبيب يدوياً عند
    # تعطّل حسابه عن الدخول -- الحالة الأشيع: حساب قديم أُنشئ عبر زر "الدخول
    # بـ Google" (قبل إزالته من login.html) وكانت كلمة مروره المخزّنة قيمة
    # عشوائية غير معروفة لأحد (google-oauth-{uuid4().hex})، فلا توجد أي كلمة
    # مرور حقيقية يمكن للطبيب استرجاعها أو تذكّرها. محمي بنفس مفتاح الإدارة
    # السرّي المستخدم في /api/admin/renewal-keys/generate. الكلمة الجديدة تُخزَّن
    # مباشرة بصيغة الهاش الآمن PBKDF2 (وليس نصاً صريحاً قديماً).
    if not x_admin_secret or x_admin_secret != ADMIN_SECRET_KEY:
        raise HTTPException(status_code=401, detail="مفتاح الإدارة السرّي مفقود أو غير صحيح.")

    normalized_email = (request.email or "").strip().lower()
    new_password = request.new_password or ""

    if not normalized_email:
        raise HTTPException(status_code=400, detail="يرجى إدخال البريد الإلكتروني.")
    if len(new_password) < 6:
        raise HTTPException(status_code=400, detail="كلمة المرور الجديدة يجب أن تكون 6 أحرف على الأقل.")

    user = db.query(models.User).filter(models.User.email == normalized_email).first()
    if not user:
        raise HTTPException(status_code=404, detail="لا يوجد حساب طبيب بهذا البريد الإلكتروني.")

    try:
        user.hashed_password = hash_password(new_password)
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=500, detail="تعذر تحديث كلمة المرور في قاعدة البيانات.")

    return {
        "status": "success",
        "message": f"تم تعيين كلمة مرور جديدة للحساب {normalized_email} بنجاح.",
        "email": normalized_email,
    }


@app.post("/api/admin/backfill-opening-balance")
def admin_backfill_opening_balance(
    x_admin_secret: str | None = Header(default=None, alias="X-Admin-Secret"),
    db: Session = Depends(database.get_db),
):
    # مسار إداري لمرة واحدة (2026-08-25) لتصحيح دفعات سُجّلت عبر واجهة ترحيل
    # فواتير العلاج القديمة (نظام "السجل المالي السابق (مرحّل تلقائياً)") لكنها
    # ظهرت بالخطأ كدخل الشهر الحالي بدل تصنيفها "رصيد افتتاحي/سابق" -- انظر شرح
    # كامل عند get_finance_summary() ومذكرة dental_project_finance_integrity_fix.
    # يُصحح أي دفعة income مرتبطة بفاتورة تحمل عنوان الترحيل التلقائي بالضبط،
    # لكل الأطباء دفعة واحدة، بغض النظر عن تاريخها -- محمي بنفس مفتاح الإدارة
    # السرّي. آمن تماماً للتكرار (idempotent): الشرط "is_opening_balance = FALSE"
    # يجعله لا يُغيّر شيئاً بعد أول تشغيل ناجح.
    if not x_admin_secret or x_admin_secret != ADMIN_SECRET_KEY:
        raise HTTPException(status_code=401, detail="مفتاح الإدارة السرّي مفقود أو غير صحيح.")

    legacy_invoice_title = "السجل المالي السابق (مرحّل تلقائياً)"

    try:
        result = db.execute(
            text(
                """
                UPDATE financial_transactions
                SET is_opening_balance = TRUE
                WHERE type = 'income'
                  AND is_opening_balance = FALSE
                  AND invoice_id IN (
                      SELECT id FROM treatment_invoices WHERE title = :legacy_title
                  )
                """
            ),
            {"legacy_title": legacy_invoice_title},
        )
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=500, detail="تعذر تنفيذ التصحيح في قاعدة البيانات.")

    updated_count = result.rowcount if result.rowcount is not None else 0

    return {
        "status": "success",
        "message": f"تم تصنيف {updated_count} دفعة كرصيد افتتاحي/سابق بنجاح.",
        "updated_count": updated_count,
    }



# ====================================================================
# مسارات صفحة الحجز العامة (public booking page) -- بلا مصادقة إطلاقاً --
# 2026-08-23. هذه المسارات يستدعيها booking.html مباشرة من متصفح أي زائر/مريض
# مجهول الهوية تماماً، لذا يجب ألا تُرجع أي بيانات حساسة عن الطبيب (لا بريده،
# لا كلمة سره، لا أي مريض آخر) -- فقط الحد الأدنى اللازم لعرض صفحة الحجز.
# ====================================================================
def compute_available_slots_for_date(db: Session, doctor: models.User, target_date: date) -> List[str]:
    if not doctor.work_days or not doctor.work_start_time or not doctor.work_end_time:
        return []

    allowed_weekdays = set()
    for part in doctor.work_days.split(","):
        part = part.strip()
        if part.isdigit():
            allowed_weekdays.add(int(part))

    if target_date.weekday() not in allowed_weekdays:
        return []

    try:
        start_hour, start_minute = (int(piece) for piece in doctor.work_start_time.split(":"))
        end_hour, end_minute = (int(piece) for piece in doctor.work_end_time.split(":"))
    except (ValueError, AttributeError):
        return []

    slot_minutes = doctor.slot_duration_minutes or 30
    day_start = datetime.combine(target_date, datetime.min.time()).replace(hour=start_hour, minute=start_minute)
    day_end = datetime.combine(target_date, datetime.min.time()).replace(hour=end_hour, minute=end_minute)

    if day_end <= day_start:
        return []

    now_local = datetime.now(KEEP_ALIVE_TIMEZONE).replace(tzinfo=None)

    # أي حالة موعد "تشغل" الوقت وتمنع حجزه من جديد: بانتظار (pending)، بانتظار
    # قبول الطبيب (pending_confirmation)، أو تم تسجيل الحضور فعلاً (checked_in).
    # الحالة "rejected" أو "no_show" لا تشغل الوقت، فيعود متاحاً للحجز مجدداً.
    taken_times = {
        appointment.appointment_time
        for appointment in (
            db.query(models.Appointment)
            .filter(
                models.Appointment.doctor_email == doctor.email,
                models.Appointment.appointment_date >= day_start,
                models.Appointment.appointment_date < day_start + timedelta(days=1),
                models.Appointment.status.in_(["pending", "pending_confirmation", "checked_in"]),
            )
            .all()
        )
    }

    available_slots: List[str] = []
    cursor = day_start
    while cursor + timedelta(minutes=slot_minutes) <= day_end:
        if target_date == now_local.date() and cursor <= now_local:
            cursor += timedelta(minutes=slot_minutes)
            continue
        slot_label = cursor.strftime("%H:%M")
        if slot_label not in taken_times:
            available_slots.append(slot_label)
        cursor += timedelta(minutes=slot_minutes)

    return available_slots


def get_public_doctor_or_404(db: Session, slug: str) -> models.User:
    normalized_slug = (slug or "").strip().lower()
    doctor = (
        db.query(models.User)
        .filter(models.User.booking_slug == normalized_slug, models.User.public_booking_enabled.is_(True))
        .first()
    )
    if not doctor:
        raise HTTPException(status_code=404, detail="صفحة الحجز غير موجودة أو غير مُفعَّلة حالياً.")
    return doctor


@app.get("/api/public/doctor/{slug}")
def get_public_doctor_info(slug: str, db: Session = Depends(database.get_db)):
    doctor = get_public_doctor_or_404(db, slug)
    return {
        "doctor_name": doctor.doctor_name,
        "clinic_name": doctor.clinic_name,
        "clinic_address": doctor.clinic_address,
        "avatar_url": doctor.avatar_url,
        "slot_duration_minutes": doctor.slot_duration_minutes,
    }


@app.get("/api/public/doctor/{slug}/available-slots")
def get_public_available_slots(
    slug: str,
    target_date: str = Query(..., alias="date"),
    db: Session = Depends(database.get_db),
):
    doctor = get_public_doctor_or_404(db, slug)
    try:
        parsed_date = date.fromisoformat(target_date.strip())
    except ValueError:
        raise HTTPException(status_code=400, detail="صيغة التاريخ غير صالحة. المتوقع YYYY-MM-DD")

    today_local = datetime.now(KEEP_ALIVE_TIMEZONE).date()
    if parsed_date < today_local:
        raise HTTPException(status_code=400, detail="لا يمكن حجز موعد في تاريخ ماضٍ.")
    if parsed_date > today_local + timedelta(days=90):
        raise HTTPException(status_code=400, detail="الحجز متاح خلال 90 يوماً القادمة فقط.")

    return {
        "date": parsed_date.isoformat(),
        "available_slots": compute_available_slots_for_date(db, doctor, parsed_date),
    }


class PublicBookingRequest(BaseModel):
    date: str
    time: str
    patient_name: str
    patient_phone: str
    notes: Optional[str] = None


@app.post("/api/public/doctor/{slug}/book", status_code=201)
def create_public_booking_request(
    slug: str,
    booking: PublicBookingRequest,
    db: Session = Depends(database.get_db),
):
    doctor = get_public_doctor_or_404(db, slug)

    trimmed_name = (booking.patient_name or "").strip()
    trimmed_phone = (booking.patient_phone or "").strip()
    if not trimmed_name or not trimmed_phone:
        raise HTTPException(status_code=400, detail="الاسم ورقم الهاتف مطلوبان.")

    try:
        parsed_date = date.fromisoformat((booking.date or "").strip())
    except ValueError:
        raise HTTPException(status_code=400, detail="صيغة التاريخ غير صالحة.")

    trimmed_time = (booking.time or "").strip()
    if len(trimmed_time) != 5 or trimmed_time[2] != ":":
        raise HTTPException(status_code=400, detail="صيغة الوقت غير صالحة.")

    # إعادة التحقق من توفر الموعد على السيرفر (وليس فقط الاعتماد على القائمة
    # التي عرضها الفرونت إند سابقاً للمريض) -- يمنع سباقاً (race condition) بين
    # مريضين يحاولان حجز نفس الموعد في نفس اللحظة تقريباً.
    available_slots = compute_available_slots_for_date(db, doctor, parsed_date)
    if trimmed_time not in available_slots:
        raise HTTPException(status_code=409, detail="عذراً، هذا الموعد لم يعد متاحاً. يرجى اختيار موعد آخر.")

    try:
        appointment_date_time = datetime.combine(parsed_date, datetime.min.time()).replace(
            hour=int(trimmed_time[:2]), minute=int(trimmed_time[3:])
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="صيغة الوقت غير صالحة.")

    db_appointment = models.Appointment(
        doctor_email=doctor.email,
        patient_name=trimmed_name,
        patient_phone=trimmed_phone,
        appointment_date=appointment_date_time,
        appointment_time=trimmed_time,
        procedure_type=(booking.notes or "").strip() or "حجز عبر صفحة الحجز العامة",
        notes=(booking.notes or "").strip() or None,
        status="pending_confirmation",
    )

    try:
        db.add(db_appointment)
        db.commit()
        db.refresh(db_appointment)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر إرسال طلب الحجز. حاول مرة أخرى.")

    # إشعار الطبيب عبر واتساب بطلب حجز جديد (best-effort، لا يوقف الطلب لو فشل الإرسال)
    if doctor.clinic_phone:
        doctor_message = (
            f"📅 طلب حجز جديد من {trimmed_name} ({trimmed_phone}) "
            f"بتاريخ {parsed_date.isoformat()} الساعة {trimmed_time}. "
            "يرجى مراجعة صفحة المواعيد للقبول أو الرفض."
        )
        send_whatsapp_message_for_doctor(doctor, doctor.clinic_phone, doctor_message)

    # إشعار Push فوري لتطبيق الطبيب على أندرويد (best-effort مثل واتساب أعلاه
    # تماماً -- مستقل عنه، يعمل حتى لو واتساب غير مضبوط أو فشل إرساله)
    send_push_notification_to_doctor(
        doctor,
        title="📅 طلب حجز جديد",
        body=f"{trimmed_name} حجز موعداً بتاريخ {parsed_date.isoformat()} الساعة {trimmed_time}",
        data={"type": "new_booking", "appointment_id": str(db_appointment.id)},
    )

    return {
        "message": "تم إرسال طلب الحجز بنجاح، سيصلك إشعار عند رد الطبيب.",
        "appointment_id": db_appointment.id,
    }


# يتحقق المريض من حالة آخر طلب حجز أرسله عبر صفحة الحجز العامة (booking.html)
# باستخدام رقم هاتفه فقط -- لا حاجة لتسجيل دخول أو رابط خاص. أُضيف 2026-08-24
# لأن قناة واتساب (Green API) غير مُفعَّلة بعد، فكانت هذه الوسيلة الوحيدة الممكنة
# لإعلام المريض برفض طلبه ودفعه لاختيار موعد آخر بدل بقائه بلا أي إشعار على الإطلاق.
@app.get("/api/public/doctor/{slug}/booking-status")
def get_public_booking_status(
    slug: str,
    phone: str = Query(..., min_length=1),
    db: Session = Depends(database.get_db),
):
    doctor = get_public_doctor_or_404(db, slug)

    normalized_phone = normalize_whatsapp_phone(phone)
    if not normalized_phone:
        raise HTTPException(status_code=400, detail="رقم الهاتف غير صالح.")

    # لا يوجد عمود مُطبَّع لرقم الهاتف بقاعدة البيانات، والمقارنة النصية المباشرة
    # غير موثوقة لاختلاف صيغ الإدخال (00963.. / 0.. / بدون رمز الدولة..) -- لذا
    # نجلب مواعيد هذا الطبيب فقط (معزولة أصلاً بـ doctor_email) ونطبّع كل رقم
    # بايثونياً بنفس الدالة المستخدمة لإرسال واتساب، لضمان تطابق حقيقي.
    candidate_appointments = (
        db.query(models.Appointment)
        .filter(
            models.Appointment.doctor_email == doctor.email,
            models.Appointment.patient_phone.isnot(None),
        )
        .order_by(models.Appointment.id.desc())
        .all()
    )
    appointment = next(
        (
            candidate
            for candidate in candidate_appointments
            if normalize_whatsapp_phone(candidate.patient_phone) == normalized_phone
        ),
        None,
    )

    if not appointment:
        raise HTTPException(
            status_code=404,
            detail="لم يتم العثور على طلب حجز مرتبط بهذا الرقم لدى هذا الطبيب.",
        )

    return {
        "appointment_id": appointment.id,
        "status": appointment.status,
        "patient_name": appointment.patient_name,
        "appointment_date": appointment.appointment_date.strftime("%Y-%m-%d") if appointment.appointment_date else None,
        "appointment_time": appointment.appointment_time,
    }


@app.get("/d/{slug}", include_in_schema=False)
def serve_public_booking_page(slug: str):
    # يخدم محتوى booking.html مباشرة (FileResponse وليس إعادة توجيه) حتى يبقى
    # شريط عنوان المتصفح عارضاً الرابط النظيف /d/<slug> نفسه الذي يشاركه الطبيب
    # مع مرضاه -- الصفحة نفسها تقرأ الـ slug من location.pathname بجافاسكربت.
    #
    # Cache-Control صريح ومقصود (اكتُشفت الحاجة له 2026-08-24): هذه الصفحة
    # عرضة للتعديل والإصلاح بمرور الوقت بينما رابطها (/d/<slug>) يبقى ثابتاً --
    # بدون هذا الهيدر يعتمد المتصفح على تخمين افتراضي (heuristic caching) وقد
    # يستمر بعرض نسخة قديمة مكسورة من booking.html لمريض فتح الرابط أكثر من
    # مرة، حتى بعد إصلاح الخلل ونشره فعلياً على السيرفر -- وهذا بالضبط ما صعّب
    # تشخيص عطل "الرابط غير متاح" (كان الخلل الفعلي مُصلَحاً على السيرفر، لكن
    # متصفح المريض استمر بعرض النسخة القديمة المخزّنة من قبل الإصلاح).
    return FileResponse(
        os.path.join("frontend_web", "booking.html"),
        headers={"Cache-Control": "no-cache, no-store, must-revalidate"},
    )


@app.get("/", include_in_schema=False)
def redirect_to_landing():
    # الرابط الرئيسي للموقع (/) كان يُحوَّل مباشرة إلى شاشة تسجيل الدخول،
    # متخطياً صفحة التسويق (landing.html) بالكامل رغم وجودها فعلياً على
    # السيرفر -- لم يكن هناك أي رابط بأي صفحة يقود إليها، فكانت غير مرئية
    # عملياً لأي زائر جديد يفتح الرابط الأساسي للمنصة (2026-08-23). الآن يرى
    # كل زائر جديد صفحة التسويق أولاً، وفيها أزرار واضحة لكل من "تسجيل الدخول"
    # (للأطباء المشتركين أصلاً) و"ابدأ الآن" (تسجيل حساب جديد عبر register.html).
    return RedirectResponse(url="/landing.html", status_code=302)

app.mount("/uploads", StaticFiles(directory=UPLOADS_DIR), name="uploads")
app.mount("/", StaticFiles(directory="frontend_web", html=True), name="static")

if __name__ == "__main__":
    # قراءة المنفذ ديناميكياً من بيئة Render العالمية، وإلا استخدام 8090 كبديل محلي
    port = int(os.environ.get("PORT", 8090))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=False)