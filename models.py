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
    # بيانات اتصال Green API الخاصة بكل طبيب على حدة (أُضيفت 2026-09-01) --
    # كل طبيب يربط حساب واتساب/Green API الخاص به (رقم عيادته هو)، بدل الاعتماد
    # على حساب واحد مشترك للمنصة كلها -- قرار معماري مقصود: تكلفة/إدارة حساب
    # مشترك واحد كانت ستتصاعد مع كل طبيب جديد ينضم للمنصة (خطة Green API
    # Business تُدفع لكل Instance على حدة أصلاً)، وأيضاً رسائل كل عيادة تصل
    # لمرضاها من رقم عيادتها الفعلي بدل رقم منصة مشترك غريب عنهم. انظر
    # send_whatsapp_message_for_doctor() بالأسفل -- القيمة NULL تعني ببساطة أن
    # هذا الطبيب لم يربط حساب واتساب خاص به بعد، فتُتجاهَل أي محاولة إرسال له
    # بصمت (نفس نمط best-effort المستخدم بكل ميزات واتساب بالمشروع).
    green_api_instance_id = Column(String, nullable=True)
    green_api_token = Column(String, nullable=True)
    # رمز جهاز Firebase Cloud Messaging لتطبيق الطبيب على أندرويد (أُضيف 2026-08-24)
    # -- يُخزَّن هنا آخر توكن FCM سجّله تطبيق الطبيب بعد تسجيل الدخول (جهاز واحد
    # لكل طبيب حالياً، يُستبدل بالأحدث عند كل POST /api/auth/register-device)،
    # ويُستخدَم لإرسال إشعار Push فوري عند وصول طلب حجز جديد عبر صفحة الحجز
    # العامة. قيمة NULL تعني ببساطة أن التطبيق لم يُثبّت/يُفعّل بعد لهذا الطبيب.
    fcm_token = Column(String, nullable=True)
    # --- تتبّع نشاط الطبيب + تذكير الخمول اليومي (أُضيفت 2026-09-05) ---
    # last_active_at: آخر لحظة نفّذ فيها هذا الطبيب أي طلب موثّق، من الموقع أو
    # من التطبيق على حدّ سواء -- تُختم مركزياً في get_current_doctor_user داخل
    # main.py (النقطة الوحيدة التي يمرّ منها كل طلب موثّق في المشروع)، مع
    # throttle زمني حتى لا نكتب في القاعدة مع كل طلب. القيمة NULL تعني ببساطة
    # أن هذا الطبيب لم يدخل النظام منذ إضافة الميزة، ويُعامَل كخامل تماماً.
    last_active_at = Column(DateTime, nullable=True)
    # رمز إشعارات المتصفح (FCM Web Push) -- منفصل عمداً عن fcm_token الخاص
    # بتطبيق أندرويد وليس بديلاً عنه: الطبيب قد يستخدم الموقع والتطبيق معاً،
    # ويجب أن يصله التذكير على السطحين. NULL = لم يفعّل إشعارات المتصفح بعد.
    web_push_token = Column(String, nullable=True)
    # حارس عدم التكرار لمحرّك تذكير الخمول: آخر تذكير أُرسل فعلاً لهذا الطبيب.
    # المحرّك يفحص أن قيمته أقدم من منتصف ليلة اليوم المحلي قبل أي إرسال، فلا
    # يمكن أن يصل الطبيب أكثر من تذكير واحد في اليوم مهما تكرّر تنفيذ الحلقة
    # (إعادة إقلاع الخادم، فحص كل 15 دقيقة داخل ساعة الإرسال، ... إلخ).
    last_idle_reminder_at = Column(DateTime, nullable=True)


class ActivationKey(Base):
    __tablename__ = "activation_keys"

    id = Column(Integer, primary_key=True, index=True)
    key_code = Column(String, unique=True, index=True, nullable=False)
    duration_days = Column(Integer, default=30, nullable=False)
    is_used = Column(Boolean, default=False, nullable=False)
    used_by_email = Column(String, nullable=True)
    # الباقة الصريحة المقصودة لهذا الكود، تُضبط دائماً عند التوليد عبر
    # /api/admin/renewal-keys/generate. القيم الصالحة (2026-09-14):
    #   "premium"      -- الباقة الفخمة
    #   "premium_plus" -- باقة العيادات (تفتح إدارة نسب الأطباء)
    #   "trial"        -- كود تجربة مجانية، يفتح premium_plus كاملة لمدته
    #   "standard"     -- مرادف قديم فقط، لم تعد تُولَّد؛ يفتح premium
    # القيمة "trial" تبقى محفوظة هنا بعد الاستهلاك للمحاسبة الإدارية، ولا
    # تُكتب إطلاقاً في users.tier -- لا توجد حالة مستخدم اسمها trial.
    # قد تكون NULL للأكواد الثابتة القديمة المزروعة يدوياً -- عندها يرجع
    # resolve_activation_key_tier لتخمين نصي احتياطي من الكود نفسه.
    intended_tier = Column(String, nullable=True)
    # تاريخ توليد الكود (2026-09-14) -- nullable عمداً وبلا server_default:
    # الأكواد المولَّدة قبل هذا التاريخ لا يُعرَف تاريخها، وختمها بتاريخ
    # الترحيل كان سيكذب على كل دفعة سابقة. يُملأ صراحةً في
    # generate_renewal_keys وحده، فكل دفعة جديدة تحمل تاريخها الحقيقي.
    created_at = Column(DateTime, nullable=True)


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
    # آخر مرة أُرسلت فيها رسالة "استرجاع مريض" (تذكير متابعة دورية عبر واتساب)
    # لهذا المريض، تلقائياً كانت أو يدوياً (2026-09-01) -- تمنع إعادة إرسال نفس
    # الرسالة له في كل دورة فحص لمحرك الاسترجاع التلقائي. انظر main.py:
    # get_due_recall_patients/send_due_recall_messages.
    last_recall_sent_at = Column(DateTime, nullable=True)

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
    # رمز إشعارات متصفح المريض صاحب طلب الحجز (أُضيف 2026-09-05) -- يُملأ فقط إن
    # ضغط المريض زر "فعّل التنبيه" في صفحة الحجز العامة بعد إرسال طلبه ووافق على
    # إذن المتصفح، ويُستخدم مرة واحدة: لإشعاره بقرار الطبيب (قبول/رفض) على متصفحه
    # مباشرة. مخزَّن على الموعد نفسه وليس على المريض عمداً: صاحب الطلب قد لا يكون
    # له سجل مريض أصلاً وقت الحجز (يُنشأ سجله عند القبول فقط)، والرمز مرتبط
    # بمتصفح وجهاز بعينه لا بشخص. NULL = لم يفعّل التنبيه، فيُتجاهَل بصمت.
    patient_web_push_token = Column(String, nullable=True)
    # مدة الموعد بالدقائق (أُضيف 2026-09-10) -- يختارها الطبيب/السكرتيرة لكل موعد
    # على حدة من صفحة المواعيد اليومية (15 دقيقة وحتى 3 ساعات، بخطوة ربع ساعة).
    # هي أساس فحص التعارض: موعدان يتقاطعان زمنياً لا يمكن حجزهما معاً، ويُقترح
    # على المستخدم أول وقت متاح بعد نهاية الموعد السابق. القيمة الافتراضية 30
    # دقيقة تعني أن كل المواعيد القديمة (قبل إضافة الحقل) تُعامَل كنصف ساعة.
    duration_minutes = Column(Integer, nullable=False, default=30, server_default=text("30"))


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
    # الطبيب المساعد المنفّذ لهذه الفاتورة (2026-09-13) -- يُستخدَم كقيمة
    # افتراضية مقترحة عند تسجيل أي دفعة عليها، فلا يضطر المستخدم لاختيار
    # الطبيب مع كل قسط. النسبة نفسها تُحسب دوماً على الدفعة لا على الفاتورة،
    # انظر models.DoctorEarning. NULL = الطبيب المدير (صاحب الحساب) نفسه.
    clinic_doctor_id = Column(Integer, ForeignKey("clinic_doctors.id"), index=True, nullable=True)

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
    # يُميّز الحركة كـ"رصيد افتتاحي/سابق" مُرحّل إلى النظام بدل دخل حقيقي لهذه
    # الفترة الزمنية تحديداً (2026-08-25) -- انظر شرح كامل عند get_finance_summary()
    # في main.py. تُستبعد أي حركة is_opening_balance=True من أي تقرير شهري محدد،
    # لكنها تبقى محسوبة ضمن الإجمالي التراكمي الكلي (all_time=true) لأنها تمثل
    # أموالاً حقيقية تم تحصيلها فعلاً، فقط بتاريخ غير معروف بدقة كافية لتحديد
    # شهرها الصحيح.
    is_opening_balance = Column(Boolean, nullable=False, default=False, server_default=text("false"))

    # يربط الدفعة بالطبيب المساعد الذي نفّذ العلاج/حصّل المبلغ (2026-09-13) --
    # انظر شرح كامل عند models.ClinicDoctor بالأسفل. NULL = عمل الطبيب المدير
    # (صاحب الحساب) نفسه، وهي القيمة الصحيحة تلقائياً لكل الصفوف التاريخية
    # السابقة لهذه الميزة، فلا يحتاج أي ترحيل بيانات إطلاقاً.
    clinic_doctor_id = Column(Integer, ForeignKey("clinic_doctors.id"), index=True, nullable=True)

    invoice = relationship("TreatmentInvoice", back_populates="payments")
    # cascade="all, delete-orphan" ضروري هنا تحديداً: doctor_earnings يحمل FK
    # نحو financial_transactions.id، وحذف فاتورة علاج يمرّ عبر db.delete(invoice)
    # (حذف ORM) الذي يحذف دفعاتها -- بلا هذه العلاقة يرفض Postgres حذف صف
    # الدفعة بانتهاك قيد الـ FK. أما مسارات الحذف الجماعي الخام (Query.delete)
    # مثل delete_patient() فلا تمرّ من الـ ORM إطلاقاً، ولذلك تُنظَّف فيها صفوف
    # doctor_earnings صراحةً أيضاً -- نفس درس قصة حذف المريض متعددة الطبقات.
    earnings = relationship("DoctorEarning", back_populates="transaction", cascade="all, delete-orphan")


# ====================================================================
# العيادات متعددة الأطباء: الأطباء بالنسبة -- 2026-09-13
# ====================================================================
# الطبيب المساعد ليس مستخدماً في جدول users عمداً. كل عزل البيانات في هذا
# المشروع مبني على doctor_email == صاحب الحساب، فلو أُعطي الطبيب المساعد
# حساب users مستقلاً لرأى قاعدة بيانات فارغة، ولاحتاج إصلاح ذلك تعديل كل
# استعلام في main.py. هنا الطبيب المساعد سجلٌّ مملوك لحساب العيادة
# (clinic_email) ولا شيء أكثر؛ وعند إضافة دخول مستقل له لاحقاً (المرحلة ٢)
# تبقى جلسته تُترجَم إلى بريد العيادة عند عزل البيانات، ويُحدَّد ما يراه عبر
# clinic_doctor_id وحده -- فيبقى التعديل في نقطة واحدة (get_current_doctor_user).
class ClinicDoctor(Base):
    __tablename__ = "clinic_doctors"

    id = Column(Integer, primary_key=True, index=True)
    # بريد حساب العيادة المالك لهذا السجل (users.email) -- نفس منطق
    # Patient.doctor_email الموثّق أعلاه، وهو الحقل الرسمي لعزل أطباء كل عيادة.
    clinic_email = Column(String, index=True, nullable=False)
    full_name = Column(String, nullable=False)
    phone = Column(String, nullable=True)
    specialty = Column(String, nullable=True)
    # النسبة المئوية الحالية لهذا الطبيب (0 إلى 100). تنبيه معماري جوهري:
    # هذه القيمة تُستخدَم فقط لحساب الدفعات الجديدة من لحظة حفظها فصاعداً،
    # ولا تُستخدَم إطلاقاً عند عرض أي حركة قديمة -- كل حركة تحمل نسختها
    # المجمّدة من النسبة في DoctorEarning.applied_percent. بدون هذا الفصل،
    # تعديل النسبة من 40% إلى 50% كان سيُعيد كتابة تاريخ كل الشهور الماضية
    # بأثر رجعي، وهو أخطر خلل محاسبي ممكن في هذه الميزة.
    commission_percent = Column(Numeric(5, 2), nullable=False, default=0, server_default=text("0"))
    # طبيب متوقف عن العمل في العيادة: يختفي من قوائم الاختيار عند تسجيل دفعة
    # جديدة، لكن كل سجله المالي وكشف حسابه يبقى كما هو (لا حذف للتاريخ).
    is_active = Column(Boolean, default=True, nullable=False, server_default=text("true"))
    notes = Column(String, nullable=True)
    created_at = Column(DateTime, nullable=False, server_default=text("CURRENT_TIMESTAMP"))

    earnings = relationship("DoctorEarning", back_populates="clinic_doctor")
    payouts = relationship("DoctorPayout", back_populates="clinic_doctor")


class DoctorEarning(Base):
    __tablename__ = "doctor_earnings"

    # سطر استحقاق واحد مقابل كل دفعة مقبوضة فعلياً (FinancialTransaction من نوع
    # income) نُسبت لطبيب مساعد. القاعدة المعتمدة: النسبة تُحسب على المبلغ
    # المحصّل فعلاً لا على قيمة الفاتورة -- الطبيب لا يستحق نسبة على دين لم
    # يُقبض بعد، والأقساط تُوزَّع تلقائياً لأن كل دفعة تولّد سطرها المستقل.
    #
    # العلاقة مع الدفعة هي 1:1 عمداً (transaction_id فريد فعلياً بالاستخدام):
    # تعديل الدفعة يُحدّث هذا السطر في مكانه مع الإبقاء على applied_percent
    # مجمّدة كما كانت، وحذف الدفعة يحذفه. هذا يُبقي كشف حساب الطبيب مطابقاً
    # سطراً بسطر لصفحة المالية بدل أن يتضخم بأسطر عكسية لا يفهمها المستخدم.
    id = Column(Integer, primary_key=True, index=True)
    clinic_email = Column(String, index=True, nullable=False)
    clinic_doctor_id = Column(Integer, ForeignKey("clinic_doctors.id"), index=True, nullable=False)
    transaction_id = Column(Integer, ForeignKey("financial_transactions.id"), index=True, nullable=True)
    patient_id = Column(Integer, nullable=True)
    invoice_id = Column(Integer, nullable=True)
    patient_name = Column(String, nullable=True)
    description = Column(String, nullable=True)
    # المبلغ المحصّل من المريض في هذه الدفعة تحديداً.
    gross_amount = Column(Numeric(12, 2), nullable=False, default=0)
    # لقطة النسبة لحظة التسجيل -- لا تتغير أبداً بعد ذلك مهما عُدّلت نسبة الطبيب.
    applied_percent = Column(Numeric(5, 2), nullable=False, default=0)
    doctor_share = Column(Numeric(12, 2), nullable=False, default=0)
    clinic_share = Column(Numeric(12, 2), nullable=False, default=0)
    # تاريخ الدفعة نفسها (وليس تاريخ إنشاء هذا السطر) -- هو ما تُبنى عليه
    # التقارير الشهرية، حتى تبقى مطابقة تماماً لتقرير المالية لنفس الشهر
    # حين يُسجَّل دفعة قديمة بتاريخها الحقيقي.
    earned_at = Column(DateTime, nullable=False, server_default=text("CURRENT_TIMESTAMP"))
    # آخر مرة عُدّلت فيها الدفعة الأصلية بعد تسجيلها (NULL = لم تُعدَّل قط).
    adjusted_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, server_default=text("CURRENT_TIMESTAMP"))

    clinic_doctor = relationship("ClinicDoctor", back_populates="earnings")
    transaction = relationship("FinancialTransaction", back_populates="earnings")


class DoctorPayout(Base):
    __tablename__ = "doctor_payouts"

    # تسوية: مبلغ سُلِّم فعلاً للطبيب المساعد من مستحقاته المتراكمة.
    # الرصيد المستحق = مجموع doctor_share - مجموع التسويات.
    #
    # كل تسوية تُنشئ في نفس العملية حركة مصروف (FinancialTransaction من نوع
    # expense) على حساب العيادة، وإلا يبقى "صافي أرباح العيادة" في صفحة
    # المالية منتفخاً بمال خرج فعلاً من الصندوق. expense_transaction_id يحفظ
    # رابط تلك الحركة ليُحذَف الاثنان معاً عند التراجع عن تسوية.
    id = Column(Integer, primary_key=True, index=True)
    clinic_email = Column(String, index=True, nullable=False)
    clinic_doctor_id = Column(Integer, ForeignKey("clinic_doctors.id"), index=True, nullable=False)
    amount = Column(Numeric(12, 2), nullable=False)
    note = Column(String, nullable=True)
    expense_transaction_id = Column(Integer, nullable=True)
    paid_at = Column(DateTime, nullable=False, server_default=text("CURRENT_TIMESTAMP"))
    created_at = Column(DateTime, nullable=False, server_default=text("CURRENT_TIMESTAMP"))

    clinic_doctor = relationship("ClinicDoctor", back_populates="payouts")


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