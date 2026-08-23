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


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()