import os

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import declarative_base, sessionmaker

# مسار قاعدة البيانات المحلي أو من المتغير البيئي DATABASE_URL
SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./dental.db")

engine_kwargs = {}
if SQLALCHEMY_DATABASE_URL.startswith("sqlite"):
    engine_kwargs["connect_args"] = {"check_same_thread": False}

engine = create_engine(SQLALCHEMY_DATABASE_URL, **engine_kwargs)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def init_db():
    Base.metadata.create_all(bind=engine)

    if SQLALCHEMY_DATABASE_URL.startswith("sqlite"):
        inspector = inspect(engine)
        if "patients" in inspector.get_table_names():
            columns = {column["name"] for column in inspector.get_columns("patients")}
            if "doctor_name" not in columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE patients ADD COLUMN doctor_name VARCHAR"))
            if "total_treatment_cost" not in columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE patients ADD COLUMN total_treatment_cost FLOAT NOT NULL DEFAULT 0.0"))
            if "chart_state" not in columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE patients ADD COLUMN chart_state TEXT"))

        if "users" in inspector.get_table_names():
            user_columns = {column["name"] for column in inspector.get_columns("users")}
            if "tier" not in user_columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE users ADD COLUMN tier VARCHAR NOT NULL DEFAULT 'standard'"))

        if "financial_transactions" in inspector.get_table_names():
            finance_columns = {column["name"] for column in inspector.get_columns("financial_transactions")}
            if "patient_id" not in finance_columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE financial_transactions ADD COLUMN patient_id INTEGER"))

        if "appointments" in inspector.get_table_names():
            appointment_columns = {column["name"] for column in inspector.get_columns("appointments")}
            if "patient_name" not in appointment_columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE appointments ADD COLUMN patient_name VARCHAR NOT NULL DEFAULT ''"))
            if "appointment_time" not in appointment_columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE appointments ADD COLUMN appointment_time VARCHAR NOT NULL DEFAULT ''"))
            if "procedure_type" not in appointment_columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE appointments ADD COLUMN procedure_type VARCHAR NOT NULL DEFAULT ''"))
            if "status" not in appointment_columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE appointments ADD COLUMN status VARCHAR NOT NULL DEFAULT 'pending'"))
            if "appointment_date" not in appointment_columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE appointments ADD COLUMN appointment_date DATETIME"))
            if "notes" not in appointment_columns:
                with engine.begin() as connection:
                    connection.execute(text("ALTER TABLE appointments ADD COLUMN notes VARCHAR"))

    # ترحيل أعمدة صفحة "حسابي" (بيانات الطبيب/العيادة) -- يُنفَّذ بلا شرط نوع
    # قاعدة البيانات (خلافاً لكتلة SQLite أعلاه) لأن بيئة الإنتاج الحقيقية على
    # Render تستخدم Supabase Postgres وليس SQLite، و create_all() وحدها لا تُضيف
    # أعمدة لجدول users الموجود مسبقاً. صياغة ALTER TABLE ADD COLUMN مدعومة في
    # كل من SQLite وPostgres، والفحص المسبق عبر inspector يجعل العملية آمنة
    # للتكرار (idempotent) في كلتا الحالتين.
    inspector = inspect(engine)
    if "users" in inspector.get_table_names():
        user_columns = {column["name"] for column in inspector.get_columns("users")}
        if "clinic_name" not in user_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE users ADD COLUMN clinic_name VARCHAR"))
        if "clinic_address" not in user_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE users ADD COLUMN clinic_address VARCHAR"))
        if "avatar_url" not in user_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE users ADD COLUMN avatar_url VARCHAR"))

    # ترحيل أعمدة أرشيف/صور المرضى الشعاعية (patient_xrays) -- مصحح في 2026-08-25:
    # كانت هذه الكتلة محصورة خطأً داخل كتلة SQLite أعلاه فلم تصل إطلاقاً إلى
    # إنتاج Postgres الحقيقي على Render — مما كان يتسبب بفشل أي محاولة
    # لحذف مريض لديه صورة شعاعية/أرشيف مرفوع بخطأ 500 غير معالج
    # ("column patient_xrays.file_name does not exist"). بلا شرط نوع قاعدة البيانات
    # لنفس السبب الموضح أعلاه لأعمدة users/appointments.
    if "patient_xrays" in inspector.get_table_names():
        archive_columns = {column["name"] for column in inspector.get_columns("patient_xrays")}
        if "file_name" not in archive_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE patient_xrays ADD COLUMN file_name VARCHAR"))
        if "file_url" not in archive_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE patient_xrays ADD COLUMN file_url VARCHAR"))
        if "file_type" not in archive_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE patient_xrays ADD COLUMN file_type VARCHAR"))

    # ترحيل أعمدة محرك تذكيرات واتساب التلقائية (2026-08-23) -- بلا شرط نوع
    # قاعدة البيانات، لنفس السبب الموضح أعلاه لأعمدة "حسابي" (الإنتاج الحقيقي
    # Postgres وليس SQLite). patient_id: يربط الموعد بسجل المريض مباشرة (كان
    # الطلب يستقبله دائماً لكنه لم يكن يُخزَّن إطلاقاً). reminder_sent: يمنع
    # إرسال نفس تذكير الموعد أكثر من مرة.
    if "appointments" in inspector.get_table_names():
        appointment_reminder_columns = {column["name"] for column in inspector.get_columns("appointments")}
        if "patient_id" not in appointment_reminder_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE appointments ADD COLUMN patient_id INTEGER"))
        if "reminder_sent" not in appointment_reminder_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE appointments ADD COLUMN reminder_sent BOOLEAN NOT NULL DEFAULT FALSE"))

    # ====================================================================
    # عزل بيانات الأطباء متعدد المستأجرين (multi-tenant isolation) -- 2026-08-23
    # ====================================================================
    # مشكلة أمنية جوهرية تم اكتشافها: جداول patients / appointments /
    # financial_transactions لم يكن لديها أي عمود بريد إلكتروني موثوق لتحديد
    # مالك السجل. كانت بعض المسارات تعتمد على doctor_name (نص حر قابل للتكرار
    # بين طبيبين مختلفين، وقابل للتلاعب من العميل)، وبعضها الآخر (كل مسارات
    # المواعيد المفردة، وملخص الحسابات المالية، ومعظم مسارات المرضى المفردة)
    # لم يكن به أي فلترة إطلاقاً -- أي طبيب مسجّل دخول كان يستطيع قراءة أو
    # تعديل أو حذف بيانات أي طبيب آخر بمجرد تخمين رقم المعرّف (IDOR). نضيف هنا
    # عمود doctor_email الرسمي على الجداول الثلاثة (بنفس نمط
    # InventoryItem.doctor_email الصحيح أصلاً)، ثم نُرحّل (backfill) الصفوف
    # القديمة تلقائياً وبأمان فقط في حال وجود طبيب واحد مسجّل حتى الآن (الحالة
    # الحقيقية الحالية للمشروع) -- إن وُجد أكثر من طبيب مسجّل، لا نخمّن أبداً
    # لمن تعود هذه الصفوف القديمة، فتبقى doctor_email فيها NULL، والكود في
    # main.py يعامل أي سجل بلا doctor_email مطابق كأنه غير موجود لأي طبيب
    # (fail closed) بدلاً من عرضه لأول طبيب يستعلم -- وهذا أهم بكثير من
    # استرجاع بيانات قديمة مبهمة الملكية.
    if "patients" in inspector.get_table_names():
        patient_columns = {column["name"] for column in inspector.get_columns("patients")}
        if "doctor_email" not in patient_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE patients ADD COLUMN doctor_email VARCHAR"))

    if "appointments" in inspector.get_table_names():
        appointment_tenancy_columns = {column["name"] for column in inspector.get_columns("appointments")}
        if "doctor_email" not in appointment_tenancy_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE appointments ADD COLUMN doctor_email VARCHAR"))

    if "financial_transactions" in inspector.get_table_names():
        finance_tenancy_columns = {column["name"] for column in inspector.get_columns("financial_transactions")}
        if "doctor_email" not in finance_tenancy_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE financial_transactions ADD COLUMN doctor_email VARCHAR"))

    # ترحيل آمن للصفوف القديمة بلا doctor_email: فقط إذا كان هناك طبيب واحد
    # بالضبط مسجّلاً حتى الآن في جدول users، نُسند له كل الصفوف اليتيمة تلقائياً
    # (لأنها بالضرورة تخصه، فهو المستخدم الوحيد الذي أنشأها). بمجرد أن يصبح
    # هناك أكثر من طبيب، تتوقف هذه الخطوة تلقائياً ولا تُخمّن الملكية إطلاقاً.
    if "users" in inspector.get_table_names():
        with engine.begin() as connection:
            user_count = connection.execute(text("SELECT COUNT(*) FROM users")).scalar() or 0
            if user_count == 1:
                sole_email = connection.execute(text("SELECT email FROM users LIMIT 1")).scalar()
                if sole_email:
                    connection.execute(
                        text("UPDATE patients SET doctor_email = :email WHERE doctor_email IS NULL"),
                        {"email": sole_email},
                    )
                    connection.execute(
                        text("UPDATE appointments SET doctor_email = :email WHERE doctor_email IS NULL"),
                        {"email": sole_email},
                    )
                    connection.execute(
                        text("UPDATE financial_transactions SET doctor_email = :email WHERE doctor_email IS NULL"),
                        {"email": sole_email},
                    )

    # ====================================================================
    # صفحة الحجز العامة (public booking page) -- 2026-08-23
    # ====================================================================
    # كل طبيب يقدر يفعّل رابطاً عاماً خاصاً فيه (site.com/d/<booking_slug>)
    # يسمح لأي مريض بحجز موعد مباشرة بلا تسجيل دخول. الأعمدة الجديدة كلها
    # nullable/بقيمة افتراضية آمنة، فلا تؤثر على أي طبيب لم يفعّل الميزة بعد.
    if "users" in inspector.get_table_names():
        booking_columns = {column["name"] for column in inspector.get_columns("users")}
        if "clinic_phone" not in booking_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE users ADD COLUMN clinic_phone VARCHAR"))
        if "booking_slug" not in booking_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE users ADD COLUMN booking_slug VARCHAR"))
        if "public_booking_enabled" not in booking_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE users ADD COLUMN public_booking_enabled BOOLEAN NOT NULL DEFAULT FALSE"))
        if "work_days" not in booking_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE users ADD COLUMN work_days VARCHAR"))
        if "work_start_time" not in booking_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE users ADD COLUMN work_start_time VARCHAR"))
        if "work_end_time" not in booking_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE users ADD COLUMN work_end_time VARCHAR"))
        if "slot_duration_minutes" not in booking_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE users ADD COLUMN slot_duration_minutes INTEGER NOT NULL DEFAULT 30"))

    if "appointments" in inspector.get_table_names():
        appointment_booking_columns = {column["name"] for column in inspector.get_columns("appointments")}
        if "patient_phone" not in appointment_booking_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE appointments ADD COLUMN patient_phone VARCHAR"))

    # فهرس فريد جزئي (Postgres) لعمود booking_slug: نسمح لعدة صفوف بقيمة NULL
    # (أطباء لم يختاروا رابطاً بعد) لكن نمنع تكرار أي slug فعلي بين طبيبين.
    # SQLite المحلي يتجاهل شرط UNIQUE على عمود NULL تلقائياً فلا حاجة لفهرس
    # منفصل هناك؛ Postgres يحتاج فهرساً جزئياً صريحاً لتحقيق نفس السلوك لأن
    # قيد UNIQUE العادي على العمود لا يُنشأ تلقائياً عبر ALTER TABLE ADD COLUMN.
    if not SQLALCHEMY_DATABASE_URL.startswith("sqlite") and "users" in inspector.get_table_names():
        with engine.begin() as connection:
            connection.execute(
                text(
                    "CREATE UNIQUE INDEX IF NOT EXISTS ix_users_booking_slug_unique "
                    "ON users (booking_slug) WHERE booking_slug IS NOT NULL"
                )
            )

    # ====================================================================
    # رمز جهاز Firebase Push لتطبيق الطبيب على أندرويد -- 2026-08-24
    # ====================================================================
    # بلا شرط نوع قاعدة البيانات (خلافاً لكتلة SQLite بالأعلى)، لأن الإنتاج
    # الحقيقي على Render يستخدم Supabase Postgres وليس SQLite -- نفس السبب
    # الموثّق أعلاه لأعمدة "حسابي" وصفحة الحجز العامة.
    if "users" in inspector.get_table_names():
        push_columns = {column["name"] for column in inspector.get_columns("users")}
        if "fcm_token" not in push_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE users ADD COLUMN fcm_token VARCHAR"))

    # ====================================================================
    # تتبّع نشاط الطبيب + تذكير الخمول اليومي -- 2026-09-05
    # ====================================================================
    # ثلاثة أعمدة nullable بالكامل على users، فلا تؤثر على أي صف قائم: آخر نشاط
    # موثّق للطبيب، رمز إشعارات المتصفح، وآخر تذكير خمول أُرسل له. بلا شرط نوع
    # قاعدة البيانات لنفس السبب الموثّق أعلاه (الإنتاج على Render هو Supabase
    # Postgres وليس SQLite). انظر أيضاً كتلة ALTER TABLE ... IF NOT EXISTS
    # المقابلة في on_startup داخل main.py.
    if "users" in inspector.get_table_names():
        activity_columns = {column["name"] for column in inspector.get_columns("users")}
        if "last_active_at" not in activity_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE users ADD COLUMN last_active_at TIMESTAMP"))
        if "web_push_token" not in activity_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE users ADD COLUMN web_push_token VARCHAR"))
        if "last_idle_reminder_at" not in activity_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE users ADD COLUMN last_idle_reminder_at TIMESTAMP"))

    # رمز إشعارات متصفح المريض على طلب الحجز -- 2026-09-05 (انظر models.py).
    if "appointments" in inspector.get_table_names():
        patient_push_columns = {column["name"] for column in inspector.get_columns("appointments")}
        if "patient_web_push_token" not in patient_push_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE appointments ADD COLUMN patient_web_push_token VARCHAR"))

    # مدة الموعد بالدقائق -- 2026-09-10 (انظر models.py عند
    # Appointment.duration_minutes). عمود NOT NULL DEFAULT 30 حتى تُعامَل كل
    # المواعيد القديمة كنصف ساعة تلقائياً بلا أي عملية تعبئة يدوية، وحتى لا
    # يفشل فحص التعارض على صف قديم بقيمة NULL. بلا شرط نوع قاعدة البيانات
    # لنفس السبب الموثّق بالأسفل: الإنتاج الحقيقي على Render يستخدم Postgres.
    if "appointments" in inspector.get_table_names():
        appointment_duration_columns = {column["name"] for column in inspector.get_columns("appointments")}
        if "duration_minutes" not in appointment_duration_columns:
            with engine.begin() as connection:
                connection.execute(
                    text("ALTER TABLE appointments ADD COLUMN duration_minutes INTEGER NOT NULL DEFAULT 30")
                )

    # الطبيب المنفّذ للموعد -- 2026-09-17 (انظر models.py عند
    # Appointment.clinic_doctor_id). عمود nullable بلا قيد FK في الـ ALTER --
    # نفس نمط financial_transactions.invoice_id: إضافة قيد مفتاح أجنبي على
    # جدول قائم في Postgres عملية أثقل وأخطر بلا فائدة هنا، والتحقّق يجري في
    # الخادم (resolve_appointment_clinic_doctor). NULL = الطبيب المدير، فلا
    # يحتاج أي موعد قديم أي تعبئة. بلا شرط نوع قاعدة بيانات: الإنتاج Postgres.
    if "appointments" in inspector.get_table_names():
        appointment_doctor_columns = {column["name"] for column in inspector.get_columns("appointments")}
        if "clinic_doctor_id" not in appointment_doctor_columns:
            with engine.begin() as connection:
                connection.execute(
                    text("ALTER TABLE appointments ADD COLUMN clinic_doctor_id INTEGER")
                )

    # الطبيب المعالج للمريض -- 2026-09-24 (انظر models.py عند
    # Patient.clinic_doctor_id). نفس نمط appointments.clinic_doctor_id أعلاه
    # حرفياً: nullable بلا قيد FK في الـ ALTER، والتحقّق في الخادم
    # (resolve_clinic_doctor_id)، وNULL = الطبيب المدير فلا تعبئة.
    if "patients" in inspector.get_table_names():
        patient_doctor_columns = {column["name"] for column in inspector.get_columns("patients")}
        if "clinic_doctor_id" not in patient_doctor_columns:
            with engine.begin() as connection:
                connection.execute(
                    text("ALTER TABLE patients ADD COLUMN clinic_doctor_id INTEGER")
                )

    # ====================================================================
    # فواتير العلاج المستقلة (treatment_invoices) -- 2026-08-25
    # ====================================================================
    # يحل مشكلة تداخل حسابات المريض: كانت "التكلفة الإجمالية" حقلاً واحداً
    # قابلاً للاستبدال على patients.total_treatment_cost، بينما "المدفوع"
    # يُحسب كمجموع كل دفعات المريض التاريخية بلا فصل بين جولات العلاج. جدول
    # treatment_invoices الجديد (تُنشئه Base.metadata.create_all أعلاه تلقائياً
    # لأنه جدول جديد بالكامل) يفصل كل جولة علاج كصف مستقل بتكلفته الخاصة.
    # عمود financial_transactions.invoice_id يربط كل دفعة بفاتورتها تحديداً --
    # بلا شرط نوع قاعدة البيانات (خلافاً لكتلة SQLite بالأعلى)، لنفس السبب
    # الموثّق أعلاه لأعمدة "حسابي"/الحجز العام/patient_xrays: الإنتاج الحقيقي
    # على Render يستخدم Supabase Postgres وليس SQLite.
    if "financial_transactions" in inspector.get_table_names():
        finance_invoice_columns = {column["name"] for column in inspector.get_columns("financial_transactions")}
        if "invoice_id" not in finance_invoice_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE financial_transactions ADD COLUMN invoice_id INTEGER"))

    # عمود "رصيد افتتاحي/سابق" (2026-08-25) -- انظر شرح كامل في models.py عند
    # FinancialTransaction.is_opening_balance. بلا شرط نوع قاعدة البيانات لنفس
    # سبب عمود invoice_id أعلاه: الإنتاج الحقيقي على Render يستخدم Postgres.
    if "financial_transactions" in inspector.get_table_names():
        finance_opening_balance_columns = {column["name"] for column in inspector.get_columns("financial_transactions")}
        if "is_opening_balance" not in finance_opening_balance_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE financial_transactions ADD COLUMN is_opening_balance BOOLEAN NOT NULL DEFAULT FALSE"))

    # ترحيل بيانات لمرة واحدة لكل مريض: أي مريض كانت لديه تكلفة/دفعات مسجّلة
    # قبل هذا التحديث (total_treatment_cost > 0 أو دفعات income/received قديمة
    # بلا invoice_id) يحصل تلقائياً على "فاتورة تاريخية" واحدة تحمل نفس قيمة
    # total_treatment_cost الحالية، وتُربط بها كل دفعاته القديمة غير المرتبطة.
    # هذا يحافظ حرفياً على نفس رصيد "المتبقي" الذي كان يراه الطبيب قبل الترحيل
    # (نفس صيغة max(cost - paid, 0))، ثم من هذه اللحظة فصاعداً أي فاتورة جديدة
    # تُفتح من صفحة المريض تكون مستقلة تماماً بحساباتها. آمنة للتكرار
    # (idempotent): الشرط "WHERE id NOT IN (... treatment_invoices ...)" يجعلها
    # لا تعمل شيئاً بعد أول تشغيل ناجح لكل مريض.
    if "treatment_invoices" in inspector.get_table_names() and "patients" in inspector.get_table_names() and "financial_transactions" in inspector.get_table_names():
        with engine.begin() as connection:
            candidate_patients = connection.execute(
                text(
                    """
                    SELECT id, total_treatment_cost, doctor_email FROM patients
                    WHERE id NOT IN (
                        SELECT DISTINCT patient_id FROM treatment_invoices WHERE patient_id IS NOT NULL
                    )
                    AND (
                        COALESCE(total_treatment_cost, 0) > 0
                        OR id IN (
                            SELECT DISTINCT patient_id FROM financial_transactions
                            WHERE patient_id IS NOT NULL
                              AND invoice_id IS NULL
                              AND type IN ('income', 'received')
                              AND amount > 0
                        )
                    )
                    """
                )
            ).fetchall()

            for row in candidate_patients:
                legacy_patient_id = row[0]
                legacy_total_cost = float(row[1] or 0)
                legacy_doctor_email = row[2]

                connection.execute(
                    text(
                        """
                        INSERT INTO treatment_invoices (patient_id, doctor_email, title, total_cost, created_at)
                        VALUES (:patient_id, :doctor_email, :title, :total_cost, CURRENT_TIMESTAMP)
                        """
                    ),
                    {
                        "patient_id": legacy_patient_id,
                        "doctor_email": legacy_doctor_email,
                        "title": "السجل المالي السابق (مرحّل تلقائياً)",
                        "total_cost": legacy_total_cost,
                    },
                )

                new_invoice_id = connection.execute(
                    text(
                        "SELECT id FROM treatment_invoices WHERE patient_id = :pid ORDER BY id DESC LIMIT 1"
                    ),
                    {"pid": legacy_patient_id},
                ).scalar()

                connection.execute(
                    text(
                        """
                        UPDATE financial_transactions
                        SET invoice_id = :invoice_id, is_opening_balance = TRUE
                        WHERE patient_id = :pid
                          AND invoice_id IS NULL
                          AND type IN ('income', 'received')
                          AND amount > 0
                        """
                    ),
                    {"invoice_id": new_invoice_id, "pid": legacy_patient_id},
                )

    # ====================================================================
    # نظام استرجاع المرضى التلقائي (Patient Recall Engine) -- 2026-09-01
    # ====================================================================
    # last_recall_sent_at يسجّل آخر مرة أُرسلت فيها رسالة واتساب تلقائية/يدوية
    # لتذكير مريض متأخر عن موعد متابعته بالحجز مجدداً، لمنع إرسال نفس الرسالة
    # له بشكل متكرر كل دورة فحص. بلا شرط نوع قاعدة البيانات (خلافاً لكتلة
    # SQLite بالأعلى)، لنفس السبب الموثّق مراراً في هذا الملف: الإنتاج الحقيقي
    # على Render يستخدم Supabase Postgres وليس SQLite.
    if "patients" in inspector.get_table_names():
        recall_columns = {column["name"] for column in inspector.get_columns("patients")}
        if "last_recall_sent_at" not in recall_columns:
            with engine.begin() as connection:
                # TIMESTAMP وليس DATETIME عمداً: DATETIME نوع صالح بـ SQLite فقط (type
                # affinity)، بينما PostgreSQL لا يعرف نوعاً اسمه DATETIME إطلاقاً ويرفضه
                # بخطأ "type \"datetime\" does not exist" -- وهذا بالضبط ما كسر أول
                # نشر حقيقي لهذا العمود على Render/Supabase (2026-09-02، commit 08116f6،
                # راجع dental_project_patient_recall_engine.md). TIMESTAMP نوع صالح
                # ومتوافق بكلا قاعدتي البيانات.
                connection.execute(text("ALTER TABLE patients ADD COLUMN last_recall_sent_at TIMESTAMP"))

    # ====================================================================
    # بيانات اتصال Green API الخاصة بكل طبيب (users.green_api_instance_id/
    # green_api_token) -- 2026-09-01. انظر شرح كامل عند models.User أعلاه.
    # بلا شرط نوع قاعدة البيانات (خلافاً لكتلة SQLite بالأعلى)، لنفس السبب
    # الموثّق مراراً في هذا الملف: الإنتاج الحقيقي على Render يستخدم Supabase
    # Postgres وليس SQLite.
    if "users" in inspector.get_table_names():
        green_api_columns = {column["name"] for column in inspector.get_columns("users")}
        if "green_api_instance_id" not in green_api_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE users ADD COLUMN green_api_instance_id VARCHAR"))
        if "green_api_token" not in green_api_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE users ADD COLUMN green_api_token VARCHAR"))

    # ====================================================================
    # العيادات متعددة الأطباء: الأطباء بالنسبة -- 2026-09-13
    # ====================================================================
    # الجداول الثلاثة الجديدة (clinic_doctors / doctor_earnings /
    # doctor_payouts) تُنشئها Base.metadata.create_all() في أول سطر من هذه
    # الدالة تلقائياً لأنها جداول جديدة بالكامل. ما يحتاج ترحيلاً يدوياً هنا
    # هو العمودان المُضافان على جدولين قائمين فقط.
    #
    # كلاهما nullable بالكامل بلا أي قيمة افتراضية، وNULL يعني صراحةً "الطبيب
    # المدير صاحب الحساب نفسه" -- ولهذا لا يحتاج أي صف تاريخي أي تعبئة
    # (backfill) إطلاقاً، وتبقى كل حسابات العيادات ذات الطبيب الواحد صحيحة
    # حرفياً كما كانت قبل هذا التحديث.
    #
    # بلا شرط نوع قاعدة البيانات (خلافاً لكتلة SQLite بالأعلى)، لنفس السبب
    # الموثّق مراراً في هذا الملف: الإنتاج الحقيقي على Render يستخدم Supabase
    # Postgres وليس SQLite.
    #
    # ملاحظة مقصودة: نضيف العمود بلا قيد REFERENCES في جملة ALTER TABLE.
    # SQLite لا يدعم إضافة قيد مفتاح خارجي إلى جدول قائم عبر ALTER TABLE
    # أصلاً، والقيد على مستوى قاعدة البيانات ليس ضرورياً هنا لأن main.py
    # يتحقق من ملكية clinic_doctor_id لنفس العيادة قبل أي كتابة، وتنظيف
    # الصفوف عند حذف طبيب مساعد يتم صراحةً في مسار الحذف نفسه.
    inspector = inspect(engine)

    if "financial_transactions" in inspector.get_table_names():
        finance_doctor_columns = {column["name"] for column in inspector.get_columns("financial_transactions")}
        if "clinic_doctor_id" not in finance_doctor_columns:
            with engine.begin() as connection:
                connection.execute(
                    text("ALTER TABLE financial_transactions ADD COLUMN clinic_doctor_id INTEGER")
                )

    if "treatment_invoices" in inspector.get_table_names():
        invoice_doctor_columns = {column["name"] for column in inspector.get_columns("treatment_invoices")}
        if "clinic_doctor_id" not in invoice_doctor_columns:
            with engine.begin() as connection:
                connection.execute(
                    text("ALTER TABLE treatment_invoices ADD COLUMN clinic_doctor_id INTEGER")
                )

    # ====================================================================
    # توحيد الباقات: standard -> premium  (2026-09-14)
    # ====================================================================
    # قرار صريح من صاحب المنصة: لم تعد هناك إلا باقة مدفوعة واحدة (Premium)،
    # وفوقها "باقة العيادات (Premium Plus)" لميزة إدارة نسب الأطباء وحدها.
    #
    # الترحيل يرفع كل صف قديم من standard إلى premium -- **رفع لا تخفيض**:
    # طبيب اشترى سابقاً لا يجوز أن يجد نفسه بصلاحيات أقل مما يحصل عليه مشترك
    # اليوم. وينطبق الأمر نفسه على أكواد التفعيل غير المستخدمة التي وُزِّعت
    # بالفعل على أطباء ولم تُستهلك بعد -- تبقى صالحة وتفتح Premium كاملة.
    #
    # آمن للتكرار: بعد أول تشغيل ناجح لا يبقى صف واحد بقيمة standard فلا
    # تفعل الجملتان شيئاً. وmain.py يترجم "standard" إلى premium في وقت
    # التشغيل أيضاً (normalize_tier)، فحتى لو فشل هذا الترحيل لأي سبب لا
    # يُحرَم أي طبيب من صلاحياته.
    if "users" in inspector.get_table_names():
        with engine.begin() as connection:
            connection.execute(
                text("UPDATE users SET tier = 'premium' WHERE LOWER(TRIM(tier)) = 'standard'")
            )
    if "activation_keys" in inspector.get_table_names():
        activation_columns = {column["name"] for column in inspector.get_columns("activation_keys")}
        if "intended_tier" in activation_columns:
            with engine.begin() as connection:
                connection.execute(
                    text(
                        "UPDATE activation_keys SET intended_tier = 'premium' "
                        "WHERE LOWER(TRIM(intended_tier)) = 'standard'"
                    )
                )

    # تاريخ توليد كود التفعيل (2026-09-14) -- يخدم مسار الجرد الإداري
    # GET /api/admin/activation-keys. nullable بلا قيمة افتراضية: الأكواد
    # القديمة تبقى NULL بصدق بدل أن تُختَم كلها بتاريخ الترحيل.
    if "activation_keys" in inspector.get_table_names():
        key_columns = {column["name"] for column in inspector.get_columns("activation_keys")}
        if "created_at" not in key_columns:
            with engine.begin() as connection:
                # TIMESTAMP لا DATETIME -- الأخيرة نوع صالح بـ SQLite فقط
                # ويرفضها Postgres (الدرس الموثّق عند patients.last_recall_sent_at).
                connection.execute(text("ALTER TABLE activation_keys ADD COLUMN created_at TIMESTAMP"))

    # حسابات الأطباء المساعدين (2026-09-25): أعمدة الدخول على clinic_doctors،
    # وعمود «من أدخل» (created_by_staff_id) على الجداول التي يكتب فيها المساعد.
    if "clinic_doctors" in inspector.get_table_names():
        staff_columns = {column["name"] for column in inspector.get_columns("clinic_doctors")}
        with engine.begin() as connection:
            if "login_email" not in staff_columns:
                connection.execute(text("ALTER TABLE clinic_doctors ADD COLUMN login_email VARCHAR"))
            if "hashed_password" not in staff_columns:
                connection.execute(text("ALTER TABLE clinic_doctors ADD COLUMN hashed_password VARCHAR"))
            if "login_enabled" not in staff_columns:
                connection.execute(text("ALTER TABLE clinic_doctors ADD COLUMN login_enabled BOOLEAN NOT NULL DEFAULT false"))
            if "can_view_all_patients" not in staff_columns:
                connection.execute(text("ALTER TABLE clinic_doctors ADD COLUMN can_view_all_patients BOOLEAN NOT NULL DEFAULT false"))
            if "sessions_valid_after" not in staff_columns:
                connection.execute(text("ALTER TABLE clinic_doctors ADD COLUMN sessions_valid_after TIMESTAMP"))
            if "last_login_at" not in staff_columns:
                connection.execute(text("ALTER TABLE clinic_doctors ADD COLUMN last_login_at TIMESTAMP"))
    for audited_table in ("patients", "appointments", "treatment_invoices", "financial_transactions",
                          "invoice_material_usages", "prescriptions"):
        if audited_table in inspector.get_table_names():
            audited_columns = {column["name"] for column in inspector.get_columns(audited_table)}
            if "created_by_staff_id" not in audited_columns:
                with engine.begin() as connection:
                    connection.execute(text(f"ALTER TABLE {audited_table} ADD COLUMN created_by_staff_id INTEGER"))

    # استبدال الرمز بدل تكديسه (2026-09-25): يوم الاستهلاك، ويوم الإلغاء
    # والرمز الذي حلّ محلّه. nullable كلها -- القديم يبقى NULL بصدق.
    if "activation_keys" in inspector.get_table_names():
        key_columns = {column["name"] for column in inspector.get_columns("activation_keys")}
        with engine.begin() as connection:
            if "used_at" not in key_columns:
                connection.execute(text("ALTER TABLE activation_keys ADD COLUMN used_at TIMESTAMP"))
            if "revoked_at" not in key_columns:
                connection.execute(text("ALTER TABLE activation_keys ADD COLUMN revoked_at TIMESTAMP"))
            if "replaced_by_code" not in key_columns:
                connection.execute(text("ALTER TABLE activation_keys ADD COLUMN replaced_by_code VARCHAR"))

    # فهارس البحث الأكثر تكراراً في هذه الميزة: كشف حساب طبيب واحد ضمن شهر
    # محدد، ورصيد كل أطباء عيادة واحدة. CREATE INDEX IF NOT EXISTS مدعومة في
    # SQLite وPostgres معاً، والعملية آمنة للتكرار في كلتيهما.
    if "doctor_earnings" in inspector.get_table_names():
        with engine.begin() as connection:
            connection.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_doctor_earnings_doctor_earned_at "
                    "ON doctor_earnings (clinic_doctor_id, earned_at)"
                )
            )
    if "doctor_payouts" in inspector.get_table_names():
        with engine.begin() as connection:
            connection.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_doctor_payouts_doctor_paid_at "
                    "ON doctor_payouts (clinic_doctor_id, paid_at)"
                )
            )

    # ====================================================================
    # لائحة أسعار العلاجات + استهلاك المواد  --  2026-09-14
    # ====================================================================
    # الجداول الثلاثة الجديدة (treatment_catalog_items /
    # treatment_catalog_materials / invoice_material_usages) تُنشئها
    # Base.metadata.create_all() في أول سطر من هذه الدالة. ما يحتاج ALTER هو
    # العمودان المضافان إلى جدولين قائمين فقط.
    #
    # unit_cost بـ NOT NULL DEFAULT 0 -- الصياغة مدعومة في SQLite وPostgres
    # معاً، وكل مادة قديمة تصبح بتكلفة صفر بصدق: النظام يعرض تكلفة علاج صفراً
    # حتى يُدخل الطبيب أسعاره بنفسه، بدل أن يخترع له رقماً.
    if "inventory_items" in inspector.get_table_names():
        inventory_cost_columns = {column["name"] for column in inspector.get_columns("inventory_items")}
        if "unit_cost" not in inventory_cost_columns:
            with engine.begin() as connection:
                connection.execute(
                    text("ALTER TABLE inventory_items ADD COLUMN unit_cost NUMERIC(12, 2) NOT NULL DEFAULT 0")
                )

    # nullable بلا قيمة افتراضية: كل فاتورة سابقة للميزة تبقى NULL بصدق
    # (كُتبت يدوياً بلا حالة جاهزة) فلا يحتاج أي صف تاريخي backfill.
    if "treatment_invoices" in inspector.get_table_names():
        invoice_catalog_columns = {column["name"] for column in inspector.get_columns("treatment_invoices")}
        if "catalog_item_id" not in invoice_catalog_columns:
            with engine.begin() as connection:
                connection.execute(
                    text("ALTER TABLE treatment_invoices ADD COLUMN catalog_item_id INTEGER")
                )

    # الاستعلامان الأكثر تكراراً في هذه الميزة: مواد فاتورة واحدة، وتكلفة كل
    # مواد طبيب مساعد ضمن فترة. CREATE INDEX IF NOT EXISTS آمنة للتكرار في
    # SQLite وPostgres معاً.
    if "invoice_material_usages" in inspector.get_table_names():
        with engine.begin() as connection:
            connection.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_invoice_material_usages_invoice "
                    "ON invoice_material_usages (invoice_id)"
                )
            )
            connection.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_invoice_material_usages_doctor_created "
                    "ON invoice_material_usages (clinic_doctor_id, created_at)"
                )
            )
    if "treatment_catalog_materials" in inspector.get_table_names():
        with engine.begin() as connection:
            connection.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_treatment_catalog_materials_item "
                    "ON treatment_catalog_materials (catalog_item_id)"
                )
            )

    _apply_invoice_created_at_damascus_fix()


# ── إصلاحات بيانات تُطبَّق مرة واحدة (2026-09-25) ──
# علامة كل إصلاح صفٌّ في data_fixes يُدرَج **قبل** الإصلاح وفي المعاملة نفسها:
# نسختان من الخادم تقلعان معاً لا تطبّقانه مرتين -- الثانية تصطدم بالمفتاح
# الأساسي فتُلغى معاملتها كلها، بما فيها التعديل.
def _apply_invoice_created_at_damascus_fix():
    """فواتير العلاج كانت تُختم بـ CURRENT_TIMESTAMP (توقيت غرينتش) والدفعات
    بتوقيت دمشق، فظهرت الفاتورة أقدم بثلاث ساعات، وانزلقت فواتير ما بعد منتصف
    الليل إلى اليوم/الشهر السابق في تقرير الربحية. الجديدة تُختم بتوقيت دمشق في
    create_patient_invoice، وهذا يُزيح القديمة +3 ساعات مرة واحدة (سوريا على
    UTC+3 طوال العام منذ تشرين الأول 2022، وكل فواتير النظام بعد ذلك)."""
    fix_name = "invoice_created_at_damascus"
    if "treatment_invoices" not in inspect(engine).get_table_names():
        return
    with engine.begin() as connection:
        connection.execute(
            text("CREATE TABLE IF NOT EXISTS data_fixes (name VARCHAR PRIMARY KEY, applied_at TIMESTAMP)")
        )
    try:
        with engine.begin() as connection:
            already = connection.execute(
                text("SELECT 1 FROM data_fixes WHERE name = :name"), {"name": fix_name}
            ).first()
            if already:
                return
            connection.execute(
                text("INSERT INTO data_fixes (name, applied_at) VALUES (:name, CURRENT_TIMESTAMP)"),
                {"name": fix_name},
            )
            if engine.dialect.name == "sqlite":
                shifted = "datetime(created_at, '+3 hours')"
            else:
                shifted = "created_at + INTERVAL '3 hours'"
            connection.execute(
                text(f"UPDATE treatment_invoices SET created_at = {shifted} WHERE created_at IS NOT NULL")
            )
    except Exception as exc:
        # نسخة أخرى طبّقته في اللحظة نفسها (تعارض المفتاح) -- لا شيء نفعله.
        print(f"[data_fixes] {fix_name}: {exc}")


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()