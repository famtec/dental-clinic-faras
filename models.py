from sqlalchemy import Boolean, Column, Integer, String, Date, DateTime, Numeric, Float, ForeignKey, Text, text
from sqlalchemy.orm import relationship
from datetime import datetime
from database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    doctor_name = Column(String, nullable=True)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    # افتراضي آمن: أي مستخدم يُنشأ دون تحديد صريح لقيمة tier (سواء في مسار حالي
    # لم يمرّ عليه المراجعة، أو مسار جديد يُضاف لاحقاً وينسى تمرير tier=...) يجب أن
    # يبدأ بلا أي صلاحية مدفوعة، وليس بباقة "standard" مجانية ضمنياً.
    tier = Column(String, default="pending_activation", nullable=False)
    subscription_expires_at = Column(DateTime, nullable=True)
    is_active = Column(Boolean, default=True, nullable=False)
    # حقول بيانات حساب الطبيب/العيادة لصفحة "حسابي" (أُضيفت 2026-08-23):
    clinic_name = Column(String, nullable=True)
    clinic_address = Column(String, nullable=True)
    avatar_url = Column(String, nullable=True)


class ActivationKey(Base):
    __tablename__ = "activation_keys"

    id = Column(Integer, primary_key=True, index=True)
    key_code = Column(String, unique=True, index=True, nullable=False)
    duration_days = Column(Integer, default=30, nullable=False)
    is_used = Column(Boolean, default=False, nullable=False)
    used_by_email = Column(String, nullable=True)
    # الرتبة الصريحة المقصودة لهذا الكود ("premium" أو "standard")، تُضبط دائماً
    # عند توليد أكواد التجديد الشهرية الجديدة عبر /api/admin/renewal-keys/generate.
    # قد تكون NULL للأكواد الثابتة القديمة المزروعة يدوياً -- /api/activate يرجع
    # عندها لتخمين نصي احتياطي (duration_days/كلمات مفتاحية في الكود نفسه).
    intended_tier = Column(String, nullable=True)


class Patient(Base):
    __tablename__ = "patients"

    id = Column(Integer, primary_key=True, index=True)
    doctor_name = Column(String, nullable=True)
    full_name = Column(String, index=True)
    phone = Column(String, nullable=False)
    birth_date = Column(Date, nullable=True)
    gender = Column(String, nullable=True)
    medical_history = Column(String, nullable=True)
    total_treatment_cost = Column(Float, nullable=False, default=0.0, server_default=text("0.0"))
    chart_state = Column(Text, nullable=True)

    visits = relationship("Visit", back_populates="patient", cascade="all, delete-orphan")
    treatments = relationship("Treatment", back_populates="patient", cascade="all, delete-orphan")
    prescriptions = relationship("Prescription", back_populates="patient", cascade="all, delete-orphan")


class Appointment(Base):
    __tablename__ = "appointments"

    id = Column(Integer, primary_key=True, index=True)
    patient_name = Column(String, nullable=False)
    appointment_date = Column(DateTime, nullable=True)
    appointment_time = Column(String, nullable=False)
    procedure_type = Column(String, nullable=False)
    notes = Column(String, nullable=True)
    status = Column(String, nullable=False, default="pending", server_default=text("'pending'"))


class Visit(Base):
    __tablename__ = "visits"

    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=False)
    diagnosis = Column(String, nullable=False)
    total_cost = Column(Numeric(10, 2), nullable=False)
    amount_paid = Column(Numeric(10, 2), nullable=False)

    patient = relationship("Patient", back_populates="visits")


class Treatment(Base):
    __tablename__ = "treatments"

    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=False)
    tooth_number = Column(Integer, nullable=False)
    treatment_type = Column(String, nullable=False)
    notes = Column(String, nullable=True)
    color = Column(String, nullable=True)

    patient = relationship("Patient", back_populates="treatments")


class Expense(Base):
    __tablename__ = "expenses"

    id = Column(Integer, primary_key=True, index=True)
    doctor_name = Column(String, nullable=True)
    amount = Column(Numeric(12, 2), nullable=False)
    description = Column(String, nullable=False)
    created_at = Column(DateTime, nullable=False, server_default=text("CURRENT_TIMESTAMP"))


class FinancialTransaction(Base):
    __tablename__ = "financial_transactions"

    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=True)
    doctor_name = Column(String, nullable=True)
    amount = Column(Numeric(12, 2), nullable=False)
    type = Column(String, nullable=False, default="expense")
    description = Column(String, nullable=False)
    created_at = Column(DateTime, nullable=False, server_default=text("CURRENT_TIMESTAMP"))


class PatientXRay(Base):
    __tablename__ = "patient_xrays"

    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), index=True, nullable=False)
    image_url = Column(String, nullable=False)
    file_name = Column(String, nullable=True)
    file_url = Column(String, nullable=True)
    description = Column(String, nullable=True)
    file_type = Column(String, nullable=True)
    uploaded_at = Column(DateTime, default=datetime.utcnow, nullable=False)


class Prescription(Base):
    __tablename__ = "prescriptions"

    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), index=True, nullable=False)
    medications = Column(Text, nullable=False)
    instructions = Column(Text, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    patient = relationship("Patient", back_populates="prescriptions")


class InventoryItem(Base):
    __tablename__ = "inventory_items"

    id = Column(Integer, primary_key=True, index=True)
    doctor_email = Column(String, index=True, nullable=False)
    item_name = Column(String, nullable=False)
    quantity = Column(Integer, nullable=False)
    min_alert_quantity = Column(Integer, default=5, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)