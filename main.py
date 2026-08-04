from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text, func
from sqlalchemy.orm import Session
from typing import List, Optional
import json
from pydantic import BaseModel, Field, ConfigDict
from datetime import date, datetime, timedelta
from decimal import Decimal
import os
from uuid import uuid4
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token
import models
import database

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
            db.execute(
                text(
                    """
                    INSERT OR IGNORE INTO activation_keys (key_code, duration_days, is_used, used_by_email)
                    VALUES (:key_code, :duration_days, 0, NULL)
                    """
                ),
                {
                    "key_code": key_code,
                    "duration_days": duration_days,
                },
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


class PatientResponse(PatientCreate):
    id: int
    chart_state: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)


class AppointmentCreate(BaseModel):
    patient_name: Optional[str] = None
    appointment_date: Optional[datetime] = None
    appointment_time: Optional[str] = None
    procedure_type: Optional[str] = None
    notes: Optional[str] = None
    status: str = "Pending"
    patient_id: Optional[int] = None


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

    chart_state = chart_update.chart_state
    if isinstance(chart_state, str):
        chart_state_value = chart_state.strip()
        if not chart_state_value:
            raise HTTPException(status_code=400, detail="Chart state cannot be empty")
    else:
        chart_state_value = json.dumps(chart_state, ensure_ascii=False)

    try:
        patient.chart_state = chart_state_value
        db.commit()
        db.refresh(patient)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر حفظ حالة المخطط السني حالياً. حاول مرة أخرى.")

    return patient


# 6. مسار لحجز موعد جديد لمريض [POST]
@app.post("/api/appointments", response_model=AppointmentResponse)
def create_appointment(appointment: AppointmentCreate, db: Session = Depends(database.get_db)):
    if appointment.patient_id is not None:
        patient = db.query(models.Patient).filter(models.Patient.id == appointment.patient_id).first()
        if not patient:
            raise HTTPException(status_code=404, detail="Patient not found")

    db_appointment = models.Appointment(
        patient_name=appointment.patient_name or "",
        appointment_date=appointment.appointment_date,
        appointment_time=appointment.appointment_time or "",
        procedure_type=appointment.procedure_type or "",
        notes=appointment.notes,
        status=appointment.status,
    )
    db.add(db_appointment)
    db.commit()
    db.refresh(db_appointment)
    return db_appointment


@app.put("/api/appointments/{appointment_id}", response_model=AppointmentResponse)
def update_appointment(appointment_id: int, appointment_update: AppointmentUpdate, db: Session = Depends(database.get_db)):
    appointment = db.query(models.Appointment).filter(models.Appointment.id == appointment_id).first()
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")

    try:
        if appointment_update.appointment_date is not None:
            appointment.appointment_date = appointment_update.appointment_date
        if appointment_update.appointment_time is not None:
            appointment.appointment_time = appointment_update.appointment_time.strip()
        if appointment_update.description is not None:
            appointment.notes = appointment_update.description.strip()

        db.commit()
        db.refresh(appointment)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=400, detail="تعذر تحديث الموعد حالياً. حاول مرة أخرى.")

    return appointment


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
    import uvicorn
    port = int(os.environ.get("PORT", 8090))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
