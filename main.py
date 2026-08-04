from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text, func
from sqlalchemy.orm import Session
from typing import List, Optional
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

app = FastAPI(title="Dental Clinic API")

# 1. تشغيل السيرفر وإنشاء الجداول تلقائياً عند الإقلاع
database.init_db()

UPLOADS_DIR = "uploads"
os.makedirs(UPLOADS_DIR, exist_ok=True)


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


seed_default_activation_key()

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
    full_name: str
    phone: str
    birth_date: date = None
    gender: str = None
    medical_history: Optional[str] = None


class PatientUpdate(BaseModel):
    doctor_name: Optional[str] = None
    full_name: Optional[str] = None
    phone: Optional[str] = None
    medical_history: Optional[str] = None


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
    image_url: str
    description: Optional[str] = None
    uploaded_at: datetime
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


def ensure_user_subscription_is_active(user: models.User) -> None:
    now = datetime.utcnow()
    subscription_expired = (
        user.subscription_expires_at is not None
        and user.subscription_expires_at < now
    )

    if not user.is_active or subscription_expired:
        raise HTTPException(
            status_code=403,
            detail="عذراً، انتهت مدة الاشتراك السنوية. يرجى التواصل مع المهندس فارس حلاوي للتجديد ودفع الاشتراك.",
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

    ensure_user_subscription_is_active(user)
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


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.post("/api/auth/register")
def register_user(register_request: RegisterRequest, db: Session = Depends(database.get_db)):
    try:
        normalized_email = register_request.email.strip().lower()
        activation_code = register_request.activation_code.strip()
        user_tier = (
            "premium"
            if (
                "-Y-" in activation_code.upper()
                or "PREMIUM" in activation_code.upper()
                or "VIP" in activation_code.upper()
            )
            else "standard"
        )

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


@app.post("/api/auth/login", response_model=LoginResponse)
def login_user(login_request: LoginRequest, db: Session = Depends(database.get_db)):
    normalized_email = login_request.email.strip().lower()

    if not normalized_email:
        raise HTTPException(status_code=401, detail="البريد الإلكتروني أو كلمة المرور غير صحيحة!")

    user = db.query(models.User).filter(models.User.email == normalized_email).first()

    if not user:
        raise HTTPException(status_code=401, detail="البريد الإلكتروني أو كلمة المرور غير صحيحة!")

    if user.hashed_password != login_request.password:
        raise HTTPException(status_code=401, detail="البريد الإلكتروني أو كلمة المرور غير صحيحة!")

    ensure_user_subscription_is_active(user)

    return LoginResponse(
        token="secure-session-token",
        doctor_name=user.doctor_name,
        email=user.email,
        tier=user.tier or "standard",
        subscription_active=True,
    )


@app.post("/api/auth/google-login", response_model=LoginResponse)
def google_login(login_request: GoogleLoginRequest, db: Session = Depends(database.get_db)):
    google_client_id = os.getenv("GOOGLE_CLIENT_ID", "").strip()
    if not google_client_id:
        raise HTTPException(
            status_code=503,
            detail="Google Sign-In is not configured on the server. Missing GOOGLE_CLIENT_ID.",
        )

    credential = login_request.credential.strip()
    if not credential:
        raise HTTPException(status_code=400, detail="Google credential is required.")

    try:
        token_payload = id_token.verify_oauth2_token(
            credential,
            google_requests.Request(),
            google_client_id,
        )
    except Exception:
        raise HTTPException(status_code=401, detail="تعذر التحقق من حساب Google.")

    if not token_payload.get("email_verified"):
        raise HTTPException(status_code=401, detail="بريد Google غير موثق.")

    email = str(token_payload.get("email", "")).strip().lower()
    if not email:
        raise HTTPException(status_code=401, detail="تعذر قراءة البريد من حساب Google.")

    user = db.query(models.User).filter(models.User.email == email).first()
    if not user:
        raise HTTPException(status_code=401, detail="لا يوجد حساب مفعل بهذا البريد داخل النظام.")

    ensure_user_subscription_is_active(user)

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
def create_patient(patient: PatientCreate, db: Session = Depends(database.get_db)):
    db_patient = models.Patient(
        doctor_name=patient.doctor_name,
        full_name=patient.full_name,
        phone=patient.phone,
        birth_date=patient.birth_date if patient.birth_date else None,
        gender=patient.gender if patient.gender else "Male",
        medical_history=patient.medical_history
    )
    db.add(db_patient)
    db.commit()
    db.refresh(db_patient)
    return db_patient


# 5. مسار جلب قائمة جميع المرضى المخزنين في العيادة [GET]
@app.get("/api/patients", response_model=List[PatientResponse])
def get_all_patients(db: Session = Depends(database.get_db)):
    return db.query(models.Patient).all()


@app.get("/api/patients/{patient_id}", response_model=PatientResponse)
def get_patient(patient_id: str, db: Session = Depends(database.get_db)):
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
def delete_patient(patient_id: int, db: Session = Depends(database.get_db)):
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
def update_patient(patient_id: int, patient_update: PatientUpdate, db: Session = Depends(database.get_db)):
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

        db.commit()
        db.refresh(patient)
    except Exception:
        db.rollback()
        raise

    return patient


@app.put("/api/patients/{patient_id}/chart", response_model=PatientResponse)
def update_patient_chart(patient_id: int, chart_update: PatientChartUpdate, db: Session = Depends(database.get_db)):
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
def create_appointment(appointment: AppointmentCreate, db: Session = Depends(database.get_db)):
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
        status=(appointment.status or "Pending").strip() or "Pending",
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
def update_appointment(appointment_id: int, appointment_update: AppointmentUpdate, db: Session = Depends(database.get_db)):
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


@app.delete("/api/appointments/{appointment_id}", status_code=200)
def delete_appointment(appointment_id: int, db: Session = Depends(database.get_db)):
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
def get_all_appointments(db: Session = Depends(database.get_db)):
    return db.query(models.Appointment).all()


# 8. مسار لتسجيل زيارة علاجية جديدة لمريض مع تفاصيل الأسنان [POST]
@app.post("/api/visits", response_model=VisitResponse)
def create_visit(visit: VisitCreate, db: Session = Depends(database.get_db)):
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
def create_treatment(treatment: TreatmentCreate, db: Session = Depends(database.get_db)):
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
def create_expense(expense: ExpenseCreate, db: Session = Depends(database.get_db)):
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
def get_finance_summary(db: Session = Depends(database.get_db)):
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
def get_patient_financial_transactions(patient_id: int, db: Session = Depends(database.get_db)):
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
    user = get_current_doctor_user(db, doctor_email=doctor_email, authorization=authorization)
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
def create_prescription(prescription: PrescriptionCreate, db: Session = Depends(database.get_db)):
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
def get_patient_prescriptions(patient_id: int, db: Session = Depends(database.get_db)):
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    return (
        db.query(models.Prescription)
        .filter(models.Prescription.patient_id == patient_id)
        .order_by(models.Prescription.created_at.desc())
        .all()
    )


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


@app.get("/api/patients/{patient_id}/treatments", response_model=List[TreatmentResponse])
def get_patient_treatments(patient_id: int, db: Session = Depends(database.get_db)):
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    return db.query(models.Treatment).filter(models.Treatment.patient_id == patient_id).all()


@app.post("/api/patients/{patient_id}/xrays", response_model=PatientXRayResponse)
async def upload_patient_xray(
    patient_id: int,
    file: UploadFile = File(...),
    description: str = Form(""),
    db: Session = Depends(database.get_db),
):
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    original_name = file.filename or "xray"
    _, ext = os.path.splitext(original_name)
    ext = ext.lower()
    allowed_ext = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".tiff"}
    safe_ext = ext if ext in allowed_ext else ".bin"
    unique_filename = f"xray_{patient_id}_{uuid4().hex}{safe_ext}"
    saved_path = os.path.join(UPLOADS_DIR, unique_filename)

    try:
        content = await file.read()
        with open(saved_path, "wb") as output_file:
            output_file.write(content)

        db_xray = models.PatientXRay(
            patient_id=patient_id,
            image_url=f"/uploads/{unique_filename}",
            description=description.strip() or None,
        )
        db.add(db_xray)
        db.commit()
        db.refresh(db_xray)
        return db_xray
    except Exception:
        db.rollback()
        if os.path.exists(saved_path):
            try:
                os.remove(saved_path)
            except OSError:
                pass
        raise HTTPException(status_code=400, detail="تعذر رفع صورة الأشعة حالياً. حاول مرة أخرى.")
    finally:
        await file.close()


@app.get("/api/patients/{patient_id}/xrays", response_model=List[PatientXRayResponse])
def get_patient_xrays(patient_id: int, db: Session = Depends(database.get_db)):
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    return (
        db.query(models.PatientXRay)
        .filter(models.PatientXRay.patient_id == patient_id)
        .order_by(models.PatientXRay.uploaded_at.desc())
        .all()
    )


@app.get("/", include_in_schema=False)
def redirect_to_login():
    return RedirectResponse(url="/login.html", status_code=302)

app.mount("/uploads", StaticFiles(directory=UPLOADS_DIR), name="uploads")
app.mount("/", StaticFiles(directory="frontend_web", html=True), name="static")

if __name__ == "__main__":
    # قراءة المنفذ ديناميكياً من بيئة Render العالمية، وإلا استخدام 8090 كبديل محلي
    port = int(os.environ.get("PORT", 8090))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=False)
