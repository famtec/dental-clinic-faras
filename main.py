from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel, Field, ConfigDict
from datetime import date, datetime
from decimal import Decimal
import models
import database

app = FastAPI(title="Dental Clinic API")

# 1. تشغيل السيرفر وإنشاء الجداول تلقائياً عند الإقلاع
database.init_db()

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
    full_name: str
    phone: str
    birth_date: date = None
    gender: str = None
    medical_history: str = None


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


class LoginResponse(BaseModel):
    token: str
    doctor_name: Optional[str] = None
    subscription_active: bool


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.post("/api/auth/login", response_model=LoginResponse)
def login_user(login_request: LoginRequest, db: Session = Depends(database.get_db)):
    user = db.query(models.User).filter(models.User.email == login_request.email).first()

    if not user:
        raise HTTPException(status_code=401, detail="البريد الإلكتروني أو كلمة المرور غير صحيحة!")

    if user.hashed_password != login_request.password:
        raise HTTPException(status_code=401, detail="البريد الإلكتروني أو كلمة المرور غير صحيحة!")

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

    return LoginResponse(
        token="secure-session-token",
        doctor_name=user.doctor_name,
        subscription_active=True,
    )


# 4. مسار إرسال (حفظ) مريض جديد في النظام [POST]
@app.post("/api/patients", response_model=PatientResponse)
def create_patient(patient: PatientCreate, db: Session = Depends(database.get_db)):
    db_patient = models.Patient(
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


@app.get("/")
def redirect_to_login():
    return RedirectResponse(url="/login.html")

app.mount("/", StaticFiles(directory="frontend_web", html=True), name="static")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8080, reload=True)
