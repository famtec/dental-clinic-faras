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
    # حقول صفحة الحجز العامة (public booking page) -- أُضيفت 2026-08-23:
    # كل طبيب يقدر يفعّل رابطاً عاماً خاصاً فيه (site.com/d/<booking_slug>)
    # يسمح لأي مريض بحجز موعد مباشرة بلا تسجيل دخول ولا اتصال هاتفي.
    clinic_phone = Column(String, nullable=True)  # رقم واتساب العيادة لاستقبال إشعارات الطلبات الجديدة
    booking_slug = Column(String, unique=True, index=True, nullable=True)
    public_booking_enabled = Column(Boolean, default=False, nullable=False, server_default=text("false"))
    work_days = Column(String, nullable=True)  # قائمة أرقام مفصولة بفواصل، Monday=0..Sunday=6 (نفس ترميز date.weekday())
    work_start_time = Column(String, nullable=True)  # "HH:MM"
    work_end_time = Column(String, nullable=True)  # "HH:MM"
    slot_duration_minutes = Column(Integer, nullable=False, default=30, server_default=text("30"))
    # رمز جهاز Firebase Cloud Messaging لتطبيق الطبيب على أندرويد (أُضيف 2026-08-24)
    # -- يُخزَّن هنا آخر توكن FCM سجّله تطبيق الطبيب بعد تسجيل الدخول (جهاز واحد
    # لكل طبيب حالياً، يُستبدل بالأحدث عند كل POST /api/auth/register-device)،
    # ويُستخدَم لإرسال إشعار Push فوري عند وصول طلب حجز جديد عبر صفحة الحجز
    # العامة. قيمة NULL تعني ببساطة أن التطبيق لم يُثبّت/يُفعّل بعد لهذا الطبيب.
    fcm_token = Column(String, nullable=True)


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
    # الحقل الرسمي (authoritative) لعزل بيانات كل طبيب عن غيره -- على عكس
    # doctor_name (نص قابل للتكرار بين أطباء مختلفين)، هذا البريد فريد لكل
    # حساب طبيب (users.email) ويُستخدم في كل استعلام قراءة/تعديل/حذف
    # للتحقق أن هذا المريض يخص هذا الطبيب فعلاً قبل السماح بالوصول (2026-08-23).
    doctor_email = Column(String, index=True, nullable=True)
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
    # فواتير العلاج المستقلة (2026-08-25) -- انظر شرح models.TreatmentInvoice
    # أدناه لسبب وجودها؛ cascade="all, delete-orphan" هنا للتناسق مع بقية
    # علاقات Patient، لكن main.py.delete_patient() يحذفها صراحة أيضاً عبر
    # bulk delete قبل حذف صف patients نفسه (لا يعتمد فقط على cascade الـ ORM)،
    # بنفس نمط الدرس المستفاد من قصة حذف المريض ثلاثية الطبقات الموثقة هناك.
    treatment_invoices = relationship("TreatmentInvoice", back_populates="patient", cascade="all, delete-orphan")


class Appointment(Base):
    __tablename__ = "appointments"

    id = Column(Integer, primary_key=True, index=True)
    # الحقل الرسمي لعزل مواعيد كل طبيب عن غيره (2026-08-23) -- انظر تعليق
    # Patient.doctor_email أعلاه لنفس المنطق.
    doctor_email = Column(String, index=True, nullable=True)
    patient_name = Column(String, nullable=False)
    appointment_date = Column(DateTime, nullable=True)
    appointment_time = Column(String, nullable=False)
    procedure_type = Column(String, nullable=False)
    notes = Column(String, nullable=True)
    status = Column(String, nullable=False, default="pending", server_default=text("'pending'"))
    # حقلان أُضيفا 2026-08-23 لمحرك تذكيرات واتساب التلقائية: patient_id يربط
    # الموعد بالمريض مباشرة (كان مفقوداً تماماً من قبل رغم أن create_appointment
    # يستقبله في الطلب -- لم يكن يُخزَّن على الإطلاق)، وreminder_sent يمنع إرسال
    # نفس تذكير الموعد أكثر من مرة واحدة.
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=True)
    reminder_sent = Column(Boolean, default=False, nullable=False, server_default=text("false"))
    # رقم هاتف صاحب طلب الحجز العام (2026-08-23) -- يُملأ فقط للمواعيد الناتجة
    # عن صفحة الحجز العامة (booking.html) قبل أي ربط بسجل مريض فعلي في النظام،
    # ويُستخدم لإرسال إشعار واتساب بقرار الطبيب (قبول/رفض) لهذا الطلب تحديداً.
    patient_phone = Column(String, nullable=True)


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


class TreatmentInvoice(Base):
    __tablename__ = "treatment_invoices"

    # فاتورة علاج مستقلة (2026-08-25) -- تحل مشكلة تداخل الحسابات التي كانت
    # تحدث سابقاً عندما تُحسب "التكلفة الإجمالية" كحقل واحد قابل للاستبدال على
    # Patient (total_treatment_cost)، بينما "المدفوع" يُحسب كمجموع كل دفعات
    # المريض التاريخية بلا أي فصل بين جولات العلاج المختلفة. الآن: كل جولة
    # علاج جديدة = صف مستقل هنا بتكلفته الخاصة، ودفعاته (FinancialTransaction
    # عبر invoice_id) مرتبطة به تحديداً فقط. "المتبقي" يُحسب دائماً لكل فاتورة
    # على حدة (max(total_cost - مجموع دفعاتها, 0))، فتسديد فاتورة قديمة
    # بالكامل لا يؤثر إطلاقاً على حساب أي فاتورة جديدة تُفتح لاحقاً. لا يوجد
    # عمود "status" مخزَّن عمداً -- الحالة (مفتوحة/مغلقة) تُشتق دائماً من
    # مقارنة total_cost بمجموع الدفعات المرتبطة، لتفادي أي احتمال لتضارب حالة
    # مخزَّنة مع الحسابات الفعلية.
    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), index=True, nullable=False)
    doctor_email = Column(String, index=True, nullable=True)
    title = Column(String, nullable=False)
    total_cost = Column(Numeric(12, 2), nullable=False, default=0)
    created_at = Column(DateTime, nullable=False, server_default=text("CURRENT_TIMESTAMP"))

    patient = relationship("Patient", back_populates="treatment_invoices")
    payments = relationship("FinancialTransaction", back_populates="invoice", cascade="all, delete-orphan")


class FinancialTransaction(Base):
    __tablename__ = "financial_transactions"

    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=True)
    doctor_name = Column(String, nullable=True)
    # الحقل الرسمي لعزل الحركات المالية لكل طبيب عن غيره (2026-08-23) -- انظر
    # تعليق Patient.doctor_email أعلاه لنفس المنطق.
    doctor_email = Column(String, index=True, nullable=True)
    amount = Column(Numeric(12, 2), nullable=False)
    type = Column(String, nullable=False, default="expense")
    description = Column(String, nullable=False)
    created_at = Column(DateTime, nullable=False, server_default=text("CURRENT_TIMESTAMP"))
    # يربط دفعة مريض معينة (type="income") بفاتورة علاج محددة (2026-08-25) --
    # nullable لأن مصاريف العيادة العامة (type="expense") لا علاقة لها بأي
    # فاتورة مريض إطلاقاً. القيم القديمة (قبل هذا الترحيل) تُملأ تلقائياً عبر
    # ترحيل بيانات database.py.init_db() الذي يربطها بفاتورة "تاريخية" واحدة
    # لكل مريض كان لديه تكلفة/دفعات سابقة، فلا يُفقد أي سجل تاريخي.
    invoice_id = Column(Integer, ForeignKey("treatment_invoices.id"), index=True, nullable=True)

    invoice = relationship("TreatmentInvoice", back_populates="payments")


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