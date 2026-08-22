from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse, StreamingResponse
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
from decimal import Decimal
import os
from uuid import uuid4
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token
import models
import database
import os
import uvicorn
import asyncio
import requests
import secrets
import string
from zoneinfo import ZoneInfo
from pydantic import BaseModel
app = FastAPI(title="Dental Clinic API")

# معرّف عميل Google الرسمي (بدون أي رموز إضافية مثل ":" في البداية، وإلا يفشل التحقق بخطأ invalid_client)
GOOGLE_CLIENT_ID = "446271578356-qju6aml2tiqbd2v6p23utrfb7nosketm.apps.googleusercontent.com"

# مفتاح إداري سرّي لتوليد أكواد التجديد الشهرية عبر /api/admin/renewal-keys/generate
# فقط -- **يجب** ضبطه كمتغيّر بيئة حقيقي (ADMIN_SECRET_KEY) في إعدادات Render قبل
# الإطلاق التجاري؛ القيمة الافتراضية بالأسفل معروفة للجميع ولا تصلح للإنتاج.
ADMIN_SECRET_KEY = os.getenv("ADMIN_SECRET_KEY", "change-me-fares-admin-2026")

UPLOADS_DIR = "uploads"
os.makedirs(UPLOADS_DIR, exist_ok=True)
ARCHIVE_UPLOADS_DIR = os.path.join(UPLOADS_DIR, "patient_xrays")
os.makedirs(ARCHIVE_UPLOADS_DIR, exist_ok=True)


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
    birth_date: date = None
    gender: str = None
    medical_history: Optional[str] = None
    total_treatment_cost: float = 0.0


class PatientUpdate(BaseModel):
    doctor_name: Optional[str] = None
    full_name: Optional[str] = None
    phone: Optional[str] = None
    medical_history: Optional[str] = None
    total_treatment_cost: Optional[float] = None


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


class ExpenseResponse(BaseModel):
    id: int
    amount: Decimal
    type: str
    patient_id: Optional[int] = None
    description: str
    doctor_name: Optional[str] = None
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class FinancialTransactionResponse(BaseModel):
    id: int
    patient_id: Optional[int] = None
    doctor_name: Optional[str] = None
    amount: Decimal
    type: str
    description: str
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class FinancialTransactionUpdate(BaseModel):
    amount: float
    description: str


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


def require_premium_user_by_email(db: Session, doctor_email: str | None) -> models.User:
    normalized_email = (doctor_email or "").strip().lower()
    if not normalized_email:
        raise HTTPException(status_code=401, detail="Doctor email header is required")

    user = db.query(models.User).filter(models.User.email == normalized_email).first()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")

    if user.tier != "premium":
        raise HTTPException(
            status_code=403,
            detail="هذه الميزة المحاسبية المتقدمة لإدارة المستودع متاحة حصرياً للباقة الفخمة (Premium).",
        )

    ensure_user_subscription_is_active(user, db)
    return user


def get_current_doctor_user(
    db: Session,
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
) -> models.User:
    normalized_email = (doctor_email or "").strip().lower()
    if not normalized_email:
        auth_value = (authorization or "").strip()
        if auth_value.lower().startswith("bearer "):
            auth_value = auth_value[7:].strip()
        normalized_email = auth_value.lower()

    if not normalized_email:
        raise HTTPException(status_code=401, detail="Doctor email header is required")

    user = db.query(models.User).filter(models.User.email == normalized_email).first()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")

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


@app.post("/api/auth/register")
def register_user(register_request: RegisterRequest, db: Session = Depends(database.get_db)):
    try:
        normalized_email = register_request.email.strip().lower()
        activation_code = register_request.activation_code.strip()

        if not normalized_email:
            raise HTTPException(status_code=400, detail="البريد الإلكتروني مطلوب.")

        activation_key = (
            db.query(models.ActivationKey)
            .filter(models.ActivationKey.key_code == activation_code)
            .first()
        )

        if not activation_key or activation_key.is_used:
            raise HTTPException(
                status_code=400,
                detail="كود التفعيل خاطئ، منتهي، أو تم استخدامه مسبقاً! يرجى التواصل مع المهندس فارس حلاوي لشراء كود جديد.",
            )

        user_tier = (
            "premium"
            if (
                activation_key.duration_days >= 365
                or "-Y-" in activation_code.upper()
                or "PREMIUM" in activation_code.upper()
                or "VIP" in activation_code.upper()
                or activation_code.upper().startswith("PRM-")
            )
            else "standard"
        )

        existing_user = db.query(models.User).filter(models.User.email == normalized_email).first()
        if existing_user:
            raise HTTPException(status_code=400, detail="هذا البريد الإلكتروني مُسجل مسبقًا.")

        subscription_expires_at = datetime.utcnow() + timedelta(days=activation_key.duration_days)

        new_user = models.User(
            doctor_name=register_request.doctor_name,
            email=normalized_email,
            hashed_password=register_request.password,
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
            "token": "secure-session-token",
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
        
    # 3. التحقق الصارم من تطابق كلمة المرور (سواء كانت مشفرة أو نصية حسب نظامك الحالي)
    # ملاحظة: إذا كنت تستخدم التشفير استبدل هذا بالدالة المعتمدة لديك، وإلا فالنص المباشر هو الحاسم:
    if user.hashed_password != login_request.password:
        raise HTTPException(status_code=401, detail="البريد الإلكتروني أو كلمة المرور غير صحيحة!")
        
    try:
        # 4. العبور المحاسبي الآمن وإرجاع قاموس JSON صافي ومطابق 100% للـ Frontend
        return {
            "status": "success",
            "email": user.email,
            "tier": user.tier or "standard"
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
        token="secure-session-token",
        doctor_name=user.doctor_name,
        email=user.email,
        tier=user.tier or "standard",
        subscription_active=True,
    )


@app.post("/api/auth/upgrade-tier")
def upgrade_user_tier(upgrade_request: UpgradeTierRequest, db: Session = Depends(database.get_db)):
    activation_code = upgrade_request.activation_code.strip()
    normalized_email = (upgrade_request.email or "").strip().lower()
    doctor_name = (upgrade_request.doctor_name or "").strip()

    if not activation_code:
        raise HTTPException(status_code=400, detail="كود الترقية مطلوب.")

    activation_key = (
        db.query(models.ActivationKey)
        .filter(models.ActivationKey.key_code == activation_code)
        .first()
    )

    if not activation_key or activation_key.is_used:
        raise HTTPException(status_code=400, detail="كود الترقية غير صالح أو مستخدم مسبقاً.")

    is_premium_key = (
        activation_key.duration_days >= 365
        or "PREMIUM" in activation_code.upper()
        or "VIP" in activation_code.upper()
    )
    if not is_premium_key:
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

    resolved_doctor_name = (patient.doctor_name or "").strip()
    if not resolved_doctor_name:
        resolved_doctor_name = (current_user.doctor_name or current_user.email or "").strip()

    db_patient = models.Patient(
        doctor_name=resolved_doctor_name or None,
        full_name=patient.full_name,
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


# 5. مسار جلب قائمة جميع المرضى المخزنين في العيادة [GET]
@app.get("/api/patients", response_model=List[PatientResponse])
def get_all_patients(
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    authorization: str | None = Header(default=None, alias="Authorization"),
    db: Session = Depends(database.get_db),
):
    user = require_active_doctor_user(db=db, doctor_email=doctor_email, authorization=authorization)
    doctor_name = (user.doctor_name or "").strip()
    if not doctor_name:
        doctor_name = user.email

    doctor_identifiers = {doctor_name, user.email}

    linked_patients = (
        db.query(models.Patient)
        .filter(models.Patient.doctor_name.in_(doctor_identifiers))
        .all()
    )
    patients = linked_patients
    if not patients:
        patients = (
            db.query(models.Patient)
            .filter(models.Patient.doctor_name.is_(None))
            .all()
        )

    patient_ids = [patient.id for patient in patients]
    paid_amount_by_patient_id: dict[int, Decimal] = {}

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

    response_payload: list[dict] = []
    for patient in patients:
        paid_amount = paid_amount_by_patient_id.get(patient.id, Decimal("0"))
        if paid_amount < 0:
            paid_amount = Decimal("0")

        response_payload.append(
            {
                "id": patient.id,
                "doctor_name": patient.doctor_name,
                "doctor_email": None,
                "full_name": patient.full_name,
                "phone": patient.phone,
                "birth_date": patient.birth_date,
                "gender": patient.gender,
                "medical_history": patient.medical_history,
                "total_treatment_cost": float(getattr(patient, "total_treatment_cost", 0) or 0),
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
    doctor_name = (user.doctor_name or "").strip()
    if not doctor_name:
        doctor_name = user.email

    doctor_identifiers = {doctor_name, user.email}

    linked_patients = (
        db.query(models.Patient)
        .filter(models.Patient.doctor_name.in_(doctor_identifiers))
        .all()
    )
    patients = linked_patients
    if not patients:
        legacy_patients = (
            db.query(models.Patient)
            .filter(models.Patient.doctor_name.is_(None))
            .all()
        )
        patients = legacy_patients

    # Step 1: Safe patient ID extraction -- only IDs of patients that are
    # currently active and actually belong to this doctor (or are legacy
    # unassigned patients). Any patient_id NOT in this list (e.g. an
    # orphaned financial_transactions row left behind by a deleted patient)
    # can never contribute to the sums below.
    patient_ids = [patient.id for patient in patients]

    try:
        patient_names = {
            (patient.full_name or "").strip().lower(): patient.id
            for patient in patients
            if (patient.full_name or "").strip()
        }

        now = datetime.utcnow()
        active_appointments = 0
        if patient_names:
            appointments = db.query(models.Appointment).all()
            for appointment in appointments:
                appointment_patient_name = (appointment.patient_name or "").strip().lower()
                if appointment_patient_name not in patient_names:
                    continue

                appointment_status = (appointment.status or "").strip().lower()
                appointment_date = appointment.appointment_date
                is_upcoming = appointment_date is not None and appointment_date >= now
                is_pending = appointment_status in {"pending", "upcoming"}

                if is_upcoming or is_pending:
                    active_appointments += 1

        pending_balances = Decimal("0.00")
        if patient_ids:
            # Step 2: In-list transaction filtering -- only sum transaction
            # rows whose patient_id is inside our verified active array.
            received_rows = (
                db.query(
                    models.FinancialTransaction.patient_id,
                    func.coalesce(func.sum(models.FinancialTransaction.amount), 0).label("total_received"),
                )
                .filter(models.FinancialTransaction.patient_id.in_(patient_ids))
                .filter(models.FinancialTransaction.type.in_(["income", "received"]))
                .filter(models.FinancialTransaction.amount > 0)
                .group_by(models.FinancialTransaction.patient_id)
                .all()
            )
            received_by_patient_id = {
                patient_id: Decimal(str(total_received or 0))
                for patient_id, total_received in received_rows
                if patient_id is not None
            }

            for patient in patients:
                total_treatment_cost = Decimal(str(getattr(patient, "total_treatment_cost", 0) or 0))
                if total_treatment_cost < 0:
                    total_treatment_cost = Decimal("0")

                total_received = received_by_patient_id.get(patient.id, Decimal("0"))
                if total_received < 0:
                    total_received = Decimal("0")

                # Prevent overpayments or corrupted values from creating negative debt.
                patient_net_debt = max(total_treatment_cost - total_received, Decimal("0"))
                pending_balances += patient_net_debt

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
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    try:
        patient_id_int = int(patient_id)
    except (TypeError, ValueError):
        raise HTTPException(status_code=404, detail="المريض غير موجود")

    try:
        patient = db.query(models.Patient).filter(models.Patient.id == patient_id_int).first()
    except Exception:
        raise HTTPException(status_code=404, detail="المريض غير موجود")

    if not patient:
        raise HTTPException(status_code=404, detail="المريض غير موجود")

    return patient


@app.delete("/api/patients/{patient_id}")
def delete_patient(
    patient_id: int,
    db: Session = Depends(database.get_db),
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    try:
        db.query(models.Visit).filter(models.Visit.patient_id == patient_id).delete(synchronize_session=False)
        db.query(models.Treatment).filter(models.Treatment.patient_id == patient_id).delete(synchronize_session=False)
        db.delete(patient)
        db.commit()
    except Exception:
        db.rollback()
        raise

    return {"message": "Patient deleted successfully"}


@app.put("/api/patients/{patient_id}", response_model=PatientResponse)
def update_patient(
    patient_id: int,
    patient_update: PatientUpdate,
    db: Session = Depends(database.get_db),
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
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
        if patient_update.total_treatment_cost is not None:
            patient.total_treatment_cost = max(float(patient_update.total_treatment_cost), 0.0)

        db.commit()
        db.refresh(patient)
    except Exception:
        db.rollback()
        raise

    return patient


@app.put("/api/patients/{patient_id}/chart", response_model=PatientResponse)
def update_patient_chart(
    patient_id: int,
    chart_update: PatientChartUpdate,
    db: Session = Depends(database.get_db),
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
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
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    patient = db.query(models.Patient).filter(models.Patient.id == appointment.patient_id).first()
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
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    appointment = db.query(models.Appointment).filter(models.Appointment.id == appointment_id).first()
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
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    appointment = db.query(models.Appointment).filter(models.Appointment.id == appointment_id).first()
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


@app.delete("/api/appointments/{appointment_id}", status_code=200)
def delete_appointment(
    appointment_id: int,
    db: Session = Depends(database.get_db),
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    appointment = db.query(models.Appointment).filter(models.Appointment.id == appointment_id).first()
    if not appointment:
        raise HTTPException(status_code=404, detail="الموعد غير موجود")

    try:
        db.delete(appointment)
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر حذف الموعد حالياً. حاول مرة أخرى.")

    return {"message": "تم حذف الموعد بنجاح"}


# 7. مسار لجلب قائمة بجميع المواعيد المحجوزة [GET]
@app.get("/api/appointments", response_model=List[AppointmentResponse])
def get_all_appointments(
    db: Session = Depends(database.get_db),
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    return db.query(models.Appointment).all()


# 8. مسار لتسجيل زيارة علاجية جديدة لمريض مع تفاصيل الأسنان [POST]
@app.post("/api/visits", response_model=VisitResponse)
def create_visit(
    visit: VisitCreate,
    db: Session = Depends(database.get_db),
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    patient = db.query(models.Patient).filter(models.Patient.id == visit.patient_id).first()
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
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    patient = db.query(models.Patient).filter(models.Patient.id == treatment.patient_id).first()
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
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    if expense.amount <= 0:
        raise HTTPException(status_code=400, detail="قيمة المصروف يجب أن تكون أكبر من صفر.")

    description = expense.description.strip()
    if not description:
        raise HTTPException(status_code=400, detail="وصف المصروف مطلوب.")

    transaction_type = expense.type.strip().lower()
    if transaction_type not in {"income", "expense"}:
        raise HTTPException(status_code=400, detail="نوع العملية يجب أن يكون income أو expense.")

    if expense.patient_id is not None:
        patient = db.query(models.Patient).filter(models.Patient.id == expense.patient_id).first()
        if not patient:
            raise HTTPException(status_code=404, detail="Patient not found")

    try:
        db_expense = models.FinancialTransaction(
            patient_id=expense.patient_id,
            doctor_name=expense.doctor_name,
            amount=expense.amount,
            type=transaction_type,
            description=description,
        )
        db.add(db_expense)
        db.commit()
        db.refresh(db_expense)
        return db_expense
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر حفظ المصروف حالياً. حاول مرة أخرى.")


@app.get("/api/finance/summary")
def get_finance_summary(
    db: Session = Depends(database.get_db),
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    total_income = (
        db.query(func.coalesce(func.sum(models.FinancialTransaction.amount), 0))
        .filter(models.FinancialTransaction.type == "income")
        .scalar()
    )
    total_expenses = (
        db.query(func.coalesce(func.sum(models.FinancialTransaction.amount), 0))
        .filter(models.FinancialTransaction.type == "expense")
        .scalar()
    )

    income_value = Decimal(total_income or 0)
    expenses_value = Decimal(total_expenses or 0)
    net_profit = income_value - expenses_value

    return {
        "total_income": float(income_value),
        "total_expenses": float(expenses_value),
        "net_profit": float(net_profit),
        "total_revenue": float(income_value),
    }


@app.get("/api/finance/patient/{patient_id}", response_model=List[FinancialTransactionResponse])
def get_patient_financial_transactions(
    patient_id: int,
    db: Session = Depends(database.get_db),
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    return (
        db.query(models.FinancialTransaction)
        .filter(models.FinancialTransaction.patient_id == patient_id)
        .filter(models.FinancialTransaction.type == "income")
        .order_by(models.FinancialTransaction.created_at.desc())
        .all()
    )


@app.put("/api/finance/transaction/{transaction_id}", status_code=200)
def update_financial_transaction(
    transaction_id: int,
    transaction_update: FinancialTransactionUpdate,
    db: Session = Depends(database.get_db),
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    transaction = (
        db.query(models.FinancialTransaction)
        .filter(models.FinancialTransaction.id == transaction_id)
        .first()
    )
    if not transaction:
        raise HTTPException(status_code=404, detail="الدفعة المالية غير موجودة")

    description = transaction_update.description.strip()
    if not description:
        raise HTTPException(status_code=400, detail="وصف الدفعة مطلوب")
    if transaction_update.amount <= 0:
        raise HTTPException(status_code=400, detail="قيمة الدفعة يجب أن تكون أكبر من صفر")

    try:
        transaction.amount = Decimal(str(transaction_update.amount))
        transaction.description = description
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
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    transaction = (
        db.query(models.FinancialTransaction)
        .filter(models.FinancialTransaction.id == transaction_id)
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
    doctor_identifiers = {doctor_name, user.email}

    patients = (
        db.query(models.Patient)
        .filter(models.Patient.doctor_name.in_(doctor_identifiers))
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
        .filter(models.FinancialTransaction.doctor_name.in_(doctor_identifiers))
        .order_by(models.FinancialTransaction.created_at.asc(), models.FinancialTransaction.id.asc())
        .all()
    )

    appointments = db.query(models.Appointment).order_by(models.Appointment.id.asc()).all()
    filtered_appointments = [
        appointment
        for appointment in appointments
        if (appointment.patient_name or "").strip().lower() in patient_name_to_id
    ]

    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow([
        "record_type",
        "record_id",
        "patient_id",
        "patient_name",
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


@app.post("/api/prescriptions", response_model=PrescriptionResponse, status_code=201)
def create_prescription(
    prescription: PrescriptionCreate,
    db: Session = Depends(database.get_db),
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    patient = db.query(models.Patient).filter(models.Patient.id == prescription.patient_id).first()
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
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
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
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    prescription = db.query(models.Prescription).filter(models.Prescription.id == prescription_id).first()
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
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    prescription = db.query(models.Prescription).filter(models.Prescription.id == prescription_id).first()
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
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    db: Session = Depends(database.get_db),
):
    user = require_premium_user_by_email(db, doctor_email)

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
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    db: Session = Depends(database.get_db),
):
    user = require_premium_user_by_email(db, doctor_email)

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
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    db: Session = Depends(database.get_db),
):
    user = require_premium_user_by_email(db, doctor_email)

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
    doctor_email: str | None = Header(default=None, alias="X-Doctor-Email"),
    db: Session = Depends(database.get_db),
):
    user = require_premium_user_by_email(db, doctor_email)

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


@app.get("/api/patients/{patient_id}/treatments", response_model=List[TreatmentResponse])
def get_patient_treatments(
    patient_id: int,
    db: Session = Depends(database.get_db),
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
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
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
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
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
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
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
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
    _activation_gate: models.User = Depends(require_active_doctor_user),
):
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
    activation_key = (
        db.query(models.ActivationKey)
        .filter(models.ActivationKey.key_code == activation_code)
        .first()
    )
    if not activation_key or activation_key.is_used:
        raise HTTPException(status_code=400, detail="كود التفعيل خاطئ، منتهي، أو تم استخدامه مسبقاً!")

    # نُفضّل عمود intended_tier الصريح إن وُجد (كل أكواد التجديد الشهرية
    # الجديدة التي يولّدها /api/admin/renewal-keys/generate تضبطه دائماً) --
    # ونلجأ فقط للتخمين النصي القديم كخط رجوع للأكواد الثابتة القديمة التي لا
    # تملك هذا العمود. هذا يصلح خللاً كامناً حقيقياً: كود شهري بصيغة "PM-...."
    # مدته 30 يوماً فقط، فكان سيُصنَّف خطأً كـ"standard" تحت الشرط القديم
    # (duration_days >= 365) لولا هذا التفضيل.
    explicit_tier = (getattr(activation_key, "intended_tier", None) or "").strip().lower()
    if explicit_tier in ("premium", "standard"):
        target_tier = explicit_tier
    else:
        target_tier = (
            "premium"
            if (
                activation_key.duration_days >= 365
                or "PREMIUM" in activation_code.upper()
                or "VIP" in activation_code.upper()
            )
            else "standard"
        )

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
                    .filter(models.ActivationKey.key_code == candidate_code)
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


@app.get("/", include_in_schema=False)
def redirect_to_login():
    return RedirectResponse(url="/login.html", status_code=302)

app.mount("/uploads", StaticFiles(directory=UPLOADS_DIR), name="uploads")
app.mount("/", StaticFiles(directory="frontend_web", html=True), name="static")

if __name__ == "__main__":
    # قراءة المنفذ ديناميكياً من بيئة Render العالمية، وإلا استخدام 8090 كبديل محلي
    port = int(os.environ.get("PORT", 8090))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=False)