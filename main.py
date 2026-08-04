from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel, Field, ConfigDict
from datetime import date, datetime, timedelta
from decimal import Decimal
import os
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token
import models
import database

app = FastAPI(title="Dental Clinic API")

# 1. تشغيل السيرفر وإنشاء الجداول تلقائياً عند الإقلاع
database.init_db()


def seed_default_activation_key() -> None:
    db = database.SessionLocal()
    try:
        existing_key = db.query(models.ActivationKey).filter(
            models.ActivationKey.key_code == "FARAS-30DAYS-2026"
        ).first()
        if existing_key is None:
            new_key = models.ActivationKey(
                key_code="FARAS-30DAYS-2026",
                duration_days=30,
                is_used=False,
            )
            db.add(new_key)
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


class PatientResponse(PatientCreate):
    id: int
    model_config = ConfigDict(from_attributes=True)


class AppointmentCreate(BaseModel):
    patient_name: Optional[str] = None
    appointment_time: Optional[str] = None
    procedure_type: Optional[str] = None
    status: str = "Pending"
    patient_id: Optional[int] = None
    appointment_date: Optional[datetime] = None
    notes: Optional[str] = None


class AppointmentResponse(BaseModel):
    id: int
    patient_name: Optional[str] = None
    appointment_time: Optional[str] = None
    procedure_type: Optional[str] = None
    status: str
    patient_id: Optional[int] = None
    appointment_date: Optional[datetime] = None
    notes: Optional[str] = None
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
    tier: str
    subscription_active: bool


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
    normalized_email = register_request.email.strip().lower()
    activation_code = register_request.activation_code.strip()
    user_tier = "premium" if "-Y-" in activation_code.upper() else "standard"

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

    try:
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
    except Exception:
        db.rollback()
        raise

    return {
        "message": "تم إنشاء الحساب بنجاح.",
        "doctor_name": new_user.doctor_name,
        "email": new_user.email,
        "subscription_expires_at": subscription_expires_at.isoformat(),
    }


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
        tier=user.tier or "standard",
        subscription_active=True,
    )


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


# 6. مسار لحجز موعد جديد لمريض [POST]
@app.post("/api/appointments", response_model=AppointmentResponse)
def create_appointment(appointment: AppointmentCreate, db: Session = Depends(database.get_db)):
    if appointment.patient_id is not None:
        patient = db.query(models.Patient).filter(models.Patient.id == appointment.patient_id).first()
        if not patient:
            raise HTTPException(status_code=404, detail="Patient not found")

    db_appointment = models.Appointment(
        patient_name=appointment.patient_name or "",
        appointment_time=appointment.appointment_time or "",
        procedure_type=appointment.procedure_type or "",
        status=appointment.status,
    )
    db.add(db_appointment)
    db.commit()
    db.refresh(db_appointment)
    return db_appointment


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


@app.get("/api/patients/{patient_id}/treatments", response_model=List[TreatmentResponse])
def get_patient_treatments(patient_id: int, db: Session = Depends(database.get_db)):
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    return db.query(models.Treatment).filter(models.Treatment.patient_id == patient_id).all()


@app.get("/", include_in_schema=False)
def redirect_to_login():
    return RedirectResponse(url="/login.html", status_code=302)

app.mount("/", StaticFiles(directory="frontend_web", html=True), name="static")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8080, reload=True)
